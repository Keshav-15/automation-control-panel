/// See docs/RUN_EXPERIENCE_REDESIGN.md §6/§11 — the device-picker flow and
/// (later) the global device management screen both read this.
enum DevicePlatform { android, ios }

enum DeviceKind { simulator, physical }

/// One simulator/emulator or physical device, as reported by the platform
/// tooling (`xcrun simctl`, `adb`, `xcrun devicectl`) — see
/// `lib/src/base/qa/device_probe.dart`.
class DeviceInfo {
  final String udid;
  final String name;
  final DevicePlatform platform;
  final DeviceKind kind;

  /// Simulator: `state == "Booted"`. Physical: connected/authorized (a
  /// listed device is always reachable, so always true).
  final bool booted;

  const DeviceInfo({
    required this.udid,
    required this.name,
    required this.platform,
    required this.kind,
    required this.booted,
  });
}

/// One creatable iOS simulator model (`xcrun simctl list devicetypes`) —
/// used by the "Add simulator" flow, docs/RUN_EXPERIENCE_REDESIGN.md §11.
class IosDeviceType {
  final String identifier;
  final String name;
  const IosDeviceType({required this.identifier, required this.name});
}

/// One installed iOS runtime (`xcrun simctl list runtimes`) — the OS version
/// a new simulator gets created against.
class IosRuntime {
  final String identifier;
  final String version;
  const IosRuntime({required this.identifier, required this.version});
}

/// One Android hardware profile (`avdmanager list device`) — e.g. "pixel_7".
class AndroidDeviceProfile {
  final String id;
  final String name;
  const AndroidDeviceProfile({required this.id, required this.name});
}
