import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_boilerplate/src/base/qa/report_archive_store.dart';
import 'package:flutter_boilerplate/src/base/qa/report_opener.dart';
import 'package:flutter_boilerplate/src/models/qa/report_archive_model.dart';
import 'package:flutter_boilerplate/src/models/qa/run_model.dart';
import 'package:flutter_boilerplate/src/providers/qa/run_provider.dart';
import 'package:provider/provider.dart';

/// Live/recent runs screen (docs/RUN_EXPERIENCE_REDESIGN.md §9/§10) — every
/// entry currently in [RunProvider.activeRuns] (running, or finished but not
/// yet dismissed), each as an expandable card mirroring the visual style of
/// [project_detail_screen.dart]'s surface cards. Unlike [RunPanel] (which
/// only ever shows the *primary* run), this shows every concurrent run at
/// once — the whole point of the registry (§10).
///
/// Deliberately thin on metadata: [RunEntry] today only carries `recipeId`
/// (== the surface id for a project-backed run), `recipeName`, and
/// `deviceUdid` — no `projectId`/`environment`/`script` fields yet (those are
/// step 10's "re-run" metadata work, in flight concurrently — see this file's
/// class doc note below and the design doc's step-9 entry for what's
/// deferred).
class ActiveRunsScreen extends StatefulWidget {
  const ActiveRunsScreen({super.key});

  @override
  State<ActiveRunsScreen> createState() => _ActiveRunsScreenState();
}

class _ActiveRunsScreenState extends State<ActiveRunsScreen> {
  final Set<String> _expanded = {};

  /// Drives the elapsed-time readout for running entries; RunProvider only
  /// notifies on log/step activity, which can be silent for minutes — same
  /// reason RunPanel keeps its own ticker.
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && context.read<RunProvider>().isRunning) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.surface,
        elevation: 0,
        title: const Text('Active runs'),
      ),
      body: Consumer<RunProvider>(
        builder: (context, run, _) {
          final entries = run.activeRuns;
          if (entries.isEmpty) {
            return Center(
              child: Text(
                'No runs in progress',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            // Newest first — the run someone just kicked off is the one
            // they came here to watch.
            itemCount: entries.length,
            itemBuilder: (context, index) {
              final entry = entries[entries.length - 1 - index];
              return _RunEntryCard(
                key: ValueKey(entry.id),
                entry: entry,
                run: run,
                isExpanded: _expanded.contains(entry.id),
                onToggleExpand: () => setState(() {
                  if (!_expanded.add(entry.id)) _expanded.remove(entry.id);
                }),
              );
            },
          );
        },
      ),
    );
  }
}

// ── Card ──────────────────────────────────────────────────────────────────────

class _RunEntryCard extends StatelessWidget {
  final RunEntry entry;
  final RunProvider run;
  final bool isExpanded;
  final VoidCallback onToggleExpand;

  const _RunEntryCard({
    super.key,
    required this.entry,
    required this.run,
    required this.isExpanded,
    required this.onToggleExpand,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isRunning = entry.status == RunStatus.running;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isRunning
              ? cs.primary
              : isExpanded
                  ? cs.outline
                  : cs.outlineVariant,
          width: isRunning || isExpanded ? 1.5 : 1,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: onToggleExpand,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  _StatusDot(status: entry.status),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.recipeName,
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _subtitle(entry),
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    _fmtDuration(entry.elapsed),
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          fontFamily: 'monospace',
                          color: cs.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(width: 12),
                  if (isRunning)
                    OutlinedButton.icon(
                      onPressed: () => run.cancel(entry.id),
                      icon: const Icon(Icons.stop_circle_outlined, size: 16),
                      label: const Text('Cancel'),
                      style: OutlinedButton.styleFrom(foregroundColor: cs.error),
                    )
                  else
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _ViewReportButton(runId: entry.id),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: () => run.reset(entry.id),
                          icon: const Icon(Icons.close, size: 16),
                          label: const Text('Dismiss'),
                        ),
                      ],
                    ),
                  const SizedBox(width: 4),
                  Tooltip(
                    message: 'Copy all logs',
                    child: IconButton(
                      icon: const Icon(Icons.copy_outlined, size: 16),
                      onPressed: entry.logs.isEmpty
                          ? null
                          : () async {
                              await Clipboard.setData(ClipboardData(
                                text: entry.logs.map((l) => l.text).join('\n'),
                              ));
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Logs copied.')),
                                );
                              }
                            },
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    isExpanded ? Icons.expand_less : Icons.expand_more,
                    color: cs.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
          if (isExpanded) ...[
            const Divider(height: 1),
            SizedBox(
              height: 320,
              child: _EntryLogView(entry: entry),
            ),
          ],
        ],
      ),
    );
  }

  static String _subtitle(RunEntry entry) {
    final parts = <String>[];
    if (entry.deviceUdid != null) parts.add('device ${entry.deviceUdid}');
    if (entry.status == RunStatus.running) {
      final step = entry.currentStepName;
      parts.add(step == null
          ? 'Starting…'
          : 'Step ${entry.stepIndex}/${entry.stepTotal} — $step');
    } else {
      final failed =
          entry.stepResults.where((s) => s.outcome.isTerminal).firstOrNull;
      if (failed != null) {
        parts.add('${failed.step.name} — ${failed.note ?? failed.outcome.name}');
      } else {
        final skipped = entry.stepResults
            .where((s) => s.outcome == StepOutcome.skipped)
            .length;
        final ran = entry.stepResults.length - skipped;
        parts.add('$ran steps run${skipped > 0 ? ', $skipped skipped' : ''}');
      }
    }
    return parts.join(' · ');
  }
}

class _StatusDot extends StatelessWidget {
  final RunStatus status;
  const _StatusDot({required this.status});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (status == RunStatus.running) {
      return SizedBox(
        width: 14,
        height: 14,
        child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary),
      );
    }
    final color = switch (status) {
      RunStatus.done => Colors.green,
      RunStatus.failed => cs.error,
      RunStatus.cancelled => Colors.orange,
      RunStatus.running => cs.primary, // unreachable, handled above
    };
    return Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

/// "View report" — only shown once a [ReportArchive] exists for this run.
/// Looked up once per build via [ReportArchiveStore.findByRunId] (a cheap
/// SharedPreferences read, same cost as the rest of this app's store reads).
class _ViewReportButton extends StatefulWidget {
  final String runId;
  const _ViewReportButton({required this.runId});

  @override
  State<_ViewReportButton> createState() => _ViewReportButtonState();
}

class _ViewReportButtonState extends State<_ViewReportButton> {
  final _opener = ReportOpener();
  bool _opening = false;

  Future<void> _open(ReportArchive report) async {
    setState(() => _opening = true);
    final message = await _opener.open(report.archivePath);
    if (!mounted) return;
    setState(() => _opening = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final report = ReportArchiveStore.findByRunId(widget.runId);
    if (report == null) return const SizedBox.shrink();
    return OutlinedButton.icon(
      onPressed: _opening ? null : () => _open(report),
      icon: const Icon(Icons.assessment_outlined, size: 16),
      label: const Text('View report'),
    );
  }
}

// ── Log view (mirrors RunPanel's _LogView, adapted per-entry) ──────────────

class _EntryLogView extends StatefulWidget {
  final RunEntry entry;
  const _EntryLogView({required this.entry});

  @override
  State<_EntryLogView> createState() => _EntryLogViewState();
}

class _EntryLogViewState extends State<_EntryLogView> {
  final ScrollController _scroll = ScrollController();
  bool _follow = true;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final atBottom = _scroll.offset >= _scroll.position.maxScrollExtent - 40;
    if (atBottom != _follow) setState(() => _follow = atBottom);
  }

  void _scrollToEnd() {
    if (!_follow || !_scroll.hasClients) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final logs = widget.entry.logs;
    _scrollToEnd();
    if (logs.isEmpty) {
      return const Center(child: Text('Waiting for output…'));
    }
    return Column(
      children: [
        Expanded(
          child: SelectionArea(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              itemCount: logs.length + (widget.entry.logsTruncated ? 1 : 0),
              itemBuilder: (context, index) {
                if (widget.entry.logsTruncated) {
                  if (index == 0) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        '… earlier output trimmed '
                        '(keeping the last ${RunProvider.maxLogLines} lines)',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              fontStyle: FontStyle.italic,
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                      ),
                    );
                  }
                  return _LogRow(text: logs[index - 1].text, isError: logs[index - 1].isError);
                }
                return _LogRow(text: logs[index].text, isError: logs[index].isError);
              },
            ),
          ),
        ),
        if (!_follow)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: TextButton.icon(
              onPressed: () {
                setState(() => _follow = true);
                _scrollToEnd();
              },
              icon: const Icon(Icons.arrow_downward, size: 14),
              label: const Text('Jump to latest'),
            ),
          ),
      ],
    );
  }
}

class _LogRow extends StatelessWidget {
  final String text;
  final bool isError;
  const _LogRow({required this.text, required this.isError});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Text(
      text,
      style: TextStyle(
        fontFamily: 'monospace',
        fontSize: 12,
        height: 1.45,
        color: isError ? scheme.error : scheme.onSurface,
      ),
    );
  }
}

String _fmtDuration(Duration d) {
  final m = d.inMinutes;
  final s = d.inSeconds % 60;
  return m < 1 ? '${s}s' : '${m}m ${s.toString().padLeft(2, '0')}s';
}
