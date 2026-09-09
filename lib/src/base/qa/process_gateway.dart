import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Low-level shell runner.
///
/// Every command actually runs under a plain `/bin/zsh -l -c <command>` —
/// clean stdout/stderr, nothing but the command's own output. PATH
/// resolution is a separate concern, handled once and cached (see below).
///
/// UI and controllers must NOT call [Process.start] directly; go through this
/// gateway so we have one place to fix PATH / PTY / signal issues.
///
/// ### Why PATH resolution needed its own path (pun intended)
///
/// `-l` (login) alone is not enough to match Terminal's PATH — zsh only
/// sources `.zshrc` for *interactive* shells, and that's where most
/// PATH-affecting tool setup actually lives (nvm's own installer, for
/// instance, appends its sourcing lines to `.zshrc`, not `.zprofile`).
/// Without `.zshrc`, a login-only shell can end up with no PATH entry for a
/// tool at all — a real, found-in-production bug: `npm install -g yarn`
/// failing with `env: node: No such file or directory` because Node
/// genuinely wasn't on PATH without it.
///
/// The obvious fix — add `-i` to every spawn — was tried and reverted: it
/// does source `.zshrc` and fix PATH, but it also means zsh has no real TTY,
/// so anything `.zshrc` prints for a human's benefit (this exact user's own
/// `nvm use node` line echoes "Now using node vX.Y.Z (npm vA.B.C)") leaks
/// onto stdout ahead of the command's real output — silently corrupting
/// every check that parses stdout (git branch name, `--version` output,
/// `echo "$PATH"`, etc.). Confirmed by running the full suite: 8 tests broke
/// immediately.
///
/// So PATH resolution and command execution are split: [_resolvedPath]
/// spawns exactly one `-i -l` shell, ever (cached for the process's
/// lifetime), asks it to `echo` PATH after a unique marker, and scans for
/// that marker line rather than trusting the first line — any startup noise
/// before it is simply ignored. Every real command then runs through a
/// plain, quiet `-l` shell with that resolved PATH injected via `extraEnv`,
/// getting nvm/rbenv/etc.'s PATH correctly without any interactive noise
/// risk on the command's own output.
class ProcessGateway {
  /// Dart's `Process.start` does NOT call `setsid()` in normal mode, so a plain
  /// child inherits *our* process group — which makes `kill -TERM -<pgid>` either
  /// a no-op or (worse) a signal aimed at this app. Re-exec through perl's
  /// `setpgrp` so the child zsh becomes its own group leader (pgid == pid) and
  /// [ProcessHandle.kill] can take down the whole npm/gradle/flutter tree.
  ///
  /// perl is preinstalled on macOS; if it ever isn't, fall back to a plain zsh
  /// (single-process kill only) rather than failing every command.
  static final bool _hasPerl = File(_perl).existsSync();
  static const String _perl = '/usr/bin/perl';

  List<String> _spawn(String command) => _hasPerl
      ? [_perl, '-e', 'setpgrp; exec @ARGV', '/bin/zsh', '-l', '-c', command]
      : ['/bin/zsh', '-l', '-c', command];

  /// Resolved once per process lifetime (static — shared by every instance,
  /// per the class doc). `null` means "not resolved yet"; resolution itself
  /// is de-duped via [_resolvingPath] so concurrent early callers don't each
  /// spawn their own shell.
  static String? _resolvedPathCache;
  static Future<String>? _resolvingPath;
  static const String _pathMarker = '__QA_RESOLVED_PATH__';

  /// The PATH a real interactive login shell would have — see the class doc
  /// for why this can't just be `Platform.environment['PATH']`.
  Future<String> _resolvedPath() {
    final cached = _resolvedPathCache;
    if (cached != null) return Future.value(cached);
    return _resolvingPath ??= _resolvePathOnce();
  }

  Future<String> _resolvePathOnce() async {
    try {
      // 15s, not 5s: this resolution is cached for the whole app lifetime
      // (see the class doc) — a login+interactive shell sourcing nvm/rbenv/
      // oh-my-zsh/etc. genuinely takes a few seconds even under normal load,
      // and a 5s timeout could clip that under any real system load (another
      // build running, a heavy background process), silently poisoning the
      // cache with the bare fallback PATH below for as long as the app stays
      // open — exactly the kind of Doctor-check failure that's confusing to
      // debug since it looks like a real missing-tool problem.
      final result = await Process.run(
        '/bin/zsh',
        ['-i', '-l', '-c', 'echo "$_pathMarker\$PATH"'],
      ).timeout(const Duration(seconds: 15));
      for (final line in (result.stdout as String).split('\n')) {
        if (line.startsWith(_pathMarker)) {
          final path = line.substring(_pathMarker.length).trim();
          if (path.isNotEmpty) return _resolvedPathCache = path;
        }
      }
    } catch (_) {
      // Fall through to the fallback below.
    }
    // Couldn't resolve (no zsh, timeout, weird shell config) — fall back to
    // whatever PATH this process already has rather than breaking every
    // command.
    return _resolvedPathCache = Platform.environment['PATH'] ?? '';
  }

  /// Run [command] and return stdout as a trimmed string.
  ///
  /// Throws [ProcessException] if the exit code is non-zero (unless
  /// [ignoreExitCode] is true).
  Future<String> exec(
    String command, {
    String? workingDirectory,
    Map<String, String>? extraEnv,
    bool ignoreExitCode = false,
  }) async {
    // Short-lived and awaited — no kill needed, so skip the setpgrp wrapper.
    final result = await Process.run(
      '/bin/zsh',
      ['-l', '-c', command],
      workingDirectory: workingDirectory,
      environment: await _buildEnv(extraEnv),
    );

    final stdout = (result.stdout as String).trim();
    if (!ignoreExitCode && result.exitCode != 0) {
      final stderr = (result.stderr as String).trim();
      throw ProcessException(
        '/bin/zsh',
        ['-l', '-c', command],
        'exit ${result.exitCode}: $stderr',
        result.exitCode,
      );
    }
    return stdout;
  }

  /// Start [command] and stream stdout + stderr lines.
  ///
  /// Yields [LogLine] objects so the UI can distinguish stdout from stderr.
  /// Completes when the process exits. The [handle] exposes a way to kill the
  /// process (and its group) on Cancel, and carries the exit code — which is
  /// always set before this stream closes.
  Stream<LogLine> stream(
    String command, {
    String? workingDirectory,
    Map<String, String>? extraEnv,
    ProcessHandle? handle,
  }) async* {
    final argv = _spawn(command);
    final process = await Process.start(
      argv.first,
      argv.sublist(1),
      workingDirectory: workingDirectory,
      environment: await _buildEnv(extraEnv),
    );

    handle?._attach(process);

    final controller = StreamController<LogLine>();

    Future<void> pump(Stream<List<int>> src, {required bool isError}) {
      return src
          .transform(const SystemEncoding().decoder)
          .transform(const LineSplitter())
          .forEach((line) {
            if (!controller.isClosed) {
              controller.add(LogLine(line, isError: isError));
            }
          })
          // A decode/pipe error must not sink the pipeline.
          .catchError((_) {});
    }

    final drained = Future.wait([
      pump(process.stdout, isError: false),
      pump(process.stderr, isError: true),
    ]);

    // Close on exit, but give the pipes a grace period to flush their tail so
    // the last lines of output aren't lost. The race guards the opposite case:
    // a grandchild that inherited stdout and never closes it would otherwise
    // hang the pipeline forever.
    unawaited(process.exitCode.then((code) async {
      await Future.any([
        drained,
        Future<void>.delayed(const Duration(seconds: 2)),
      ]);
      handle?.setExitCode(code);
      await controller.close();
    }));

    yield* controller.stream;
  }

  /// Spawn [command] detached (fire-and-forget, e.g. `allure open`).
  Future<void> detach(
    String command, {
    String? workingDirectory,
    Map<String, String>? extraEnv,
  }) async {
    // ProcessStartMode.detached already calls setsid() — no perl wrapper needed.
    await Process.start(
      '/bin/zsh',
      ['-l', '-c', command],
      workingDirectory: workingDirectory,
      environment: await _buildEnv(extraEnv),
      mode: ProcessStartMode.detached,
    );
  }

  /// Prepended to PATH for every spawned command — set once from
  /// `MachineProfile.extraPathDirs` (Setup screen, Phase 5) for the rare
  /// machine where a tool works in Terminal but isn't on the login-shell
  /// PATH this app inherits. Empty for almost everyone.
  ///
  /// "Prepended" is what we control going in — the login shell's own
  /// startup files (`.zprofile`, `/usr/libexec/path_helper`) run afterward
  /// and can reorder PATH further. What's guaranteed is that the directory
  /// ends up on PATH somewhere, which is all a bare `flutter`/`adb`/`node`
  /// lookup needs.
  List<String> extraPathDirs = const [];

  Future<Map<String, String>> _buildEnv(Map<String, String>? extra) async {
    final base = {...Platform.environment, 'PATH': await _resolvedPath()};
    final merged = (extra == null || extra.isEmpty) ? base : {...base, ...extra};
    return _withExtraPath(merged);
  }

  Map<String, String> _withExtraPath(Map<String, String> env) {
    if (extraPathDirs.isEmpty) return env;
    final current = env['PATH'] ?? '';
    return {
      ...env,
      'PATH': [...extraPathDirs, current].where((s) => s.isNotEmpty).join(':'),
    };
  }
}

/// A running process handle — passed to [ProcessGateway.stream] so the caller
/// can cancel / kill the process from outside the stream.
class ProcessHandle {
  Process? _process;
  int? _exitCode;
  bool _killed = false;

  void _attach(Process p) => _process = p;

  /// Set by [ProcessGateway.stream] before its stream closes. Public only so
  /// fake gateways in tests can report an exit code the same way.
  void setExitCode(int code) => _exitCode = code;

  int? get exitCode => _exitCode;
  bool get isRunning => _process != null && _exitCode == null;
  bool get wasKilled => _killed;

  /// Write [line] + a newline to the child's stdin.
  ///
  /// WDIO's OTP prompt (`otpFetcher.ts`) blocks on `readline` reading its own
  /// stdin — a normal-mode [Process.start] leaves that pipe open, so this is
  /// all that's needed to answer it. Silently a no-op once the process has
  /// exited (stale UI input arriving after the step already finished).
  void writeStdin(String line) {
    if (!isRunning) return;
    _process!.stdin.writeln(line);
  }

  /// Send SIGTERM to the process group (kills child processes too).
  void kill() {
    final p = _process;
    if (p == null) return;
    _killed = true;
    // Negative pid targets the entire process group — works because
    // ProcessGateway starts the child via perl's setpgrp (pgid == pid).
    Process.killPid(-p.pid, ProcessSignal.sigterm);
    Process.killPid(p.pid, ProcessSignal.sigterm);
  }
}

/// A single line of output from a running process.
class LogLine {
  final String text;
  final bool isError;
  final DateTime timestamp;

  LogLine(this.text, {required this.isError}) : timestamp = DateTime.now();

  @override
  String toString() => text;
}
