import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_boilerplate/src/base/qa/device_probe.dart';
import 'package:flutter_boilerplate/src/models/qa/device_model.dart';
import 'package:flutter_boilerplate/src/providers/qa/run_provider.dart';
import 'package:provider/provider.dart';

/// Global (app-level) device list — Android/iOS tabs, both simulators and
/// physical devices under each. Fetched live on demand (no persisted
/// cache — a stale list is worse than a fast query, and `simctl list`/`adb
/// devices` are both sub-second), with a manual Sync/Reload button. Busy
/// status comes from [RunProvider]'s own active-runs registry, not an
/// OS-level signal — see docs/RUN_EXPERIENCE_REDESIGN.md §11.
class DevicesScreen extends StatefulWidget {
  const DevicesScreen({super.key});

  @override
  State<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends State<DevicesScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _loading = true;
  List<DeviceInfo> _android = [];
  List<DeviceInfo> _ios = [];

  // Simulator/physical filter — shared across both tabs (iOS mixes both
  // kinds into one list; Android real devices show up here too via `adb
  // devices`, not just AVDs).
  DeviceKind? _kindFilter;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _refresh();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    final results = await Future.wait([
      DeviceProbe.listAndroidDevices(),
      DeviceProbe.listIosSimulators(),
      DeviceProbe.listIosPhysicalDevices(),
    ]);
    if (!mounted) return;
    setState(() {
      _android = results[0];
      _ios = [...results[1], ...results[2]];
      _loading = false;
    });
  }

  Future<void> _addSimulator() async {
    final platform = await showDialog<DevicePlatform>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Add simulator/emulator'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, DevicePlatform.ios),
            child: const Text('iOS simulator'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, DevicePlatform.android),
            child: const Text('Android emulator (AVD)'),
          ),
        ],
      ),
    );
    if (platform == null || !mounted) return;
    bool? created;
    if (platform == DevicePlatform.ios) {
      created = await showDialog<bool>(
        context: context,
        builder: (_) => const _AddIosSimulatorDialog(),
      );
    } else {
      created = await showDialog<bool>(
        context: context,
        builder: (_) => const _AddAndroidAvdDialog(),
      );
    }
    if (created == true) await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: cs.surface,
        elevation: 0,
        title: const Text('Devices'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Android'),
            Tab(text: 'iOS'),
          ],
        ),
        actions: [
          Tooltip(
            message: 'Add simulator/emulator',
            child: IconButton(
              icon: const Icon(Icons.add_circle_outline),
              onPressed: _addSimulator,
            ),
          ),
          Tooltip(
            message: 'Sync/Reload',
            child: IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _loading ? null : _refresh,
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('All'),
                  selected: _kindFilter == null,
                  onSelected: (_) => setState(() => _kindFilter = null),
                ),
                ChoiceChip(
                  label: const Text('Simulators'),
                  selected: _kindFilter == DeviceKind.simulator,
                  onSelected: (_) =>
                      setState(() => _kindFilter = DeviceKind.simulator),
                ),
                ChoiceChip(
                  label: const Text('Physical devices'),
                  selected: _kindFilter == DeviceKind.physical,
                  onSelected: (_) =>
                      setState(() => _kindFilter = DeviceKind.physical),
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(
                    controller: _tabController,
                    children: [
                      _DeviceList(devices: _android, kindFilter: _kindFilter),
                      _DeviceList(devices: _ios, kindFilter: _kindFilter),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _DeviceList extends StatelessWidget {
  final List<DeviceInfo> devices;
  final DeviceKind? kindFilter;
  const _DeviceList({required this.devices, this.kindFilter});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final filtered = kindFilter == null
        ? devices
        : devices.where((d) => d.kind == kindFilter).toList();
    if (filtered.isEmpty) {
      return Center(
        child: Text(
          devices.isEmpty ? 'No devices found' : 'No devices match this filter',
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
        ),
      );
    }
    return Consumer<RunProvider>(
      builder: (context, run, _) => ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: filtered.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final d = filtered[index];
          final busy = run.isDeviceBusy(d.udid);
          return ListTile(
            leading: Icon(
              d.kind == DeviceKind.simulator
                  ? Icons.smartphone
                  : Icons.phone_iphone,
              color: busy
                  ? cs.error
                  : (d.booted ? cs.primary : cs.onSurfaceVariant),
            ),
            title: Text(d.name),
            subtitle: Text(
              '${d.kind == DeviceKind.simulator ? 'Simulator' : 'Physical device'}'
              ' · ${d.udid}',
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
              overflow: TextOverflow.ellipsis,
            ),
            trailing: Chip(
              label: Text(busy ? 'Busy' : (d.booted ? 'Idle' : 'Shutdown')),
              backgroundColor: busy
                  ? cs.errorContainer
                  : (d.booted
                        ? cs.primaryContainer
                        : cs.surfaceContainerHighest),
              visualDensity: VisualDensity.compact,
            ),
          );
        },
      ),
    );
  }
}

// ── Add iOS simulator ──────────────────────────────────────────────────────

class _AddIosSimulatorDialog extends StatefulWidget {
  const _AddIosSimulatorDialog();

  @override
  State<_AddIosSimulatorDialog> createState() => _AddIosSimulatorDialogState();
}

class _AddIosSimulatorDialogState extends State<_AddIosSimulatorDialog> {
  final _nameCtrl = TextEditingController();
  List<IosDeviceType> _deviceTypes = [];
  List<IosRuntime> _runtimes = [];
  IosDeviceType? _selectedType;
  IosRuntime? _selectedRuntime;
  bool _loading = true;
  bool _creating = false;
  String? _error;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  // `simctl` occasionally hangs (cold Xcode cache, a stuck simulator daemon)
  // — without a timeout, that leaves this dialog spinning forever with no
  // way out except force-quitting the app. A bounded wait + a visible
  // error/retry beats a silent hang.
  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final results = await Future.wait([
        DeviceProbe.listIosDeviceTypes(),
        DeviceProbe.listIosRuntimes(),
      ]).timeout(const Duration(seconds: 20));
      if (!mounted) return;
      setState(() {
        _deviceTypes = results[0] as List<IosDeviceType>;
        _runtimes = results[1] as List<IosRuntime>;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e is TimeoutException
            ? 'Timed out waiting for simctl — it may be stuck. Try again.'
            : 'Could not load device types/runtimes: $e';
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final type = _selectedType;
    final runtime = _selectedRuntime;
    final name = _nameCtrl.text.trim();
    if (type == null || runtime == null || name.isEmpty) return;
    setState(() {
      _creating = true;
      _error = null;
    });
    try {
      await DeviceProbe.createIosSimulator(
        name: name,
        deviceTypeId: type.identifier,
        runtimeId: runtime.identifier,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add iOS simulator'),
      content: _loading
          ? const SizedBox(
              width: 320,
              height: 80,
              child: Center(child: CircularProgressIndicator()),
            )
          : _loadError != null
          ? SizedBox(
              width: 320,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _loadError!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(onPressed: _load, child: const Text('Retry')),
                ],
              ),
            )
          : SizedBox(
              width: 360,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _nameCtrl,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: 'Name',
                      border: OutlineInputBorder(),
                      hintText: 'My iPhone 17 Pro',
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<IosDeviceType>(
                    initialValue: _selectedType,
                    decoration: const InputDecoration(
                      labelText: 'Device type',
                      border: OutlineInputBorder(),
                    ),
                    items: _deviceTypes
                        .map(
                          (t) =>
                              DropdownMenuItem(value: t, child: Text(t.name)),
                        )
                        .toList(),
                    onChanged: (v) => setState(() => _selectedType = v),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<IosRuntime>(
                    initialValue: _selectedRuntime,
                    decoration: const InputDecoration(
                      labelText: 'OS version',
                      border: OutlineInputBorder(),
                    ),
                    items: _runtimes
                        .map(
                          (r) => DropdownMenuItem(
                            value: r,
                            child: Text('iOS ${r.version}'),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setState(() => _selectedRuntime = v),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _creating ? null : _create,
          child: _creating
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Create'),
        ),
      ],
    );
  }
}

// ── Add Android AVD ────────────────────────────────────────────────────────

class _AddAndroidAvdDialog extends StatefulWidget {
  const _AddAndroidAvdDialog();

  @override
  State<_AddAndroidAvdDialog> createState() => _AddAndroidAvdDialogState();
}

class _AddAndroidAvdDialogState extends State<_AddAndroidAvdDialog> {
  final _nameCtrl = TextEditingController();
  List<AndroidDeviceProfile> _profiles = [];
  List<String> _systemImages = [];
  AndroidDeviceProfile? _selectedProfile;
  String? _selectedImage;
  bool _loading = true;
  bool _creating = false;
  String? _error;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  // avdmanager/sdkmanager are JVM tools — slow to cold-start, and
  // sdkmanager can sit forever waiting on stdin for a license prompt that
  // never comes. A bounded wait + a visible error/retry beats a silent hang.
  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final results = await Future.wait([
        DeviceProbe.listAndroidDeviceProfiles(),
        DeviceProbe.listAndroidSystemImages(),
      ]).timeout(const Duration(seconds: 20));
      if (!mounted) return;
      setState(() {
        _profiles = results[0] as List<AndroidDeviceProfile>;
        _systemImages = results[1] as List<String>;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e is TimeoutException
            ? 'Timed out waiting for avdmanager/sdkmanager — they may be '
                  'stuck (e.g. on a license prompt). Try again.'
            : 'Could not load device profiles/system images: $e';
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final profile = _selectedProfile;
    final image = _selectedImage;
    final name = _nameCtrl.text.trim();
    if (profile == null || image == null || name.isEmpty) return;
    setState(() {
      _creating = true;
      _error = null;
    });
    try {
      await DeviceProbe.createAndroidAvd(
        name: name,
        systemImage: image,
        device: profile.id,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final noSdk = !_loading && (_profiles.isEmpty || _systemImages.isEmpty);
    return AlertDialog(
      title: const Text('Add Android emulator'),
      content: _loading
          ? const SizedBox(
              width: 320,
              height: 80,
              child: Center(child: CircularProgressIndicator()),
            )
          : _loadError != null
          ? SizedBox(
              width: 320,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _loadError!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(onPressed: _load, child: const Text('Retry')),
                ],
              ),
            )
          : noSdk
          ? const SizedBox(
              width: 360,
              child: Text(
                'No Android SDK device profiles / installed system images '
                'found — install the Android SDK command-line tools '
                '(avdmanager, sdkmanager) and at least one system image '
                'first, then try again.',
              ),
            )
          : SizedBox(
              width: 360,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _nameCtrl,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: 'AVD name',
                      border: OutlineInputBorder(),
                      hintText: 'My_Pixel_7',
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<AndroidDeviceProfile>(
                    initialValue: _selectedProfile,
                    decoration: const InputDecoration(
                      labelText: 'Device profile',
                      border: OutlineInputBorder(),
                    ),
                    items: _profiles
                        .map(
                          (p) =>
                              DropdownMenuItem(value: p, child: Text(p.name)),
                        )
                        .toList(),
                    onChanged: (v) => setState(() => _selectedProfile = v),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _selectedImage,
                    decoration: const InputDecoration(
                      labelText: 'System image',
                      border: OutlineInputBorder(),
                    ),
                    items: _systemImages
                        .map(
                          (img) => DropdownMenuItem(
                            value: img,
                            child: Text(img, overflow: TextOverflow.ellipsis),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setState(() => _selectedImage = v),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        if (!noSdk)
          FilledButton(
            onPressed: _creating ? null : _create,
            child: _creating
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Create'),
          ),
      ],
    );
  }
}
