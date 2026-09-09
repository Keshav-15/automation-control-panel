import 'package:flutter/foundation.dart';
import 'package:flutter_boilerplate/src/base/dependencyinjection/locator.dart';
import 'package:flutter_boilerplate/src/base/qa/manifest_loader.dart';
import 'package:flutter_boilerplate/src/base/qa/process_gateway.dart';
import 'package:flutter_boilerplate/src/base/utils/common_methods.dart';
import 'package:flutter_boilerplate/src/controllers/qa/doctor_controller.dart';
import 'package:flutter_boilerplate/src/controllers/qa/home_controller.dart';
import 'package:flutter_boilerplate/src/controllers/qa/setup_controller.dart';
import 'package:flutter_boilerplate/src/models/qa/doctor_model.dart';
import 'package:flutter_boilerplate/src/models/qa/machine_profile_model.dart';
import 'package:flutter_boilerplate/src/models/qa/manifest_model.dart';

enum QALoadState { idle, loading, ready, error }

/// Top-level state for the QA Control Center.
///
/// Owned by a [ChangeNotifierProvider] above [MaterialApp] so all QA screens
/// can read it. Keeps a single-source-of-truth for:
///   • manifest (from YAML)
///   • machine profile (saved paths)
///   • tool versions (Phase 0)
///   • doctor results per recipe (Phase 2)
class QAProvider extends ChangeNotifier {
  final SetupController _setup;
  final HomeController _home;
  final ManifestLoader _loader;
  final DoctorController _doctor;
  final ProcessGateway _gateway;

  QAProvider({
    SetupController? setup,
    HomeController? home,
    ManifestLoader? loader,
    DoctorController? doctor,
    ProcessGateway? gateway,
  })  : _setup = setup ?? locator<SetupController>(),
        _home = home ?? locator<HomeController>(),
        _loader = loader ?? locator<ManifestLoader>(),
        _doctor = doctor ?? locator<DoctorController>(),
        _gateway = gateway ?? locator<ProcessGateway>();

  // ── State ─────────────────────────────────────────────────────────────────

  QALoadState _loadState = QALoadState.idle;
  QALoadState get loadState => _loadState;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  ManifestModel? _manifest;
  ManifestModel? get manifest => _manifest;

  MachineProfile? _profile;
  MachineProfile? get profile => _profile;

  ToolVersions _toolVersions = ToolVersions.empty;
  ToolVersions get toolVersions => _toolVersions;

  bool get hasProfile => _profile?.isValid == true;

  // ── Doctor state (Phase 2) ─────────────────────────────────────────────────

  /// Keyed by recipeId. Null = not yet run.
  final Map<String, DoctorResult> _doctorResults = {};
  Map<String, DoctorResult> get doctorResults =>
      Map.unmodifiable(_doctorResults);

  /// True while a Doctor run is in flight for the given recipeId.
  final Set<String> _doctorRunning = {};
  bool isDoctorRunning(String recipeId) => _doctorRunning.contains(recipeId);

  /// True when Doctor has passed (no blocking failures) for the recipe.
  bool isRecipeRunnable(String recipeId) {
    final result = _doctorResults[recipeId];
    if (result == null) return false;
    return result.isRunnable;
  }

  DoctorResult? doctorResultFor(String recipeId) => _doctorResults[recipeId];

  // ── Init ──────────────────────────────────────────────────────────────────

  /// Call once on app start (from main or initState of the root widget).
  Future<void> initialise() async {
    _loadState = QALoadState.loading;
    _errorMessage = null;
    notifyListeners();

    try {
      // 1. Load the manifest (bundled asset)
      _manifest = await _loader.load();

      // 2. Load machine profile from SharedPreferences
      _profile = _setup.loadProfile();
      _applyExtraPathDirs();

      // 3. Fetch tool versions in parallel (Phase 0)
      _toolVersions = await _home.loadToolVersions();

      _loadState = QALoadState.ready;
    } catch (e) {
      _errorMessage = e.toString();
      _loadState = QALoadState.error;
    }

    notifyListeners();
  }

  // ── Profile updates ───────────────────────────────────────────────────────

  Future<void> saveProfile(MachineProfile profile) async {
    await _setup.saveProfile(profile);
    _profile = profile;
    _applyExtraPathDirs();
    // Saved profile invalidates any cached Doctor results (paths may have changed)
    _doctorResults.clear();
    notifyListeners();
  }

  Future<void> clearProfile() async {
    await _setup.clearProfile();
    _profile = null;
    _gateway.extraPathDirs = const [];
    _doctorResults.clear();
    notifyListeners();
  }

  /// Push `MachineProfile.extraPathDirs` into the shared [ProcessGateway] so
  /// every spawned command (Doctor checks, tool-version fetch, pipeline
  /// steps) sees them on PATH — not just steps that happen to declare
  /// `env_file`. See `ProcessGateway._buildEnv`.
  void _applyExtraPathDirs() {
    _gateway.extraPathDirs = _profile?.extraPathDirs ?? const [];
  }

  // ── Refresh ───────────────────────────────────────────────────────────────

  Future<void> refreshVersions() async {
    _toolVersions = await _home.loadToolVersions();
    notifyListeners();
  }

  // ── Doctor (Phase 2) ──────────────────────────────────────────────────────

  /// Run Doctor for a single recipe. Safe to call while another recipe's Doctor
  /// is already running — each recipe is independent.
  Future<void> runDoctor({
    required String recipeId,
    required IosBuildTarget iosTarget,
  }) async {
    final m = _manifest;
    final p = _profile;
    if (m == null || p == null) return;

    final recipe = m.recipes[recipeId];
    if (recipe == null) return;

    // Mark in-flight
    _doctorRunning.add(recipeId);
    _doctorResults.remove(recipeId);
    notifyListeners();

    try {
      final result = await _doctor.runDoctor(
        recipe: recipe,
        profile: p,
        manifest: m,
        iosTarget: iosTarget,
      );
      _doctorResults[recipeId] = result;
    } catch (e) {
      // Defensive: DoctorRunner is meant to never throw, but just in case
      _doctorResults[recipeId] = DoctorResult(
        recipeId: recipeId,
        checks: [
          DoctorCheck(
            id: 'unexpected_error',
            label: 'Doctor failed unexpectedly',
            status: DoctorStatus.fail,
            fixHint: e.toString(),
          ),
        ],
        ranAt: DateTime.now(),
      );
    } finally {
      _doctorRunning.remove(recipeId);
      notifyListeners();
    }
  }

  // ── Report / log reopening (Phase 5) ──────────────────────────────────────

  /// Re-run [recipe]'s report-open step (`yarn allure:open`,
  /// `npm run report:open`, …) — this is what "Reopen last report" does.
  /// Re-invoking the real command, rather than opening a static file
  /// directly, matters: `allure open` runs a local server, and the report's
  /// data won't load over a bare `file://` URL.
  Future<void> reopenReport(RecipeConfig recipe) async {
    final step = recipe.reportStep;
    final p = _profile;
    final relPath = _manifest?.repos[step?.repo]?.relPath;
    if (step == null || p == null || relPath == null) return;

    try {
      await _gateway.detach(step.command, workingDirectory: p.repoPath(relPath));
    } catch (e) {
      logger('QAProvider.reopenReport(${recipe.id}): $e');
    }
  }

  /// Open a saved run log in the user's default text viewer.
  Future<void> openLogFile(String path) async {
    try {
      await _gateway.detach('open "$path"');
    } catch (e) {
      logger('QAProvider.openLogFile: $e');
    }
  }
}
