import 'package:flutter_boilerplate/src/base/dependencyinjection/locator.dart';
import 'package:flutter_boilerplate/src/base/qa/doctor_runner.dart';
import 'package:flutter_boilerplate/src/base/qa/process_gateway.dart';
import 'package:flutter_boilerplate/src/models/qa/doctor_model.dart';
import 'package:flutter_boilerplate/src/models/qa/machine_profile_model.dart';
import 'package:flutter_boilerplate/src/models/qa/manifest_model.dart';

// Controller that orchestrates Doctor runs for a recipe.
//
// Thin layer between [QAProvider] and [DoctorRunner]:
//   • keeps its own [ProcessGateway] reference
//   • delegates all check logic to [DoctorRunner.run]
//   • returns a [DoctorResult] — provider owns the state

class DoctorController {
  final ProcessGateway _gateway;

  DoctorController({ProcessGateway? gateway})
      : _gateway = gateway ?? locator<ProcessGateway>();

  /// Run all checks for [recipe] with the given profile + iOS target.
  ///
  /// Never throws. Errors within individual checks produce [DoctorStatus.fail]
  /// results with a helpful [DoctorCheck.fixHint].
  Future<DoctorResult> runDoctor({
    required RecipeConfig recipe,
    required MachineProfile profile,
    required ManifestModel manifest,
    IosBuildTarget iosTarget = IosBuildTarget.simulator,
  }) {
    return DoctorRunner.run(
      recipe: recipe,
      profile: profile,
      manifest: manifest,
      iosTarget: iosTarget,
      gateway: _gateway,
    );
  }
}
