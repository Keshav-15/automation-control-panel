import 'package:flutter_boilerplate/src/apis/api_service.dart';
import 'package:flutter_boilerplate/src/apis/apimanagers/auth_api_manager.dart';
import 'package:flutter_boilerplate/src/base/qa/manifest_loader.dart';
import 'package:flutter_boilerplate/src/base/qa/process_gateway.dart';
import 'package:flutter_boilerplate/src/base/qa/project_store.dart';
import 'package:flutter_boilerplate/src/base/utils/navigation_utils.dart';
import 'package:flutter_boilerplate/src/controllers/auth/auth_controller.dart';
import 'package:flutter_boilerplate/src/controllers/qa/doctor_controller.dart';
import 'package:flutter_boilerplate/src/controllers/qa/home_controller.dart';
import 'package:flutter_boilerplate/src/controllers/qa/project_controller.dart';
import 'package:flutter_boilerplate/src/controllers/qa/setup_controller.dart';
import 'package:get_it/get_it.dart';

final locator = GetIt.instance;

void setupLocator() {
  // ── Core ──────────────────────────────────────────────────────────────────
  locator.registerSingleton<NavigationUtils>(NavigationUtils());

  // ── Boilerplate (keep for reference; not used by QA flows) ────────────────
  locator.registerSingleton<ApiService>(ApiService());
  locator.registerSingleton<AuthApiManager>(AuthApiManager());
  locator.registerSingleton<AuthController>(AuthController());

  // ── QA Control Center — legacy ────────────────────────────────────────────
  locator.registerSingleton<ProcessGateway>(ProcessGateway());
  locator.registerSingleton<ManifestLoader>(ManifestLoader());
  locator.registerSingleton<SetupController>(SetupController());
  locator.registerSingleton<HomeController>(HomeController());
  locator.registerSingleton<DoctorController>(DoctorController());

  // ── QA Control Center — multi-project ────────────────────────────────────
  locator.registerSingleton<ProjectStore>(ProjectStore());
  locator.registerSingleton<ProjectController>(
    ProjectController(store: locator<ProjectStore>()),
  );
}
