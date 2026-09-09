import 'package:flutter/material.dart';
import 'package:flutter_boilerplate/src/base/qa/run_dispatcher.dart';
import 'package:flutter_boilerplate/src/models/qa/project_model.dart';
import 'package:flutter_boilerplate/src/providers/qa/project_provider.dart';
import 'package:provider/provider.dart';

/// Route arguments for [CommandEditScreen].
class CommandEditArgs {
  final ProjectConfig project;

  /// When provided, the saved command is automatically added to this surface's
  /// commandIds (in addition to the project pool).
  final String? surfaceId;

  final CommandConfig? existing; // null = create mode

  /// Pre-seeded into the tags list for a brand-new command (ignored when
  /// [existing] is set) — e.g. opening "Add command" from the Report
  /// manager pre-adds the `report` tag, same convenience the old fixed
  /// category dropdown gave.
  final String? presetTag;

  const CommandEditArgs({
    required this.project,
    this.surfaceId,
    this.existing,
    this.presetTag,
  });
}

/// Reserved tags with real dispatch meaning (see
/// [ProjectConfig.testCommandFor] et al.) — offered as quick-add chips so
/// the common case still feels like a dropdown, without it being a fixed
/// enum a command is limited to.
const _kStageTags = ['prerequisite', 'git', 'build', 'test', 'report'];

/// Form screen for editing / creating a single [CommandConfig].
///
/// Saves to the project's global command pool. If [CommandEditArgs.surfaceId]
/// is provided, also assigns the command to that surface.
class CommandEditScreen extends StatefulWidget {
  final CommandEditArgs args;
  const CommandEditScreen({super.key, required this.args});

  @override
  State<CommandEditScreen> createState() => _CommandEditScreenState();
}

class _CommandEditScreenState extends State<CommandEditScreen> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _idCtrl;
  late final TextEditingController _nameCtrl;
  late final TextEditingController _commandCtrl;
  late final TextEditingController _timeoutCtrl;
  late final TextEditingController _envFileCtrl;
  late final TextEditingController _specCommandCtrl;
  late final TextEditingController _tagCtrl;

  late String _repoRole;
  late bool _skipIfNoSync;
  late bool _skipIfNoBuild;
  late bool _detach;
  late bool _checkAppium;
  String? _target;
  late List<String> _tags;

  // Surfaces this command is assigned to — shown as checkboxes at the bottom.
  // Starts from current assignment; toggled by user before save.
  late Set<String> _assignedSurfaceIds;

  bool _saving = false;

  CommandConfig? get _existing => widget.args.existing;
  ProjectConfig get _project => widget.args.project;
  String? get _surfaceId => widget.args.surfaceId;

  List<String> get _repoRoles => _project.repos.keys.toList();
  // Target (simulator/device) is the one dispatch-relevant axis left besides
  // script/device-udid — genuinely swaps in a different iOS build/install/
  // test command, so it's still shown as its own control rather than a tag.
  bool get _isIosSurface =>
      (_surfaceId != null ? _project.surfaceById(_surfaceId!)?.isIos : null) ??
      false;

  @override
  void initState() {
    super.initState();
    final e = _existing;
    _idCtrl = TextEditingController(text: e?.id ?? '');
    _nameCtrl = TextEditingController(text: e?.name ?? '');
    _commandCtrl = TextEditingController(text: e?.command ?? '');
    _timeoutCtrl =
        TextEditingController(text: e?.timeoutSeconds?.toString() ?? '');
    _envFileCtrl = TextEditingController(text: e?.envFile ?? '');
    _specCommandCtrl =
        TextEditingController(text: e?.specCommand ?? '');
    _tagCtrl = TextEditingController();

    _repoRole = e?.repoRole ?? (_repoRoles.isNotEmpty ? _repoRoles.first : '');
    _skipIfNoSync = e?.skipIfNoSync ?? false;
    _skipIfNoBuild = e?.skipIfNoBuild ?? false;
    _detach = e?.detach ?? false;
    _checkAppium = e?.checkAppium ?? false;
    _target = e?.target;
    _tags = e != null
        ? List.of(e.tags)
        : [if (widget.args.presetTag != null) widget.args.presetTag!];

    // Determine which surfaces currently include this command
    if (e != null) {
      _assignedSurfaceIds = _project.surfaces
          .where((s) => s.commandIds.contains(e.id))
          .map((s) => s.id)
          .toSet();
    } else {
      // New command: pre-assign to the surface the user came from (if any)
      _assignedSurfaceIds = _surfaceId != null ? {_surfaceId!} : {};
    }
  }

  void _addTag(String raw) {
    final tag = raw.trim();
    _tagCtrl.clear();
    if (tag.isEmpty || _tags.contains(tag)) return;
    setState(() => _tags.add(tag));
  }

  @override
  void dispose() {
    _idCtrl.dispose();
    _nameCtrl.dispose();
    _commandCtrl.dispose();
    _timeoutCtrl.dispose();
    _envFileCtrl.dispose();
    _specCommandCtrl.dispose();
    _tagCtrl.dispose();
    super.dispose();
  }

  // ── Save ──────────────────────────────────────────────────────────────────

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    // Mirrors the "Runs in repo" dropdown's validator, but that field doesn't
    // even render when the project has zero repos (just a hint text instead)
    // — so without this, a command could save with an empty, meaningless
    // repoRole. The dropdown itself already defaults to a real repo and
    // can't be left blank whenever repos DO exist, so this only ever fires
    // in that zero-repos case.
    if (_repoRoles.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content:
                Text('Add a repo to this project before creating a command.')),
      );
      return;
    }
    setState(() => _saving = true);

    try {
      final provider = context.read<ProjectProvider>();

      final rawId = _idCtrl.text.trim();
      final id = rawId.isNotEmpty
          ? rawId
          : _nameCtrl.text
              .trim()
              .toLowerCase()
              .replaceAll(RegExp(r'[^a-z0-9]+'), '_');

      final timeout = int.tryParse(_timeoutCtrl.text.trim());
      final envFile = _envFileCtrl.text.trim().isEmpty
          ? null
          : _envFileCtrl.text.trim();
      final specCommand = _specCommandCtrl.text.trim().isEmpty
          ? null
          : _specCommandCtrl.text.trim();

      final existingOrder = _existing?.order ??
          (_project.commands.length); // append to pool

      final cmd = CommandConfig(
        id: id,
        name: _nameCtrl.text.trim(),
        command: _commandCtrl.text.trim(),
        repoRole: _repoRole,
        timeoutSeconds: timeout,
        skipIfNoSync: _skipIfNoSync,
        skipIfNoBuild: _skipIfNoBuild,
        detach: _detach,
        envFile: envFile,
        target: _isIosSurface ? _target : null,
        checkAppium: _checkAppium,
        specCommand: specCommand,
        order: existingOrder,
        tags: _tags,
      );

      // Upsert in project pool
      var updated = await provider.upsertProjectCommand(
        project: _project,
        command: cmd,
      );

      // Sync surface assignments: add to checked, remove from unchecked
      final allSurfaceIds = _project.surfaces.map((s) => s.id).toSet();
      for (final sid in allSurfaceIds) {
        final surface = updated.surfaceById(sid);
        if (surface == null) continue;
        final currentlyIn = surface.commandIds.contains(cmd.id);
        final shouldBeIn = _assignedSurfaceIds.contains(sid);
        if (shouldBeIn && !currentlyIn) {
          updated = await provider.updateSurfaceCommandIds(
            project: updated,
            surfaceId: sid,
            commandIds: [...surface.commandIds, cmd.id],
          );
        } else if (!shouldBeIn && currentlyIn) {
          updated = await provider.updateSurfaceCommandIds(
            project: updated,
            surfaceId: sid,
            commandIds: surface.commandIds
                .where((id) => id != cmd.id)
                .toList(),
          );
        }
      }

      if (mounted) Navigator.of(context).pop(cmd);
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
        title: Text(_existing == null ? 'Add command' : 'Edit command'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Save'),
            ),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Name
                    TextFormField(
                      controller: _nameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Name *',
                        border: OutlineInputBorder(),
                        hintText: 'e.g. Run Playwright tests',
                      ),
                      autofocus: _existing == null,
                      validator: (v) =>
                          (v == null || v.trim().isEmpty)
                              ? 'Name is required'
                              : null,
                    ),
                    const SizedBox(height: 16),

                    // Command
                    TextFormField(
                      controller: _commandCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Command *',
                        border: OutlineInputBorder(),
                        hintText: 'yarn test',
                      ),
                      style: const TextStyle(
                          fontFamily: 'monospace', fontSize: 13),
                      maxLines: 3,
                      minLines: 1,
                      validator: (v) =>
                          (v == null || v.trim().isEmpty)
                              ? 'Command is required'
                              : null,
                    ),
                    const SizedBox(height: 8),
                    _PlaceholderLegend(),
                    const SizedBox(height: 16),

                    // Repo role
                    _repoRoles.isNotEmpty
                        ? DropdownButtonFormField<String>(
                            // ignore: deprecated_member_use
                            value: _repoRoles.contains(_repoRole)
                                ? _repoRole
                                : _repoRoles.first,
                            decoration: const InputDecoration(
                              labelText: 'Runs in repo',
                              border: OutlineInputBorder(),
                              helperText:
                                  'Which repo folder this command runs in.',
                            ),
                            items: _repoRoles
                                .map((r) => DropdownMenuItem(
                                    value: r, child: Text(r)))
                                .toList(),
                            onChanged: (v) {
                              if (v != null) setState(() => _repoRole = v);
                            },
                            validator: (v) =>
                                (v == null || v.isEmpty)
                                    ? 'Select a repo'
                                    : null,
                          )
                        : Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              border: Border.all(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .outlineVariant),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'No repos configured — add repos in Edit Project first.',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                            ),
                          ),
                    const SizedBox(height: 16),

                    // Tags — replaces the old fixed category enum. One of
                    // these (test/build/report/git/prerequisite) decides
                    // when this command runs; anything else is just a label
                    // for search/filtering.
                    _sectionLabel('Tags'),
                    const SizedBox(height: 4),
                    Text(
                      'A "test"/"build"/"report"/"git"/"prerequisite" tag '
                      'decides which command runs when — everything else is '
                      'just a label.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        ..._tags.map((t) => Chip(
                              label: Text(t),
                              onDeleted: () => setState(() => _tags.remove(t)),
                            )),
                        ..._kStageTags.where((t) => !_tags.contains(t)).map(
                              (t) => ActionChip(
                                label: Text('+ $t'),
                                onPressed: () => setState(() => _tags.add(t)),
                              ),
                            ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _tagCtrl,
                      decoration: InputDecoration(
                        labelText: 'Add a tag',
                        border: const OutlineInputBorder(),
                        hintText: 'e.g. smoke',
                        isDense: true,
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.add),
                          onPressed: () => _addTag(_tagCtrl.text),
                        ),
                      ),
                      onFieldSubmitted: _addTag,
                    ),
                    const SizedBox(height: 16),

                    // Step ID
                    TextFormField(
                      controller: _idCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Step ID (optional)',
                        border: OutlineInputBorder(),
                        hintText: 'auto-generated from name if left blank',
                        helperText: 'Unique key used in logs.',
                      ),
                    ),
                    const SizedBox(height: 20),

                    // ── Behaviour ─────────────────────────────────────────────
                    _sectionLabel('Behaviour'),
                    const SizedBox(height: 8),
                    _toggle(
                      'Skip when Sync is off',
                      'This step runs git pull — skip when Sync toggle is disabled.',
                      _skipIfNoSync,
                      (v) => setState(() => _skipIfNoSync = v),
                    ),
                    _toggle(
                      'Skip when Build+Install is off',
                      'This step builds/installs the app — skip when Build+Install is disabled.',
                      _skipIfNoBuild,
                      (v) => setState(() => _skipIfNoBuild = v),
                    ),
                    _toggle(
                      'Detach (fire-and-forget)',
                      'Launch without waiting — use for `allure open` or long-running servers.',
                      _detach,
                      (v) => setState(() => _detach = v),
                    ),
                    _toggle(
                      'Re-check Appium before step',
                      'Abort the pipeline if Appium is not running right before this step.',
                      _checkAppium,
                      (v) => setState(() => _checkAppium = v),
                    ),
                    const SizedBox(height: 20),

                    // Target (iOS surfaces only — the one axis still picked
                    // at Run time, since it genuinely swaps in a different
                    // build/install/test command)
                    if (_isIosSurface) ...[
                      _sectionLabel('Target filter'),
                      const SizedBox(height: 8),
                      SegmentedButton<String?>(
                        segments: const [
                          ButtonSegment<String?>(
                              value: null, label: Text('Both')),
                          ButtonSegment<String?>(
                              value: 'simulator',
                              label: Text('Simulator only')),
                          ButtonSegment<String?>(
                              value: 'device', label: Text('Device only')),
                        ],
                        selected: {_target},
                        onSelectionChanged: (Set<String?> v) =>
                            setState(() => _target = v.first),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // ── Optional ──────────────────────────────────────────────
                    _sectionLabel('Optional'),
                    const SizedBox(height: 8),

                    TextFormField(
                      controller: _timeoutCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Timeout (seconds)',
                        border: OutlineInputBorder(),
                        hintText: '600',
                        helperText: 'Kill the step after this many seconds.',
                      ),
                      keyboardType: TextInputType.number,
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return null;
                        if (int.tryParse(v.trim()) == null) {
                          return 'Must be a whole number';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    TextFormField(
                      controller: _envFileCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Env file',
                        border: OutlineInputBorder(),
                        hintText:
                            'centurion-app-automation-tests-ts/.env.dev',
                        helperText:
                            'Relative to Projects folder. Vars merged into this step\'s environment.',
                      ),
                      style: const TextStyle(
                          fontFamily: 'monospace', fontSize: 12),
                    ),
                    const SizedBox(height: 16),

                    TextFormField(
                      controller: _specCommandCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Spec/filter command',
                        border: OutlineInputBorder(),
                        hintText: 'yarn test -- --grep {flags}',
                        helperText:
                            'Used when spec/flags are typed. {flags} replaced at runtime.',
                      ),
                      style: const TextStyle(
                          fontFamily: 'monospace', fontSize: 12),
                      maxLines: 2,
                      minLines: 1,
                    ),
                    const SizedBox(height: 24),

                    // ── Surface assignment ────────────────────────────────────
                    if (_project.surfaces.isNotEmpty) ...[
                      _sectionLabel('Assign to surfaces'),
                      const SizedBox(height: 4),
                      Text(
                        'This command will be added to the selected surfaces\' pipeline.',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                      ),
                      const SizedBox(height: 8),
                      ..._project.surfaces.map((s) => CheckboxListTile(
                            value: _assignedSurfaceIds.contains(s.id),
                            onChanged: (v) => setState(() {
                              if (v == true) {
                                _assignedSurfaceIds.add(s.id);
                              } else {
                                _assignedSurfaceIds.remove(s.id);
                              }
                            }),
                            title: Row(
                              children: [
                                Text(s.icon,
                                    style: const TextStyle(fontSize: 16)),
                                const SizedBox(width: 8),
                                Text(s.name),
                              ],
                            ),
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                          )),
                      const SizedBox(height: 16),
                    ],

                    FilledButton(
                      onPressed: _saving ? null : _save,
                      style: FilledButton.styleFrom(
                          padding:
                              const EdgeInsets.symmetric(vertical: 16)),
                      child: _saving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2))
                          : Text(_existing == null
                              ? 'Add command'
                              : 'Save changes'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) => Text(
        text,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      );

  Widget _toggle(
    String label,
    String description,
    bool value,
    void Function(bool) onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Theme.of(context).textTheme.bodyMedium),
                Text(
                  description,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context)
                            .colorScheme
                            .onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

/// Every `{token}` the Command field's text (and the Env file field below)
/// actually gets substituted at Run time — sourced straight from
/// [RunDispatcher.placeholderDocs] so this can never drift out of sync with
/// what the dispatcher itself does. Shown here so a hardcoded value (a
/// literal branch name, bundle id, ...) isn't mistaken for the only option.
class _PlaceholderLegend extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline, size: 14, color: cs.onSurfaceVariant),
              const SizedBox(width: 6),
              Text(
                'Dynamic placeholders — filled in at Run time',
                style: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(color: cs.onSurfaceVariant, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ...RunDispatcher.placeholderDocs.entries.map(
            (e) => Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: RichText(
                text: TextSpan(
                  style: Theme.of(context)
                      .textTheme
                      .labelSmall
                      ?.copyWith(color: cs.onSurfaceVariant),
                  children: [
                    TextSpan(
                      text: '${e.key}  ',
                      style: const TextStyle(
                          fontFamily: 'monospace', fontWeight: FontWeight.bold),
                    ),
                    TextSpan(text: e.value),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
