import 'dart:io';

import 'package:flutter_boilerplate/src/base/utils/dir_copy_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tempRoot;

  setUp(() {
    tempRoot = Directory.systemTemp.createTempSync('dir_copy_test_');
  });

  tearDown(() {
    if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
  });

  group('copyDirectoryContents', () {
    test('copies a flat file into a brand-new destination', () {
      final src = Directory('${tempRoot.path}/src')..createSync();
      File('${src.path}/a.txt').writeAsStringSync('hello');
      final dest = Directory('${tempRoot.path}/dest');

      copyDirectoryContents(src, dest);

      expect(File('${dest.path}/a.txt').readAsStringSync(), 'hello');
      // Source untouched — this is a copy, not a move.
      expect(File('${src.path}/a.txt').existsSync(), isTrue);
    });

    test('recurses into nested subdirectories, preserving structure', () {
      final src = Directory('${tempRoot.path}/src')..createSync();
      Directory('${src.path}/nested/deeper').createSync(recursive: true);
      File('${src.path}/top.txt').writeAsStringSync('top');
      File('${src.path}/nested/mid.txt').writeAsStringSync('mid');
      File('${src.path}/nested/deeper/bottom.txt').writeAsStringSync('bottom');
      final dest = Directory('${tempRoot.path}/dest');

      copyDirectoryContents(src, dest);

      expect(File('${dest.path}/top.txt').readAsStringSync(), 'top');
      expect(File('${dest.path}/nested/mid.txt').readAsStringSync(), 'mid');
      expect(File('${dest.path}/nested/deeper/bottom.txt').readAsStringSync(),
          'bottom');
    });

    test('merges into an existing destination without wiping other files', () {
      final src = Directory('${tempRoot.path}/src')..createSync();
      File('${src.path}/new.txt').writeAsStringSync('new');
      final dest = Directory('${tempRoot.path}/dest')..createSync();
      File('${dest.path}/existing.txt').writeAsStringSync('existing');

      copyDirectoryContents(src, dest);

      expect(File('${dest.path}/existing.txt').readAsStringSync(), 'existing');
      expect(File('${dest.path}/new.txt').readAsStringSync(), 'new');
    });
  });

  group('directorySizeBytes', () {
    test('sums every file recursively', () {
      final dir = Directory('${tempRoot.path}/sized')..createSync();
      Directory('${dir.path}/sub').createSync();
      File('${dir.path}/a.txt').writeAsStringSync('12345'); // 5 bytes
      File('${dir.path}/sub/b.txt').writeAsStringSync('1234567890'); // 10 bytes

      expect(directorySizeBytes(dir), 15);
    });

    test('returns 0 for a missing directory', () {
      expect(directorySizeBytes(Directory('${tempRoot.path}/nope')), 0);
    });
  });

  group('deleteDirectoryQuietly', () {
    test('deletes an existing directory tree', () {
      final dir = Directory('${tempRoot.path}/todelete')..createSync();
      File('${dir.path}/f.txt').writeAsStringSync('x');

      deleteDirectoryQuietly(dir.path);

      expect(dir.existsSync(), isFalse);
    });

    test('is a no-op (does not throw) for a path that does not exist', () {
      expect(() => deleteDirectoryQuietly('${tempRoot.path}/never-existed'),
          returnsNormally);
    });
  });
}
