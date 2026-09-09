import 'package:flutter/material.dart';
import 'package:flutter_boilerplate/src/base/utils/constants/fontsize_constant.dart';
import 'package:flutter_boilerplate/src/providers/theme_provier.dart';
import 'package:provider/provider.dart';

class ThemeText extends StatelessWidget {
  final String text;
  final Color lightTextColor;
  final Color? darkTextColor;
  final double fontSize;
  final FontWeight fontWeight;
  final int? maxLines;
  final TextOverflow? overflow;
  final TextAlign? textAlign;

  const ThemeText({
    super.key,
    required this.text,
    required this.lightTextColor,
    this.darkTextColor,
    required this.fontSize,
    this.fontWeight = fontWeightRegular,
    this.maxLines,
    this.overflow,
    this.textAlign,
  });
  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeProvider>(
      builder: (context, themeData, _) => Text(
        text,
        maxLines: maxLines,
        overflow: overflow,
        textAlign: textAlign,
        style: TextStyle(
          color: themeData.isDarkMode ? darkTextColor : lightTextColor,
          fontSize: fontSize,
          fontWeight: fontWeight,
        ),
      ),
    );
  }
}
