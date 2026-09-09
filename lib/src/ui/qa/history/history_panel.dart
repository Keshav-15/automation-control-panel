import 'package:flutter/material.dart';
import 'package:flutter_boilerplate/src/base/utils/date_utils.dart';
import 'package:flutter_boilerplate/src/models/qa/run_record_model.dart';
import 'package:flutter_boilerplate/src/providers/qa/qa_provider.dart';
import 'package:flutter_boilerplate/src/providers/qa/run_provider.dart';
import 'package:provider/provider.dart';

/// Last N runs across all recipes, newest first — survives an app restart
/// (backed by [RunHistoryStore]). Tap the report icon to reopen the Allure
/// report; tap the log icon to open that run's saved log file.
class HistoryPanel extends StatelessWidget {
  /// How many rows to show — the store itself keeps up to 50.
  static const int visibleCount = 8;

  const HistoryPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final history = context.select<RunProvider, List<RunRecord>>((r) => r.history);
    if (history.isEmpty) return const SizedBox.shrink();

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.history,
                    size: 20, color: Theme.of(context).colorScheme.onSurfaceVariant),
                const SizedBox(width: 10),
                Text('Recent runs', style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 12),
            ...history
                .take(visibleCount)
                .map((r) => _HistoryRow(record: r)),
          ],
        ),
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  final RunRecord record;
  const _HistoryRow({required this.record});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (icon, color) = switch (record.status) {
      'done' => (Icons.check_circle, Colors.green),
      'failed' => (Icons.error, scheme.error),
      'cancelled' => (Icons.stop_circle, Colors.orange),
      _ => (Icons.help_outline, scheme.onSurfaceVariant),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: Text(record.recipeName,
                style: Theme.of(context).textTheme.bodyMedium,
                overflow: TextOverflow.ellipsis),
          ),
          Expanded(
            flex: 2,
            child: Text(
              '${timeAgo(record.startedAt)} · ${_fmtDuration(record.duration)}',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
          ),
          if (record.hasReport)
            IconButton(
              icon: const Icon(Icons.open_in_new, size: 16),
              tooltip: 'Reopen Allure report',
              visualDensity: VisualDensity.compact,
              onPressed: () => _reopenReport(context),
            ),
          if (record.logPath != null)
            IconButton(
              icon: const Icon(Icons.description_outlined, size: 16),
              tooltip: 'Open saved log',
              visualDensity: VisualDensity.compact,
              onPressed: () =>
                  context.read<QAProvider>().openLogFile(record.logPath!),
            ),
        ],
      ),
    );
  }

  void _reopenReport(BuildContext context) {
    final qa = context.read<QAProvider>();
    final recipe = qa.manifest?.recipes[record.recipeId];
    if (recipe != null) qa.reopenReport(recipe);
  }
}

String _fmtDuration(Duration d) {
  final m = d.inMinutes;
  final s = d.inSeconds % 60;
  return m < 1 ? '${s}s' : '${m}m ${s.toString().padLeft(2, '0')}s';
}
