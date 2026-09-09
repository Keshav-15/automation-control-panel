import 'package:flutter/material.dart';
import 'package:flutter_boilerplate/src/base/dependencyinjection/locator.dart';
import 'package:flutter_boilerplate/src/base/utils/constants/navigation_route_constants.dart';
import 'package:flutter_boilerplate/src/base/utils/navigation_utils.dart';
import 'package:flutter_boilerplate/src/models/qa/project_model.dart';
import 'package:flutter_boilerplate/src/providers/qa/project_provider.dart';
import 'package:flutter_boilerplate/src/ui/qa/commands/command_edit_screen.dart';
import 'package:flutter_boilerplate/src/ui/qa/commands/command_tile.dart';
import 'package:provider/provider.dart';

/// Route arguments for [SurfaceCommandManagerScreen].
class SurfaceCommandManagerArgs {
  final ProjectConfig project;
  final String surfaceId;

  /// Only commands carrying at least one of these tags are shown/creatable
  /// here — e.g. `['test']` for the Script commands manager, `['git',
  /// 'prerequisite']` for the Prerequisites manager (two tags both count as
  /// "prerequisite", same as [ProjectConfig.prerequisiteCommandsFor]).
  final List<String> stageTags;
  final String title;

  const SurfaceCommandManagerArgs({
    required this.project,
    required this.surfaceId,
    required this.stageTags,
    required this.title,
  });
}

/// A single surface's commands for one pipeline stage — replaces the old
/// whole-project tabs-per-surface Command Library for this use case. Search
/// + drag-to-reorder + tap-to-edit + remove/delete + add, scoped to just
/// this surface and this stage, so it isn't confusing with unrelated
/// surfaces/stages mixed in.
class SurfaceCommandManagerScreen extends StatefulWidget {
  final SurfaceCommandManagerArgs args;
  const SurfaceCommandManagerScreen({super.key, required this.args});

  @override
  State<SurfaceCommandManagerScreen> createState() =>
      _SurfaceCommandManagerScreenState();
}

class _SurfaceCommandManagerScreenState
    extends State<SurfaceCommandManagerScreen> {
  late ProjectConfig _project;
  final _searchCtrl = TextEditingController();
  String _query = '';

  String get _surfaceId => widget.args.surfaceId;
  SurfaceConfig? get _surface => _project.surfaceById(_surfaceId);
  bool get _isSearching => _query.trim().isNotEmpty;

  bool _matchesStage(CommandConfig c) =>
      widget.args.stageTags.any(c.hasTag);

  bool _matchesSearch(CommandConfig c) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return c.name.toLowerCase().contains(q) ||
        c.command.toLowerCase().contains(q);
  }

  @override
  void initState() {
    super.initState();
    _project = widget.args.project;
    _searchCtrl.addListener(() => setState(() => _query = _searchCtrl.text));
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _refresh() {
    final provider = context.read<ProjectProvider>();
    final updated = provider.projects
        .firstWhere((p) => p.id == _project.id, orElse: () => _project);
    setState(() => _project = updated);
  }

  Future<void> _openEdit({CommandConfig? existing}) async {
    await locator<NavigationUtils>().push(
      routeCommandEdit,
      arguments: CommandEditArgs(
        project: _project,
        surfaceId: _surfaceId,
        existing: existing,
        presetTag: existing == null ? widget.args.stageTags.first : null,
      ),
    );
    if (mounted) _refresh();
  }

  Future<void> _toggleAssignment(CommandConfig cmd) async {
    final surface = _surface;
    if (surface == null) return;
    final ids = List<String>.of(surface.commandIds);
    if (ids.contains(cmd.id)) {
      ids.remove(cmd.id);
    } else {
      ids.add(cmd.id);
    }
    final updated = await context.read<ProjectProvider>().updateSurfaceCommandIds(
          project: _project,
          surfaceId: _surfaceId,
          commandIds: ids,
        );
    setState(() => _project = updated);
  }

  Future<void> _deleteCommand(CommandConfig cmd) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete command?'),
        content: Text(
            '"${cmd.name}" will be removed from the project library and all surfaces.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final updated = await context.read<ProjectProvider>().deleteProjectCommand(
          project: _project,
          commandId: cmd.id,
        );
    setState(() => _project = updated);
  }

  /// Reorders just the stage-tag subsequence within [surface.commandIds],
  /// leaving every other command's position untouched — the full list still
  /// has to stay the single source of truth for execution order across
  /// every stage, so this can't just replace it with the filtered subset.
  Future<void> _onReorder(List<CommandConfig> visible, int oldIndex, int newIndex) async {
    final surface = _surface;
    if (surface == null) return;
    if (newIndex > oldIndex) newIndex--;
    final subOrder = visible.map((c) => c.id).toList();
    final moved = subOrder.removeAt(oldIndex);
    subOrder.insert(newIndex, moved);

    final full = List<String>.of(surface.commandIds);
    final subsetIds = visible.map((c) => c.id).toSet();
    final positions = [
      for (var i = 0; i < full.length; i++)
        if (subsetIds.contains(full[i])) i,
    ];
    for (var i = 0; i < positions.length; i++) {
      full[positions[i]] = subOrder[i];
    }

    final updated = await context.read<ProjectProvider>().updateSurfaceCommandIds(
          project: _project,
          surfaceId: _surfaceId,
          commandIds: full,
        );
    setState(() => _project = updated);
  }

  @override
  Widget build(BuildContext context) {
    final surface = _surface;
    final cs = Theme.of(context).colorScheme;

    final assignedAll = surface == null
        ? <CommandConfig>[]
        : _project.commandsForSurface(_surfaceId).where(_matchesStage).toList();
    final assignedIds = assignedAll.map((c) => c.id).toSet();
    final unassignedAll = _project.commands
        .where((c) => _matchesStage(c) && !assignedIds.contains(c.id))
        .toList();

    final assigned = assignedAll.where(_matchesSearch).toList();
    final unassigned = unassignedAll.where(_matchesSearch).toList();

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: cs.surface,
        elevation: 0,
        title: Text(widget.args.title),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton.icon(
              onPressed: () => _openEdit(),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add command'),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                isDense: true,
                prefixIcon: const Icon(Icons.search, size: 20),
                hintText: 'Search commands…',
                border: const OutlineInputBorder(),
                suffixIcon: _isSearching
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: _searchCtrl.clear,
                      )
                    : null,
              ),
            ),
          ),
          Expanded(
            child: assignedAll.isEmpty && unassignedAll.isEmpty
                ? Center(
                    child: Text(
                      'No ${widget.args.title.toLowerCase()} yet.\nUse '
                      '"Add command" to create one.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                    ),
                  )
                : assigned.isEmpty && unassigned.isEmpty
                    ? Center(
                        child: Text(
                          'No commands match "$_query".',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: cs.onSurfaceVariant),
                        ),
                      )
                    : CustomScrollView(
                        slivers: [
                          if (assignedAll.isNotEmpty) ...[
                            SliverPadding(
                              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                              sliver: SliverToBoxAdapter(
                                child: Text(
                                  _isSearching
                                      ? 'In this surface'
                                      : 'In this surface — drag to reorder',
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelMedium
                                      ?.copyWith(color: cs.onSurfaceVariant),
                                ),
                              ),
                            ),
                            if (_isSearching)
                              SliverPadding(
                                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                                sliver: SliverList(
                                  delegate: SliverChildBuilderDelegate(
                                    (context, index) {
                                      final cmd = assigned[index];
                                      return CommandTile(
                                        key: ValueKey('assigned_${cmd.id}'),
                                        command: cmd,
                                        assignedSurfaces: [surface!],
                                        allSurfaces: _project.surfaces,
                                        showDragHandle: false,
                                        isInCurrentSurface: true,
                                        onEdit: () => _openEdit(existing: cmd),
                                        onDelete: () => _deleteCommand(cmd),
                                        onToggleSurface: (_) =>
                                            _toggleAssignment(cmd),
                                      );
                                    },
                                    childCount: assigned.length,
                                  ),
                                ),
                              )
                            else
                              SliverPadding(
                                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                                sliver: SliverReorderableList(
                                  itemCount: assigned.length,
                                  onReorder: (o, n) => _onReorder(assigned, o, n),
                                  itemBuilder: (context, index) {
                                    final cmd = assigned[index];
                                    return ReorderableDelayedDragStartListener(
                                      key: ValueKey(cmd.id),
                                      index: index,
                                      child: CommandTile(
                                        key: ValueKey('assigned_${cmd.id}'),
                                        command: cmd,
                                        assignedSurfaces: [surface!],
                                        allSurfaces: _project.surfaces,
                                        showDragHandle: true,
                                        isInCurrentSurface: true,
                                        onEdit: () => _openEdit(existing: cmd),
                                        onDelete: () => _deleteCommand(cmd),
                                        onToggleSurface: (_) =>
                                            _toggleAssignment(cmd),
                                      ),
                                    );
                                  },
                                ),
                              ),
                          ],
                          if (unassigned.isNotEmpty) ...[
                            SliverPadding(
                              padding: EdgeInsets.fromLTRB(
                                  16, assigned.isEmpty ? 16 : 24, 16, 0),
                              sliver: SliverToBoxAdapter(
                                child: Text(
                                  'Available from library — tap ＋ to add',
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelMedium
                                      ?.copyWith(color: cs.onSurfaceVariant),
                                ),
                              ),
                            ),
                            SliverPadding(
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                              sliver: SliverList(
                                delegate: SliverChildBuilderDelegate(
                                  (context, index) {
                                    final cmd = unassigned[index];
                                    return CommandTile(
                                      key: ValueKey('unassigned_${cmd.id}'),
                                      command: cmd,
                                      assignedSurfaces: _project.surfaces
                                          .where((s) =>
                                              s.commandIds.contains(cmd.id))
                                          .toList(),
                                      allSurfaces: _project.surfaces,
                                      showDragHandle: false,
                                      isInCurrentSurface: false,
                                      onEdit: () => _openEdit(existing: cmd),
                                      onDelete: () => _deleteCommand(cmd),
                                      onToggleSurface: (_) =>
                                          _toggleAssignment(cmd),
                                    );
                                  },
                                  childCount: unassigned.length,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
          ),
        ],
      ),
    );
  }
}
