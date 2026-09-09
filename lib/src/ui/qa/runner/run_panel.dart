import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_boilerplate/src/base/qa/process_gateway.dart';
import 'package:flutter_boilerplate/src/models/qa/run_model.dart';
import 'package:flutter_boilerplate/src/providers/qa/run_provider.dart';
import 'package:provider/provider.dart';

/// Live pipeline output — header with step progress, scrolling log, Cancel.
///
/// Rendered by [HomeScreen] as a bottom pane whenever [RunProvider] is not idle.
class RunPanel extends StatefulWidget {
  const RunPanel({super.key});

  @override
  State<RunPanel> createState() => _RunPanelState();
}

class _RunPanelState extends State<RunPanel> {
  final ScrollController _scroll = ScrollController();

  /// Auto-follow the tail until the user scrolls up, then leave them alone.
  bool _follow = true;

  /// Drives the elapsed-time readout while a run is in flight; RunProvider
  /// only notifies on log/step activity, which can be silent for minutes.
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && context.read<RunProvider>().isRunning) setState(() {});
    });
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final atBottom =
        _scroll.offset >= _scroll.position.maxScrollExtent - 40;
    if (atBottom != _follow) setState(() => _follow = atBottom);
  }

  void _scrollToEnd() {
    if (!_follow || !_scroll.hasClients) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<RunProvider>(
      builder: (context, run, _) {
        if (run.isIdle) return const SizedBox.shrink();

        final decoration = BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerLowest,
          border: Border(
            top: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
          ),
        );

        // Minimized: just the header, and — critically — not wrapped in an
        // Expanded by whichever screen embeds this (see RunProvider.minimized's
        // doc) so it actually gives back the screen space instead of just
        // sitting empty inside a reserved flex share.
        if (run.minimized) {
          return Container(decoration: decoration, child: _RunHeader(run: run));
        }

        _scrollToEnd();
        return Container(
          decoration: decoration,
          child: Column(
            children: [
              _RunHeader(run: run),
              const Divider(height: 1),
              Expanded(child: _LogView(run: run, controller: _scroll)),
              if (!_follow)
                _JumpToLatest(onTap: () {
                  setState(() => _follow = true);
                  _scrollToEnd();
                }),
            ],
          ),
        );
      },
    );
  }
}

// ── Header ────────────────────────────────────────────────────────────────────

class _RunHeader extends StatelessWidget {
  final RunProvider run;
  const _RunHeader({required this.run});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          _StatusBadge(status: run.status!),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  run.recipeName ?? '',
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 2),
                Text(
                  _subtitle(run),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
          Text(
            _fmt(run.elapsed),
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  fontFamily: 'monospace',
                  color: scheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(width: 8),
          Tooltip(
            message: 'Copy all logs',
            child: IconButton(
              icon: const Icon(Icons.copy_outlined, size: 18),
              onPressed: run.logs.isEmpty
                  ? null
                  : () async {
                      await Clipboard.setData(ClipboardData(
                        text: run.logs.map((l) => l.text).join('\n'),
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
          Tooltip(
            message: run.minimized ? 'Expand' : 'Minimize — see the rest of the screen',
            child: IconButton(
              icon: Icon(
                run.minimized ? Icons.expand_more : Icons.expand_less,
                size: 20,
              ),
              onPressed: run.toggleMinimized,
            ),
          ),
          const SizedBox(width: 8),
          if (run.isRunning)
            OutlinedButton.icon(
              onPressed: run.cancel,
              icon: const Icon(Icons.stop_circle_outlined, size: 16),
              label: const Text('Cancel'),
              style: OutlinedButton.styleFrom(foregroundColor: scheme.error),
            )
          else
            OutlinedButton.icon(
              onPressed: run.reset,
              icon: const Icon(Icons.close, size: 16),
              label: const Text('Close'),
            ),
        ],
      ),
    );
  }

  static String _subtitle(RunProvider run) {
    if (run.isRunning) {
      final step = run.currentStepName;
      if (step == null) return 'Starting…';
      return 'Step ${run.stepIndex}/${run.stepTotal} — $step';
    }
    final failed =
        run.stepResults.where((s) => s.outcome.isTerminal).firstOrNull;
    if (failed != null) {
      return '${failed.step.name} — ${failed.note ?? failed.outcome.name}';
    }
    final skipped = run.stepResults
        .where((s) => s.outcome == StepOutcome.skipped)
        .length;
    final ran = run.stepResults.length - skipped;
    return '$ran steps run${skipped > 0 ? ', $skipped skipped' : ''}';
  }
}

class _StatusBadge extends StatelessWidget {
  final RunStatus status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (icon, color, label) = switch (status) {
      RunStatus.running => (null, scheme.primary, 'RUNNING'),
      RunStatus.done => (Icons.check_circle, Colors.green, 'PASSED'),
      RunStatus.failed => (Icons.error, scheme.error, 'FAILED'),
      RunStatus.cancelled => (Icons.stop_circle, Colors.orange, 'CANCELLED'),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon == null)
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(strokeWidth: 2, color: color),
            )
          else
            Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
          ),
        ],
      ),
    );
  }
}

// ── Log view ──────────────────────────────────────────────────────────────────

class _LogView extends StatelessWidget {
  final RunProvider run;
  final ScrollController controller;
  const _LogView({required this.run, required this.controller});

  @override
  Widget build(BuildContext context) {
    final logs = run.logs;
    if (logs.isEmpty) {
      return const Center(child: Text('Waiting for output…'));
    }

    return SelectionArea(
      child: ListView.builder(
        controller: controller,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        itemCount: logs.length + (run.logsTruncated ? 1 : 0),
        itemBuilder: (context, index) {
          if (run.logsTruncated) {
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
            return _LogRow(line: logs[index - 1]);
          }
          return _LogRow(line: logs[index]);
        },
      ),
    );
  }
}

class _LogRow extends StatelessWidget {
  final LogLine line;
  const _LogRow({required this.line});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Text(
      line.text,
      style: TextStyle(
        fontFamily: 'monospace',
        fontSize: 12,
        height: 1.45,
        color: line.isError ? scheme.error : scheme.onSurface,
      ),
    );
  }
}

class _JumpToLatest extends StatelessWidget {
  final VoidCallback onTap;
  const _JumpToLatest({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextButton.icon(
        onPressed: onTap,
        icon: const Icon(Icons.arrow_downward, size: 14),
        label: const Text('Jump to latest'),
      ),
    );
  }
}

String _fmt(Duration d) {
  final m = d.inMinutes;
  final s = d.inSeconds % 60;
  return m < 1 ? '${s}s' : '${m}m ${s.toString().padLeft(2, '0')}s';
}
