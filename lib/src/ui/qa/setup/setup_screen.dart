import 'package:flutter/material.dart';
import 'package:flutter_boilerplate/src/base/dependencyinjection/locator.dart';
import 'package:flutter_boilerplate/src/base/utils/constants/navigation_route_constants.dart';
import 'package:flutter_boilerplate/src/base/utils/navigation_utils.dart';
import 'package:flutter_boilerplate/src/controllers/qa/setup_controller.dart';
import 'package:flutter_boilerplate/src/models/qa/machine_profile_model.dart';
import 'package:flutter_boilerplate/src/models/qa/manifest_model.dart';
import 'package:flutter_boilerplate/src/providers/qa/qa_provider.dart';
import 'package:provider/provider.dart';

/// First-run screen: user selects their Projects root folder.
///
/// Repo list comes from [ManifestModel.repos] in centurion.yaml — the YAML
/// declares each repo key and its relative path; this screen just checks
/// whether each folder exists on disk after the user picks a root.
///
/// Layout uses LayoutBuilder + SingleChildScrollView + ConstrainedBox(minHeight)
/// so the card is vertically centred when short but scrollable when the repo
/// list + advanced section pushes it past the window height.
class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final _setupCtrl = locator<SetupController>();
  final _extraPathController = TextEditingController();

  String? _selectedRoot;
  Map<String, bool> _repoStatus = {}; // repoKey → exists on disk
  bool _picking = false;

  // Advanced: extra PATH dirs. Hidden behind an expander because most users
  // never need this — login-shell PATH already covers all tools.
  List<String> _extraPathDirs = [];
  bool _advancedExpanded = false;

  bool get _canSave =>
      _selectedRoot != null && _repoStatus.values.any((v) => v);

  ManifestModel? get _manifest => context.read<QAProvider>().manifest;

  @override
  void initState() {
    super.initState();
    // Prefill from existing profile when re-visiting via the gear icon.
    final profile = context.read<QAProvider>().profile;
    if (profile != null) {
      _selectedRoot = profile.projectsRoot;
      _extraPathDirs = List.of(profile.extraPathDirs);
      _advancedExpanded = _extraPathDirs.isNotEmpty;
      _repoStatus = _setupCtrl.validateRepoPaths(
        profile.projectsRoot,
        _manifest?.repos.map((k, v) => MapEntry(k, v.relPath)) ?? {},
      );
    }
  }

  @override
  void dispose() {
    _extraPathController.dispose();
    super.dispose();
  }

  // ── Actions ───────────────────────────────────────────────────────────────

  Future<void> _pickFolder() async {
    if (_picking) return;
    setState(() => _picking = true);

    final path = await _setupCtrl.pickProjectsRoot();
    if (path != null) {
      final relPaths =
          _manifest?.repos.map((k, v) => MapEntry(k, v.relPath)) ?? {};
      final status = _setupCtrl.validateRepoPaths(path, relPaths);
      setState(() {
        _selectedRoot = path;
        _repoStatus = status;
      });
    }

    setState(() => _picking = false);
  }

  void _addExtraPath() {
    final value = _extraPathController.text.trim();
    if (value.isEmpty || _extraPathDirs.contains(value)) return;
    setState(() {
      _extraPathDirs.add(value);
      _extraPathController.clear();
    });
  }

  void _removeExtraPath(String value) =>
      setState(() => _extraPathDirs.remove(value));

  Future<void> _save() async {
    if (!_canSave || _selectedRoot == null) return;
    await context.read<QAProvider>().saveProfile(
          MachineProfile(
            projectsRoot: _selectedRoot!,
            extraPathDirs: _extraPathDirs,
          ),
        );
    if (mounted) locator<NavigationUtils>().pushAndRemoveUntil(routeQAHome);
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.canPop(context);

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: canPop
          ? AppBar(
              backgroundColor: Theme.of(context).colorScheme.surface,
              elevation: 0,
            )
          : null,
      // LayoutBuilder gives us the real available height so we can enforce
      // minHeight on the scroll child — content centres when short, scrolls
      // when tall (repo list + advanced section can push past the window).
      body: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          child: ConstrainedBox(
            // minHeight centres the card vertically when content is short;
            // the scroll view handles the case where content exceeds it.
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 40, vertical: 48),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildHeader(),
                      const SizedBox(height: 32),
                      _buildFolderPicker(),
                      if (_selectedRoot != null) ...[
                        const SizedBox(height: 24),
                        _buildRepoList(),
                      ],
                      const SizedBox(height: 20),
                      _buildAdvanced(),
                      const SizedBox(height: 32),
                      _buildSaveButton(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Sections ──────────────────────────────────────────────────────────────

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('🧪', style: TextStyle(fontSize: 32)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'QA Control Center',
                style: Theme.of(context)
                    .textTheme
                    .headlineMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Point this tool at your Projects folder and it will find the '
          'Centurion repos automatically.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      ],
    );
  }

  Widget _buildFolderPicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Projects folder',
            style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  border: Border.all(
                      color: Theme.of(context).colorScheme.outline),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _selectedRoot ?? 'No folder selected',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: _selectedRoot == null
                            ? Theme.of(context).colorScheme.onSurfaceVariant
                            : null,
                        fontFamily: 'monospace',
                      ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
            ),
            const SizedBox(width: 10),
            FilledButton.tonal(
              onPressed: _picking ? null : _pickFolder,
              child: _picking
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Browse…'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildRepoList() {
    final manifest = _manifest;
    if (manifest == null) return const SizedBox.shrink();

    final allFound = _repoStatus.values.every((v) => v);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text('Centurion repos',
                style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(width: 8),
            Text(
              '(from centurion.yaml)',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ...manifest.repos.entries.map((entry) => _RepoRow(
              key: ValueKey(entry.key),
              repoKey: entry.key,
              relPath: entry.value.relPath,
              projectsRoot: _selectedRoot ?? '',
              found: _repoStatus[entry.key] ?? false,
            )),
        if (!allFound) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Theme.of(context)
                  .colorScheme
                  .errorContainer
                  .withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              'Missing repos are shown in red. Clone them into the '
              'selected folder with the exact folder names shown, '
              'then tap Browse… again.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ],
    );
  }

  /// Advanced section — hidden by default.
  ///
  /// "Extra PATH directories" is only needed on machines where a required tool
  /// (node, flutter, yarn, adb, …) is installed somewhere the login shell
  /// doesn't put on PATH. In practice this almost never happens because
  /// [ProcessGateway] already uses `/bin/zsh -l` (login-shell), which loads
  /// `~/.zshrc`, nvm, fvm, Homebrew, etc. — the same PATH you see in Terminal.
  ///
  /// The only real-world case is a corporate machine where IT drops a tool in
  /// a non-standard prefix that isn't on the login-shell PATH. In that case
  /// the user adds the directory here and it gets prepended to PATH for every
  /// command the app runs.
  Widget _buildAdvanced() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Disclosure row
        InkWell(
          onTap: () =>
              setState(() => _advancedExpanded = !_advancedExpanded),
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Icon(
                  _advancedExpanded
                      ? Icons.expand_less
                      : Icons.expand_more,
                  size: 18,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
                Text(
                  'Advanced',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color:
                            Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                if (_extraPathDirs.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${_extraPathDirs.length}',
                      style: Theme.of(context)
                          .textTheme
                          .labelSmall
                          ?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onPrimaryContainer,
                          ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),

        // Expanded content
        if (_advancedExpanded) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Extra PATH directories',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 4),
                Text(
                  'Prepended to PATH for every command this app runs. '
                  'Only needed if Doctor reports a tool as "not found" '
                  'but it works in your Terminal — login-shell PATH covers '
                  'most setups automatically.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color:
                            Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 10),
                for (final dir in _extraPathDirs)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            dir,
                            style:
                                const TextStyle(fontFamily: 'monospace'),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, size: 16),
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          onPressed: () => _removeExtraPath(dir),
                        ),
                      ],
                    ),
                  ),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _extraPathController,
                        decoration: const InputDecoration(
                          isDense: true,
                          border: OutlineInputBorder(),
                          hintText: '/opt/homebrew/bin',
                        ),
                        style: const TextStyle(
                            fontFamily: 'monospace', fontSize: 13),
                        onSubmitted: (_) => _addExtraPath(),
                      ),
                    ),
                    const SizedBox(width: 10),
                    OutlinedButton(
                      onPressed: _addExtraPath,
                      child: const Text('Add'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildSaveButton() {
    return FilledButton(
      onPressed: _canSave ? _save : null,
      style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 16)),
      child: const Text('Save & Continue'),
    );
  }
}

// ── _RepoRow ──────────────────────────────────────────────────────────────────

class _RepoRow extends StatelessWidget {
  final String repoKey;     // manifest key, e.g. "app"
  final String relPath;     // folder name, e.g. "crichq-app-flutter"
  final String projectsRoot;
  final bool found;

  const _RepoRow({
    super.key,
    required this.repoKey,
    required this.relPath,
    required this.projectsRoot,
    required this.found,
  });

  @override
  Widget build(BuildContext context) {
    final color = found
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.error;
    final absPath = '$projectsRoot/$relPath';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(
            found ? Icons.check_circle_outline : Icons.error_outline,
            color: color,
            size: 18,
          ),
          const SizedBox(width: 8),
          // Repo key — bold, fixed width so path column aligns
          SizedBox(
            width: 96,
            child: Text(
              repoKey,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 4),
          // Path — fills remaining space; tooltip reveals the full path on hover
          Expanded(
            child: Tooltip(
              message: absPath,
              waitDuration: const Duration(milliseconds: 400),
              child: Text(
                absPath,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                      color: color,
                    ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
