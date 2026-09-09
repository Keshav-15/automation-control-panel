import 'package:flutter/material.dart';
import 'package:flutter_boilerplate/src/base/utils/constants/navigation_route_constants.dart';
import 'package:flutter_boilerplate/src/base/utils/date_utils.dart';
import 'package:flutter_boilerplate/src/base/utils/navigation_utils.dart';
import 'package:flutter_boilerplate/src/base/dependencyinjection/locator.dart';
import 'package:flutter_boilerplate/src/models/qa/manifest_model.dart';
import 'package:flutter_boilerplate/src/models/qa/run_record_model.dart';
import 'package:flutter_boilerplate/src/providers/qa/qa_provider.dart';
import 'package:flutter_boilerplate/src/providers/qa/run_provider.dart';
import 'package:flutter_boilerplate/src/ui/qa/doctor/doctor_panel.dart';
import 'package:flutter_boilerplate/src/ui/qa/history/history_panel.dart';
import 'package:flutter_boilerplate/src/ui/qa/runner/run_panel.dart';
import 'package:provider/provider.dart';

/// Main control-center home screen.
///
/// Phase 0: version banner (git/node/flutter/yarn/npm) via login-shell PATH.
/// Phase 1: three recipe cards — Web / iOS / Android — with toggles.
///           iOS card additionally has Simulator / Real Device selector.
/// Phase 2: Doctor panel embedded in each card; Run button gated on Doctor pass.
/// Phase 3: Run starts the pipeline; live output in the [RunPanel] bottom pane.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // Per-recipe toggles — keyed by recipeId
  final Map<String, bool> _syncEnabled = {};
  final Map<String, bool> _buildEnabled = {};

  // iOS target — keyed by recipeId (only 'ios' recipe uses this)
  final Map<String, IosBuildTarget> _iosTarget = {};

  // Optional spec/flags text field per recipe (Phase 6) — lazily created so
  // typing doesn't lose cursor position across rebuilds.
  final Map<String, TextEditingController> _specControllers = {};

  TextEditingController _specController(String recipeId) =>
      _specControllers.putIfAbsent(recipeId, () => TextEditingController());

  @override
  void dispose() {
    for (final c in _specControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  // Redirect to Setup at most once — guards against a rebuild (e.g. the
  // manifest reload button) re-triggering the check after the user is
  // already on Home.
  bool _profileChecked = false;

  /// Only meaningful once [QALoadState.ready] — before that, [QAProvider]'s
  /// SharedPreferences read hasn't completed and `hasProfile` would read as
  /// false even when a profile was saved on a previous run.
  void _checkProfile(QAProvider qa) {
    if (_profileChecked || qa.loadState != QALoadState.ready) return;
    _profileChecked = true;
    if (!qa.hasProfile) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => locator<NavigationUtils>().pushAndRemoveUntil(routeQASetup),
      );
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Consumer<QAProvider>(
      builder: (context, qa, _) {
        if (qa.loadState == QALoadState.loading) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (qa.loadState == QALoadState.error) {
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline, size: 48, color: Colors.red),
                    const SizedBox(height: 16),
                    Text(qa.errorMessage ?? 'Unknown error',
                        textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () => qa.initialise(),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        _checkProfile(qa);

        final manifest = qa.manifest;
        if (manifest == null) return const Scaffold(body: SizedBox());

        // Narrow selects — the log stream notifies ~10x/s and must not rebuild
        // the version banner or the Doctor panels.
        final runIdle = context.select<RunProvider, bool>((r) => r.isIdle);
        final runMinimized =
            context.select<RunProvider, bool>((r) => r.minimized);
        final runningRecipeId =
            context.select<RunProvider, String?>((r) => r.isRunning ? r.recipeId : null);

        return Scaffold(
          backgroundColor: Theme.of(context).colorScheme.surface,
          appBar: _buildAppBar(context, qa, manifest),
          body: Column(
            children: [
              _buildVersionBanner(context, qa),
              const Divider(height: 1),
              Expanded(
                flex: 3,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildRecipeGrid(
                          context, qa, manifest, runningRecipeId),
                      const SizedBox(height: 20),
                      const HistoryPanel(),
                    ],
                  ),
                ),
              ),
              // Live pipeline output — absent from the tree while idle.
              // Minimized: bare (not Expanded), same reasoning as the
              // multi-project screen — see RunProvider.minimized's doc.
              if (!runIdle)
                runMinimized
                    ? const RunPanel()
                    : const Expanded(flex: 4, child: RunPanel()),
            ],
          ),
        );
      },
    );
  }

  // ── App bar ───────────────────────────────────────────────────────────────

  PreferredSizeWidget _buildAppBar(
      BuildContext context, QAProvider qa, ManifestModel manifest) {
    return AppBar(
      title: Row(
        children: [
          const Text('🧪', style: TextStyle(fontSize: 20)),
          const SizedBox(width: 8),
          Text(
            'QA Control Center',
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(width: 12),
          _EnvChip(label: manifest.environment.toUpperCase()),
        ],
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh),
          tooltip: 'Refresh tool versions',
          onPressed: () => qa.refreshVersions(),
        ),
        IconButton(
          icon: const Icon(Icons.settings_outlined),
          tooltip: 'Setup / change paths',
          onPressed: () => locator<NavigationUtils>().push(routeQASetup),
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  // ── Version banner ────────────────────────────────────────────────────────

  Widget _buildVersionBanner(BuildContext context, QAProvider qa) {
    final v = qa.toolVersions;
    final items = [
      ('git', v.git),
      ('node', v.node),
      ('flutter', v.flutter),
      ('yarn', v.yarn),
      ('npm', v.npm),
    ];
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
      child: Row(
        children: [
          const Icon(Icons.terminal, size: 16),
          const SizedBox(width: 8),
          Text(
            'Tool versions (login-shell PATH)',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Wrap(
              spacing: 12,
              runSpacing: 4,
              children: items
                  .map((item) =>
                      _VersionChip(tool: item.$1, version: item.$2))
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }

  // ── Recipe grid ───────────────────────────────────────────────────────────

  Widget _buildRecipeGrid(BuildContext context, QAProvider qa,
      ManifestModel manifest, String? runningRecipeId) {
    final anyRunning = runningRecipeId != null;
    return Wrap(
      spacing: 20,
      runSpacing: 20,
      children: manifest.recipes.values
          .map((recipe) {
            final target = _iosTarget[recipe.id] ?? IosBuildTarget.simulator;
            final runnable = qa.isRecipeRunnable(recipe.id);
            // Per-card select — a new record for one recipe must not rebuild
            // the other two cards.
            final lastReport = context.select<RunProvider, RunRecord?>(
                (r) => r.lastReportFor(recipe.id));

            return _RecipeCard(
              key: ValueKey(recipe.id),
              recipe: recipe,
              lastReport: lastReport,
              onReopenReport: () => qa.reopenReport(recipe),
              syncEnabled: _syncEnabled[recipe.id] ?? true,
              buildEnabled: _buildEnabled[recipe.id] ?? false,
              specController: _specController(recipe.id),
              iosTarget: target,
              onSyncChanged: (v) =>
                  setState(() => _syncEnabled[recipe.id] = v),
              onBuildChanged: (v) =>
                  setState(() => _buildEnabled[recipe.id] = v),
              onIosTargetChanged: anyRunning
                  ? null
                  : (v) {
                      setState(() => _iosTarget[recipe.id] = v);
                      // Doctor re-runs automatically when iOS target changes
                      qa.runDoctor(recipeId: recipe.id, iosTarget: v);
                    },
              // Run needs a clear Doctor and no other run in flight (Phase 3)
              onRun: runnable && !anyRunning
                  ? () => _onRun(context, recipe, target)
                  : null,
              isRunningThis: runningRecipeId == recipe.id,
              isBlockedByOtherRun:
                  anyRunning && runningRecipeId != recipe.id,
            );
          })
          .toList(),
    );
  }

  void _onRun(
      BuildContext context, RecipeConfig recipe, IosBuildTarget iosTarget) {
    final qa = context.read<QAProvider>();
    final manifest = qa.manifest;
    final profile = qa.profile;
    if (manifest == null || profile == null) return;

    context.read<RunProvider>().start(
          recipe: recipe,
          profile: profile,
          manifest: manifest,
          syncEnabled: _syncEnabled[recipe.id] ?? true,
          buildEnabled: _buildEnabled[recipe.id] ?? false,
          iosTarget: iosTarget,
          specFlags: _specController(recipe.id).text,
        );
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _EnvChip extends StatelessWidget {
  final String label;
  const _EnvChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.onPrimaryContainer,
              fontWeight: FontWeight.bold,
            ),
      ),
    );
  }
}

class _VersionChip extends StatelessWidget {
  final String tool;
  final String version;
  const _VersionChip({required this.tool, required this.version});

  @override
  Widget build(BuildContext context) {
    final notFound =
        version.isEmpty || version == '—' || version.contains('not found');
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$tool:',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(width: 3),
        Text(
          notFound ? 'not found' : version,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontFamily: 'monospace',
                fontWeight: FontWeight.w600,
                color: notFound
                    ? Theme.of(context).colorScheme.error
                    : Theme.of(context).colorScheme.primary,
              ),
        ),
      ],
    );
  }
}

class _RecipeCard extends StatelessWidget {
  final RecipeConfig recipe;
  final bool syncEnabled;
  final bool buildEnabled;
  final IosBuildTarget iosTarget;
  final ValueChanged<bool> onSyncChanged;
  final ValueChanged<bool> onBuildChanged;
  final ValueChanged<IosBuildTarget>? onIosTargetChanged;
  final VoidCallback? onRun;

  /// Optional spec/flags text field (Phase 6) — e.g. a Playwright `--grep`
  /// pattern or a WDIO `--spec` path. Blank runs the full suite, unchanged.
  final TextEditingController specController;

  /// This card's pipeline is the one currently running.
  final bool isRunningThis;

  /// A different recipe is running — Run is disabled for a reason other than Doctor.
  final bool isBlockedByOtherRun;

  /// Most recent completed run for this recipe with a report to reopen —
  /// backs the "Reopen last report" shortcut (Phase 5). Null if none yet.
  final RunRecord? lastReport;
  final VoidCallback? onReopenReport;

  const _RecipeCard({
    super.key,
    required this.recipe,
    required this.syncEnabled,
    required this.buildEnabled,
    required this.iosTarget,
    required this.onSyncChanged,
    required this.onBuildChanged,
    required this.onIosTargetChanged,
    required this.onRun,
    required this.specController,
    this.isRunningThis = false,
    this.isBlockedByOtherRun = false,
    this.lastReport,
    this.onReopenReport,
  });

  String get _emoji {
    return switch (recipe.surface) {
      'ios' => '🍎',
      'android' => '🤖',
      _ => '🌐',
    };
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 340,
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
              color: Theme.of(context).colorScheme.outlineVariant),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(context),
              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 12),
              _buildToggles(context),
              const SizedBox(height: 16),
              const Divider(height: 1),
              // Doctor panel — Phase 2
              DoctorPanel(
                recipeId: recipe.id,
                iosTarget: iosTarget,
              ),
              const SizedBox(height: 16),
              _buildSpecField(context),
              const SizedBox(height: 12),
              _buildRunButton(context),
              if (lastReport != null && !isRunningThis) ...[
                const SizedBox(height: 8),
                Center(
                  child: TextButton.icon(
                    onPressed: onReopenReport,
                    icon: const Icon(Icons.open_in_new, size: 14),
                    label: Text(
                        'Reopen last report (${timeAgo(lastReport!.startedAt)})'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// One line per surface — the exact flag syntax its test runner accepts.
  String get _specHint {
    return switch (recipe.surface) {
      'web' => r'e.g. --grep "@smoke"  (blank = full suite)',
      _ => r'e.g. --spec test/specs/login.e2e.ts  (blank = full suite)',
    };
  }

  Widget _buildSpecField(BuildContext context) {
    return TextField(
      controller: specController,
      enabled: !isRunningThis && !isBlockedByOtherRun,
      decoration: InputDecoration(
        isDense: true,
        border: const OutlineInputBorder(),
        labelText: 'Spec / extra flags (optional)',
        hintText: _specHint,
      ),
      style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Row(
      children: [
        Text(_emoji, style: const TextStyle(fontSize: 28)),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            recipe.name,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }

  Widget _buildToggles(BuildContext context) {
    return Column(
      children: [
        _Toggle(
          label: 'Sync (git pull develop)',
          value: syncEnabled,
          onChanged: isRunningThis || isBlockedByOtherRun ? null : onSyncChanged,
        ),
        if (recipe.isMobile) ...[
          const SizedBox(height: 4),
          _Toggle(
            label: 'Build + Install (dev flavor)',
            value: buildEnabled,
            onChanged:
                isRunningThis || isBlockedByOtherRun ? null : onBuildChanged,
          ),
        ],
        // iOS target selector — Simulator vs Real Device
        if (recipe.isIos) ...[
          const SizedBox(height: 12),
          _IosTargetSelector(
            selected: iosTarget,
            onChanged: onIosTargetChanged,
          ),
        ],
      ],
    );
  }

  Widget _buildRunButton(BuildContext context) {
    final (icon, label) = switch (this) {
      _ when isRunningThis => (
          Icons.hourglass_top,
          'Running…',
        ),
      _ when isBlockedByOtherRun => (
          Icons.lock_outline,
          'Another run in progress',
        ),
      _ when onRun == null => (
          Icons.health_and_safety_outlined,
          'Run (Doctor required)',
        ),
      _ => (Icons.play_arrow, 'Run'),
    };

    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: onRun,
        icon: Icon(icon),
        label: Text(label),
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
      ),
    );
  }
}

/// Segmented toggle for choosing between Simulator and Real Device on iOS cards.
class _IosTargetSelector extends StatelessWidget {
  final IosBuildTarget selected;

  /// Null while a run is in flight — switching target mid-run is meaningless.
  final ValueChanged<IosBuildTarget>? onChanged;

  const _IosTargetSelector({
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Target',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 6),
        SegmentedButton<IosBuildTarget>(
          style: SegmentedButton.styleFrom(
            visualDensity: VisualDensity.compact,
          ),
          segments: IosBuildTarget.values
              .map((t) => ButtonSegment<IosBuildTarget>(
                    value: t,
                    label: Text('${t.icon}  ${t.label}'),
                  ))
              .toList(),
          selected: {selected},
          onSelectionChanged:
              onChanged == null ? null : (s) => onChanged!(s.first),
        ),
      ],
    );
  }
}

class _Toggle extends StatelessWidget {
  final String label;
  final bool value;

  /// Null disables the switch (frozen while a run is in flight).
  final ValueChanged<bool>? onChanged;

  const _Toggle({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
            child: Text(label,
                style: Theme.of(context).textTheme.bodyMedium)),
        Switch(value: value, onChanged: onChanged),
      ],
    );
  }
}
