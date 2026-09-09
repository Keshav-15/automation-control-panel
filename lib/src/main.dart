import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_boilerplate/src/base/utils/constants/navigation_route_constants.dart';
import 'package:flutter_boilerplate/src/base/utils/localization/localization.dart';
import 'package:flutter_boilerplate/src/base/utils/preference_utils.dart';
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

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    return MultiProvider(
      providers: [ChangeNotifierProvider(create: (_) => ThemeProvider())],
      child: Consumer<ThemeProvider>(
        builder: (context, themeData, child) => MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'flutter-boilerplate',
          builder: (context, child) {
            return MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(1.0)),
              child: child ?? Container(),
            );
          },
          themeMode: themeData.getTheme() ? ThemeMode.dark : ThemeMode.light,
          theme: lightThemeData(),
          darkTheme: darkThemeData(),
          navigatorKey: locator<NavigationUtils>().navigatorKey,
          onGenerateRoute: locator<NavigationUtils>().generateRoute,
          initialRoute: routeLogin,
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
