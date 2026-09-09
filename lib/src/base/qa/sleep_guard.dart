import 'dart:io';

/// Holds off macOS idle sleep for the duration of a pipeline run.
///
/// A Flutter build or long WDIO suite can run for 20+ minutes with the lid
/// closed or the machine untouched; without this, macOS suspends the whole
/// process tree mid-build. Just shells out to the `caffeinate` binary that
/// ships with macOS — no need to reimplement IOKit power-assertion bindings
/// for what is, in effect, "run this one command until told to stop".
class SleepGuard {
  Process? _process;

  /// Start holding off idle sleep. Safe to call again while already running
  /// (no-op) — [RunProvider] calls this once per pipeline run.
  Future<void> start() async {
    if (_process != null) return;
    try {
      // -i: prevent idle sleep. Deliberately omits -d (display sleep) — the
      // screen can still turn off, only the machine itself must stay up.
      _process = await Process.start('/usr/bin/caffeinate', ['-i']);
    } catch (_) {
      // No caffeinate on this machine (shouldn't happen on macOS) — the run
      // still proceeds, just without the sleep guard. Never block a test run
      // over this.
    }
  }

  /// Stop holding off sleep. Safe to call when never started, or twice.
  void stop() {
    _process?.kill();
    _process = null;
  }
}
