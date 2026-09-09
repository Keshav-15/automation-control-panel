// Cells Container Decoration
import 'package:flutter/material.dart';
import 'package:flutter_boilerplate/src/widgets/themewidgets/theme_text.dart';
import 'constants/color_constant.dart';
import 'constants/fontsize_constant.dart';

// Text Style
TextStyle lightPopupMenuTextStyle() {
  return const TextStyle(
    color: primaryTextColor,
    fontWeight: fontWeightRegular,
    fontSize: fontSize14,
  );
}

TextStyle darkPopupMenuTextStyle() {
  return const TextStyle(
    color: Colors.white,
    fontWeight: fontWeightRegular,
    fontSize: fontSize14,
  );
}

ThemeData lightCalendarTheme() {
  return ThemeData.light().copyWith(
    colorScheme: const ColorScheme.light().copyWith(primary: primaryColor),
  );
}

ThemeData darkCalendarTheme() {
  return ThemeData.dark().copyWith();
}

// Media Picker Bottom Sheet Action Style
Widget getBottomSheetAction({
  required IconData icon,
  required String title,
  required Function onTap,
  required BuildContext context,
}) {
  return GestureDetector(
    onTap: () {
      Navigator.of(context).pop();
      onTap();
    },
    child: Container(
      margin: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Column(
        children: <Widget>[
          ClipOval(
            child: Container(
              color: primaryColor,
              padding: const EdgeInsets.all(10.0),
              child: Icon(icon, color: Colors.white),
            ),
          ),
          ThemeText(
            text: title,
            lightTextColor: secondaryTextColor,
            darkTextColor: Colors.white,
            fontSize: fontSize13,
            fontWeight: fontWeightRegular,
          ),
        ],
      ),
    ),
  );
}
