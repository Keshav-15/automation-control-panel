import 'package:flutter/material.dart';
import 'package:flutter_boilerplate/src/models/qa/project_model.dart';
import 'package:flutter_boilerplate/src/ui/auth/login/login_screen.dart';
import 'package:flutter_boilerplate/src/ui/qa/commands/command_edit_screen.dart';
import 'package:flutter_boilerplate/src/ui/qa/commands/command_library_screen.dart';
import 'package:flutter_boilerplate/src/ui/qa/commands/surface_command_manager_screen.dart';
import 'package:flutter_boilerplate/src/ui/qa/devices/devices_screen.dart';
import 'package:flutter_boilerplate/src/ui/qa/history/recent_runs_screen.dart';
import 'package:flutter_boilerplate/src/ui/qa/home/home_screen.dart';
import 'package:flutter_boilerplate/src/ui/qa/projects/create_edit_project_screen.dart';
import 'package:flutter_boilerplate/src/ui/qa/projects/project_detail_screen.dart';
import 'package:flutter_boilerplate/src/ui/qa/projects/projects_list_screen.dart';
import 'package:flutter_boilerplate/src/ui/qa/reports/reports_screen.dart';
import 'package:flutter_boilerplate/src/ui/qa/runner/active_runs_screen.dart';
import 'package:flutter_boilerplate/src/ui/qa/scripts/scripts_screen.dart';
import 'package:flutter_boilerplate/src/ui/qa/setup/setup_screen.dart';

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
    RouteSettings currentRoute = const RouteSettings(name: '', arguments: {});
    _navigatorKey.currentState?.popUntil((route) {
      currentRoute = route.settings;
      return true;
    });
    return currentRoute;
  }

  Route<dynamic> generateRoute(RouteSettings settings) {
    switch (settings.name) {
      // ── Multi-project routes (new landing flow) ───────────────────────────
      case routeProjects:
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => const ProjectsListScreen(),
        );
      case routeProjectDetail:
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => ProjectDetailScreen(
            args: settings.arguments as ProjectDetailArgs,
          ),
        );
      case routeCreateProject:
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => CreateEditProjectScreen(
            // arguments is ProjectConfig when importing; null for a brand-new project
            importedProject: settings.arguments as ProjectConfig?,
          ),
        );
      case routeEditProject:
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => CreateEditProjectScreen(
            existingProject: settings.arguments as ProjectConfig?,
          ),
        );
      case routeCommandLibrary:
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => CommandLibraryScreen(
            args: settings.arguments as CommandLibraryArgs,
          ),
        );
      case routeCommandEdit:
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => CommandEditScreen(
            args: settings.arguments as CommandEditArgs,
          ),
        );
      case routeSurfaceCommandManager:
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => SurfaceCommandManagerScreen(
            args: settings.arguments as SurfaceCommandManagerArgs,
          ),
        );
      case routeScripts:
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => ScriptsScreen(
            args: settings.arguments as ScriptsArgs,
          ),
        );
      case routeReports:
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => ReportsScreen(
            args: settings.arguments as ReportsArgs,
          ),
        );
      case routeRecentRuns:
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => const RecentRunsScreen(),
        );
      case routeActiveRuns:
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => const ActiveRunsScreen(),
        );
      case routeDevices:
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => const DevicesScreen(),
        );

      // ── Legacy single-project routes (kept for backward compat) ──────────
      case routeQAHome:
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => const HomeScreen(),
        );
      case routeQASetup:
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => const SetupScreen(),
        );

      // ── Boilerplate auth (kept, not used in QA flows) ────────────────────
      case routeLogin:
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => const LoginScreen(),
        );

      default:
        return _errorRoute('Route not found: ${settings.name}');
    }
  }

  Route<dynamic> _errorRoute(String message) {
    return MaterialPageRoute(
      builder: (context) => Scaffold(
        appBar: AppBar(title: const Text('Error')),
        body: Center(child: Text(message)),
      ),
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
