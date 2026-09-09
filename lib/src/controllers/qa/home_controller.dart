import 'package:flutter_boilerplate/src/base/dependencyinjection/locator.dart';
import 'package:flutter_boilerplate/src/base/qa/process_gateway.dart';
import 'package:flutter_boilerplate/src/base/utils/common_methods.dart';
import 'package:flutter_boilerplate/src/models/qa/manifest_model.dart';
import 'package:flutter_boilerplate/src/models/qa/machine_profile_model.dart';

/// Tool versions shown in the header of the Home screen.
class ToolVersions {
  final String git;
  final String node;
  final String flutter;
  final String yarn;
  final String npm;

  const ToolVersions({
    required this.git,
    required this.node,
    required this.flutter,
    required this.yarn,
    required this.npm,
  });

  static const empty = ToolVersions(
    git: '—',
    node: '—',
    flutter: '—',
    yarn: '—',
    npm: '—',
  );
}

class HomeController {
  final ProcessGateway _gateway;

  HomeController({ProcessGateway? gateway})
      : _gateway = gateway ?? locator<ProcessGateway>();

  // ── Tool versions (Phase 0 done-when: matches Terminal) ──────────────────

  Future<ToolVersions> loadToolVersions() async {
    final results = await Future.wait([
      _safeExec('git --version'),
      _safeExec('node --version'),
      _safeExec('flutter --version | head -1'),
      _safeExec('yarn --version'),
      _safeExec('npm --version'),
    ]);

    return ToolVersions(
      git: _strip(results[0], prefix: 'git version '),
      node: results[1],
      flutter: _strip(results[2], prefix: 'Flutter '),
      yarn: results[3],
      npm: results[4],
    );
  }

  // ── Resolve absolute repo paths from manifest + machine profile ──────────

  /// Returns map: repoKey → absolute path for every repo in the manifest.
  Map<String, String> resolveRepoPaths(
    ManifestModel manifest,
    MachineProfile profile,
  ) {
    return manifest.repos.map(
      (key, repo) => MapEntry(key, profile.repoPath(repo.relPath)),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  Future<String> _safeExec(String cmd) async {
    try {
      return await _gateway.exec(cmd, ignoreExitCode: true);
    } catch (e) {
      logger('HomeController._safeExec("$cmd"): $e');
      return 'not found';
    }
  }

  String _strip(String value, {required String prefix}) {
    if (value.startsWith(prefix)) return value.substring(prefix.length).trim();
    return value;
  }
}
