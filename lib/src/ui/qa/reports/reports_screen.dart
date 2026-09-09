import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_boilerplate/src/base/qa/report_archive_store.dart';
import 'package:flutter_boilerplate/src/base/qa/report_archiver.dart';
import 'package:flutter_boilerplate/src/base/qa/report_opener.dart';
import 'package:flutter_boilerplate/src/base/utils/dir_copy_utils.dart';
import 'package:flutter_boilerplate/src/controllers/qa/project_controller.dart';
import 'package:flutter_boilerplate/src/models/qa/project_model.dart';
import 'package:flutter_boilerplate/src/models/qa/report_archive_model.dart';

/// Route arguments for [ReportsScreen].
class ReportsArgs {
  final ProjectConfig project;
  final String surfaceId;
  const ReportsArgs({required this.project, required this.surfaceId});
}

/// Lists a surface's archived reports (see docs/RUN_EXPERIENCE_REDESIGN.md
/// §8) with per-report Download / Share / Regenerate / Open actions, plus a
/// manual "Clear all reports" (§12's retention companion action). No
/// share-sheet integration exists anywhere in this app yet, so Share is
/// scoped down to Finder-reveal + "copy path" for v1, exactly as the design
/// doc anticipated.
class ReportsScreen extends StatefulWidget {
  final ReportsArgs args;
  const ReportsScreen({super.key, required this.args});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  final _archiver = ReportArchiver();
  final _opener = ReportOpener();
  late List<ReportArchive> _reports;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _reports = ReportArchiveStore.forSurface(
        widget.args.project.id, widget.args.surfaceId);
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _withBusy(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ── Actions ────────────────────────────────────────────────────────────────

  Future<void> _download(ReportArchive report) => _withBusy(() async {
        final folder = await ProjectController().pickFolder(
          dialogTitle: 'Choose where to copy the report',
        );
        if (folder == null) return;
        try {
          final dest = Directory('$folder/${report.runId}');
          copyDirectoryContents(Directory(report.archivePath), dest);
          _toast('Copied to ${dest.path}');
        } catch (e) {
          _toast('Copy failed: $e');
        }
      });

  Future<void> _reveal(ReportArchive report) =>
      Process.run('open', ['-R', report.archivePath]);

  Future<void> _copyPath(ReportArchive report) async {
    await Clipboard.setData(ClipboardData(text: report.archivePath));
    _toast('Path copied to clipboard.');
  }

  Future<void> _open(ReportArchive report) => _withBusy(() async {
        final message = await _opener.open(report.archivePath);
        _toast(message);
      });

  Future<void> _regenerate(ReportArchive report) => _withBusy(() async {
        final ok = await _archiver.regenerate(report, widget.args.project);
        if (!ok) {
          _toast('Raw results are gone — a full re-run is needed instead.');
          return;
        }
        setState(_load);
        _toast('Report regenerated.');
      });

  Future<void> _clearAll() => _withBusy(() async {
        await ReportArchiveStore.clearFor(
            widget.args.project.id, widget.args.surfaceId);
        setState(_load);
        _toast('Cleared all reports for this surface.');
      });

  // ── UI ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final surface = widget.args.project.surfaceById(widget.args.surfaceId);
    return Scaffold(
      appBar: AppBar(
        title: Text('Reports — ${surface?.name ?? widget.args.surfaceId}'),
        actions: [
          if (_reports.isNotEmpty)
            IconButton(
              tooltip: 'Clear all reports',
              icon: const Icon(Icons.delete_sweep_outlined),
              onPressed: _busy ? null : _confirmClearAll,
            ),
        ],
      ),
      body: _busy && _reports.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : _reports.isEmpty
              ? const Center(child: Text('No reports archived yet.'))
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _reports.length,
                  itemBuilder: (context, index) => _ReportTile(
                    report: _reports[index],
                    busy: _busy,
                    onDownload: () => _download(_reports[index]),
                    onReveal: () => _reveal(_reports[index]),
                    onCopyPath: () => _copyPath(_reports[index]),
                    onOpen: () => _open(_reports[index]),
                    onRegenerate: () => _regenerate(_reports[index]),
                  ),
                ),
    );
  }

  Future<void> _confirmClearAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear all reports?'),
        content: const Text(
            'Deletes every archived report copy for this surface. This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear all'),
          ),
        ],
      ),
    );
    if (confirmed == true) await _clearAll();
  }
}

class _ReportTile extends StatelessWidget {
  final ReportArchive report;
  final bool busy;
  final VoidCallback onDownload;
  final VoidCallback onReveal;
  final VoidCallback onCopyPath;
  final VoidCallback onOpen;
  final VoidCallback onRegenerate;

  const _ReportTile({
    required this.report,
    required this.busy,
    required this.onDownload,
    required this.onReveal,
    required this.onCopyPath,
    required this.onOpen,
    required this.onRegenerate,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final subtitleParts = [
      report.environment,
      if (report.platform != null) report.platform!,
      if (report.device != null) report.device!,
    ];
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(report.script, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 2),
            Text(
              '${subtitleParts.join(' · ')} · ${_timeAgo(report.generatedAt)}',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: busy ? null : onOpen,
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: const Text('Open'),
                ),
                OutlinedButton.icon(
                  onPressed: busy ? null : onDownload,
                  icon: const Icon(Icons.download_outlined, size: 16),
                  label: const Text('Download'),
                ),
                OutlinedButton.icon(
                  onPressed: busy ? null : onReveal,
                  icon: const Icon(Icons.folder_open_outlined, size: 16),
                  label: const Text('Reveal'),
                ),
                OutlinedButton.icon(
                  onPressed: busy ? null : onCopyPath,
                  icon: const Icon(Icons.copy_outlined, size: 16),
                  label: const Text('Copy path'),
                ),
                OutlinedButton.icon(
                  onPressed: busy ? null : onRegenerate,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('Regenerate'),
                ),
              ],
            ),
          ],
        ),
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
