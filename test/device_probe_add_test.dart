import 'package:flutter_boilerplate/src/base/qa/device_probe.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('listIosDeviceTypes / listIosRuntimes — real xcrun simctl', () {
    test('returns real, well-formed device types', () async {
      final types = await DeviceProbe.listIosDeviceTypes();
      expect(types, isNotEmpty,
          reason: 'this machine has Xcode CLI tools with simulators available');
      for (final t in types) {
        expect(t.identifier, isNotEmpty);
        expect(t.name, isNotEmpty);
      }
    });

    test('returns real, well-formed runtimes', () async {
      final runtimes = await DeviceProbe.listIosRuntimes();
      expect(runtimes, isNotEmpty);
      for (final r in runtimes) {
        expect(r.identifier, isNotEmpty);
        expect(r.version, isNotEmpty);
      }
    });
  });

  group('parseAndroidDeviceProfiles — sample avdmanager output', () {
    // This dev environment has no Android SDK installed to verify the live
    // `avdmanager list device` command against, so the parser is tested
    // directly against recorded sample output in the documented format
    // instead (per the class doc's own note).
    const sample = '''
Available devices definitions:
id: 0 or "Galaxy Nexus"
    Name: Galaxy Nexus
    OEM : Google
---------
id: 1 or "Nexus 10"
    Name: Nexus 10
    OEM : Google
---------
id: 17 or "pixel_7"
    Name: Pixel 7
    OEM : Google
    Play Store: true
---------
''';

    test('parses each id/Name block, in order', () {
      final profiles = DeviceProbe.parseAndroidDeviceProfiles(sample);
      expect(profiles.map((p) => p.id).toList(), ['Galaxy Nexus', 'Nexus 10', 'pixel_7']);
      expect(profiles.map((p) => p.name).toList(), ['Galaxy Nexus', 'Nexus 10', 'Pixel 7']);
    });

    test('a trailing block with no separator still parses', () {
      const noTrailingDashes = '''
id: 0 or "Galaxy Nexus"
    Name: Galaxy Nexus
''';
      final profiles = DeviceProbe.parseAndroidDeviceProfiles(noTrailingDashes);
      expect(profiles, hasLength(1));
      expect(profiles.single.id, 'Galaxy Nexus');
    });

    test('empty/garbage input parses to an empty list, not a crash', () {
      expect(DeviceProbe.parseAndroidDeviceProfiles(''), isEmpty);
      expect(DeviceProbe.parseAndroidDeviceProfiles('not the expected format at all'),
          isEmpty);
    });
  });

  group('parseInstalledSystemImages — sample sdkmanager output', () {
    const sample = '''
Installed packages:
  Path                                              | Version | Description
  -------                                           | ------- | -------
  platform-tools                                    | 34.0.4  | Android SDK Platform-Tools
  system-images;android-34;google_apis;arm64-v8a    | 1       | Google APIs ARM 64 v8a System Image
  system-images;android-33;default;x86_64           | 5       | Default System Image
''';

    test('extracts only the system-images package paths', () {
      final images = DeviceProbe.parseInstalledSystemImages(sample);
      expect(images, [
        'system-images;android-34;google_apis;arm64-v8a',
        'system-images;android-33;default;x86_64',
      ]);
    });

    test('empty input parses to an empty list, not a crash', () {
      expect(DeviceProbe.parseInstalledSystemImages(''), isEmpty);
    });
  });
}
