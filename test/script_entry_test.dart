import 'package:flutter_boilerplate/src/models/qa/project_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ScriptEntry.displayName', () {
    test('falls back to the filename when no custom name is set', () {
      final s = ScriptEntry(
        id: '1',
        path: '/repo/test/specs/login.e2e.ts',
        addedAt: DateTime.now(),
      );
      expect(s.displayName, 'login.e2e.ts');
    });

    test('a path with no slash (a package.json script name) passes through',
        () {
      final s = ScriptEntry(id: '1', path: 'test:smoke', addedAt: DateTime.now());
      expect(s.displayName, 'test:smoke');
    });

    test('a non-empty custom name wins over the derived filename', () {
      final s = ScriptEntry(
        id: '1',
        path: '/repo/test/specs/login.e2e.ts',
        customName: 'Login test case',
        addedAt: DateTime.now(),
      );
      expect(s.displayName, 'Login test case');
    });

    test('a blank custom name still falls back to the filename', () {
      final s = ScriptEntry(
        id: '1',
        path: '/repo/test/specs/login.e2e.ts',
        customName: '   ',
        addedAt: DateTime.now(),
      );
      expect(s.displayName, 'login.e2e.ts');
    });
  });

  group('ScriptEntry JSON round-trip', () {
    test('preserves all fields', () {
      final s = ScriptEntry(
        id: 'abc',
        path: '/x/y.ts',
        customName: 'My test',
        addedAt: DateTime.utc(2026, 1, 1),
      );
      final back = ScriptEntry.fromJson(s.toJson());
      expect(back.id, 'abc');
      expect(back.path, '/x/y.ts');
      expect(back.customName, 'My test');
      expect(back.addedAt, DateTime.utc(2026, 1, 1));
    });

    test('a null customName round-trips as null, not the key missing crashing',
        () {
      final s = ScriptEntry(id: 'abc', path: '/x/y.ts', addedAt: DateTime.now());
      final back = ScriptEntry.fromJson(s.toJson());
      expect(back.customName, isNull);
    });
  });

  group('ScriptEntry.mergeUnique', () {
    test('adds new paths and reports how many were actually new', () {
      final result = ScriptEntry.mergeUnique([], ['/a.ts', '/b.ts']);
      expect(result.scripts, hasLength(2));
      expect(result.added, 2);
    });

    test('skips a path already present in the existing list', () {
      final existing = [
        ScriptEntry(id: '1', path: '/a.ts', addedAt: DateTime.now()),
      ];
      final result = ScriptEntry.mergeUnique(existing, ['/a.ts', '/b.ts']);
      expect(result.scripts.map((s) => s.path), ['/a.ts', '/b.ts']);
      expect(result.added, 1); // only /b.ts is new
    });

    test('a batch with an internal duplicate only adds it once', () {
      final result = ScriptEntry.mergeUnique([], ['/a.ts', '/a.ts', '/b.ts']);
      expect(result.scripts.map((s) => s.path).toList(), ['/a.ts', '/b.ts']);
      expect(result.added, 2);
    });

    test('re-importing the exact same set a second time adds nothing', () {
      final first = ScriptEntry.mergeUnique([], ['/a.ts', '/b.ts']);
      final second = ScriptEntry.mergeUnique(first.scripts, ['/a.ts', '/b.ts']);
      expect(second.added, 0);
      expect(second.scripts, hasLength(2)); // unchanged, not duplicated
    });

    test('customName is applied to every newly-added entry', () {
      final result =
          ScriptEntry.mergeUnique([], ['test:smoke'], customName: 'Smoke');
      expect(result.scripts.single.customName, 'Smoke');
    });
  });
}
