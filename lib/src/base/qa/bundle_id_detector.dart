import 'dart:io';

/// Best-effort parse of a mobile app's bundle id / package name per
/// environment (flavor) from the app source repo — never throws, and
/// returns whatever it could find (possibly empty). A manual-entry field
/// stays available everywhere this is used, since real project layouts vary
/// enough that this is advisory, not authoritative — see
/// docs/RUN_EXPERIENCE_REDESIGN.md §3.
class BundleIdDetector {
  BundleIdDetector._();

  /// Android `applicationId` per `productFlavors` block, from
  /// `<repoAbsPath>/android/app/build.gradle` (or `.kts`). Keys are the
  /// flavor names as written in the gradle file (e.g. `"development"`).
  static Map<String, String> detectAndroid(String repoAbsPath) {
    for (final name in ['build.gradle', 'build.gradle.kts']) {
      final file = File('$repoAbsPath/android/app/$name');
      if (file.existsSync()) {
        try {
          return _parseAndroidFlavors(file.readAsStringSync());
        } catch (_) {
          return {};
        }
      }
    }
    return {};
  }

  /// Depth-counting scan for `productFlavors { <name> { applicationId "..." } }`
  /// — good enough for the standard Flutter-generated layout without a full
  /// Gradle/Kotlin parser. Never throws on unexpected input; worst case
  /// returns a partial or empty map.
  static Map<String, String> _parseAndroidFlavors(String content) {
    final result = <String, String>{};
    var depth = 0;
    var inFlavors = false;
    var flavorsDepth = 0;
    String? flavor;
    var flavorDepth = 0;

    for (final raw in content.split('\n')) {
      final line = raw.trim();

      if (!inFlavors && RegExp(r'^productFlavors\b.*\{').hasMatch(line)) {
        inFlavors = true;
        flavorsDepth = depth;
      } else if (inFlavors && flavor == null) {
        final m = RegExp(r'^(\w+)\s*\{\s*$').firstMatch(line);
        if (m != null) {
          flavor = m.group(1);
          flavorDepth = depth;
        }
      }

      if (flavor != null) {
        // Groovy DSL: `applicationId "com.x"` — Kotlin DSL: `applicationId = "com.x"`
        final m = RegExp(r'''applicationId\s*=?\s*["']([^"']+)["']''').firstMatch(line);
        if (m != null) result[flavor] = m.group(1)!;
      }

      depth += '{'.allMatches(line).length - '}'.allMatches(line).length;

      if (flavor != null && depth <= flavorDepth) flavor = null;
      if (inFlavors && depth <= flavorsDepth) inFlavors = false;
    }
    return result;
  }

  /// iOS `PRODUCT_BUNDLE_IDENTIFIER` from every `.xcconfig` file under
  /// `<repoAbsPath>/ios`. Keys are the xcconfig's own filename (lowercased,
  /// no extension) as a best-guess flavor name — e.g. `Development.xcconfig`
  /// → `"development"`. Entries whose value still contains an unresolved
  /// `$(...)` build variable are skipped rather than surfacing a wrong or
  /// partial bundle id.
  static Map<String, String> detectIos(String repoAbsPath) {
    final iosDir = Directory('$repoAbsPath/ios');
    if (!iosDir.existsSync()) return {};
    final result = <String, String>{};
    try {
      for (final entity in iosDir.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.xcconfig')) continue;
        final match = RegExp(r'PRODUCT_BUNDLE_IDENTIFIER\s*=\s*([^\s;]+)')
            .firstMatch(entity.readAsStringSync());
        if (match == null) continue;
        final bundleId = match.group(1)!.trim();
        if (bundleId.isEmpty || bundleId.contains(r'$(')) continue;
        final fileName = entity.uri.pathSegments.last;
        final key =
            fileName.replaceAll('.xcconfig', '').toLowerCase();
        result[key] = bundleId;
      }
    } catch (_) {
      return result; // partial results from whatever we managed to read
    }
    return result;
  }
}
