import 'dart:io';

/// Shared health-check for Appium's REST server — used by both Doctor
/// (Phase 2, pre-flight) and [StepRunner] (Phase 4, right before a WDIO step
/// actually needs it — Build+Install can take minutes, long enough for
/// someone to have quit Appium in between).
class AppiumProbe {
  static const defaultBaseUrl = 'http://127.0.0.1:4723';

  /// True when `GET <baseUrl>/status` returns 200.
  static Future<bool> isRunning({String baseUrl = defaultBaseUrl}) async {
    try {
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
      final req = await client.getUrl(Uri.parse('$baseUrl/status'));
      final res = await req.close();
      client.close();
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
