import 'package:flutter_boilerplate/src/models/qa/manifest_model.dart';

/// Outcome of a single pipeline step.
enum StepOutcome {
  success,
  skipped,
  failed,
  timedOut,
  cancelled;

  bool get isTerminal =>
      this == StepOutcome.failed ||
      this == StepOutcome.timedOut ||
      this == StepOutcome.cancelled;
}

/// Overall pipeline status.
enum RunStatus { running, done, failed, cancelled }

class StepResult {
  final StepConfig step;
  final StepOutcome outcome;
  final int? exitCode;
  final Duration duration;

  /// Why the step was skipped / how it failed — shown in the log panel.
  final String? note;

  const StepResult({
    required this.step,
    required this.outcome,
    required this.duration,
    this.exitCode,
    this.note,
  });
}

class PipelineResult {
  final String recipeId;
  final RunStatus status;
  final List<StepResult> steps;
  final DateTime startedAt;
  final Duration duration;

  const PipelineResult({
    required this.recipeId,
    required this.status,
    required this.steps,
    required this.startedAt,
    required this.duration,
  });

  StepResult? get failedStep =>
      steps.where((s) => s.outcome.isTerminal).firstOrNull;
}
