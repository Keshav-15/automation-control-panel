import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_boilerplate/src/base/utils/common_methods.dart';
import 'package:yaml/yaml.dart';

import '../../models/qa/manifest_model.dart';

/// Loads and parses the product manifest YAML.
///
/// In development the file is bundled as a Flutter asset so we can hot-reload
/// manifest changes without rebuilding. In production builds the same asset
/// is used (it ships with the app).
///
/// If you ever want to load from an external path on disk (e.g. ~/manifests/),
/// call [loadFromFile] instead.
class ManifestLoader {
  static const _assetPath = 'manifests/centurion.yaml';

  ManifestModel? _cached;

  /// Load the bundled manifest. Cached after the first call.
  Future<ManifestModel> load() async {
    if (_cached != null) return _cached!;
    try {
      final raw = await rootBundle.loadString(_assetPath);
      _cached = _parse(raw);
      return _cached!;
    } catch (e) {
      logger('ManifestLoader: failed to load asset $_assetPath — $e');
      rethrow;
    }
  }

  /// Force-reload (drops cache — useful after the file changes on disk).
  void invalidate() => _cached = null;

  /// Load from an absolute file path (for advanced / override use).
  Future<ManifestModel> loadFromFile(String path) async {
    final content = await File(path).readAsString();
    return _parse(content);
  }

  ManifestModel _parse(String raw) {
    final yaml = loadYaml(raw);
    return ManifestModel.fromYaml(yaml as Map);
  }
}
