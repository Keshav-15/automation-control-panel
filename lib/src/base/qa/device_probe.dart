import 'dart:convert';
import 'dart:io';

import 'package:flutter_boilerplate/src/base/qa/process_gateway.dart';
import 'package:flutter_boilerplate/src/models/qa/device_model.dart';

/// Lists real simulators/emulators and physical devices via the platform
/// tooling already relied on elsewhere in this app (`xcrun simctl`, `adb`,
/// `xcrun devicectl`) — no persisted cache, per
/// docs/RUN_EXPERIENCE_REDESIGN.md §11 ("fetch-on-demand, no stored cache").
///
/// Every method is best-effort and never throws: a missing tool, a
/// never-installed Android SDK, or an unexpected JSON shape just yields an
/// empty list rather than blocking the device picker — manual udid entry
/// stays available wherever these are used.
class DeviceProbe {
  DeviceProbe._();

  static Future<List<DeviceInfo>> listIosSimulators({ProcessGateway? gateway}) async {
    final gw = gateway ?? ProcessGateway();
    try {
      final out = await gw.exec('xcrun simctl list devices --json',
          ignoreExitCode: true);
      if (out.trim().isEmpty) return [];
      final parsed = jsonDecode(out);
      if (parsed is! Map) return [];
      final byRuntime = parsed['devices'] as Map? ?? {};
      final result = <DeviceInfo>[];
      for (final list in byRuntime.values) {
        if (list is! List) continue;
        for (final d in list) {
          if (d is! Map) continue;
          if (d['isAvailable'] == false) continue;
          final udid = d['udid'];
          if (udid is! String) continue;
          result.add(DeviceInfo(
            udid: udid,
            name: (d['name'] as String?) ?? 'Unknown simulator',
            platform: DevicePlatform.ios,
            kind: DeviceKind.simulator,
            booted: d['state'] == 'Booted',
          ));
        }
      }
      return result;
    } catch (_) {
      return [];
    }
  }

  static Future<List<DeviceInfo>> listAndroidDevices({ProcessGateway? gateway}) async {
    final gw = gateway ?? ProcessGateway();
    try {
      final out = await gw.exec('adb devices -l', ignoreExitCode: true);
      final result = <DeviceInfo>[];
      // First line is the "List of devices attached" header.
      for (final raw in out.split('\n').skip(1)) {
        final line = raw.trim();
        if (line.isEmpty) continue;
        final parts = line.split(RegExp(r'\s+'));
        if (parts.length < 2 || parts[1] != 'device') {
          continue; // skip "offline"/"unauthorized"/malformed lines
        }
        final id = parts[0];
        final modelToken = parts
            .skip(2)
            .where((p) => p.startsWith('model:'))
            .firstOrNull;
        final name = modelToken != null
            ? modelToken.substring('model:'.length).replaceAll('_', ' ')
            : id;
        result.add(DeviceInfo(
          udid: id,
          name: name,
          platform: DevicePlatform.android,
          kind: id.startsWith('emulator-')
              ? DeviceKind.simulator
              : DeviceKind.physical,
          booted: true,
        ));
      }
      return result;
    } catch (_) {
      return [];
    }
  }

  /// `devicectl`'s JSON shape has changed across Xcode releases and the
  /// tool may not exist at all on older toolchains — any failure here just
  /// means no physical iOS devices are listed.
  static Future<List<DeviceInfo>> listIosPhysicalDevices({ProcessGateway? gateway}) async {
    final gw = gateway ?? ProcessGateway();
    final tmp = File(
        '${Directory.systemTemp.path}/qa_devicectl_${DateTime.now().microsecondsSinceEpoch}.json');
    try {
      await gw.exec('xcrun devicectl list devices --json-output "${tmp.path}"',
          ignoreExitCode: true);
      if (!tmp.existsSync()) return [];
      final parsed = jsonDecode(tmp.readAsStringSync());
      if (parsed is! Map) return [];
      final devices = (parsed['result'] as Map?)?['devices'] as List? ?? [];
      final result = <DeviceInfo>[];
      for (final d in devices) {
        if (d is! Map) continue;
        final udid = (d['hardwareProperties'] as Map?)?['udid'];
        if (udid is! String) continue;
        final name = (d['deviceProperties'] as Map?)?['name'] as String?;
        result.add(DeviceInfo(
          udid: udid,
          name: name ?? 'Unknown device',
          platform: DevicePlatform.ios,
          kind: DeviceKind.physical,
          booted: true,
        ));
      }
      return result;
    } catch (_) {
      return [];
    } finally {
      if (tmp.existsSync()) {
        try {
          tmp.deleteSync();
        } catch (_) {}
      }
    }
  }

  // ── Add simulator/emulator (docs/RUN_EXPERIENCE_REDESIGN.md §11) ─────────
  //
  // Listing here follows the same never-throws convention as above. The
  // create* methods below are the one exception — a user just pressed
  // "Create" and needs to see the real error (bad device type, SDK not
  // installed, ...), so those let `ProcessGateway`'s `ProcessException`
  // propagate rather than swallowing it, matching how the Doctor "Fix"
  // button already treats a user-initiated action's failure.

  static Future<List<IosDeviceType>> listIosDeviceTypes({ProcessGateway? gateway}) async {
    final gw = gateway ?? ProcessGateway();
    try {
      final out = await gw.exec('xcrun simctl list devicetypes --json',
          ignoreExitCode: true);
      final parsed = jsonDecode(out);
      if (parsed is! Map) return [];
      final list = parsed['devicetypes'] as List? ?? [];
      return list
          .whereType<Map>()
          .map((d) => (d['identifier'] as String?, d['name'] as String?))
          .where((t) => t.$1 != null && t.$2 != null)
          .map((t) => IosDeviceType(identifier: t.$1!, name: t.$2!))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<List<IosRuntime>> listIosRuntimes({ProcessGateway? gateway}) async {
    final gw = gateway ?? ProcessGateway();
    try {
      final out = await gw.exec('xcrun simctl list runtimes --json',
          ignoreExitCode: true);
      final parsed = jsonDecode(out);
      if (parsed is! Map) return [];
      final list = parsed['runtimes'] as List? ?? [];
      return list
          .whereType<Map>()
          .where((r) => r['isAvailable'] != false)
          .map((r) => (r['identifier'] as String?, r['version'] as String?))
          .where((t) => t.$1 != null && t.$2 != null)
          .map((t) => IosRuntime(identifier: t.$1!, version: t.$2!))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Creates a new simulator; returns its udid. Lets failures propagate —
  /// see the class-level note above.
  static Future<String> createIosSimulator({
    required String name,
    required String deviceTypeId,
    required String runtimeId,
    ProcessGateway? gateway,
  }) async {
    final gw = gateway ?? ProcessGateway();
    final udid = await gw.exec('xcrun simctl create "$name" $deviceTypeId $runtimeId');
    return udid.trim();
  }

  /// Parses `avdmanager list device`'s block format:
  /// ```
  /// id: 0 or "Galaxy Nexus"
  ///     Name: Galaxy Nexus
  ///     OEM : Google
  /// ---------
  /// ```
  /// Exposed separately from [listAndroidDeviceProfiles] so it's testable
  /// against recorded sample output — this dev environment has no Android
  /// SDK installed to verify the live command against.
  static List<AndroidDeviceProfile> parseAndroidDeviceProfiles(String output) {
    final result = <AndroidDeviceProfile>[];
    String? currentId;
    String? currentName;
    for (final raw in output.split('\n')) {
      final line = raw.trim();
      final idMatch = RegExp(r'^id:\s*\d+\s+or\s+"(.+)"$').firstMatch(line);
      if (idMatch != null) {
        currentId = idMatch.group(1);
        currentName = null;
        continue;
      }
      final nameMatch = RegExp(r'^Name:\s*(.+)$').firstMatch(line);
      if (nameMatch != null) currentName = nameMatch.group(1);
      if (line.startsWith('---') && currentId != null) {
        result.add(AndroidDeviceProfile(id: currentId, name: currentName ?? currentId));
        currentId = null;
        currentName = null;
      }
    }
    // A final entry with no trailing "---------" separator.
    if (currentId != null) {
      result.add(AndroidDeviceProfile(id: currentId, name: currentName ?? currentId));
    }
    return result;
  }

  static Future<List<AndroidDeviceProfile>> listAndroidDeviceProfiles({ProcessGateway? gateway}) async {
    final gw = gateway ?? ProcessGateway();
    try {
      final out = await gw.exec('avdmanager list device', ignoreExitCode: true);
      return parseAndroidDeviceProfiles(out);
    } catch (_) {
      return [];
    }
  }

  /// Parses `sdkmanager --list_installed`'s table for already-installed
  /// `system-images;...` package paths — the values `avdmanager create avd
  /// -k` needs. Exposed separately for the same testability reason as
  /// [parseAndroidDeviceProfiles].
  static List<String> parseInstalledSystemImages(String output) {
    final result = <String>[];
    for (final raw in output.split('\n')) {
      final firstCol = raw.split('|').first.trim();
      if (firstCol.startsWith('system-images;')) result.add(firstCol);
    }
    return result;
  }

  static Future<List<String>> listAndroidSystemImages({ProcessGateway? gateway}) async {
    final gw = gateway ?? ProcessGateway();
    try {
      final out = await gw.exec('sdkmanager --list_installed', ignoreExitCode: true);
      return parseInstalledSystemImages(out);
    } catch (_) {
      return [];
    }
  }

  /// Creates a new AVD; auto-answers avdmanager's "create a custom hardware
  /// profile?" prompt with "no" (the [device] profile is enough). Lets
  /// failures propagate — see the class-level note above.
  static Future<void> createAndroidAvd({
    required String name,
    required String systemImage,
    required String device,
    ProcessGateway? gateway,
  }) async {
    final gw = gateway ?? ProcessGateway();
    await gw.exec(
        'echo no | avdmanager create avd -n "$name" -k "$systemImage" -d "$device"');
  }
}
