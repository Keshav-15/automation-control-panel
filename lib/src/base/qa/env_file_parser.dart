import 'dart:io';

/// Parses a `.env`-style file into a `Map<String, String>`.
///
/// Rules (matches common dotenv behaviour):
///   • Lines starting with `#` (optional leading whitespace) are comments.
///   • Empty lines are ignored.
///   • Format: `KEY=value`, `KEY="value"`, `KEY='value'`.
///   • Inline comments (`KEY=value # comment`) are NOT stripped — values are
///     taken verbatim after the `=` (after optional outer quotes are removed).
///   • Duplicate keys: last one wins.
class EnvFileParser {
  /// Parse [content] (file text) into a key→value map.
  static Map<String, String> parse(String content) {
    final result = <String, String>{};
    for (final rawLine in content.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty || line.startsWith('#')) continue;

      final eqIndex = line.indexOf('=');
      if (eqIndex <= 0) continue; // no `=` or key is empty

      final key = line.substring(0, eqIndex).trim();
      if (key.isEmpty) continue;

      var value = line.substring(eqIndex + 1).trim();
      value = _stripOuterQuotes(value);
      result[key] = value;
    }
    return result;
  }

  /// Load and parse a `.env` file at [path]. Returns an empty map if the file
  /// does not exist (caller decides whether that is an error).
  static Map<String, String> loadFile(String path) {
    final file = File(path);
    if (!file.existsSync()) return {};
    return parse(file.readAsStringSync());
  }

  static String _stripOuterQuotes(String value) {
    if (value.length >= 2) {
      if ((value.startsWith('"') && value.endsWith('"')) ||
          (value.startsWith("'") && value.endsWith("'"))) {
        return value.substring(1, value.length - 1);
      }
    }
    return value;
  }
}
