import 'package:flutter/material.dart';

import '../../base/utils/common_ui_methods.dart';
import '../../base/utils/constants/color_constant.dart';

ThemeData lightThemeData() {
  return ThemeData(
    useMaterial3: true,
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      elevation: 10.0,
      foregroundColor: Colors.white,
      backgroundColor: primaryColor,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: Colors.white,
      textStyle: lightPopupMenuTextStyle(),
    ),
    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.all<Color>(secondaryColor),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.all<Color>(secondaryColor),
    ),
    bottomSheetTheme: const BottomSheetThemeData(backgroundColor: Colors.white),
    dialogTheme: const DialogThemeData(backgroundColor: Colors.white),
    scaffoldBackgroundColor: Colors.white,
    brightness: Brightness.light,
    primaryColor: primaryColor,
    visualDensity: VisualDensity.adaptivePlatformDensity,
    fontFamily: 'Poppins',
  );
}

ThemeData darkThemeData() {
  return ThemeData(
    useMaterial3: true,
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      elevation: 10.0,
      foregroundColor: Colors.white,
      backgroundColor: Colors.black45,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: Colors.black,
      textStyle: darkPopupMenuTextStyle(),
    ),
    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.all<Color>(secondaryColor),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.all<Color>(secondaryColor),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Colors.black45,
    ),
    dialogTheme: const DialogThemeData(backgroundColor: Colors.black45),
    scaffoldBackgroundColor: Colors.black,
    brightness: Brightness.dark,
    primaryColor: Colors.black,
    visualDensity: VisualDensity.adaptivePlatformDensity,
    fontFamily: 'Poppins',
  );
}
