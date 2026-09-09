import 'package:flutter/material.dart';
import 'package:flutter_boilerplate/src/base/dependencyinjection/locator.dart';
import 'package:flutter_boilerplate/src/base/utils/constants/navigation_route_constants.dart';
import 'package:flutter_boilerplate/src/base/utils/navigation_utils.dart';
import 'package:flutter_boilerplate/src/controllers/qa/project_controller.dart';
import 'package:flutter_boilerplate/src/models/qa/project_model.dart';
import 'package:flutter_boilerplate/src/providers/qa/project_provider.dart';
import 'package:flutter_boilerplate/src/ui/qa/commands/command_edit_screen.dart';
import 'package:flutter_boilerplate/src/ui/qa/commands/command_tile.dart';
import 'package:provider/provider.dart';

/// Route arguments for [CommandLibraryScreen].
class CommandLibraryArgs {
  final ProjectConfig project;

  const CommandLibraryArgs({required this.project});
}

/// Project-wide command pool — create/edit/delete/duplicate any command,
/// see which surfaces it's assigned to, search/filter by tag or repo.
///
/// Managing one surface's commands for one pipeline stage (Prerequisites/
/// Script/Report) happens in [SurfaceCommandManagerScreen] instead — this
/// screen used to also have a tab per surface for that, which turned out
/// confusing (too many tabs, no focus on the one stage you actually came to
/// manage); this is now purely "the whole pool."
class CommandLibraryScreen extends StatefulWidget {
  final CommandLibraryArgs args;
  const CommandLibraryScreen({super.key, required this.args});

  @override
  State<CommandLibraryScreen> createState() => _CommandLibraryScreenState();
}

class _CommandLibraryScreenState extends State<CommandLibraryScreen> {
  late ProjectConfig _project;

  String? _filterTag;
  String? _filterRepoRole;
  final _searchCtrl = TextEditingController();
  String _query = '';

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

  // ── Mutations ─────────────────────────────────────────────────────────────

  Future<void> _duplicateCommand(CommandConfig cmd) async {
    final existingIds = _project.commands.map((c) => c.id).toSet();
    var newId = '${cmd.id}_copy';
    var n = 2;
    while (existingIds.contains(newId)) {
      newId = '${cmd.id}_copy$n';
      n++;
    }
    final copy = cmd.copyWith(id: newId, name: '${cmd.name} (copy)');
    final updated = await context.read<ProjectProvider>().upsertProjectCommand(
        project: _project, command: copy);
    if (mounted) setState(() => _project = updated);
  }

  Future<void> _openCommandEdit({CommandConfig? existing}) async {
    await locator<NavigationUtils>().push(
      routeCommandEdit,
      arguments: CommandEditArgs(project: _project, existing: existing),
    );
    if (!mounted) return;
    final provider = context.read<ProjectProvider>();
    final updated = provider.projects
        .firstWhere((p) => p.id == _project.id, orElse: () => _project);
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
            child: const Text('Cancel'),
          ),
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

  Future<void> _toggleSurfaceAssignment(
      CommandConfig cmd, String? surfaceId) async {
    if (surfaceId == null) return;
    final surface = _project.surfaceById(surfaceId);
    if (surface == null) return;
    final ids = List<String>.of(surface.commandIds);
    if (ids.contains(cmd.id)) {
      ids.remove(cmd.id);
    } else {
      ids.add(cmd.id);
    }
    final updated = await context.read<ProjectProvider>().updateSurfaceCommandIds(
          project: _project,
          surfaceId: surfaceId,
          commandIds: ids,
        );
    setState(() => _project = updated);
  }

  // ── Import ────────────────────────────────────────────────────────────────

  Future<void> _importCommands() async {
    final imported =
        await context.read<ProjectProvider>().importCommandsFromFile();
    if (imported == null || imported.isEmpty || !mounted) return;
    _showImportPreview(imported);
  }

  Future<void> _pasteJson() async {
    String? text;
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        final ctrl = TextEditingController();
        return AlertDialog(
          title: const Text('Paste JSON commands'),
          content: TextField(
            controller: ctrl,
            maxLines: 8,
            autofocus: true,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: '[{ "id": "...", "name": "...", ... }]',
            ),
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                text = ctrl.text.trim();
                Navigator.pop(ctx);
              },
              child: const Text('Import'),
            ),
          ],
        );
      },
    );
    if (text == null || text!.isEmpty || !mounted) return;

    final validRoles = _project.repos.keys.toSet();
    final imported = locator<ProjectController>().parseCommandsJson(
      text!,
      validRepoRoles: validRoles.isEmpty ? null : validRoles,
    );
    if (imported == null || imported.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'Could not parse JSON — check format and repoRole values.')),
        );
      }
      return;
    }
    _showImportPreview(imported);
  }

  Future<void> _showImportPreview(List<CommandConfig> imported) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
            'Add ${imported.length} command${imported.length > 1 ? 's' : ''} to library?'),
        content: SizedBox(
          width: 480,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: imported.length,
            itemBuilder: (_, i) {
              final c = imported[i];
              return ListTile(
                dense: true,
                leading: Icon(
                    kStageTagIcons[c.tags.firstOrNull] ?? Icons.code_outlined,
                    size: 16),
                title: Text(c.name),
                subtitle: Text(c.command,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Add to library'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    var current = _project;
    for (final cmd in imported) {
      current = await context.read<ProjectProvider>().upsertProjectCommand(
            project: current,
            command: cmd,
          );
    }
    if (mounted) setState(() => _project = current);
  }

  // ── Filter dialog ─────────────────────────────────────────────────────────

  int get _activeFilterCount =>
      (_filterTag != null ? 1 : 0) + (_filterRepoRole != null ? 1 : 0);

  List<String> get _allTags => _project.commands
      .expand((c) => c.tags)
      .toSet()
      .toList()
    ..sort();

  Future<void> _showFilterDialog() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Filter commands'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Tag', style: Theme.of(ctx).textTheme.labelLarge),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    FilterChip(
                      label: const Text('All'),
                      selected: _filterTag == null,
                      onSelected: (_) {
                        setState(() => _filterTag = null);
                        setDialogState(() {});
                      },
                    ),
                    ..._allTags.map((tag) {
                      final count = _project.commands
                          .where((c) => c.hasTag(tag))
                          .length;
                      return FilterChip(
                        avatar: kStageTagIcons.containsKey(tag)
                            ? Icon(kStageTagIcons[tag], size: 14)
                            : null,
                        label: Text('$tag ($count)'),
                        selected: _filterTag == tag,
                        onSelected: (_) {
                          setState(
                              () => _filterTag = _filterTag == tag ? null : tag);
                          setDialogState(() {});
                        },
                      );
                    }),
                  ],
                ),
                if (_project.repos.length > 1) ...[
                  const SizedBox(height: 20),
                  Text('Repo', style: Theme.of(ctx).textTheme.labelLarge),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      FilterChip(
                        avatar: const Icon(Icons.folder_outlined, size: 14),
                        label: const Text('All repos'),
                        selected: _filterRepoRole == null,
                        onSelected: (_) {
                          setState(() => _filterRepoRole = null);
                          setDialogState(() {});
                        },
                      ),
                      ..._project.repos.keys.map((role) {
                        final count = _project.commands
                            .where((c) => c.repoRole == role)
                            .length;
                        if (count == 0) return const SizedBox.shrink();
                        return FilterChip(
                          label: Text('$role ($count)'),
                          selected: _filterRepoRole == role,
                          onSelected: (_) {
                            setState(() => _filterRepoRole =
                                _filterRepoRole == role ? null : role);
                            setDialogState(() {});
                          },
                        );
                      }),
                    ],
                  ),
                ],
              ],
            ),
          ),
          actions: [
            if (_activeFilterCount > 0)
              TextButton(
                onPressed: () {
                  setState(() {
                    _filterTag = null;
                    _filterRepoRole = null;
                  });
                  setDialogState(() {});
                },
                child: const Text('Clear all'),
              ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final query = _query.trim().toLowerCase();
    final cmds = _project.commands
        .where((c) => _filterTag == null || c.hasTag(_filterTag!))
        .where((c) => _filterRepoRole == null || c.repoRole == _filterRepoRole)
        .where((c) =>
            query.isEmpty ||
            c.name.toLowerCase().contains(query) ||
            c.command.toLowerCase().contains(query))
        .toList();

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: cs.surface,
        elevation: 0,
        title: const Text('📦  Command Library'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Badge(
              label: Text('$_activeFilterCount'),
              isLabelVisible: _activeFilterCount > 0,
              child: IconButton(
                tooltip: 'Filter commands',
                icon: const Icon(Icons.filter_list),
                onPressed: _showFilterDialog,
              ),
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'Import',
            icon: const Icon(Icons.file_download_outlined),
            onSelected: (v) {
              if (v == 'file') _importCommands();
              if (v == 'paste') _pasteJson();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'file',
                child: ListTile(
                  leading: Icon(Icons.file_open_outlined, size: 20),
                  title: Text('Import from file'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'paste',
                child: ListTile(
                  leading: Icon(Icons.content_paste_go_outlined, size: 20),
                  title: Text('Paste JSON'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton.icon(
              onPressed: () => _openCommandEdit(),
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
                suffixIcon: _query.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: _searchCtrl.clear,
                      )
                    : null,
              ),
            ),
          ),
          Expanded(
            child: cmds.isEmpty
                ? _buildEmpty(context)
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: cmds.length,
                    itemBuilder: (context, i) {
                      final cmd = cmds[i];
                      final assignedSurfaces = _project.surfaces
                          .where((s) => s.commandIds.contains(cmd.id))
                          .toList();
                      return CommandTile(
                        key: ValueKey(cmd.id),
                        command: cmd,
                        assignedSurfaces: assignedSurfaces,
                        allSurfaces: _project.surfaces,
                        showDragHandle: false,
                        onEdit: () => _openCommandEdit(existing: cmd),
                        onDuplicate: () => _duplicateCommand(cmd),
                        onDelete: () => _deleteCommand(cmd),
                        onToggleSurface: (sid) =>
                            _toggleSurfaceAssignment(cmd, sid),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.list_alt_outlined, size: 48),
          const SizedBox(height: 16),
          Text(_query.isNotEmpty ? 'No commands match.' : 'No commands yet'),
          const SizedBox(height: 8),
          if (_query.isEmpty)
            Text(
              'Add commands to the project library and assign them to surfaces.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
        ],
      ),
    );
  }
}
