import 'dart:io';

import 'package:flutter_boilerplate/src/base/qa/process_gateway.dart';
import 'package:flutter_test/flutter_test.dart';

/// These run real shell processes — the point is to catch the failures a fake
/// can't see: a lost output tail, an exit code read after the stream closed,
/// and orphaned grandchildren surviving Cancel.
void main() {
  final gateway = ProcessGateway();

  test('splits stdout/stderr, keeps the tail, and sets the exit code',
      () async {
    final lines = <LogLine>[];
    final handle = ProcessHandle();

    await for (final line in gateway.stream(
      'echo out1; echo err1 >&2; echo out2; exit 3',
      handle: handle,
    )) {
      lines.add(line);
    }

    final out = lines.where((l) => !l.isError).map((l) => l.text);
    final err = lines.where((l) => l.isError).map((l) => l.text);

    expect(out, containsAll(['out1', 'out2']),
        reason: 'last line before exit must not be dropped');
    expect(err, contains('err1'));
    expect(handle.exitCode, 3,
        reason: 'StepRunner reads exitCode right after the stream closes');
  });

  test('kill() takes down the whole process tree, not just the shell',
      () async {
    const marker = 'sleep 314159';
    Future<int> countProcs() async {
      final r = await Process.run(
          '/bin/sh', ['-c', 'pgrep -f "$marker" | wc -l']);
      return int.parse((r.stdout as String).trim());
    }

    final handle = ProcessHandle();
    final sub =
        gateway.stream('$marker & $marker & wait', handle: handle).listen((_) {});
    addTearDown(sub.cancel);

    await Future<void>.delayed(const Duration(seconds: 2));
    expect(await countProcs(), greaterThanOrEqualTo(2),
        reason: 'children should be running before we kill');

    handle.kill();
    await Future<void>.delayed(const Duration(seconds: 2));

    // Dart does not setsid() a normal child, so this only passes because
    // ProcessGateway re-execs through perl's setpgrp.
    expect(await countProcs(), 0, reason: 'grandchildren survived kill()');
  });

  test('extraEnv reaches the child process', () async {
    final lines = <String>[];
    await for (final line in gateway.stream(
      r'echo "got=$MY_TEST_VAR"',
      extraEnv: {'MY_TEST_VAR': 'hello-42'},
    )) {
      lines.add(line.text);
    }
    expect(lines, contains('got=hello-42'));
  });

  test('writeStdin answers a readline-style blocking prompt (OTP flow)',
      () async {
    // Mirrors otpFetcher.ts: the child prints a prompt, blocks on `read`
    // (Node's readline equivalent), then echoes what it got. This is the
    // exact mechanism the RunPanel's stdin field relies on — the child's
    // stdin pipe stays open on a normal (non-detached) start.
    final handle = ProcessHandle();
    final lines = <String>[];
    final sub = gateway
        .stream(r'echo "PROMPT: enter otp"; read code; echo "GOT:$code"',
            handle: handle)
        .listen((l) => lines.add(l.text));
    addTearDown(sub.cancel);

    // Wait for the child to actually reach `read` before answering it.
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (!lines.any((l) => l.contains('PROMPT')) &&
        DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }

    handle.writeStdin('123456');

    await Future<void>.delayed(const Duration(milliseconds: 500));
    expect(lines, contains('GOT:123456'));
  });

  test('extraPathDirs ends up on PATH for a command with no extraEnv',
      () async {
    final gateway = ProcessGateway()..extraPathDirs = ['/my/custom/bin'];
    final lines = <String>[];
    await for (final line in gateway.stream(r'echo "PATH=$PATH"')) {
      lines.add(line.text);
    }
    // Login-shell startup files (.zprofile, /usr/libexec/path_helper) run
    // after we set PATH and can reorder it further — the only thing we
    // actually control is that the directory ends up on PATH at all.
    expect(lines.single, contains('/my/custom/bin'));
  });

  test('extraPathDirs is applied even when a step also sets extraEnv',
      () async {
    final gateway = ProcessGateway()..extraPathDirs = ['/my/custom/bin'];
    final lines = <String>[];
    await for (final line in gateway.stream(
      r'echo "PATH=$PATH FOO=$FOO"',
      extraEnv: {'FOO': 'bar'},
    )) {
      lines.add(line.text);
    }
    expect(lines.single, contains('/my/custom/bin'));
    expect(lines.single, contains('FOO=bar'));
  });

  test('an empty extraPathDirs leaves PATH untouched', () async {
    final gateway = ProcessGateway();
    final before = await gateway.exec(r'echo "$PATH"');
    final after = await (ProcessGateway()..extraPathDirs = [])
        .exec(r'echo "$PATH"');
    expect(after, before);
  });

  test(
      'PATH resolution uses an interactive shell internally but never lets '
      'that leak into a command\'s own stdout', () async {
    // The whole point of the resolve/execute split: .zshrc can print things
    // (nvm's "Now using node vX.Y.Z" banner, on this exact machine) on an
    // interactive shell's stdout. If that ever leaked, this would return
    // more than one line.
    final out = await gateway.exec('echo only-this-line');
    expect(out, 'only-this-line');
  });

  test('resolved PATH pulls in .zshrc, not just a login-only shell\'s PATH',
      () async {
    // A plain `-l` (login, non-interactive) shell never sources .zshrc, so
    // its PATH is deterministic and repeatable — the real regression this
    // whole split fixes ("env: node: No such file or directory") is that
    // this baseline is missing whatever .zshrc adds (nvm, etc). The gateway's
    // resolved PATH must be more than that baseline.
    final loginOnly =
        await Process.run('/bin/zsh', ['-l', '-c', r'echo "$PATH"'])
            .then((r) => (r.stdout as String).trim());
    final resolved = await gateway.exec(r'echo "$PATH"');
    expect(resolved, isNot(equals(loginOnly)),
        reason: '.zshrc should contribute something a login-only shell lacks');
  });

  group('exec exit-code contract', () {
    // The Doctor quick-fix feature's success/failure detection depends
    // entirely on this: a real failure must throw (carrying stderr), or
    // every failure would look identical to success with empty stdout.
    test('a failing command throws, with stderr in the message', () async {
      await expectLater(
        gateway.exec('echo "boom" >&2; exit 7'),
        throwsA(isA<ProcessException>().having(
            (e) => e.message, 'message', contains('boom'))),
      );
    });

    test('a succeeding command does not throw and returns stdout', () async {
      final out = await gateway.exec('echo ok');
      expect(out, 'ok');
    });

    test('ignoreExitCode: true suppresses the throw on failure', () async {
      final out =
          await gateway.exec('exit 7', ignoreExitCode: true);
      expect(out, isEmpty); // no exception, just whatever stdout there was
    });
  });
}
