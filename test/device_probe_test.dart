import 'package:flutter_boilerplate/src/base/qa/device_probe.dart';
import 'package:flutter_boilerplate/src/models/qa/device_model.dart';
import 'package:flutter_test/flutter_test.dart';

/// Real `xcrun simctl` / `adb` / `xcrun devicectl` calls — this machine's
/// actual toolchain, not a mock. Whatever devices happen to exist locally
/// vary, so these assert the *shape*/never-throws contract, not exact
/// device lists.
void main() {
  test('listIosSimulators returns real, well-formed simulator entries', () async {
    final result = await DeviceProbe.listIosSimulators();
    for (final d in result) {
      expect(d.udid, isNotEmpty);
      expect(d.platform, DevicePlatform.ios);
      expect(d.kind, DeviceKind.simulator);
    }
  });

  test('listAndroidDevices never throws, regardless of whether adb/emulators exist',
      () async {
    final result = await DeviceProbe.listAndroidDevices();
    for (final d in result) {
      expect(d.udid, isNotEmpty);
      expect(d.platform, DevicePlatform.android);
    }
  });

  test(
      'listAndroidDevices classifies emulator- ids as simulator, everything else as physical',
      () async {
    // Can't force a real emulator/device to exist for this test — just
    // confirm the classification rule against synthetic ids via the same
    // logic path indirectly by checking real output stays internally
    // consistent (every simulator-kind entry's id does start with
    // "emulator-", every physical one doesn't).
    final result = await DeviceProbe.listAndroidDevices();
    for (final d in result) {
      expect(d.udid.startsWith('emulator-'), d.kind == DeviceKind.simulator);
    }
  });

  test('listIosPhysicalDevices never throws even if devicectl is unavailable/unexpected',
      () async {
    final result = await DeviceProbe.listIosPhysicalDevices();
    for (final d in result) {
      expect(d.udid, isNotEmpty);
      expect(d.platform, DevicePlatform.ios);
      expect(d.kind, DeviceKind.physical);
    }
  });
}
