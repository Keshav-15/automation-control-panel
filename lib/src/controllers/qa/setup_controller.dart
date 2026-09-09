import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_boilerplate/src/base/utils/common_methods.dart';
import 'package:flutter_boilerplate/src/base/utils/constants/preference_key_constant.dart';
import 'package:flutter_boilerplate/src/base/utils/preference_utils.dart';
import 'package:flutter_boilerplate/src/models/qa/machine_profile_model.dart';

/// Manages the first-run Setup screen — folder selection and profile persistence.
class SetupController {
  // ── Profile persistence ───────────────────────────────────────────────────

  /// Load the saved machine profile. Returns null if no profile has been saved.
  MachineProfile? loadProfile() {
    final root = getString(prefkeyQAProjectsRoot);
    if (root.isEmpty) return null;
    final extraRaw = getStringList(prefkeyQAExtraPath);
    final extra = extraRaw.where((s) => s.isNotEmpty).toList();
    return MachineProfile(projectsRoot: root, extraPathDirs: extra);
  }

  Future<void> saveProfile(MachineProfile profile) async {
    await setString(prefkeyQAProjectsRoot, profile.projectsRoot);
    await setStringList(prefkeyQAExtraPath, profile.extraPathDirs);
    logger('SetupController: saved profile root=${profile.projectsRoot}');
  }

  Future<void> clearProfile() async {
    await remove(prefkeyQAProjectsRoot);
    await remove(prefkeyQAExtraPath);
  }

  // ── Folder picking ────────────────────────────────────────────────────────

  /// Open a native folder-picker dialog and return the chosen path (or null).
  Future<String?> pickProjectsRoot() async {
    final result = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Select your Projects folder',
      lockParentWindow: true,
    );
    return result;
  }

  // ── Validation ────────────────────────────────────────────────────────────

  /// Check that each repo directory exists under [projectsRoot].
  /// Returns a map of repoKey → absolute path for each repo that IS found,
  /// and logs a warning for any that are missing.
  Map<String, bool> validateRepoPaths(
    String projectsRoot,
    Map<String, String> relPaths, // repoKey → relPath from manifest
  ) {
    final results = <String, bool>{};
    for (final entry in relPaths.entries) {
      final absPath = '$projectsRoot/${entry.value}';
      final exists = Directory(absPath).existsSync();
      results[entry.key] = exists;
      if (!exists) {
        logger(
          'SetupController: repo "${entry.key}" not found at $absPath',
        );
      }
    }
    return results;
  }
}
