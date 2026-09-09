import 'package:flutter/material.dart';
import 'package:flutter_boilerplate/src/base/dependencyinjection/locator.dart';
import 'package:flutter_boilerplate/src/base/utils/constants/navigation_route_constants.dart';
import 'package:flutter_boilerplate/src/base/utils/navigation_utils.dart';
import 'package:flutter_boilerplate/src/models/qa/project_model.dart';
import 'package:flutter_boilerplate/src/providers/qa/project_provider.dart';
import 'package:flutter_boilerplate/src/ui/qa/commands/command_library_screen.dart';
import 'package:flutter_boilerplate/src/ui/qa/projects/project_detail_screen.dart';
import 'package:provider/provider.dart';

/// Landing screen — shows all projects with pinned at top and recent below.
/// The entry point for the multi-project flow (initial route).
class ProjectsListScreen extends StatefulWidget {
  const ProjectsListScreen({super.key});

  @override
  State<ProjectsListScreen> createState() => _ProjectsListScreenState();
}

class _ProjectsListScreenState extends State<ProjectsListScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() => setState(() => _query = _searchCtrl.text));
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.surface,
        elevation: 0,
        title: Row(
          children: [
            const Text('🧪', style: TextStyle(fontSize: 22)),
            const SizedBox(width: 10),
            Text(
              'QA Control Center',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        actions: [
          // Devices (global — simulators/emulators/physical devices)
          Tooltip(
            message: 'Devices',
            child: IconButton(
              icon: const Icon(Icons.devices_outlined),
              onPressed: () => locator<NavigationUtils>().push(routeDevices),
            ),
          ),
          // Recent runs (global, across every project)
          Tooltip(
            message: 'Recent runs',
            child: IconButton(
              icon: const Icon(Icons.history),
              onPressed: () =>
                  locator<NavigationUtils>().push(routeRecentRuns),
            ),
          ),
          // Import project from JSON
          Tooltip(
            message: 'Import project from JSON',
            child: IconButton(
              icon: const Icon(Icons.file_download_outlined),
              onPressed: () => _importProject(context),
            ),
          ),
          // Create new project
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton.icon(
              onPressed: () => locator<NavigationUtils>()
                  .push(routeCreateProject),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('New project'),
            ),
          ),
        ],
      ),
      body: Consumer<ProjectProvider>(
        builder: (context, provider, _) {
          if (provider.loading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (provider.error != null) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, size: 48, color: Colors.red),
                  const SizedBox(height: 12),
                  Text(provider.error!),
                ],
              ),
            );
          }

          if (provider.projects.isEmpty) {
            return _EmptyState(onCreatePressed: () {
              locator<NavigationUtils>().push(routeCreateProject);
            });
          }

          final query = _query.trim().toLowerCase();
          final filtered = query.isEmpty
              ? provider.projects
              : provider.projects
                  .where((p) => p.name.toLowerCase().contains(query))
                  .toList();

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                child: TextField(
                  controller: _searchCtrl,
                  decoration: InputDecoration(
                    isDense: true,
                    prefixIcon: const Icon(Icons.search, size: 20),
                    hintText: 'Search projects…',
                    border: const OutlineInputBorder(),
                    suffixIcon: query.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: _searchCtrl.clear,
                          )
                        : null,
                  ),
                ),
              ),
              Expanded(
                child: filtered.isEmpty
                    ? Center(
                        child: Text(
                          'No projects match "$_query".',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color:
                                    Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      )
                    : _ProjectList(projects: filtered),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _importProject(BuildContext context) async {
    final provider = context.read<ProjectProvider>();
    final imported = await provider.importProjectFromFile();
    if (imported == null) return;

    // Open the edit screen so the user can verify + remap paths.
    if (context.mounted) {
      locator<NavigationUtils>().push(
        routeCreateProject,
        arguments: imported,
      );
    }
  }
}

// ── Project list ──────────────────────────────────────────────────────────────

class _ProjectList extends StatelessWidget {
  final List<ProjectConfig> projects;
  const _ProjectList({required this.projects});

  @override
  Widget build(BuildContext context) {
    final pinned = projects.where((p) => p.isPinned).toList();
    final recent = projects.where((p) => !p.isPinned).toList();

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        if (pinned.isNotEmpty) ...[
          _sectionLabel(context, '📌  Pinned'),
          const SizedBox(height: 10),
          ...pinned.map((p) => _ProjectCard(project: p)),
          const SizedBox(height: 24),
        ],
        if (recent.isNotEmpty) ...[
          _sectionLabel(context, '🕐  All projects'),
          const SizedBox(height: 10),
          ...recent.map((p) => _ProjectCard(project: p)),
        ],
      ],
    );
  }

  Widget _sectionLabel(BuildContext context, String text) => Text(
        text,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      );
}

// ── Project card ──────────────────────────────────────────────────────────────

class _ProjectCard extends StatelessWidget {
  final ProjectConfig project;
  const _ProjectCard({required this.project});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final lastOpened = project.lastOpenedAt;
    final openedLabel = lastOpened == null
        ? 'Never opened'
        : 'Last opened ${_relativeTime(lastOpened)}';

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _openProject(context),
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: cs.outlineVariant),
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          child: Row(
            children: [
              // Surfaces chips
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          project.name,
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        if (project.isPinned) ...[
                          const SizedBox(width: 6),
                          Icon(Icons.push_pin_rounded,
                              size: 14, color: cs.primary),
                        ],
                      ],
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      children: project.surfaces
                          .map((s) => _SurfaceChip(surface: s))
                          .toList(),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      openedLabel,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
              // Context menu
              _ProjectMenu(project: project),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openProject(BuildContext context) async {
    await context.read<ProjectProvider>().openProject(project);
    if (context.mounted) {
      locator<NavigationUtils>().push(
        routeProjectDetail,
        arguments: ProjectDetailArgs(project: project),
      );
    }
  }

  static String _relativeTime(DateTime t) {
    final diff = DateTime.now().difference(t);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${t.day}/${t.month}/${t.year}';
  }
}

// ── Surface chip ──────────────────────────────────────────────────────────────

class _SurfaceChip extends StatelessWidget {
  final dynamic surface;
  const _SurfaceChip({required this.surface});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        '${surface.icon}  ${surface.name}',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSecondaryContainer,
            ),
      ),
    );
  }
}

// ── Context menu ──────────────────────────────────────────────────────────────

class _ProjectMenu extends StatelessWidget {
  final ProjectConfig project;
  const _ProjectMenu({required this.project});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_ProjectAction>(
      tooltip: 'Project options',
      icon: const Icon(Icons.more_vert),
      onSelected: (action) => _onAction(context, action),
      itemBuilder: (_) => [
        PopupMenuItem(
          value: _ProjectAction.open,
          child: const ListTile(
            leading: Icon(Icons.open_in_new, size: 20),
            title: Text('Open'),
            contentPadding: EdgeInsets.zero,
            dense: true,
          ),
        ),
        PopupMenuItem(
          value: _ProjectAction.pin,
          child: ListTile(
            leading: Icon(
              project.isPinned ? Icons.push_pin_outlined : Icons.push_pin,
              size: 20,
            ),
            title: Text(project.isPinned ? 'Unpin' : 'Pin'),
            contentPadding: EdgeInsets.zero,
            dense: true,
          ),
        ),
        PopupMenuItem(
          value: _ProjectAction.edit,
          child: const ListTile(
            leading: Icon(Icons.edit_outlined, size: 20),
            title: Text('Edit project'),
            contentPadding: EdgeInsets.zero,
            dense: true,
          ),
        ),
        PopupMenuItem(
          value: _ProjectAction.commands,
          child: const ListTile(
            leading: Icon(Icons.tune_outlined, size: 20),
            title: Text('Commands'),
            contentPadding: EdgeInsets.zero,
            dense: true,
          ),
        ),
        PopupMenuItem(
          value: _ProjectAction.export,
          child: const ListTile(
            leading: Icon(Icons.file_upload_outlined, size: 20),
            title: Text('Export JSON'),
            contentPadding: EdgeInsets.zero,
            dense: true,
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: _ProjectAction.delete,
          child: ListTile(
            leading: Icon(Icons.delete_outline,
                size: 20,
                color: Theme.of(context).colorScheme.error),
            title: Text('Delete',
                style: TextStyle(
                    color: Theme.of(context).colorScheme.error)),
            contentPadding: EdgeInsets.zero,
            dense: true,
          ),
        ),
      ],
    );
  }

  Future<void> _onAction(BuildContext context, _ProjectAction action) async {
    final provider = context.read<ProjectProvider>();
    switch (action) {
      case _ProjectAction.open:
        await provider.openProject(project);
        if (context.mounted) {
          locator<NavigationUtils>().push(
            routeProjectDetail,
            arguments: ProjectDetailArgs(project: project),
          );
        }
      case _ProjectAction.pin:
        await provider.togglePin(project);
      case _ProjectAction.edit:
        locator<NavigationUtils>()
            .push(routeEditProject, arguments: project);
      case _ProjectAction.commands:
        locator<NavigationUtils>().push(
          routeCommandLibrary,
          arguments: CommandLibraryArgs(project: project),
        );
      case _ProjectAction.export:
        final path = await provider.exportProject(project);
        if (context.mounted && path != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Exported to $path')),
          );
        }
      case _ProjectAction.delete:
        final confirmed = await _confirmDelete(context);
        if (confirmed == true) await provider.deleteProject(project.id);
    }
  }

  Future<bool?> _confirmDelete(BuildContext context) => showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Delete project?'),
          content: Text(
            'This removes "${project.name}" from this device. '
            'Commands and settings are deleted — exported JSON is not affected.',
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
}

enum _ProjectAction { open, pin, edit, commands, export, delete }

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final VoidCallback onCreatePressed;
  const _EmptyState({required this.onCreatePressed});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('🧪', style: TextStyle(fontSize: 56)),
          const SizedBox(height: 20),
          Text(
            'No projects yet',
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Create a project to start running your test suites.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: onCreatePressed,
            icon: const Icon(Icons.add),
            label: const Text('Create first project'),
          ),
        ],
      ),
    );
  }
}
