import 'dart:convert';
import 'dart:io';

import 'package:flutter_boilerplate/src/controllers/qa/project_controller.dart';
import 'package:flutter_test/flutter_test.dart';

/// Real temp directories/files — these two helpers are thin wrappers over
/// real filesystem/JSON parsing, so the point is proving the actual
/// mechanism (recursion, files-only, malformed JSON) works, not just that a
/// mock was called correctly.
void main() {
  final controller = ProjectController();

  group('collectFilesUnder', () {
    late Directory root;
    setUp(() => root = Directory.systemTemp.createTempSync('qa_scripts_import'));
    tearDown(() => root.deleteSync(recursive: true));

    test('recursively collects files, skipping directory entries themselves',
        () {
      File('${root.path}/a.e2e.ts').writeAsStringSync('');
      Directory('${root.path}/nested').createSync();
      File('${root.path}/nested/b.e2e.ts').writeAsStringSync('');
      Directory('${root.path}/nested/deeper').createSync();
      File('${root.path}/nested/deeper/c.e2e.ts').writeAsStringSync('');

      final files = controller.collectFilesUnder(root.path);

      expect(files, hasLength(3));
      expect(files.any((f) => f.endsWith('a.e2e.ts')), isTrue);
      expect(files.any((f) => f.endsWith('nested/b.e2e.ts')), isTrue);
      expect(files.any((f) => f.endsWith('nested/deeper/c.e2e.ts')), isTrue);
      // The bare directory paths themselves must not appear as "files".
      expect(files, isNot(contains('${root.path}/nested')));
    });

    test('a non-existent folder returns an empty list, not a crash', () {
      expect(controller.collectFilesUnder('${root.path}/does_not_exist'), isEmpty);
    });

    test('an empty folder returns an empty list', () {
      expect(controller.collectFilesUnder(root.path), isEmpty);
    });
  });

  group('parsePackageJsonScripts', () {
    late Directory root;
    setUp(() => root = Directory.systemTemp.createTempSync('qa_pkg_json'));
    tearDown(() => root.deleteSync(recursive: true));

    test('extracts the scripts map', () {
      final path = '${root.path}/package.json';
      File(path).writeAsStringSync(jsonEncode({
        'name': 'web-app',
        'scripts': {'test': 'jest', 'test:smoke': 'jest --grep smoke'},
      }));

      final scripts = controller.parsePackageJsonScripts(path);

      expect(scripts, {'test': 'jest', 'test:smoke': 'jest --grep smoke'});
    });

    test('a missing package.json returns null, not a crash', () {
      expect(controller.parsePackageJsonScripts('${root.path}/nope.json'), isNull);
    });

    test('malformed JSON returns null, not a crash', () {
      final path = '${root.path}/package.json';
      File(path).writeAsStringSync('{ not valid json');
      expect(controller.parsePackageJsonScripts(path), isNull);
    });

    test('valid JSON with no "scripts" key returns null', () {
      final path = '${root.path}/package.json';
      File(path).writeAsStringSync(jsonEncode({'name': 'web-app'}));
      expect(controller.parsePackageJsonScripts(path), isNull);
    });
  });
}
