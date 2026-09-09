import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:flutter_boilerplate/src/base/utils/constants/navigation_route_constants.dart';
import 'package:flutter_boilerplate/src/base/utils/localization/localization.dart';
import 'package:flutter_boilerplate/src/base/utils/preference_utils.dart';
import 'package:flutter_boilerplate/src/providers/qa/project_provider.dart';
import 'package:flutter_boilerplate/src/providers/qa/qa_provider.dart';
import 'package:flutter_boilerplate/src/providers/qa/run_provider.dart';
import 'package:flutter_boilerplate/src/providers/theme_provier.dart';
import 'package:flutter_boilerplate/src/widgets/themewidgets/theme_data.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';

import 'base/dependencyinjection/locator.dart';
import 'base/utils/navigation_utils.dart';

void mainDelegate() async {
  WidgetsFlutterBinding.ensureInitialized();
  setupLocator();
  await init();
  await initializeDateFormatting();
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

/// [WidgetsBindingObserver] mixin only for [didRequestAppExit] — Cmd+Q (or
/// Quit from the menu) calls this before macOS actually terminates the
/// process, giving us a chance to kill an in-flight pipeline's process group
/// and release the sleep guard. Without it, a running npm/gradle/flutter
/// build (and `caffeinate`) is orphaned to launchd and keeps the machine
/// awake indefinitely — the same class of bug Phase 3 fixed for Cancel.
class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  // Created here (not via ChangeNotifierProvider's `create:`) so this State
  // can reach it directly in didRequestAppExit without a BuildContext, which
  // may already be tearing down mid-quit.
  final RunProvider _runProvider = RunProvider();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _runProvider.dispose();
    super.dispose();
  }

  @override
  Future<AppExitResponse> didRequestAppExit() async {
    await _runProvider.cancelAndWait();
    return AppExitResponse.exit;
  }

  @override
  Widget build(BuildContext context) {
    // Note: no SystemChrome.setPreferredOrientations — this is a macOS desktop
    // app and orientation lock is a no-op / error on desktop targets.
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => QAProvider()..initialise()),
        ChangeNotifierProvider.value(value: _runProvider),
        ChangeNotifierProvider(create: (_) => ProjectProvider()..initialise()),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeData, child) => MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'QA Control Center',
          builder: (context, child) {
            return MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(1.0)),
              child: child ?? const SizedBox(),
            );
          },
          themeMode: themeData.getTheme() ? ThemeMode.dark : ThemeMode.light,
          theme: lightThemeData(),
          darkTheme: darkThemeData(),
          navigatorKey: locator<NavigationUtils>().navigatorKey,
          onGenerateRoute: locator<NavigationUtils>().generateRoute,
          // Start at the projects list; it shows a "Create project" prompt on first launch
          initialRoute: routeProjects,
          localizationsDelegates: const [
            MyLocalizationsDelegate(),
            DefaultMaterialLocalizations.delegate,
            DefaultWidgetsLocalizations.delegate,
          ],
          supportedLocales: const [Locale('en', '')],
        ),
      ),
    );
  }
}
