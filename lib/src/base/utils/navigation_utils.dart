import 'package:flutter/material.dart';
import 'package:flutter_boilerplate/src/ui/auth/login/login_screen.dart';

import 'constants/navigation_route_constants.dart';

class NavigationUtils {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  BuildContext get getCurrentContext {
    return _navigatorKey.currentContext!;
  }

  GlobalKey<NavigatorState> get navigatorKey {
    return _navigatorKey;
  }

  RouteSettings getCurrentRoute() {
    RouteSettings currentRoute = const RouteSettings(name: "", arguments: {});
    _navigatorKey.currentState?.popUntil((route) {
      currentRoute = route.settings;
      return true;
    });
    return currentRoute;
  }

  Route<dynamic> generateRoute(RouteSettings settings) {
    Map<String, dynamic>? args = settings.arguments as Map<String, dynamic>?;
    switch (settings.name) {
      case routeLogin:
        return MaterialPageRoute(
          settings: settings,
          builder: (_) =>
              const LoginScreen(), // To pass args use as const LoginScreen(id: args?["id"])
        );
      default:
        return _errorRoute(" Comming soon...");
    }
  }

  Route<dynamic> _errorRoute(String message) {
    return MaterialPageRoute(
      builder: (context) {
        return Scaffold(
          appBar: AppBar(title: const Text('Error')),
          body: Center(child: Text(message)),
        );
      },
    );
  }

  void pushReplacement(String routeName, {Object? arguments}) {
    _navigatorKey.currentState?.pushReplacementNamed(
      routeName,
      arguments: arguments,
    );
  }

  Future<dynamic>? push(String routeName, {Object? arguments}) {
    return _navigatorKey.currentState?.pushNamed(
      routeName,
      arguments: arguments,
    );
  }

  void pop({dynamic args}) {
    _navigatorKey.currentState?.pop(args);
  }

  Future<dynamic>? pushAndRemoveUntil(String routeName, {Object? arguments}) {
    return _navigatorKey.currentState?.pushNamedAndRemoveUntil(
      routeName,
      (route) => false,
      arguments: arguments,
    );
  }
}
