import 'dart:io';

import 'package:flutter_boilerplate/src/base/qa/bundle_id_detector.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory repo;
  setUp(() => repo = Directory.systemTemp.createTempSync('qa_bundle_id'));
  tearDown(() => repo.deleteSync(recursive: true));

  group('detectAndroid', () {
    test('parses applicationId per flavor from a standard build.gradle', () {
      final dir = Directory('${repo.path}/android/app')..createSync(recursive: true);
      File('${dir.path}/build.gradle').writeAsStringSync('''
android {
    defaultConfig {
        applicationId "com.goa.app"
    }
    productFlavors {
        development {
            applicationId "com.goa.app.dev"
            versionNameSuffix "-dev"
        }
        production {
            applicationId "com.goa.app"
        }
    }
}
''');

      final result = BundleIdDetector.detectAndroid(repo.path);

      expect(result, {
        'development': 'com.goa.app.dev',
        'production': 'com.goa.app',
      });
    });

    test('falls back to build.gradle.kts when build.gradle is absent', () {
      final dir = Directory('${repo.path}/android/app')..createSync(recursive: true);
      File('${dir.path}/build.gradle.kts').writeAsStringSync('''
android {
    productFlavors {
        create("development") {
        }
        staging {
            applicationId = "com.goa.app.staging"
        }
    }
}
''');
      final result = BundleIdDetector.detectAndroid(repo.path);
      // `create("development") { }` isn't the simple `<name> {` shape this
      // best-effort scanner recognizes — it's fine for that flavor to be
      // missing entirely, as long as it doesn't crash and finds what it can.
      expect(result['staging'], 'com.goa.app.staging');
    });

    test('no build.gradle at all returns an empty map, not a crash', () {
      expect(BundleIdDetector.detectAndroid(repo.path), isEmpty);
    });

    test('a defaultConfig-only applicationId (no flavors) is not picked up',
        () {
      final dir = Directory('${repo.path}/android/app')..createSync(recursive: true);
      File('${dir.path}/build.gradle').writeAsStringSync('''
android {
    defaultConfig {
        applicationId "com.goa.app"
    }
}
''');
      expect(BundleIdDetector.detectAndroid(repo.path), isEmpty);
    });
  });

  group('detectIos', () {
    test('reads PRODUCT_BUNDLE_IDENTIFIER from every .xcconfig under ios/',
        () {
      final dir = Directory('${repo.path}/ios/Flutter')..createSync(recursive: true);
      File('${dir.path}/Development.xcconfig')
          .writeAsStringSync('PRODUCT_BUNDLE_IDENTIFIER = com.goa.app.dev;\n');
      File('${dir.path}/Production.xcconfig')
          .writeAsStringSync('PRODUCT_BUNDLE_IDENTIFIER = com.goa.app;\n');

      final result = BundleIdDetector.detectIos(repo.path);

      expect(result, {
        'development': 'com.goa.app.dev',
        'production': 'com.goa.app',
      });
    });

    test('skips a config whose value is an unresolved build variable', () {
      final dir = Directory('${repo.path}/ios/Flutter')..createSync(recursive: true);
      File('${dir.path}/Shared.xcconfig').writeAsStringSync(
          r'PRODUCT_BUNDLE_IDENTIFIER = $(inherited).dev;' '\n');
      expect(BundleIdDetector.detectIos(repo.path), isEmpty);
    });

    test('an xcconfig with no PRODUCT_BUNDLE_IDENTIFIER line is skipped', () {
      final dir = Directory('${repo.path}/ios/Flutter')..createSync(recursive: true);
      File('${dir.path}/Generated.xcconfig')
          .writeAsStringSync('FLUTTER_ROOT=/some/path\n');
      expect(BundleIdDetector.detectIos(repo.path), isEmpty);
    });

    test('no ios/ folder at all returns an empty map, not a crash', () {
      expect(BundleIdDetector.detectIos(repo.path), isEmpty);
    });
  });
}
