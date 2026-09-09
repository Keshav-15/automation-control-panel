import 'package:flutter_boilerplate/src/apis/api_service.dart';
import 'package:flutter_boilerplate/src/apis/apimanagers/auth_api_manager.dart';
import 'package:flutter_boilerplate/src/base/utils/navigation_utils.dart';
import 'package:flutter_boilerplate/src/controllers/auth/auth_controller.dart';
import 'package:get_it/get_it.dart';

final locator = GetIt.instance;

void setupLocator() {
  // Common
  locator.registerSingleton<NavigationUtils>(NavigationUtils());
  locator.registerSingleton<ApiService>(ApiService());

  // API Managers
  locator.registerSingleton<AuthApiManager>(AuthApiManager());

  // Controller
  locator.registerSingleton<AuthController>(AuthController());
}
