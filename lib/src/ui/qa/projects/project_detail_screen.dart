import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_boilerplate/src/base/dependencyinjection/locator.dart';
import 'package:flutter_boilerplate/src/base/qa/bundle_id_detector.dart';
import 'package:flutter_boilerplate/src/base/qa/process_gateway.dart';
import 'package:flutter_boilerplate/src/base/qa/report_archive_store.dart';
import 'package:flutter_boilerplate/src/base/qa/report_opener.dart';
import 'package:flutter_boilerplate/src/base/utils/constants/navigation_route_constants.dart';
import 'package:flutter_boilerplate/src/base/utils/navigation_utils.dart';
import 'package:flutter_boilerplate/src/controllers/qa/doctor_controller.dart';
import 'package:flutter_boilerplate/src/models/qa/doctor_model.dart';
import 'package:flutter_boilerplate/src/models/qa/project_model.dart';
import 'package:flutter_boilerplate/src/models/qa/report_archive_model.dart';
import 'package:flutter_boilerplate/src/providers/qa/project_provider.dart';
import 'package:flutter_boilerplate/src/providers/qa/run_provider.dart';
import 'package:flutter_boilerplate/src/ui/qa/commands/command_edit_screen.dart';
import 'package:flutter_boilerplate/src/ui/qa/commands/command_library_screen.dart';
import 'package:flutter_boilerplate/src/ui/qa/commands/surface_command_manager_screen.dart';
import 'package:flutter_boilerplate/src/ui/qa/reports/reports_screen.dart';
import 'package:flutter_boilerplate/src/ui/qa/runner/run_panel.dart';
import 'package:flutter_boilerplate/src/ui/qa/runner/run_picker.dart';
import 'package:flutter_boilerplate/src/ui/qa/scripts/scripts_screen.dart';
import 'package:provider/provider.dart';

/// Route arguments for [ProjectDetailScreen].
class ProjectDetailArgs {
  final ProjectConfig project;
  const ProjectDetailArgs({required this.project});
}

/// The main run screen for a [ProjectConfig].
///
/// Shows each surface as a card (instead of a tab) with:
///   • Doctor pre-flight indicator
///   • Expandable run controls (Sync / Build toggles, spec field, Run button)
///   • Quick-run button on the collapsed card
///   • ⋮ menu: Edit surface, Edit commands, Delete surface
class ProjectDetailScreen extends StatefulWidget {
  final ProjectDetailArgs args;
  const ProjectDetailScreen({super.key, required this.args});

  @override
  State<ProjectDetailScreen> createState() => _ProjectDetailScreenState();
}

class _ProjectDetailScreenState extends State<ProjectDetailScreen> {
  late ProjectConfig _project;

  // Per-surface state (indexed by surfaceId)
  final Map<String, bool> _expanded = {};
  final Map<String, DoctorResult?> _doctorResults = {};
  final Map<String, bool> _doctorRunning = {};

  @override
  void initState() {
    super.initState();
    _project = widget.args.project;
    _initSurfaceMaps();
  }

  void _initSurfaceMaps() {
    for (final s in _project.surfaces) {
      _expanded.putIfAbsent(s.id, () => false);
      _doctorResults.putIfAbsent(s.id, () => null);
      _doctorRunning.putIfAbsent(s.id, () => false);
    }
  }

  // ── Doctor ────────────────────────────────────────────────────────────────

  Future<void> _runDoctor(String surfaceId) async {
    setState(() => _doctorRunning[surfaceId] = true);
    try {
      // Doctor's iOS checks just need *a* target to check against — no
      // separate picker for this any more (the actual run's own device
      // picker, in the Scripts screen, is the one that matters).
      final result = await locator<DoctorController>().runDoctor(
        recipe: _project.simpleRecipeForSurface(surfaceId),
        profile: _project.toProfile(),
        manifest: _project.toManifestModel(),
      );
      if (mounted) setState(() => _doctorResults[surfaceId] = result);
    } finally {
      if (mounted) setState(() => _doctorRunning[surfaceId] = false);
    }
  }

  // ── Refresh project ───────────────────────────────────────────────────────

  void _refreshProject() {
    final provider = context.read<ProjectProvider>();
    final updated = provider.projects.firstWhere(
      (p) => p.id == _project.id,
      orElse: () => _project,
    );
    setState(() {
      _project = updated;
      _initSurfaceMaps(); // init state for any new surfaces
    });
  }

  // ── Add surface dialog ────────────────────────────────────────────────────

  Future<void> _showAddSurfaceDialog() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => _AddSurfaceDialog(
        existingSurfaceIds: _project.surfaces.map((s) => s.id).toSet(),
        onAdd: (surface) async {
          final updatedProject = _project.copyWith(
            surfaces: [..._project.surfaces, surface],
          );
          await context.read<ProjectProvider>().updateProject(updatedProject);
          _refreshProject();
        },
      ),
    );
  }

  // ── Edit surface dialog ───────────────────────────────────────────────────

  Future<void> _showEditSurfaceDialog(SurfaceConfig surface) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => _EditSurfaceDialog(
        surface: surface,
        onSave: (updated) async {
          await context.read<ProjectProvider>().upsertSurface(
            project: _project,
            surface: updated,
          );
          _refreshProject();
        },
      ),
    );
  }

  // ── Duplicate surface ─────────────────────────────────────────────────────

  /// Clone [surface] under a fresh id — same icon, same command assignments
  /// (surfaces reference pool commands by id, so this is just sharing, not
  /// copying command data — editing a shared command still updates both).
  /// The *name* is what the user actually reads in the UI, so that's what
  /// gets made unique ("X (copy)", "X (copy 2)", ...) — the id just tags
  /// along, derived the same way, rather than the other way around.
  Future<void> _duplicateSurface(SurfaceConfig surface) async {
    final existingNames = _project.surfaces.map((s) => s.name).toSet();
    var newName = '${surface.name} (copy)';
    var n = 2;
    while (existingNames.contains(newName)) {
      newName = '${surface.name} (copy $n)';
      n++;
    }

    final existingIds = _project.surfaces.map((s) => s.id).toSet();
    var newId = '${surface.id}_copy';
    var i = 2;
    while (existingIds.contains(newId)) {
      newId = '${surface.id}_copy$i';
      i++;
    }

    final copy = surface.copyWith(id: newId, name: newName);
    await context.read<ProjectProvider>().upsertSurface(
      project: _project,
      surface: copy,
    );
    _refreshProject();
  }

  // ── Delete surface ────────────────────────────────────────────────────────

  Future<void> _deleteSurface(SurfaceConfig surface) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete surface?'),
        content: Text(
          '"${surface.icon} ${surface.name}" will be removed. '
          'Commands assigned only to this surface stay in the project library.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await context.read<ProjectProvider>().removeSurface(
      project: _project,
      surfaceId: surface.id,
    );
    _refreshProject();
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  Widget _surfaceList(List<SurfaceConfig> surfaces) {
    return surfaces.isEmpty
        ? _buildEmptySurfaces()
        : ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: surfaces.length,
            itemBuilder: (context, index) =>
                _surfaceCardFor(surfaces[index]),
          );
  }

  @override
  Widget build(BuildContext context) {
    final surfaces = _project.surfaces;
    // Tab per distinct environment (dev/stage/...) across the project's
    // surfaces, plus "All" — only shown once there's actually more than one
    // environment to split by, so a project with no environments set keeps
    // its old flat list.
    final environments = surfaces
        .map((s) => s.environmentId)
        .whereType<String>()
        .toSet()
        .toList()
      ..sort();

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.surface,
        elevation: 0,
        title: Text(
          _project.name,
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
        ),
        actions: [
          // Active runs (global — see docs/RUN_EXPERIENCE_REDESIGN.md §9)
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
          // Command Library (project-level)
          Tooltip(
            message: 'Command Library',
            child: IconButton(
              icon: const Icon(Icons.tune_outlined),
              onPressed: () async {
                await locator<NavigationUtils>().push(
                  routeCommandLibrary,
                  arguments: CommandLibraryArgs(project: _project),
                );
                _refreshProject();
              },
            ),
          ),
          // Add surface
          Tooltip(
            message: 'Add surface',
            child: IconButton(
              icon: const Icon(Icons.add_box_outlined),
              onPressed: _showAddSurfaceDialog,
            ),
          ),
          // Edit project settings
          Tooltip(
            message: 'Edit project',
            child: IconButton(
              icon: const Icon(Icons.settings_outlined),
              onPressed: () async {
                await locator<NavigationUtils>().push(
                  routeEditProject,
                  arguments: _project,
                );
                _refreshProject();
              },
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: environments.length > 1
                ? DefaultTabController(
                    length: environments.length + 1,
                    child: Column(
                      children: [
                        TabBar(
                          isScrollable: true,
                          tabAlignment: TabAlignment.start,
                          tabs: [
                            const Tab(text: 'All'),
                            ...environments.map((e) => Tab(text: e)),
                          ],
                        ),
                        Expanded(
                          child: TabBarView(
                            children: [
                              _surfaceList(surfaces),
                              ...environments.map((e) => _surfaceList(surfaces
                                  .where((s) => s.environmentId == e)
                                  .toList())),
                            ],
                          ),
                        ),
                      ],
                    ),
                  )
                : _surfaceList(surfaces),
          ),
          // Live run panel — shared across all surfaces. RunPanel's own
          // build() is a Column with an Expanded child (the scrolling log),
          // so it needs bounded height from its parent — bare in this outer
          // Column it got unbounded height, which crashes ('hasSize'
          // assertion) the moment a run actually starts and RunPanel stops
          // returning its idle SizedBox.shrink(). HomeScreen already wraps
          // it the same way (Expanded, gated on idle) — mirrored here.
          Consumer<RunProvider>(
            builder: (context, run, _) => run.isIdle
                ? const SizedBox.shrink()
                // Minimized: RunPanel renders just its (small, bounded)
                // header, so it goes in bare — Expanded would otherwise
                // still force it to fill the flex share with empty space,
                // defeating the point of minimizing (see RunProvider.minimized).
                : run.minimized
                    ? const RunPanel()
                    : const Expanded(flex: 3, child: RunPanel()),
          ),
        ],
      ),
    );
  }

  Widget _surfaceCardFor(SurfaceConfig surface) {
    return _SurfaceCard(
      key: ValueKey(surface.id),
      surface: surface,
      project: _project,
      isExpanded: _expanded[surface.id] ?? false,
      doctorResult: _doctorResults[surface.id],
      doctorRunning: _doctorRunning[surface.id] ?? false,
      onToggleExpand: () => setState(
        () => _expanded[surface.id] = !(_expanded[surface.id] ?? false),
      ),
      onRunDoctor: () => _runDoctor(surface.id),
      onEditSurface: () => _showEditSurfaceDialog(surface),
      onDuplicateSurface: () => _duplicateSurface(surface),
      onDeleteSurface: () => _deleteSurface(surface),
      onManageCommands: (stageTags, title) async {
        await locator<NavigationUtils>().push(
          routeSurfaceCommandManager,
          arguments: SurfaceCommandManagerArgs(
            project: _project,
            surfaceId: surface.id,
            stageTags: stageTags,
            title: title,
          ),
        );
        _refreshProject();
      },
      onEditScripts: () async {
        await locator<NavigationUtils>().push(
          routeScripts,
          arguments: ScriptsArgs(project: _project, surfaceId: surface.id),
        );
        _refreshProject();
      },
      onOpenReports: () async {
        await locator<NavigationUtils>().push(
          routeReports,
          arguments: ReportsArgs(project: _project, surfaceId: surface.id),
        );
        _refreshProject();
      },
      onSurfaceChanged: _refreshProject,
    );
  }

  Widget _buildEmptySurfaces() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.layers_outlined, size: 48),
          const SizedBox(height: 16),
          const Text('No surfaces configured'),
          const SizedBox(height: 8),
          Text(
            'Tap ➕ in the toolbar to add a surface.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _showAddSurfaceDialog,
            icon: const Icon(Icons.add),
            label: const Text('Add surface'),
          ),
        ],
      ),
    );
  }
}

// ── Add Surface Dialog ────────────────────────────────────────────────────────

/// A surface is now a custom, user-named env+platform combo (e.g. "Android
/// Dev", "Android Stage") — Platform is the one fixed choice left (it drives
/// repo role + build logic); Name/Environment/Icon are all free-form. `id`
/// is auto-slugified from platform+environment (or name, if no environment)
/// and de-duped against [existingSurfaceIds] — never hand-typed, so it can't
/// collide or contain invalid characters.
class _AddSurfaceDialog extends StatefulWidget {
  final Set<String> existingSurfaceIds;
  final Future<void> Function(SurfaceConfig) onAdd;

  const _AddSurfaceDialog({
    required this.existingSurfaceIds,
    required this.onAdd,
  });

  @override
  State<_AddSurfaceDialog> createState() => _AddSurfaceDialogState();
}

class _AddSurfaceDialogState extends State<_AddSurfaceDialog> {
  static const _kPlatforms = [
    (type: 'android', label: 'Android', icon: '🤖'),
    (type: 'ios', label: 'iOS', icon: '🍎'),
    (type: 'web', label: 'Web', icon: '🌐'),
  ];

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _envCtrl;
  late final TextEditingController _iconCtrl;
  String _platformType = _kPlatforms.first.type;
  bool _iconTouched = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController();
    _envCtrl = TextEditingController();
    _iconCtrl = TextEditingController(text: _kPlatforms.first.icon);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _envCtrl.dispose();
    _iconCtrl.dispose();
    super.dispose();
  }

  String _slugify(String s) =>
      s.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');

  String _uniqueId(String base) {
    final root = base.isEmpty ? _platformType : base;
    var id = root;
    var n = 2;
    while (widget.existingSurfaceIds.contains(id)) {
      id = '${root}_$n';
      n++;
    }
    return id;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final name = _nameCtrl.text.trim();
      final env = _envCtrl.text.trim();
      final baseSlug =
          _slugify(env.isNotEmpty ? '${_platformType}_$env' : name);
      final surface = SurfaceConfig(
        id: _uniqueId(baseSlug),
        name: name,
        icon: _iconCtrl.text.trim().isEmpty ? '🔧' : _iconCtrl.text.trim(),
        platformType: _platformType,
        environmentId: env.isEmpty ? null : env,
      );
      await widget.onAdd(surface);
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add surface'),
      content: SizedBox(
        width: 380,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Platform', style: Theme.of(context).textTheme.labelMedium),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                segments: _kPlatforms
                    .map((p) => ButtonSegment(
                          value: p.type,
                          label: Text(p.label),
                          icon: Text(p.icon),
                        ))
                    .toList(),
                selected: {_platformType},
                onSelectionChanged: (v) => setState(() {
                  _platformType = v.first;
                  if (!_iconTouched) {
                    _iconCtrl.text = _kPlatforms
                        .firstWhere((p) => p.type == _platformType)
                        .icon;
                  }
                }),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _nameCtrl,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Surface name *',
                  border: OutlineInputBorder(),
                  hintText: 'e.g. Android Dev',
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _envCtrl,
                decoration: const InputDecoration(
                  labelText: 'Environment (optional)',
                  border: OutlineInputBorder(),
                  hintText: 'e.g. dev, stage, prod',
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _iconCtrl,
                onChanged: (_) => _iconTouched = true,
                decoration: const InputDecoration(
                  labelText: 'Icon (emoji)',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _submit,
          child: const Text('Add'),
        ),
      ],
    );
  }
}

// ── Edit Surface Dialog ───────────────────────────────────────────────────────

class _EditSurfaceDialog extends StatefulWidget {
  final SurfaceConfig surface;
  final Future<void> Function(SurfaceConfig) onSave;

  const _EditSurfaceDialog({required this.surface, required this.onSave});

  @override
  State<_EditSurfaceDialog> createState() => _EditSurfaceDialogState();
}

class _EditSurfaceDialogState extends State<_EditSurfaceDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _iconCtrl;
  late final TextEditingController _envCtrl;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.surface.name);
    _iconCtrl = TextEditingController(text: widget.surface.icon);
    _envCtrl = TextEditingController(text: widget.surface.environmentId ?? '');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _iconCtrl.dispose();
    _envCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final env = _envCtrl.text.trim();
      final updated = widget.surface.copyWith(
        name: _nameCtrl.text.trim(),
        icon: _iconCtrl.text.trim().isEmpty ? '🔧' : _iconCtrl.text.trim(),
        environmentId: env.isEmpty ? null : env,
        clearEnvironmentId: env.isEmpty,
      );
      await widget.onSave(updated);
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit surface'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Surface name *',
                border: OutlineInputBorder(),
              ),
              autofocus: true,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _envCtrl,
              decoration: const InputDecoration(
                labelText: 'Environment (optional)',
                border: OutlineInputBorder(),
                hintText: 'e.g. dev, stage, prod',
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _iconCtrl,
              decoration: const InputDecoration(
                labelText: 'Icon (emoji)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _submit,
          child: const Text('Save'),
        ),
      ],
    );
  }
}

// ── Surface Card ──────────────────────────────────────────────────────────────

class _SurfaceCard extends StatelessWidget {
  final SurfaceConfig surface;
  final ProjectConfig project;
  final bool isExpanded;
  final DoctorResult? doctorResult;
  final bool doctorRunning;

  final VoidCallback onToggleExpand;
  final VoidCallback onRunDoctor;
  final VoidCallback onEditSurface;
  final VoidCallback onDuplicateSurface;
  final VoidCallback onDeleteSurface;
  // Opens the SurfaceCommandManagerScreen scoped to this surface + the given
  // stage tags (e.g. ['test'] for Script commands) — one shared entry point
  // for the three command sections' "Manage" buttons below.
  final void Function(List<String> stageTags, String title) onManageCommands;
  final VoidCallback onEditScripts;
  final VoidCallback onOpenReports;
  // Called after a section persists a change directly to ProjectProvider
  // (the prerequisite switch, the report path field, App IDs) — those
  // widgets don't rebuild on their own since [project]/[surface] are plain
  // snapshots handed down from the parent screen's own state, not reactively
  // bound to the provider. Wired to the parent's _refreshProject().
  final VoidCallback onSurfaceChanged;

  const _SurfaceCard({
    super.key,
    required this.surface,
    required this.project,
    required this.isExpanded,
    required this.doctorResult,
    required this.doctorRunning,
    required this.onToggleExpand,
    required this.onRunDoctor,
    required this.onEditSurface,
    required this.onDuplicateSurface,
    required this.onDeleteSurface,
    required this.onManageCommands,
    required this.onEditScripts,
    required this.onOpenReports,
    required this.onSurfaceChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final cmdCount = surface.commandIds.length;

    return Consumer<RunProvider>(
      builder: (context, run, _) {
        // isRunningFor checks every active run, not just the "primary" one
        // — correct even once concurrent runs across surfaces are possible.
        final isThisRunning = run.isRunningFor(surface.id);
        final doctorPassed =
            doctorResult != null &&
            !doctorResult!.checks.any((c) => c.status == DoctorStatus.fail);
        final canRun = doctorPassed && !run.isRunning;

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: isThisRunning
                  ? cs.primary
                  : isExpanded
                  ? cs.outline
                  : cs.outlineVariant,
              width: isThisRunning || isExpanded ? 1.5 : 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Card header ────────────────────────────────────────────────
              InkWell(
                onTap: onToggleExpand,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      // Icon
                      Text(surface.icon, style: const TextStyle(fontSize: 22)),
                      const SizedBox(width: 12),
                      // Name + meta
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              surface.name,
                              style: Theme.of(context).textTheme.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                _DoctorDot(
                                  result: doctorResult,
                                  running: doctorRunning,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '$cmdCount cmd${cmdCount == 1 ? '' : 's'}',
                                  style: Theme.of(context).textTheme.labelSmall
                                      ?.copyWith(color: cs.onSurfaceVariant),
                                ),
                                if (isThisRunning) ...[
                                  const SizedBox(width: 8),
                                  SizedBox(
                                    width: 10,
                                    height: 10,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 1.5,
                                      color: cs.primary,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Running…',
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall
                                        ?.copyWith(color: cs.primary),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                      // Scripts — the single entry point for actually
                      // running this surface (environment/platform/device
                      // picker lives there, via RunPicker/RunDispatcher).
                      if (!isThisRunning)
                        Tooltip(
                          message: canRun ? 'Scripts — run' : 'Run Doctor first',
                          child: IconButton(
                            icon: const Icon(Icons.play_circle_outline),
                            color: canRun ? cs.primary : cs.onSurfaceVariant,
                            onPressed: canRun ? onEditScripts : null,
                          ),
                        ),
                      // ⋮ menu
                      PopupMenuButton<String>(
                        tooltip: 'Surface options',
                        icon: const Icon(Icons.more_vert),
                        onSelected: (v) {
                          switch (v) {
                            case 'edit':
                              onEditSurface();
                            case 'duplicate':
                              onDuplicateSurface();
                            case 'scripts':
                              onEditScripts();
                            case 'reports':
                              onOpenReports();
                            case 'delete':
                              onDeleteSurface();
                          }
                        },
                        itemBuilder: (_) => [
                          const PopupMenuItem(
                            value: 'edit',
                            child: ListTile(
                              leading: Icon(
                                Icons.drive_file_rename_outline,
                                size: 18,
                              ),
                              title: Text('Edit surface'),
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'duplicate',
                            child: ListTile(
                              leading: Icon(Icons.copy_outlined, size: 18),
                              title: Text('Duplicate surface'),
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'scripts',
                            child: ListTile(
                              leading: Icon(
                                Icons.description_outlined,
                                size: 18,
                              ),
                              title: Text('Scripts'),
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'reports',
                            child: ListTile(
                              leading: Icon(
                                Icons.assessment_outlined,
                                size: 18,
                              ),
                              title: Text('Reports'),
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                          const PopupMenuDivider(),
                          PopupMenuItem(
                            value: 'delete',
                            child: ListTile(
                              leading: Icon(
                                Icons.delete_outline,
                                size: 18,
                                color: Theme.of(context).colorScheme.error,
                              ),
                              title: Text(
                                'Delete surface',
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                ),
                              ),
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                        ],
                      ),
                      // Expand/collapse chevron
                      Icon(
                        isExpanded ? Icons.expand_less : Icons.expand_more,
                        color: cs.onSurfaceVariant,
                      ),
                    ],
                  ),
                ),
              ),

              // ── Expanded body ──────────────────────────────────────────────
              if (isExpanded) ...[
                Divider(height: 1, color: cs.outlineVariant),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Doctor section
                      _DoctorSection(
                        doctorResult: doctorResult,
                        doctorRunning: doctorRunning,
                        onRunDoctor: onRunDoctor,
                      ),
                      const SizedBox(height: 16),

                      // Checkout branch per repo this surface uses — was
                      // only visible/editable from the project's repo
                      // settings (Edit project); surfaced here so it can be
                      // checked/changed without leaving the surface.
                      _BranchSection(
                        surface: surface,
                        project: project,
                        onChanged: onSurfaceChanged,
                      ),

                      // Prerequisite → Pull → Build → Script (runner) →
                      // Report — the order they actually run in, each its
                      // own sectional card so they're easy to tell apart at
                      // a glance.
                      if (surface.isMobile || surface.isWeb) ...[
                        _SectionCard(
                          child: _PrerequisiteCommandsSection(
                            surface: surface,
                            project: project,
                            onManageCommands: () => onManageCommands(
                                const ['git', 'prerequisite'], 'Prerequisites'),
                            onChanged: onSurfaceChanged,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _SectionCard(
                          child: _PullSection(
                            surface: surface,
                            project: project,
                            onChanged: onSurfaceChanged,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _SectionCard(
                          child: _BuildCommandsSection(
                            surface: surface,
                            project: project,
                            onManageCommands: () =>
                                onManageCommands(const ['build'], 'Build'),
                            onChanged: onSurfaceChanged,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _SectionCard(
                          child: _RunnerCommandsSection(
                            surface: surface,
                            project: project,
                            onManageCommands: () =>
                                onManageCommands(const ['test'], 'Script commands'),
                            onChanged: onSurfaceChanged,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _SectionCard(
                          child: _ReportSection(
                            surface: surface,
                            project: project,
                            onChanged: onSurfaceChanged,
                            onManageCommands: () =>
                                onManageCommands(const ['report'], 'Report'),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

                      // Bundle id / package name per environment (mobile only)
                      if (surface.isMobile &&
                          project.repos.containsKey('mobile_ui')) ...[
                        _AppIdsSection(
                          surface: surface,
                          project: project,
                          onChanged: onSurfaceChanged,
                        ),
                        const SizedBox(height: 16),
                      ],

                      // Run / Cancel — Run always goes through the Scripts
                      // screen, which asks for environment, then (for
                      // mobile) platform, simulator/device, and an idle
                      // device — never guesses at any of that here.
                      if (isThisRunning)
                        OutlinedButton.icon(
                          onPressed: () => context.read<RunProvider>().cancel(
                            run.runIdFor(surface.id),
                          ),
                          icon: const Icon(Icons.stop_circle_outlined),
                          label: const Text('Cancel'),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            foregroundColor: Theme.of(
                              context,
                            ).colorScheme.error,
                          ),
                        )
                      else
                        FilledButton.icon(
                          onPressed: canRun ? onEditScripts : null,
                          icon: const Icon(Icons.play_arrow_rounded),
                          label: const Text('Run from Scripts'),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),

                      if (!canRun && !isThisRunning) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Run Doctor first to enable Run.',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: cs.onSurfaceVariant),
                        ),
                      ],

                      // Run history
                      const SizedBox(height: 16),
                      _RunHistorySection(project: project, surface: surface),
                    ],
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

// ── Doctor dot (compact status indicator) ─────────────────────────────────────

class _DoctorDot extends StatelessWidget {
  final DoctorResult? result;
  final bool running;

  const _DoctorDot({required this.result, required this.running});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (running) {
      return SizedBox(
        width: 10,
        height: 10,
        child: CircularProgressIndicator(strokeWidth: 1.5, color: cs.primary),
      );
    }
    if (result == null) {
      return Tooltip(
        message: 'Doctor not run',
        child: Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: cs.outlineVariant,
            shape: BoxShape.circle,
          ),
        ),
      );
    }
    final failed = result!.checks.any((c) => c.status == DoctorStatus.fail);
    return Tooltip(
      message: failed ? 'Doctor failed' : 'Doctor passed',
      child: Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          color: failed ? cs.error : cs.primary,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

// ── Doctor section (expandable checks) ───────────────────────────────────────

class _DoctorSection extends StatefulWidget {
  final DoctorResult? doctorResult;
  final bool doctorRunning;
  final VoidCallback onRunDoctor;

  const _DoctorSection({
    required this.doctorResult,
    required this.doctorRunning,
    required this.onRunDoctor,
  });

  @override
  State<_DoctorSection> createState() => _DoctorSectionState();
}

class _DoctorSectionState extends State<_DoctorSection> {
  bool _expanded = false;

  /// Id of the check currently running a fix — only one at a time, and
  /// blocks that check's own Fix/Custom buttons while it's in flight.
  String? _fixingCheckId;

  /// Shows exactly what will run before running it, then re-runs Doctor
  /// afterward so the check list reflects whether it actually worked.
  Future<void> _confirmAndRun(DoctorCheck check, String command) async {
    final cwd = check.fixCwd;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Run this fix?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('For: ${check.label}'),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Theme.of(ctx).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(6),
              ),
              child: SelectableText(
                command,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
              ),
            ),
            if (cwd != null) ...[
              const SizedBox(height: 8),
              Text(
                'in: $cwd',
                style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                  color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Run'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _executeFix(check, command);
  }

  /// Actually runs [command] — no confirmation here, since both call sites
  /// (`_confirmAndRun`'s dialog, `_runCustomFix`'s own edit-and-Run dialog)
  /// already got explicit confirmation from the user before calling this.
  ///
  /// Deliberately does NOT pass `ignoreExitCode: true` — a real failure must
  /// actually throw here, or every failure would silently look like success
  /// (empty stdout on a real error would otherwise read as "Done.").
  Future<void> _executeFix(DoctorCheck check, String command) async {
    setState(() => _fixingCheckId = check.id);
    try {
      final output = await locator<ProcessGateway>().exec(
        command,
        workingDirectory: check.fixCwd,
      );
      if (!mounted) return;
      setState(() => _fixingCheckId = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '✓ ${output.trim().isEmpty ? "Done" : output.trim().split('\n').first}',
          ),
          backgroundColor: Colors.green.shade700,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _fixingCheckId = null);
      // A dialog, not a SnackBar — stderr can be multiple lines and a
      // one-line toast would just clip it.
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Fix failed'),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: SelectableText(
                e.toString(),
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
    if (!mounted) return;
    widget.onRunDoctor(); // refresh — did it actually fix the check?
  }

  Future<void> _runCustomFix(DoctorCheck check) async {
    final ctrl = TextEditingController(text: check.fixCommand ?? '');
    final command = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Custom fix — ${check.label}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (check.fixCwd != null) ...[
              Text(
                'Runs in: ${check.fixCwd}',
                style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                  color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
            ],
            TextField(
              controller: ctrl,
              autofocus: true,
              maxLines: 3,
              minLines: 1,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'shell command to run',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Run'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (command == null || command.isEmpty || !mounted) return;
    await _executeFix(check, command);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (widget.doctorRunning) {
      return Row(
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 10),
          Text(
            'Running doctor checks…',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      );
    }

    if (widget.doctorResult == null) {
      return OutlinedButton.icon(
        onPressed: widget.onRunDoctor,
        icon: const Icon(Icons.health_and_safety_outlined, size: 16),
        label: const Text('Run Doctor'),
        style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
      );
    }

    final result = widget.doctorResult!;
    final passed = result.checks
        .where((c) => c.status == DoctorStatus.pass)
        .length;
    final failed = result.checks
        .where((c) => c.status == DoctorStatus.fail)
        .length;
    final warned = result.checks
        .where((c) => c.status == DoctorStatus.warn)
        .length;
    final allGood = failed == 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: allGood
                  ? cs.primaryContainer.withValues(alpha: 0.4)
                  : cs.errorContainer.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  allGood ? Icons.check_circle_outline : Icons.error_outline,
                  size: 18,
                  color: allGood ? cs.primary : cs.error,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    allGood
                        ? 'Doctor passed — $passed checks OK'
                              '${warned > 0 ? ', $warned warning${warned > 1 ? 's' : ''}' : ''}'
                        : '$failed check${failed > 1 ? 's' : ''} failed — fix before running',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: allGood ? cs.primary : cs.error,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Icon(
                  _expanded ? Icons.expand_less : Icons.expand_more,
                  size: 18,
                  color: cs.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: widget.onRunDoctor,
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                  ),
                  child: const Text('Re-check'),
                ),
              ],
            ),
          ),
        ),
        if (_expanded)
          Container(
            margin: const EdgeInsets.only(top: 6),
            decoration: BoxDecoration(
              border: Border.all(color: cs.outlineVariant),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: result.checks.map((check) {
                final icon = switch (check.status) {
                  DoctorStatus.pass => Icons.check_circle_outline,
                  DoctorStatus.warn => Icons.warning_amber_outlined,
                  DoctorStatus.fail => Icons.error_outline,
                  DoctorStatus.checking => Icons.hourglass_empty_outlined,
                };
                final color = switch (check.status) {
                  DoctorStatus.pass => cs.primary,
                  DoctorStatus.warn => Colors.orange,
                  DoctorStatus.fail => cs.error,
                  DoctorStatus.checking => cs.onSurfaceVariant,
                };
                final fixing = _fixingCheckId == check.id;
                return ListTile(
                  dense: true,
                  leading: Icon(icon, color: color, size: 18),
                  title: Text(
                    check.label,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  subtitle: check.fixHint != null
                      ? Text(
                          check.fixHint!,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: cs.onSurfaceVariant,
                                fontFamily: 'monospace',
                                fontSize: 11,
                              ),
                        )
                      : (check.detail != null
                            ? Text(
                                check.detail!,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: cs.onSurfaceVariant,
                                      fontSize: 11,
                                    ),
                              )
                            : null),
                  trailing: check.fixHint == null
                      ? null
                      : fixing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (check.fixCommand != null)
                              TextButton(
                                onPressed: () =>
                                    _confirmAndRun(check, check.fixCommand!),
                                style: TextButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                ),
                                child: const Text('Fix'),
                              ),
                            IconButton(
                              tooltip: 'Run a custom fix command',
                              icon: const Icon(Icons.terminal, size: 16),
                              visualDensity: VisualDensity.compact,
                              onPressed: () => _runCustomFix(check),
                            ),
                          ],
                        ),
                );
              }).toList(),
            ),
          ),
      ],
    );
  }
}

// ── Runner commands section ───────────────────────────────────────────────────

/// The "run this script" command template per platform×target combo (mobile)
/// or the single web runner command — mandatory before the Scripts screen's
/// Run/Pull&Run/Build&Run buttons enable. Each slot picks from commands
/// already assigned to this surface (via the Command Library) rather than
/// letting a command be typed here directly — one editable place for the
/// command text, this just wires which one plays which role. See
/// docs/RUN_EXPERIENCE_REDESIGN.md §5.
// ── Section card ──────────────────────────────────────────────────────────────

/// A bordered, tinted wrapper giving each pipeline-stage section (prerequisite/
/// runner/report) its own visually distinct card, so the three are easy to
/// tell apart at a glance instead of running together as one long column.
class _SectionCard extends StatelessWidget {
  final Widget child;
  const _SectionCard({required this.child});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: child,
    );
  }
}

/// Read-only summary of this surface's `category: 'test'` pool commands —
/// there's no more per-slot dropdown to fill in: which one actually runs for
/// a given environment/platform/target combo is *resolved by filtering* at
/// dispatch time ([ProjectConfig.testCommandFor]), so this section just shows
/// what's in the pool and how each is tagged. Tag/untag via "Edit commands"
/// (the Command Library), not here.
// ── Branch section (checkout branch per repo, at the surface level) ──────────

/// One chip per repo this surface's commands touch, showing its expected
/// git checkout branch ([RepoEntry.branch]) — tap to change it. Previously
/// only editable from the project's own "Edit project" repo settings.
class _BranchSection extends StatelessWidget {
  final SurfaceConfig surface;
  final ProjectConfig project;
  final VoidCallback onChanged;

  const _BranchSection({
    required this.surface,
    required this.project,
    required this.onChanged,
  });

  List<RepoEntry> get _repos {
    final roles = project
        .commandsForSurface(surface.id)
        .map((c) => c.repoRole)
        .toSet();
    return roles.map((r) => project.repos[r]).whereType<RepoEntry>().toList();
  }

  Future<void> _editBranch(BuildContext context, RepoEntry repo) async {
    final ctrl = TextEditingController(text: repo.branch);
    final newBranch = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Checkout branch — ${repo.label}'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Branch',
            hintText: 'develop',
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (newBranch == null || !context.mounted) return;
    final trimmed = newBranch.trim();
    if (trimmed.isEmpty || trimmed == repo.branch) return;
    final updatedProject = project.copyWith(
      repos: {...project.repos, repo.role: repo.copyWith(branch: trimmed)},
    );
    await context.read<ProjectProvider>().updateProject(updatedProject);
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final repos = _repos;
    if (repos.isEmpty) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        children: repos
            .map(
              (repo) => ActionChip(
                avatar: Icon(Icons.call_split, size: 14, color: cs.onSurfaceVariant),
                label: Text('${repo.label}: ${repo.branch}'),
                labelStyle: Theme.of(context).textTheme.labelSmall,
                visualDensity: VisualDensity.compact,
                onPressed: () => _editBranch(context, repo),
              ),
            )
            .toList(),
      ),
    );
  }
}

/// Opens [command] in the command edit popup (same screen "Add command"
/// uses) and refreshes via [onChanged] on return — shared by every section
/// that lists commands, so tapping a row edits it instead of only being
/// reachable through the full Command Library.
Future<void> _openCommandDetail(
  BuildContext context, {
  required ProjectConfig project,
  required String surfaceId,
  required CommandConfig command,
  required VoidCallback onChanged,
}) async {
  await locator<NavigationUtils>().push(
    routeCommandEdit,
    arguments: CommandEditArgs(
      project: project,
      surfaceId: surfaceId,
      existing: command,
    ),
  );
  onChanged();
}

class _RunnerCommandsSection extends StatelessWidget {
  final SurfaceConfig surface;
  final ProjectConfig project;
  final VoidCallback onManageCommands;
  final VoidCallback onChanged;

  const _RunnerCommandsSection({
    required this.surface,
    required this.project,
    required this.onManageCommands,
    required this.onChanged,
  });

  List<CommandConfig> get _testCommands => surface.commandIds
      .map((id) => project.commands.where((c) => c.id == id).firstOrNull)
      .whereType<CommandConfig>()
      .where((c) => c.hasTag('test'))
      .toList();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final cmds = _testCommands;
    final complete = cmds.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Script commands',
              style: Theme.of(
                context,
              ).textTheme.labelMedium?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(width: 4),
            Tooltip(
              message:
                  'Commands tagged "test" — the ones the Run buttons '
                  'actually dispatch. Untagged = applies regardless. Use '
                  '{environment}, {udid}, and {script} in the command text.',
              child: Icon(
                Icons.info_outline,
                size: 14,
                color: cs.onSurfaceVariant,
              ),
            ),
            const Spacer(),
            Icon(
              complete ? Icons.check_circle_outline : Icons.error_outline,
              size: 16,
              color: complete ? cs.primary : cs.error,
            ),
          ],
        ),
        const SizedBox(height: 6),
        if (cmds.isEmpty)
          Text(
            'No test commands assigned to this surface yet.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          )
        else
          ...cmds.map((c) => _commandRow(context, c)),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: onManageCommands,
            icon: const Icon(Icons.tune, size: 14),
            label: const Text('Manage'),
            style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
          ),
        ),
      ],
    );
  }

  Widget _commandRow(BuildContext context, CommandConfig c) {
    final cs = Theme.of(context).colorScheme;
    final tags = [
      if (c.target != null) c.target!,
      ...c.tags,
    ];
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: () => _openCommandDetail(
        context,
        project: project,
        surfaceId: surface.id,
        command: c,
        onChanged: onChanged,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Icon(Icons.terminal, size: 14, color: cs.onSurfaceVariant),
            const SizedBox(width: 8),
            Expanded(
              child: Tooltip(
                message: c.command,
                child: Text(c.name, style: Theme.of(context).textTheme.bodySmall),
              ),
            ),
            if (tags.isEmpty)
              Text(
                'any',
                style: Theme.of(
                  context,
                ).textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
              )
            else
              Wrap(
                spacing: 4,
                children: tags
                    .map(
                      (t) => Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          t,
                          style: Theme.of(
                            context,
                          ).textTheme.labelSmall?.copyWith(fontSize: 10),
                        ),
                      ),
                    )
                    .toList(),
              ),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right, size: 14, color: cs.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

// ── Prerequisite commands section ─────────────────────────────────────────────

/// A switch + a read-only summary of pool commands tagged `git`/
/// `prerequisite` — resolved the same way dispatch resolves them (see
/// [ProjectConfig.prerequisiteCommandsFor]), so there's nothing to
/// separately check off here any more; tag/untag via "Manage".
class _PrerequisiteCommandsSection extends StatelessWidget {
  final SurfaceConfig surface;
  final ProjectConfig project;
  final VoidCallback onManageCommands;
  final VoidCallback onChanged;

  const _PrerequisiteCommandsSection({
    required this.surface,
    required this.project,
    required this.onManageCommands,
    required this.onChanged,
  });

  List<CommandConfig> get _prereqCommands =>
      project.prerequisiteCommandsFor(surface.id);

  Future<void> _persist(BuildContext context, {required bool runPrerequisites}) async {
    await context.read<ProjectProvider>().upsertSurface(
      project: project,
      surface: surface.copyWith(runPrerequisites: runPrerequisites),
    );
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final prereqs = _prereqCommands;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Switch(
              value: surface.runPrerequisites,
              onChanged: (v) => _persist(context, runPrerequisites: v),
            ),
            const SizedBox(width: 4),
            Text(
              'Run prerequisite commands',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(width: 2),
            Tooltip(
              message:
                  'Runs every command tagged "git" or "prerequisite" first, '
                  'before Pull/Build/Run — e.g. git pull, '
                  'flutter pub get, pod install, npm install.',
              child: Icon(
                Icons.info_outline,
                size: 14,
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
        // Shown regardless of the switch above — this is "what's assigned
        // and would run if the switch is on," not gated behind turning it
        // on first, so a command can be added/reviewed before flipping it.
        const SizedBox(height: 4),
        if (prereqs.isEmpty)
          Text(
            'No git/prerequisite commands tagged for this surface yet.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          )
        else
          ...prereqs.map((c) => InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: () => _openCommandDetail(
                  context,
                  project: project,
                  surfaceId: surface.id,
                  command: c,
                  onChanged: onChanged,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      Icon(Icons.checklist_outlined,
                          size: 14, color: cs.onSurfaceVariant),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Tooltip(
                          message: c.command,
                          child: Text(c.name,
                              style: Theme.of(context).textTheme.bodySmall),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(Icons.chevron_right,
                          size: 14, color: cs.onSurfaceVariant),
                    ],
                  ),
                ),
              )),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: onManageCommands,
            icon: const Icon(Icons.tune, size: 14),
            label: const Text('Manage'),
            style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
          ),
        ),
      ],
    );
  }
}

// ── Pull section ──────────────────────────────────────────────────────────────

/// Just a switch — pulling is a fixed mechanic (git pull the surface's
/// buildable repo at its configured branch), not a list of assignable
/// commands like Prerequisites/Build, so there's nothing here to preview or
/// manage.
class _PullSection extends StatelessWidget {
  final SurfaceConfig surface;
  final ProjectConfig project;
  final VoidCallback onChanged;

  const _PullSection({
    required this.surface,
    required this.project,
    required this.onChanged,
  });

  Future<void> _persist(BuildContext context, {required bool runPull}) async {
    await context.read<ProjectProvider>().upsertSurface(
      project: project,
      surface: surface.copyWith(runPull: runPull),
    );
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Switch(
          value: surface.runPull,
          onChanged: (v) => _persist(context, runPull: v),
        ),
        const SizedBox(width: 4),
        Text('Pull before build', style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(width: 2),
        Tooltip(
          message: 'Git-pulls this surface\'s buildable repo (mobile_ui for '
              'mobile, web for web) at its configured branch before Build.',
          child: Icon(Icons.info_outline, size: 14, color: cs.onSurfaceVariant),
        ),
      ],
    );
  }
}

// ── Build section ─────────────────────────────────────────────────────────────

/// Mirrors [_PrerequisiteCommandsSection] exactly — a switch plus a
/// read-only preview of the `build`-tagged commands assigned to this
/// surface (see [ProjectConfig.buildInstallCommandsFor]).
class _BuildCommandsSection extends StatelessWidget {
  final SurfaceConfig surface;
  final ProjectConfig project;
  final VoidCallback onManageCommands;
  final VoidCallback onChanged;

  const _BuildCommandsSection({
    required this.surface,
    required this.project,
    required this.onManageCommands,
    required this.onChanged,
  });

  List<CommandConfig> get _buildCommands =>
      project.buildInstallCommandsFor(surface.id);

  Future<void> _persist(BuildContext context, {required bool runBuild}) async {
    await context.read<ProjectProvider>().upsertSurface(
      project: project,
      surface: surface.copyWith(runBuild: runBuild),
    );
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final builds = _buildCommands;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Switch(
              value: surface.runBuild,
              onChanged: (v) => _persist(context, runBuild: v),
            ),
            const SizedBox(width: 4),
            Text('Run build commands', style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(width: 2),
            Tooltip(
              message: 'Runs every command tagged "build" before the script '
                  'runs — e.g. flutter build, yarn build.',
              child: Icon(Icons.info_outline, size: 14, color: cs.onSurfaceVariant),
            ),
          ],
        ),
        const SizedBox(height: 4),
        if (builds.isEmpty)
          Text(
            'No build commands tagged for this surface yet.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          )
        else
          ...builds.map((c) => InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: () => _openCommandDetail(
                  context,
                  project: project,
                  surfaceId: surface.id,
                  command: c,
                  onChanged: onChanged,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      Icon(Icons.checklist_outlined,
                          size: 14, color: cs.onSurfaceVariant),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Tooltip(
                          message: c.command,
                          child: Text(c.name,
                              style: Theme.of(context).textTheme.bodySmall),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(Icons.chevron_right,
                          size: 14, color: cs.onSurfaceVariant),
                    ],
                  ),
                ),
              )),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: onManageCommands,
            icon: const Icon(Icons.tune, size: 14),
            label: const Text('Manage'),
            style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
          ),
        ),
      ],
    );
  }
}

// ── Report section ────────────────────────────────────────────────────────────

/// Shows this surface's report command(s) (tagged `report` — one report
/// tool per surface, unlike the per-target [_RunnerCommandsSection]) and its
/// output folder. See docs/RUN_EXPERIENCE_REDESIGN.md §8.
class _ReportSection extends StatefulWidget {
  final SurfaceConfig surface;
  final ProjectConfig project;
  final VoidCallback onChanged;
  final VoidCallback onManageCommands;

  const _ReportSection({
    required this.surface,
    required this.project,
    required this.onChanged,
    required this.onManageCommands,
  });

  @override
  State<_ReportSection> createState() => _ReportSectionState();
}

class _ReportSectionState extends State<_ReportSection> {
  late TextEditingController _pathCtrl;

  @override
  void initState() {
    super.initState();
    _pathCtrl = TextEditingController(
      text: widget.surface.reportOutputRelPath ?? '',
    );
  }

  @override
  void didUpdateWidget(_ReportSection old) {
    super.didUpdateWidget(old);
    if (old.surface.reportOutputRelPath != widget.surface.reportOutputRelPath &&
        _pathCtrl.text != (widget.surface.reportOutputRelPath ?? '')) {
      _pathCtrl.text = widget.surface.reportOutputRelPath ?? '';
    }
  }

  @override
  void dispose() {
    _pathCtrl.dispose();
    super.dispose();
  }

  // Report commands assigned to this surface — resolved the same way
  // dispatch resolves them: filter the pool for the `report` tag. Which one
  // actually wins is picked at run time ([ProjectConfig.reportCommandFor]);
  // this is just showing what's there.
  List<CommandConfig> get _reportCommands => widget.surface.commandIds
      .map((id) => widget.project.commands.where((c) => c.id == id).firstOrNull)
      .whereType<CommandConfig>()
      .where((c) => c.hasTag('report'))
      .toList();

  Future<void> _persistPath(String value) async {
    await context.read<ProjectProvider>().upsertSurface(
      project: widget.project,
      surface: widget.surface.copyWith(
        reportOutputRelPath: value.trim().isEmpty ? null : value.trim(),
        clearReportOutputRelPath: value.trim().isEmpty,
      ),
    );
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final reportCmds = _reportCommands;
    final complete =
        reportCmds.isNotEmpty && widget.surface.reportOutputRelPath != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Report',
              style: Theme.of(
                context,
              ).textTheme.labelMedium?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(width: 4),
            Tooltip(
              message:
                  'Commands tagged "report" open/serve this surface\'s '
                  'report. The output folder below is relative to that '
                  'command\'s repo, and is archived after every run so it '
                  'survives the next one overwriting it.',
              child: Icon(
                Icons.info_outline,
                size: 14,
                color: cs.onSurfaceVariant,
              ),
            ),
            const Spacer(),
            Icon(
              complete ? Icons.check_circle_outline : Icons.error_outline,
              size: 16,
              color: complete ? cs.primary : cs.error,
            ),
          ],
        ),
        const SizedBox(height: 6),
        if (reportCmds.isEmpty)
          Text(
            'No report commands assigned yet — tag one "report" via Manage.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          )
        else
          ...reportCmds.map(
            (c) => InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: () => _openCommandDetail(
                context,
                project: widget.project,
                surfaceId: widget.surface.id,
                command: c,
                onChanged: widget.onChanged,
              ),
              child: Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    Icon(
                      Icons.bar_chart_outlined,
                      size: 14,
                      color: cs.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Tooltip(
                        message: c.command,
                        child: Text(
                          c.name,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(Icons.chevron_right,
                        size: 14, color: cs.onSurfaceVariant),
                  ],
                ),
              ),
            ),
          ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: widget.onManageCommands,
            icon: const Icon(Icons.tune, size: 14),
            label: const Text('Manage'),
            style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
          ),
        ),
        TextFormField(
          controller: _pathCtrl,
          decoration: InputDecoration(
            isDense: true,
            border: const OutlineInputBorder(),
            labelText:
                'Report output folder (relative to the report command\'s repo)',
            hintText: 'e.g. allure-report',
            errorText: widget.surface.reportOutputRelPath == null
                ? 'Required'
                : null,
          ),
          onFieldSubmitted: _persistPath,
          onTapOutside: (_) => _persistPath(_pathCtrl.text),
        ),
      ],
    );
  }
}

// ── App IDs section (bundle id / package name for this surface) ──────────────

/// Editable Android applicationId / iOS bundle id for this surface (see
/// [MobileAppId]) — one flat pair, not one per environment, since a surface
/// now already *is* one environment. "Auto-detect" runs a best-effort parse
/// of the repo's build.gradle/xcconfig, matched against this surface's own
/// [SurfaceConfig.environmentId], and fills in only the fields that are
/// still blank — it never overwrites something the user already typed. See
/// docs/RUN_EXPERIENCE_REDESIGN.md §3.
class _AppIdsSection extends StatefulWidget {
  final SurfaceConfig surface;
  final ProjectConfig project;
  final VoidCallback onChanged;

  const _AppIdsSection({
    required this.surface,
    required this.project,
    required this.onChanged,
  });

  @override
  State<_AppIdsSection> createState() => _AppIdsSectionState();
}

class _AppIdsSectionState extends State<_AppIdsSection> {
  late TextEditingController _androidCtrl;
  late TextEditingController _iosCtrl;
  bool _detecting = false;
  bool _dirty = false;

  RepoEntry get _repo => widget.project.repos['mobile_ui']!;

  @override
  void initState() {
    super.initState();
    _initControllers();
  }

  @override
  void didUpdateWidget(_AppIdsSection old) {
    super.didUpdateWidget(old);
    if (old.surface.appId != widget.surface.appId) {
      _disposeControllers();
      _initControllers();
    }
  }

  void _initControllers() {
    _androidCtrl = TextEditingController(
      text: widget.surface.appId?.androidApplicationId ?? '',
    );
    _iosCtrl = TextEditingController(text: widget.surface.appId?.iosBundleId ?? '');
  }

  void _disposeControllers() {
    _androidCtrl.dispose();
    _iosCtrl.dispose();
  }

  @override
  void dispose() {
    _disposeControllers();
    super.dispose();
  }

  Future<void> _autoDetect() async {
    setState(() => _detecting = true);
    try {
      final absPath = _repo.absPath(widget.project.projectsRoot);
      final android = BundleIdDetector.detectAndroid(absPath);
      final ios = BundleIdDetector.detectIos(absPath);
      final envKey = widget.surface.environmentId;
      var filled = 0;
      if (envKey != null) {
        if (widget.surface.isAndroid &&
            _androidCtrl.text.trim().isEmpty &&
            android[envKey] != null) {
          _androidCtrl.text = android[envKey]!;
          filled++;
        }
        if (widget.surface.isIos &&
            _iosCtrl.text.trim().isEmpty &&
            ios[envKey] != null) {
          _iosCtrl.text = ios[envKey]!;
          filled++;
        }
      }
      if (!mounted) return;
      if (filled > 0) setState(() => _dirty = true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            filled == 0
                ? 'Nothing detected (or already filled in) — review '
                      'manually below.'
                : 'Filled in $filled field${filled == 1 ? '' : 's'} — review '
                      'and Save.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _detecting = false);
    }
  }

  Future<void> _save() async {
    final appId = MobileAppId(
      androidApplicationId:
          _androidCtrl.text.trim().isEmpty ? null : _androidCtrl.text.trim(),
      iosBundleId: _iosCtrl.text.trim().isEmpty ? null : _iosCtrl.text.trim(),
    );
    await context.read<ProjectProvider>().upsertSurface(
      project: widget.project,
      surface: widget.surface.copyWith(
        appId: appId,
        clearAppId: appId.isEmpty,
      ),
    );
    widget.onChanged();
    if (!mounted) return;
    setState(() => _dirty = false);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Saved.')));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'App ID',
              style: Theme.of(
                context,
              ).textTheme.labelMedium?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(width: 4),
            Tooltip(
              message:
                  'Android applicationId / iOS bundle id for this surface — '
                  'used to check whether the app is already installed before '
                  'Run. Auto-detect reads the app repo\'s build.gradle/'
                  'xcconfig; always reviewable before Save.',
              child: Icon(
                Icons.info_outline,
                size: 14,
                color: cs.onSurfaceVariant,
              ),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: _detecting ? null : _autoDetect,
              icon: _detecting
                  ? const SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.auto_fix_high, size: 14),
              label: const Text('Auto-detect'),
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
            ),
          ],
        ),
        const SizedBox(height: 6),
        // Only the field this surface's platform actually uses — showing
        // both regardless of platform just invited "why is this one always
        // blank?" (a web/Android surface has no use for an iOS bundle id,
        // and vice versa).
        if (widget.surface.isAndroid)
          TextField(
            controller: _androidCtrl,
            onChanged: (_) => setState(() => _dirty = true),
            decoration: const InputDecoration(
              isDense: true,
              border: OutlineInputBorder(),
              labelText: 'Android applicationId',
              hintText: 'com.example.app.dev',
            ),
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          )
        else if (widget.surface.isIos)
          TextField(
            controller: _iosCtrl,
            onChanged: (_) => setState(() => _dirty = true),
            decoration: const InputDecoration(
              isDense: true,
              border: OutlineInputBorder(),
              labelText: 'iOS bundle id',
              hintText: 'com.example.app.dev',
            ),
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
        if (_dirty)
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.tonal(
              onPressed: _save,
              child: const Text('Save'),
            ),
          ),
      ],
    );
  }
}

// ── Run history section ───────────────────────────────────────────────────────

class _RunHistorySection extends StatelessWidget {
  final ProjectConfig project;
  final SurfaceConfig surface;
  const _RunHistorySection({required this.project, required this.surface});

  @override
  Widget build(BuildContext context) {
    return Consumer<RunProvider>(
      builder: (context, run, _) {
        // projectId-scoped — a record with no projectId on file (recorded
        // before this fix) can't be reliably attributed to this project, so
        // it stops showing here rather than risking a bleed from another
        // project's same-named surface (docs/RUN_EXPERIENCE_REDESIGN.md §9).
        final history = run.history
            .where((r) => r.recipeId == surface.id && r.projectId == project.id)
            .take(5)
            .toList();
        if (history.isEmpty) return const SizedBox.shrink();

        final cs = Theme.of(context).colorScheme;
        // The actual archived Allure/Playwright report per run — joined via
        // RunRecord.runId/ReportArchive.runId (the two were always meant to
        // be joined this way, see both models' doc comments). Previously
        // "Open last report" opened `record.logPath` instead — the run's
        // plain-text log, not a report at all.
        final archives = ReportArchiveStore.forSurface(project.id, surface.id);
        ReportArchive? archiveFor(String? runId) => runId == null
            ? null
            : archives.where((a) => a.runId == runId).firstOrNull;
        final lastArchive = archives.firstOrNull;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(
                  'Recent runs',
                  style: Theme.of(
                    context,
                  ).textTheme.labelMedium?.copyWith(color: cs.onSurfaceVariant),
                ),
                const Spacer(),
                if (lastArchive != null)
                  OutlinedButton.icon(
                    onPressed: () => _openReport(context, lastArchive),
                    icon: const Icon(Icons.open_in_new, size: 14),
                    label: const Text('Open last report'),
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            ...history.map((record) {
              final archive = archiveFor(record.runId);
              final statusColor = record.status == 'done'
                  ? cs.primary
                  : record.status == 'cancelled'
                  ? cs.onSurfaceVariant
                  : cs.error;
              final statusIcon = record.status == 'done'
                  ? Icons.check_circle_outline
                  : record.status == 'cancelled'
                  ? Icons.cancel_outlined
                  : Icons.error_outline;
              final elapsed = Duration(milliseconds: record.durationMs);
              final mins = elapsed.inMinutes;
              final secs = elapsed.inSeconds % 60;
              final elapsedStr = mins > 0 ? '${mins}m ${secs}s' : '${secs}s';
              final ago = _timeAgo(record.startedAt);

              return Container(
                margin: const EdgeInsets.only(bottom: 4),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: cs.outlineVariant),
                ),
                child: Row(
                  children: [
                    Icon(statusIcon, size: 16, color: statusColor),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        ago,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    Text(
                      elapsedStr,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                        fontFamily: 'monospace',
                      ),
                    ),
                    if (record.logPath != null) ...[
                      const SizedBox(width: 6),
                      InkWell(
                        onTap: () => Process.run('open', [record.logPath!]),
                        child: Tooltip(
                          message: 'View log',
                          child: Icon(
                            Icons.receipt_long_outlined,
                            size: 14,
                            color: cs.primary,
                          ),
                        ),
                      ),
                    ],
                    if (archive != null) ...[
                      const SizedBox(width: 6),
                      InkWell(
                        onTap: () => _openReport(context, archive),
                        child: Tooltip(
                          message: 'Open report',
                          child: Icon(
                            Icons.bar_chart_outlined,
                            size: 14,
                            color: cs.primary,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(width: 6),
                    InkWell(
                      onTap: () => RunPicker.reRun(
                        context,
                        project: project,
                        surface: surface,
                        record: record,
                      ),
                      child: Tooltip(
                        message:
                            'Re-run — reopens the picker pre-filled '
                            'with this run\'s environment.',
                        child: Icon(Icons.replay, size: 14, color: cs.primary),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        );
      },
    );
  }

  Future<void> _openReport(BuildContext context, ReportArchive archive) async {
    // ReportOpener actually serves the report (Allure CLI, else a throwaway
    // static server) instead of double-clicking index.html, which fails
    // under file:// (CORS) — same helper the Reports screen uses.
    final message = await ReportOpener().open(archive.archivePath);
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

