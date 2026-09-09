import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_boilerplate/src/base/dependencyinjection/locator.dart';
import 'package:flutter_boilerplate/src/base/qa/run_dispatcher.dart';
import 'package:flutter_boilerplate/src/base/utils/constants/navigation_route_constants.dart';
import 'package:flutter_boilerplate/src/base/utils/navigation_utils.dart';
import 'package:flutter_boilerplate/src/controllers/qa/project_controller.dart';
import 'package:flutter_boilerplate/src/models/qa/device_model.dart';
import 'package:flutter_boilerplate/src/models/qa/project_model.dart';
import 'package:flutter_boilerplate/src/providers/qa/project_provider.dart';
import 'package:flutter_boilerplate/src/providers/qa/run_provider.dart';
import 'package:flutter_boilerplate/src/ui/qa/runner/run_picker.dart';
import 'package:provider/provider.dart';

/// Route arguments for [ScriptsScreen].
class ScriptsArgs {
  final ProjectConfig project;
  final String surfaceId;
  const ScriptsArgs({required this.project, required this.surfaceId});
}

/// CRUD screen for a surface's leaf test scripts — file paths (mobile) or
/// `package.json` script names (web) — plus the Run button that dispatches
/// them (see docs/RUN_EXPERIENCE_REDESIGN.md §4/§6). Whether pull/build run
/// first is maintained on the surface itself ([SurfaceConfig.runPull]/
/// [SurfaceConfig.runBuild]), not chosen per click any more.
class ScriptsScreen extends StatefulWidget {
  final ScriptsArgs args;
  const ScriptsScreen({super.key, required this.args});

  @override
  State<ScriptsScreen> createState() => _ScriptsScreenState();
}

class _ScriptsScreenState extends State<ScriptsScreen> {
  late ProjectConfig _project;
  late SurfaceConfig _surface;
  bool _busy = false;
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // At least one "test"-tagged command assigned — gates the Run buttons,
  // same effect as the deleted runnerCommandsComplete used to.
  bool get _hasTestCommand => _surface.commandIds
      .map((id) => _project.commands.where((c) => c.id == id).firstOrNull)
      .whereType<CommandConfig>()
      .any((c) => c.hasTag('test'));

  @override
  void initState() {
    super.initState();
    _project = widget.args.project;
    _surface = _project.surfaceById(widget.args.surfaceId)!;
    _searchCtrl.addListener(() => setState(() => _query = _searchCtrl.text));
  }

  Future<void> _togglePin(ScriptEntry s) async {
    final scripts = _surface.scripts
        .map((e) => e.id == s.id
            ? e.copyWith(
                pinnedAt: e.isPinned ? null : DateTime.now(),
                clearPinnedAt: e.isPinned,
              )
            : e)
        .toList();
    await _persist(scripts);
  }

  /// Reorders within one section (pinned or the rest) — the other section's
  /// entries and relative order are left untouched, same "reorder just this
  /// subsequence" approach as [SurfaceCommandManagerScreen]'s command reorder.
  Future<void> _reorderSection(
      List<ScriptEntry> section, int oldIndex, int newIndex) async {
    if (newIndex > oldIndex) newIndex--;
    final reordered = List<ScriptEntry>.of(section);
    final moved = reordered.removeAt(oldIndex);
    reordered.insert(newIndex, moved);

    final sectionIds = section.map((s) => s.id).toSet();
    final full = List<ScriptEntry>.of(_surface.scripts);
    final positions = [
      for (var i = 0; i < full.length; i++)
        if (sectionIds.contains(full[i].id)) i,
    ];
    for (var i = 0; i < positions.length; i++) {
      full[positions[i]] = reordered[i];
    }
    await _persist(full);
  }

  Future<void> _persist(List<ScriptEntry> scripts) async {
    final updated = await context.read<ProjectProvider>().upsertSurface(
          project: _project,
          surface: _surface.copyWith(scripts: scripts),
        );
    if (!mounted) return;
    setState(() {
      _project = updated;
      _surface = updated.surfaceById(_surface.id)!;
    });
  }

  ({List<ScriptEntry> scripts, int added}) _merge(
    Iterable<String> paths, {
    String? singleCustomName,
  }) =>
      ScriptEntry.mergeUnique(_surface.scripts, paths, customName: singleCustomName);

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  // ── Mobile: add file(s) / import folder ──────────────────────────────────

  Future<void> _addFiles() async {
    setState(() => _busy = true);
    try {
      final paths = await locator<ProjectController>()
          .pickFiles(dialogTitle: 'Select script file(s)');
      if (paths.isEmpty) return;
      final result = _merge(paths);
      await _persist(result.scripts);
      _toast(result.added == 0
          ? 'Already added.'
          : 'Added ${result.added} script${result.added == 1 ? '' : 's'}.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _importFromFolder() async {
    setState(() => _busy = true);
    try {
      final controller = locator<ProjectController>();
      final testRepo = _project.repos['mobile_test'];
      final suggested = testRepo != null
          ? '${testRepo.absPath(_project.projectsRoot)}/test/specs'
          : null;
      final folder = await controller.pickFolder(
        dialogTitle: 'Select a folder to import scripts from',
        initialDirectory: suggested,
      );
      if (folder == null) return;
      final files = controller.collectFilesUnder(folder);
      if (files.isEmpty) {
        _toast('No files found in that folder.');
        return;
      }
      final result = _merge(files);
      await _persist(result.scripts);
      final skipped = files.length - result.added;
      _toast(result.added == 0
          ? 'All ${files.length} file(s) were already added.'
          : 'Added ${result.added} script${result.added == 1 ? '' : 's'}'
              '${skipped > 0 ? ' ($skipped already added, skipped)' : ''}.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ── Web: add one script / import from package.json ──────────────────────

  Future<void> _addManualScript() async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add script'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            labelText: _surface.isWeb ? 'package.json script name' : 'Path',
            hintText: _surface.isWeb ? 'test:smoke' : '/path/to/script',
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (name == null || name.isEmpty || !mounted) return;
    if (_surface.scripts.any((s) => s.path == name)) {
      _toast('Already added.');
      return;
    }
    await _persist(_merge([name]).scripts);
  }

  Future<void> _importFromPackageJson() async {
    setState(() => _busy = true);
    try {
      final webRepo = _project.repos['web'];
      if (webRepo == null) {
        _toast('No "web" repo configured on this project.');
        return;
      }
      final packageJsonPath =
          '${webRepo.absPath(_project.projectsRoot)}/package.json';
      final scripts = locator<ProjectController>()
          .parsePackageJsonScripts(packageJsonPath);
      if (scripts == null || scripts.isEmpty) {
        _toast('No "scripts" found in $packageJsonPath.');
        return;
      }
      final result = _merge(scripts.keys);
      await _persist(result.scripts);
      final skipped = scripts.length - result.added;
      _toast(result.added == 0
          ? 'All ${scripts.length} script(s) were already added.'
          : 'Added ${result.added} script${result.added == 1 ? '' : 's'}'
              '${skipped > 0 ? ' ($skipped already added, skipped)' : ''}.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ── Rename / delete ───────────────────────────────────────────────────────

  Future<void> _rename(ScriptEntry script) async {
    final ctrl = TextEditingController(text: script.customName ?? '');
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename script'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            labelText: 'Display name',
            helperText: 'Leave blank to use the file/script name.',
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (name == null || !mounted) return;
    final scripts = _surface.scripts
        .map((s) => s.id == script.id
            ? s.copyWith(customName: name, clearCustomName: name.isEmpty)
            : s)
        .toList();
    await _persist(scripts);
  }

  Future<void> _delete(ScriptEntry script) => _persist(
        _surface.scripts.where((s) => s.id != script.id).toList(),
      );

  // ── Run ───────────────────────────────────────────────────────────────────

  /// (mobile only: Platform → Simulator/Physical → Device) → dispatch, via
  /// the shared [RunPicker] flow (also used by Recent runs' Re-run action).
  /// Any step cancelled (returns null) aborts the whole flow. Environment is
  /// no longer asked here — it's static on [_surface].
  ///
  /// [RunDispatcher.dispatch] internally `await`s [RunProvider.start], which
  /// doesn't resolve until the *entire* pipeline finishes — so awaiting it
  /// here before popping meant nothing visibly happened until the run was
  /// already over. Instead: a quick synchronous check that a runner command
  /// even exists for this combo (so a real misconfiguration still surfaces
  /// immediately), then fire the dispatch without waiting for it and pop
  /// right away — the project screen's `RunPanel` picks up live progress
  /// reactively via `Consumer<RunProvider>` from that point on.
  Future<void> _startRun(ScriptEntry script) async {
    final picked = await RunPicker.pick(context, project: _project, surface: _surface);
    if (picked == null || !mounted) return;

    final targetKey = picked.deviceKind == null
        ? null
        : (picked.deviceKind == DeviceKind.physical ? 'device' : 'simulator');
    if (_project.testCommandFor(_surface.id, target: targetKey) == null) {
      _toast('Could not start — runner command missing for this combination.');
      return;
    }

    unawaited(RunDispatcher().dispatch(
      runProvider: context.read<RunProvider>(),
      project: _project,
      surface: _surface,
      script: script,
      platform: picked.platform,
      deviceKind: picked.deviceKind,
      deviceUdid: picked.deviceUdid,
    ));
    Navigator.of(context).pop();
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final query = _query.trim().toLowerCase();
    final matches = _surface.scripts.where((s) =>
        query.isEmpty ||
        s.displayName.toLowerCase().contains(query) ||
        s.path.toLowerCase().contains(query));
    final pinned = matches.where((s) => s.isPinned).toList();
    final rest = matches.where((s) => !s.isPinned).toList();
    final isSearching = query.isNotEmpty;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: cs.surface,
        elevation: 0,
        title: Text('Scripts — ${_surface.name}'),
        actions: [
          // Firing a run here now pops straight back (see _startRun) instead
          // of staying on this screen — Active Runs is the way to check on
          // one from here without needing to backtrack through the project.
          Consumer<RunProvider>(
            builder: (context, run, _) {
              final count = run.activeRuns.length;
              return Tooltip(
                message: 'Active runs',
                child: Badge(
                  label: Text('$count'),
                  isLabelVisible: count > 0,
                  child: IconButton(
                    icon: const Icon(Icons.pending_actions_outlined),
                    onPressed: () =>
                        locator<NavigationUtils>().push(routeActiveRuns),
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildActions(),
                if (_surface.scripts.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: _searchCtrl,
                    decoration: InputDecoration(
                      isDense: true,
                      prefixIcon: const Icon(Icons.search, size: 20),
                      hintText: 'Search scripts…',
                      border: const OutlineInputBorder(),
                      suffixIcon: isSearching
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: _searchCtrl.clear,
                            )
                          : null,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: _surface.scripts.isEmpty
                ? _buildEmpty()
                : pinned.isEmpty && rest.isEmpty
                    ? Center(
                        child: Text(
                          'No scripts match "$_query".',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: cs.onSurfaceVariant),
                        ),
                      )
                    : ListView(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        children: [
                          if (pinned.isNotEmpty) ...[
                            _sectionLabel('📌 Pinned', isSearching),
                            _buildSection(pinned, isSearching),
                            const SizedBox(height: 16),
                          ],
                          if (rest.isNotEmpty) ...[
                            if (pinned.isNotEmpty)
                              _sectionLabel('All scripts', isSearching),
                            _buildSection(rest, isSearching),
                          ],
                        ],
                      ),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text, bool isSearching) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(
          text,
          style: Theme.of(context)
              .textTheme
              .labelMedium
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      );

  /// A search-active section falls back to a plain (non-reorderable) list —
  /// same reasoning used everywhere else in this app: reordering indices
  /// into a filtered view would scramble the real unfiltered order.
  Widget _buildSection(List<ScriptEntry> section, bool isSearching) {
    if (isSearching) {
      return Column(
        children: section.map((s) => _scriptTile(s, showDragHandle: false)).toList(),
      );
    }
    return ReorderableListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      // Just one drag affordance (the leading handle below, long-press then
      // drag) — the framework's own default handle would otherwise also
      // show up at the trailing edge on desktop, giving two ways to grab
      // the same row.
      buildDefaultDragHandles: false,
      itemCount: section.length,
      onReorder: (o, n) => _reorderSection(section, o, n),
      itemBuilder: (context, index) =>
          _scriptTile(section[index], showDragHandle: true, dragIndex: index),
    );
  }

  Widget _scriptTile(ScriptEntry s, {required bool showDragHandle, int? dragIndex}) {
    final cs = Theme.of(context).colorScheme;
    final leading = showDragHandle
        ? const Icon(Icons.drag_handle, color: Colors.grey)
        : const Icon(Icons.description_outlined);
    return ListTile(
      key: ValueKey(s.id),
      leading: showDragHandle
          ? ReorderableDelayedDragStartListener(index: dragIndex!, child: leading)
          : leading,
      title: Text(s.displayName),
      subtitle: Text(
        s.path,
        style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_hasTestCommand)
            IconButton(
              tooltip: 'Run',
              icon: const Icon(Icons.play_circle_outline, size: 20),
              onPressed: () => _startRun(s),
            )
          else
            Tooltip(
              message: 'Set this surface\'s runner '
                  'commands first (see the project screen).',
              child: Icon(Icons.play_circle_outline,
                  size: 20, color: cs.onSurfaceVariant),
            ),
          IconButton(
            tooltip: s.isPinned ? 'Unpin' : 'Pin',
            icon: Icon(s.isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                size: 18, color: s.isPinned ? cs.primary : null),
            onPressed: () => _togglePin(s),
          ),
          IconButton(
            tooltip: 'Rename',
            icon: const Icon(Icons.edit_outlined, size: 18),
            onPressed: () => _rename(s),
          ),
          IconButton(
            tooltip: 'Delete',
            icon: Icon(Icons.delete_outline, size: 18, color: cs.error),
            onPressed: () => _delete(s),
          ),
        ],
      ),
    );
  }

  Widget _buildActions() {
    if (_busy) {
      return const Center(
        child: SizedBox(
            width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    final buttons = <Widget>[];
    if (_surface.isMobile) {
      buttons.addAll([
        OutlinedButton.icon(
          onPressed: _addFiles,
          icon: const Icon(Icons.note_add_outlined, size: 18),
          label: const Text('Add file(s)'),
        ),
        OutlinedButton.icon(
          onPressed: _importFromFolder,
          icon: const Icon(Icons.drive_folder_upload_outlined, size: 18),
          label: const Text('Import from folder'),
        ),
      ]);
    } else if (_surface.isWeb) {
      buttons.addAll([
        OutlinedButton.icon(
          onPressed: _addManualScript,
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Add script'),
        ),
        OutlinedButton.icon(
          onPressed: _importFromPackageJson,
          icon: const Icon(Icons.drive_folder_upload_outlined, size: 18),
          label: const Text('Import from package.json'),
        ),
      ]);
    } else {
      buttons.add(
        OutlinedButton.icon(
          onPressed: _addManualScript,
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Add script'),
        ),
      );
    }
    return Wrap(spacing: 10, runSpacing: 10, children: buttons);
  }

  Widget _buildEmpty() {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.description_outlined, size: 48, color: cs.onSurfaceVariant),
          const SizedBox(height: 16),
          const Text('No scripts yet'),
          const SizedBox(height: 8),
          Text(
            _surface.isMobile
                ? 'Add a file, or import every file from a folder at once.'
                : _surface.isWeb
                    ? 'Add one, or import every script from package.json at once.'
                    : 'Add a script to get started.',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
