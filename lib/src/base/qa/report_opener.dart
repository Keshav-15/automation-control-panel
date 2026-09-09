import 'dart:convert';
import 'dart:io';

/// Opens an archived report folder for viewing — the real risk flagged in
/// docs/RUN_EXPERIENCE_REDESIGN.md §8: a static copy of an Allure-style HTML
/// report usually needs to be *served*, not double-clicked, since its own
/// JSON data files fail to load under `file://` due to CORS.
///
/// Fallback chain, most-correct first:
///  1. `allure open <folder>` if the Allure CLI is on PATH — it already
///     knows how to serve a pre-generated report folder.
///  2. A throwaway local static server (`python3 -m http.server 0`, letting
///     the OS pick a free port) + `open http://localhost:<port>`.
///  3. Plain Finder-reveal, with a warning that it may not render correctly.
///
/// ponytail: one server per Open click, never explicitly torn down — matches
/// this app's existing shell-out-and-forget style elsewhere (e.g. the
/// `detach: true` "Open Allure report" pool command). Revisit with an actual
/// server-lifecycle/port-reuse story if stray `http.server` processes ever
/// become a real nuisance.
class ReportOpener {
  /// Attempts each fallback in turn. Returns a short message describing what
  /// happened, for a SnackBar — never throws.
  Future<String> open(String folderPath) async {
    if (!Directory(folderPath).existsSync()) {
      return 'Report folder is missing on disk.';
    }

    if (await _hasAllureCli()) {
      try {
        await Process.start('/bin/zsh', ['-l', '-c', 'allure open "$folderPath"'],
            mode: ProcessStartMode.detached);
        return 'Opening with Allure…';
      } catch (_) {
        // Fall through to the static-server fallback below.
      }
    }

    final port = await _tryServeStatically(folderPath);
    if (port != null) {
      await Process.run('open', ['http://localhost:$port']);
      return 'Serving locally on port $port and opening in your browser.';
    }

    await Process.run('open', ['-R', folderPath]);
    return 'Allure and python3 are both unavailable — revealed in Finder '
        'instead. Double-clicking index.html directly may not render '
        'correctly (CORS).';
  }

  Future<bool> _hasAllureCli() async {
    try {
      final result = await Process.run('/bin/zsh', ['-l', '-c', 'which allure']);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  /// Starts `python3 -m http.server 0` (OS-assigned ephemeral port) bound to
  /// [folderPath] and returns the port it actually bound to, or null if
  /// python3 isn't available / didn't report a port in time.
  Future<int?> _tryServeStatically(String folderPath) async {
    try {
      final process = await Process.start(
        '/bin/zsh',
        ['-l', '-c', 'cd "$folderPath" && python3 -m http.server 0'],
      );
      final firstLine = await process.stdout
          .transform(const SystemEncoding().decoder)
          .transform(const LineSplitter())
          .first
          .timeout(const Duration(seconds: 3));
      // e.g. "Serving HTTP on :: port 54321 (http://[::]:54321/) ..."
      final match = RegExp(r'port (\d+)').firstMatch(firstLine);
      return match == null ? null : int.tryParse(match.group(1)!);
    } catch (_) {
      return null;
    }
  }
}
