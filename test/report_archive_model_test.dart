import 'package:flutter_boilerplate/src/models/qa/report_archive_model.dart';
import 'package:flutter_test/flutter_test.dart';

ReportArchive _archive({
  String runId = 'run-1',
  String? platform,
  String? device,
}) =>
    ReportArchive(
      runId: runId,
      projectId: 'proj-1',
      surfaceId: 'mobile',
      script: 'login.e2e.ts',
      environment: 'dev',
      platform: platform,
      device: device,
      commandUsed: 'allure open allure-report',
      generatedAt: DateTime(2026, 1, 1, 12, 30),
      sourcePath: '/repo/allure-report',
      archivePath: '/app-support/reports/proj-1/mobile/run-1',
    );

void main() {
  test('toJson/fromJson round-trips every field', () {
    final original = _archive(platform: 'android', device: 'emulator-5554');
    final restored = ReportArchive.fromJson(original.toJson());

    expect(restored.runId, original.runId);
    expect(restored.projectId, original.projectId);
    expect(restored.surfaceId, original.surfaceId);
    expect(restored.script, original.script);
    expect(restored.environment, original.environment);
    expect(restored.platform, original.platform);
    expect(restored.device, original.device);
    expect(restored.commandUsed, original.commandUsed);
    expect(restored.generatedAt, original.generatedAt);
    expect(restored.sourcePath, original.sourcePath);
    expect(restored.archivePath, original.archivePath);
  });

  test('nullable platform/device round-trip as null (web reports)', () {
    final original = _archive();
    final restored = ReportArchive.fromJson(original.toJson());

    expect(restored.platform, isNull);
    expect(restored.device, isNull);
    expect(original.toJson().containsKey('platform'), isFalse);
    expect(original.toJson().containsKey('device'), isFalse);
  });

  test('copyWith updates only generatedAt/archivePath, keeps everything else',
      () {
    final original = _archive();
    final updated = original.copyWith(
      generatedAt: DateTime(2026, 2, 1),
      archivePath: '/new/path',
    );

    expect(updated.runId, original.runId);
    expect(updated.projectId, original.projectId);
    expect(updated.generatedAt, DateTime(2026, 2, 1));
    expect(updated.archivePath, '/new/path');
  });
}
