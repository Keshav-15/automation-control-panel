import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_boilerplate/src/base/dependencyinjection/locator.dart';
import 'package:flutter_boilerplate/src/base/qa/project_template.dart';
import 'package:flutter_boilerplate/src/base/utils/navigation_utils.dart';
import 'package:flutter_boilerplate/src/controllers/qa/project_controller.dart';
import 'package:flutter_boilerplate/src/models/qa/project_model.dart';
import 'package:flutter_boilerplate/src/providers/qa/project_provider.dart';
import 'package:provider/provider.dart';

/// Create a new project or edit an existing one.
///
/// [existingProject] — edit mode: pre-fills all fields.
/// [importedProject] — import mode: pre-fills from a JSON file the user just
///   picked, with a banner reminding them to verify/remap repo paths.
class CreateEditProjectScreen extends StatefulWidget {
  final ProjectConfig? existingProject;
  final ProjectConfig? importedProject;

  const CreateEditProjectScreen({
    super.key,
    this.existingProject,
    this.importedProject,
  });

  @override
  State<CreateEditProjectScreen> createState() =>
      _CreateEditProjectScreenState();
}

class _CreateEditProjectScreenState extends State<CreateEditProjectScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _rootCtrl = TextEditingController();
  final _extraPathCtrl = TextEditingController();

  ProjectConfig? get _source => widget.existingProject ?? widget.importedProject;
  bool get _isEdit => widget.existingProject != null;
  bool get _isImport => widget.importedProject != null;

  // Each repo uses three controllers:
  //   _roleNameCtrlMap[key]: editable role name (displayed in the key column)
  //   _repoCtrlMap[key]:     editable relPath (folder name)
  //   _branchCtrlMap[key]:   editable sync branch (defaults 'develop')
  //
  // The key is an internal stable identifier (original role or temp key for
  // newly added rows). On save, the actual role name is read from _roleNameCtrlMap.
  final Map<String, TextEditingController> _roleNameCtrlMap = {};
  final Map<String, TextEditingController> _repoCtrlMap = {};
  final Map<String, TextEditingController> _branchCtrlMap = {};

  // Preserved RepoEntry metadata (label, branch) for existing repos so we
  // don't lose them when the user only edits relPath.
  final Map<String, RepoEntry> _originalRepos = {};

  ProjectTemplateType _templateType = ProjectTemplateType.centurion;
  List<String> _extraPathDirs = [];
  bool _saving = false;
  bool _pickingRoot = false;

  @override
  void initState() {
    super.initState();
    _prefill();
  }

  void _prefill() {
    final src = _source;
    if (src != null) {
      _nameCtrl.text = src.name;
      _rootCtrl.text = src.projectsRoot;
      _extraPathDirs = List.of(src.extraPathDirs);
      _templateType = src.surfaces.isEmpty
          ? ProjectTemplateType.custom
          : ProjectTemplateType.centurion;

      if (src.repos.isNotEmpty) {
        for (final entry in src.repos.entries) {
          final key = entry.key; // stable internal key = original role name
          _roleNameCtrlMap[key] = TextEditingController(text: entry.key);
          _repoCtrlMap[key] =
              TextEditingController(text: entry.value.relPath);
          _branchCtrlMap[key] =
              TextEditingController(text: entry.value.branch);
          _originalRepos[key] = entry.value;
        }
      }
      // else: an existing project with zero repos on file starts genuinely
      // empty here too — "+ Add repo" is the one discoverable way to add a
      // repo now, so there's no need for placeholder rows nobody asked for.
    }
    // New project (either template) starts with zero repo rows — the user
    // adds exactly what they need via "+ Add repo"'s Web/Mobile menu below.
    // Centurion's known folder names still show up, but only once that
    // action is actually taken — see _addWebRepo/_addMobileRepoPair.
  }

  /// Centurion's known repo folder names — used to pre-fill (never
  /// silently auto-add) a row once the user actually adds it via "+ Add
  /// repo", and only when that template is selected. Kept in sync with
  /// [ProjectTemplate.centurion]'s own hardcoded defaults.
  static const _centurionDefaults = {
    'web': 'crichq-webapp-nextjs',
    'mobile_ui': 'crichq-app-flutter',
    'mobile_test': 'centurion-app-automation-tests-ts',
  };

  // ── Repo rows ─────────────────────────────────────────────────────────────

  /// "Add repo" only offers typed options for now (Web / Mobile — see
  /// [_buildRepoSection]'s menu) rather than a free-text role, so every
  /// added row's role is already meaningful. `_addWebRepo` covers the
  /// single-folder case; the mobile pair is `_addMobileRepoPair` below.
  /// More types (Android-only Appium, Flutter integration tests, ...) are
  /// meant to slot in here later as more menu entries, not a redesign.
  /// Suggested folder name for [role] — only when Centurion is the
  /// selected template, and only as a starting point the user can still
  /// edit; never filled in before they've actually added the row.
  String _suggestedFolder(String role) =>
      _templateType == ProjectTemplateType.centurion
          ? (_centurionDefaults[role] ?? '')
          : '';

  void _addWebRepo() {
    if (_repoCtrlMap.containsKey('web')) return;
    setState(() {
      _roleNameCtrlMap['web'] = TextEditingController(text: 'web');
      _repoCtrlMap['web'] = TextEditingController(text: _suggestedFolder('web'));
      _branchCtrlMap['web'] = TextEditingController(text: 'develop');
    });
  }

  /// "Mobile" is added as a pair — the app-source repo (builds/installs)
  /// and the test-scripts repo (E2E specs) — under the reserved role keys
  /// `mobile_ui` / `mobile_test`. Keeping these as well-known keys (instead
  /// of a new model field) is what a later auto-surface-creation pass keys
  /// off of, without needing anything beyond the existing free-text `role`.
  /// These same two keys are also what `ProjectTemplate.centurion()` now
  /// stores its app-source/test-scripts repos under.
  void _addMobileRepoPair() {
    setState(() {
      if (!_repoCtrlMap.containsKey('mobile_ui')) {
        _roleNameCtrlMap['mobile_ui'] =
            TextEditingController(text: 'mobile_ui');
        _repoCtrlMap['mobile_ui'] =
            TextEditingController(text: _suggestedFolder('mobile_ui'));
        _branchCtrlMap['mobile_ui'] = TextEditingController(text: 'develop');
      }
      if (!_repoCtrlMap.containsKey('mobile_test')) {
        _roleNameCtrlMap['mobile_test'] =
            TextEditingController(text: 'mobile_test');
        _repoCtrlMap['mobile_test'] =
            TextEditingController(text: _suggestedFolder('mobile_test'));
        _branchCtrlMap['mobile_test'] = TextEditingController(text: 'develop');
      }
    });
  }

  void _removeRepo(String key) {
    setState(() {
      _roleNameCtrlMap.remove(key)?.dispose();
      _repoCtrlMap.remove(key)?.dispose();
      _branchCtrlMap.remove(key)?.dispose();
      _originalRepos.remove(key);
    });
  }

  /// Clone a repo row — role name gets a `_copy` suffix so it doesn't
  /// silently collide with the original (two rows sharing one role name
  /// would have one overwrite the other in the final repos map at save time).
  void _duplicateRepo(String key) {
    final newKey = 'copy_${DateTime.now().millisecondsSinceEpoch}';
    final roleText = _roleNameCtrlMap[key]?.text ?? '';
    final pathText = _repoCtrlMap[key]?.text ?? '';
    final branchText = _branchCtrlMap[key]?.text ?? 'develop';
    setState(() {
      _roleNameCtrlMap[newKey] = TextEditingController(text: '${roleText}_copy');
      _repoCtrlMap[newKey] = TextEditingController(text: pathText);
      _branchCtrlMap[newKey] = TextEditingController(text: branchText);
      // Carry the original's branch forward too (edit/import mode only —
      // fresh creates have no _originalRepos entries at all).
      final original = _originalRepos[key];
      if (original != null) _originalRepos[newKey] = original;
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _rootCtrl.dispose();
    _extraPathCtrl.dispose();
    for (final c in _roleNameCtrlMap.values) {
      c.dispose();
    }
    for (final c in _repoCtrlMap.values) {
      c.dispose();
    }
    for (final c in _branchCtrlMap.values) {
      c.dispose();
    }
    super.dispose();
  }

  // ── Template changed ──────────────────────────────────────────────────────

  void _onTemplateChanged(ProjectTemplateType type) {
    // Doesn't touch repo rows — those are only ever added via "+ Add repo"
    // (see _addWebRepo/_addMobileRepoPair, which pull Centurion's known
    // folder names in at that point if this template is selected).
    setState(() => _templateType = type);
  }

  // ── Actions ───────────────────────────────────────────────────────────────

  Future<void> _pickRoot() async {
    if (_pickingRoot) return;
    setState(() => _pickingRoot = true);
    final path = await locator<ProjectController>()
        .pickFolder(dialogTitle: 'Select Projects folder');
    if (path != null) setState(() => _rootCtrl.text = path);
    setState(() => _pickingRoot = false);
  }

  Future<void> _pickRepoFolder(String key) async {
    final path = await locator<ProjectController>()
        .pickFolder(dialogTitle: 'Select ${_roleNameCtrlMap[key]?.text ?? key} folder');
    if (path == null) return;
    final root = _rootCtrl.text.trim();
    final rel = (root.isNotEmpty && path.startsWith('$root/'))
        ? path.substring(root.length + 1)
        : path;
    setState(() => _repoCtrlMap[key]?.text = rel);
  }

  void _addExtraPath() {
    final val = _extraPathCtrl.text.trim();
    if (val.isEmpty || _extraPathDirs.contains(val)) return;
    setState(() {
      _extraPathDirs.add(val);
      _extraPathCtrl.clear();
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    // The form validator only checks fields that exist — if every row was
    // removed there's nothing to fail, so this needs its own check. Without
    // it, a project could be saved with zero repos configured at all.
    if (_repoCtrlMap.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add at least one repository.')),
      );
      return;
    }
    // Mobile (Appium) is mandatory as a pair — the app-source repo and the
    // test-scripts repo. Scoped to exactly these two role keys so it can't
    // ever flag an existing Centurion-template project's unrelated
    // 'app'/'mobile_tests' roles.
    final hasMobileUi = _repoCtrlMap.containsKey('mobile_ui');
    final hasMobileTest = _repoCtrlMap.containsKey('mobile_test');
    if (hasMobileUi != hasMobileTest) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(hasMobileUi
            ? 'Mobile needs its test-scripts repo too — add it or remove the app source repo.'
            : 'Mobile needs its app-source repo too — add it or remove the test-scripts repo.'),
      ));
      return;
    }
    setState(() => _saving = true);
    try {
      final provider = context.read<ProjectProvider>();
      final name = _nameCtrl.text.trim();
      final root = _rootCtrl.text.trim();

      // Build repoRelPaths/repoBranches using actual role names from _roleNameCtrlMap
      final repoRelPaths = <String, String>{};
      final repoBranches = <String, String>{};
      for (final key in _repoCtrlMap.keys) {
        final roleName = _roleNameCtrlMap[key]?.text.trim() ?? key;
        final relPath = _repoCtrlMap[key]?.text.trim() ?? '';
        final branch = _branchCtrlMap[key]?.text.trim() ?? '';
        if (roleName.isNotEmpty && relPath.isNotEmpty) {
          repoRelPaths[roleName] = relPath;
        }
        if (roleName.isNotEmpty && branch.isNotEmpty) {
          repoBranches[roleName] = branch;
        }
      }

      if (_isEdit || _isImport) {
        final base = _source!;

        // Rebuild repos: match by original internal key → new role name + relPath
        final repos = <String, RepoEntry>{};
        for (final key in _repoCtrlMap.keys) {
          final roleName = _roleNameCtrlMap[key]?.text.trim() ?? key;
          final relPath = _repoCtrlMap[key]?.text.trim() ?? '';
          final branch = _branchCtrlMap[key]?.text.trim() ?? '';
          if (roleName.isEmpty) continue;

          final original = _originalRepos[key];
          repos[roleName] = RepoEntry(
            role: roleName,
            label: original?.label ?? roleName,
            relPath: relPath.isNotEmpty
                ? relPath
                : (original?.relPath ?? ''),
            branch: branch.isNotEmpty ? branch : (original?.branch ?? 'develop'),
          );
        }

        final updated = base.copyWith(
          name: name,
          projectsRoot: root,
          repos: repos,
          extraPathDirs: _extraPathDirs,
        );
        if (_isImport) {
          await provider.saveImportedProject(updated);
        } else {
          await provider.updateProject(updated);
        }
      } else {
        await provider.createProject(
          name: name,
          projectsRoot: root,
          templateType: _templateType,
          repoRelPaths: repoRelPaths.isEmpty ? null : repoRelPaths,
          repoBranches: repoBranches.isEmpty ? null : repoBranches,
          extraPathDirs: _extraPathDirs,
        );
      }
      if (mounted) locator<NavigationUtils>().pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.surface,
        elevation: 0,
        title: Text(_isEdit
            ? 'Edit project'
            : _isImport
                ? 'Import project'
                : 'New project'),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 40, vertical: 40),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_isImport) _buildImportBanner(),
                        _buildNameField(),
                        const SizedBox(height: 20),
                        if (!_isEdit && !_isImport) ...[
                          _buildTemplateSelector(),
                          const SizedBox(height: 20),
                        ],
                        _buildRootPicker(),
                        const SizedBox(height: 20),
                        _buildRepoSection(),
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
      ),
    );
  }

  // ── Sections ──────────────────────────────────────────────────────────────

  Widget _buildImportBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline,
              color: Theme.of(context).colorScheme.onPrimaryContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Verify repo paths — they were set on the exporting machine '
              'and may need updating here.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNameField() {
    return TextFormField(
      controller: _nameCtrl,
      decoration: const InputDecoration(
        labelText: 'Project name',
        border: OutlineInputBorder(),
        hintText: 'e.g. Centurion',
      ),
      autofocus: !_isEdit && !_isImport,
      validator: (v) =>
          (v == null || v.trim().isEmpty) ? 'Name is required' : null,
    );
  }

  Widget _buildTemplateSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Template', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 10),
        ...ProjectTemplateType.values.map((type) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: InkWell(
                onTap: () => _onTemplateChanged(type),
                borderRadius: BorderRadius.circular(8),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: _templateType == type
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.outlineVariant,
                      width: _templateType == type ? 2 : 1,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Text(type.icon, style: const TextStyle(fontSize: 24)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(type.label,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(
                                        fontWeight: FontWeight.w600)),
                            const SizedBox(height: 2),
                            Text(type.description,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant)),
                          ],
                        ),
                      ),
                      if (_templateType == type)
                        Icon(Icons.check_circle,
                            color: Theme.of(context).colorScheme.primary),
                    ],
                  ),
                ),
              ),
            )),
      ],
    );
  }

  Widget _buildRootPicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Projects folder',
            style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        Text(
          'The parent folder that contains all your repos.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _rootCtrl,
                readOnly: true,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  hintText: 'No folder selected',
                  hintStyle: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
            ),
            const SizedBox(width: 10),
            FilledButton.tonal(
              onPressed: _pickingRoot ? null : _pickRoot,
              child: _pickingRoot
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Browse…'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildRepoSection() {
    final root = _rootCtrl.text.trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Repositories',
                style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '(role → folder name inside Projects folder)',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ),
            // Typed add flow — pick what kind of repo this is rather than
            // typing a free-text role. Only Web/Mobile for now; more types
            // (Android-only Appium, Flutter integration tests, ...) are
            // meant to slot in as more menu entries later.
            PopupMenuButton<String>(
              tooltip: 'Add repo',
              onSelected: (type) => switch (type) {
                'web' => _addWebRepo(),
                'mobile' => _addMobileRepoPair(),
                _ => null,
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'web',
                  child: ListTile(
                    leading: Icon(Icons.language, size: 18),
                    title: Text('Web (Playwright)'),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                PopupMenuItem(
                  value: 'mobile',
                  child: ListTile(
                    leading: Icon(Icons.smartphone, size: 18),
                    title: Text('Mobile (Appium)'),
                    subtitle: Text('Adds both the app source and test-scripts repo'),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add, size: 16),
                    SizedBox(width: 4),
                    Text('Add repo'),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ..._repoCtrlMap.keys.map((key) {
          final relPathCtrl = _repoCtrlMap[key]!;
          final roleNameCtrl = _roleNameCtrlMap[key]!;
          final branchCtrl = _branchCtrlMap[key]!;
          final absPath = root.isNotEmpty && relPathCtrl.text.isNotEmpty
              ? '$root/${relPathCtrl.text}'
              : null;
          final exists = absPath != null && Directory(absPath).existsSync();
          final typeLabel = switch (key) {
            'web' => 'Web (Playwright)',
            'mobile_ui' => 'Mobile (Appium) — App source',
            'mobile_test' => 'Mobile (Appium) — Test scripts',
            _ => null,
          };

          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (typeLabel != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4, left: 2),
                    child: Text(typeLabel,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: Theme.of(context).colorScheme.primary,
                              fontWeight: FontWeight.w600,
                            )),
                  ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Role name — always editable via controller (fixes prefill bug)
                    SizedBox(
                      width: 110,
                      child: TextFormField(
                        controller: roleNameCtrl,
                        decoration: const InputDecoration(
                          isDense: true,
                          border: OutlineInputBorder(),
                          labelText: 'Role',
                          hintText: 'e.g. app',
                        ),
                        style: const TextStyle(
                            fontFamily: 'monospace', fontSize: 12),
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Required'
                            : null,
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Relative path
                    Expanded(
                      child: TextFormField(
                        controller: relPathCtrl,
                        decoration: InputDecoration(
                          isDense: true,
                          border: const OutlineInputBorder(),
                          labelText: 'Folder name',
                          hintText: 'folder-name',
                          suffixIcon: absPath != null
                              ? Icon(
                                  exists
                                      ? Icons.check_circle_outline
                                      : Icons.error_outline,
                                  size: 18,
                                  color: exists
                                      ? Theme.of(context).colorScheme.primary
                                      : Theme.of(context).colorScheme.error,
                                )
                              : null,
                        ),
                        style: const TextStyle(
                            fontFamily: 'monospace', fontSize: 13),
                        onChanged: (_) => setState(() {}),
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Required'
                            : null,
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Sync branch
                    SizedBox(
                      width: 110,
                      child: TextFormField(
                        controller: branchCtrl,
                        decoration: const InputDecoration(
                          isDense: true,
                          border: OutlineInputBorder(),
                          labelText: 'Sync branch',
                          hintText: 'develop',
                        ),
                        style: const TextStyle(
                            fontFamily: 'monospace', fontSize: 12),
                      ),
                    ),
                    const SizedBox(width: 4),
                    // Browse folder
                    IconButton(
                      tooltip: 'Browse for folder',
                      icon: const Icon(Icons.folder_open_outlined, size: 18),
                      onPressed: () => _pickRepoFolder(key),
                    ),
                    // Duplicate row
                    IconButton(
                      tooltip: 'Duplicate repo',
                      icon: const Icon(Icons.copy_outlined, size: 18),
                      onPressed: () => _duplicateRepo(key),
                    ),
                    // Remove row
                    IconButton(
                      tooltip: 'Remove repo',
                      icon: Icon(Icons.close,
                          size: 16,
                          color: Theme.of(context).colorScheme.error),
                      onPressed: () => _removeRepo(key),
                    ),
                  ],
                ),
              ],
            ),
          );
        }),
        if (_repoCtrlMap.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'No repositories configured. Tap "Add repo" to add one.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
      ],
    );
  }

  Widget _buildAdvanced() {
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      title: Text('Advanced',
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              )),
      children: [
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
              Text('Extra PATH directories',
                  style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 4),
              Text(
                'Prepended to PATH for every command this project runs.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 8),
              ..._extraPathDirs.map((dir) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(dir,
                              style: const TextStyle(fontFamily: 'monospace'),
                              overflow: TextOverflow.ellipsis),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, size: 16),
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          onPressed: () =>
                              setState(() => _extraPathDirs.remove(dir)),
                        ),
                      ],
                    ),
                  )),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _extraPathCtrl,
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
    );
  }

  Widget _buildSaveButton() {
    return FilledButton(
      onPressed: _saving ? null : _save,
      style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 16)),
      child: _saving
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2))
          : Text(_isImport
              ? 'Import project'
              : _isEdit
                  ? 'Save changes'
                  : 'Create project'),
    );
  }
}
