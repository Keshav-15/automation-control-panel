import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_boilerplate/src/base/qa/report_archive_store.dart';
import 'package:flutter_boilerplate/src/base/qa/report_opener.dart';
import 'package:flutter_boilerplate/src/models/qa/project_model.dart';
import 'package:flutter_boilerplate/src/models/qa/report_archive_model.dart';
import 'package:flutter_boilerplate/src/models/qa/run_record_model.dart';
import 'package:flutter_boilerplate/src/providers/qa/project_provider.dart';
import 'package:flutter_boilerplate/src/providers/qa/run_provider.dart';
import 'package:flutter_boilerplate/src/ui/qa/runner/run_picker.dart';
import 'package:provider/provider.dart';

/// All runs across every project, newest first — the global counterpart to
/// each surface's own "Recent runs" section. See
/// docs/RUN_EXPERIENCE_REDESIGN.md §9.
class RecentRunsScreen extends StatefulWidget {
  const RecentRunsScreen({super.key});

  @override
  State<RecentRunsScreen> createState() => _RecentRunsScreenState();
}

enum _StatusFilter { all, done, failed, cancelled }

class _RecentRunsScreenState extends State<RecentRunsScreen> {
  _StatusFilter _status = _StatusFilter.all;
  // null = all projects. A project id, not the object, so a deleted
  // project's filter selection just falls back to "All" instead of crashing.
  String? _projectId;

  bool _matchesStatus(RunRecord r) => switch (_status) {
        _StatusFilter.all => true,
        _StatusFilter.done => r.status == 'done',
        _StatusFilter.failed => r.status != 'done' && r.status != 'cancelled',
        _StatusFilter.cancelled => r.status == 'cancelled',
      };

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: cs.surface,
        elevation: 0,
        title: const Text('Recent runs'),
      ),
      body: Consumer2<RunProvider, ProjectProvider>(
        builder: (context, run, projects, _) {
          final allHistory = run.history;
          if (allHistory.isEmpty) {
            return Center(
              child: Text('No runs yet',
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: cs.onSurfaceVariant)),
            );
          }

          // Only offer a project filter for projects that actually appear in
          // history — no point listing one with nothing to show.
          final projectIdsInHistory =
              allHistory.map((r) => r.projectId).whereType<String>().toSet();
          final filterableProjects = projects.projects
              .where((p) => projectIdsInHistory.contains(p.id))
              .toList();
          if (_projectId != null &&
              !filterableProjects.any((p) => p.id == _projectId)) {
            // Selected project no longer has any history (or was deleted) —
            // fall back to "All" rather than silently showing nothing.
            _projectId = null;
          }

          final history = allHistory
              .where(_matchesStatus)
              .where((r) => _projectId == null || r.projectId == _projectId)
              .toList();

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    for (final s in _StatusFilter.values)
                      ChoiceChip(
                        label: Text(switch (s) {
                          _StatusFilter.all => 'All',
                          _StatusFilter.done => 'Passed',
                          _StatusFilter.failed => 'Failed',
                          _StatusFilter.cancelled => 'Cancelled',
                        }),
                        selected: _status == s,
                        onSelected: (_) => setState(() => _status = s),
                      ),
                    if (filterableProjects.length > 1) ...[
                      const SizedBox(width: 8, height: 1),
                      DropdownButton<String?>(
                        value: _projectId,
                        hint: const Text('All projects'),
                        underline: const SizedBox.shrink(),
                        items: [
                          const DropdownMenuItem(
                              value: null, child: Text('All projects')),
                          ...filterableProjects.map((p) => DropdownMenuItem(
                              value: p.id, child: Text(p.name))),
                        ],
                        onChanged: (v) => setState(() => _projectId = v),
                      ),
                    ],
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: history.isEmpty
                    ? Center(
                        child: Text('No runs match this filter.',
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(color: cs.onSurfaceVariant)),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: history.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final record = history[index];
                          final project = record.projectId == null
                              ? null
                              : projects.projects
                                  .where((p) => p.id == record.projectId)
                                  .firstOrNull;
                          final surface =
                              project?.surfaceById(record.recipeId);
                          final archive = (project != null && surface != null)
                              ? ReportArchiveStore.forSurface(
                                      project.id, surface.id)
                                  .where((a) => a.runId == record.runId)
                                  .firstOrNull
                              : null;
                          return _RecentRunRow(
                            record: record,
                            project: project,
                            surface: surface,
                            archive: archive,
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _RecentRunRow extends StatelessWidget {
  final RunRecord record;
  final ProjectConfig? project;
  final SurfaceConfig? surface;
  final ReportArchive? archive;

  const _RecentRunRow({
    required this.record,
    this.project,
    this.surface,
    this.archive,
  });

  Future<void> _openReport(BuildContext context) async {
    final a = archive;
    if (a == null) return;
    final message = await ReportOpener().open(a.archivePath);
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final (icon, color) = switch (record.status) {
      'done' => (Icons.check_circle_outline, cs.primary),
      'cancelled' => (Icons.cancel_outlined, cs.onSurfaceVariant),
      _ => (Icons.error_outline, cs.error),
    };
    final elapsed = record.duration;
    final mins = elapsed.inMinutes;
    final secs = elapsed.inSeconds % 60;
    final elapsedStr = mins > 0 ? '${mins}m ${secs}s' : '${secs}s';
    // project/surface both resolvable is what a re-run actually needs.
    final canReRun = project != null && surface != null;

    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(
        project != null ? '${project!.name} — ${record.recipeName}' : record.recipeName,
      ),
      subtitle: Text(
        '${_timeAgo(record.startedAt)} · $elapsedStr'
        '${record.environmentId != null ? ' · ${record.environmentId}' : ''}',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (record.logPath != null)
            IconButton(
              tooltip: 'View log',
              icon: const Icon(Icons.receipt_long_outlined, size: 20),
              onPressed: () => Process.run('open', [record.logPath!]),
            ),
          if (archive != null)
            IconButton(
              tooltip: 'Open report',
              icon: const Icon(Icons.bar_chart_outlined, size: 20),
              onPressed: () => _openReport(context),
            ),
          IconButton(
            tooltip: canReRun
                ? 'Re-run — reopens the picker pre-filled with this run\'s environment.'
                : 'Original project no longer exists — can\'t re-run this one.',
            icon: const Icon(Icons.replay),
            onPressed: canReRun
                ? () => RunPicker.reRun(context,
                    project: project!, surface: surface!, record: record)
                : null,
          ),
        ],
      ),
    );
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}
