import 'package:flutter/material.dart';
import 'package:flutter_boilerplate/src/providers/theme_provier.dart';
import 'package:provider/provider.dart';

class ThemeImage extends StatelessWidget {
  final String lightImage;
  final String? darkImage;
  final double scale;
  final double? height;
  final double? width;

  const ThemeImage({
    super.key,
    required this.lightImage,
    this.darkImage,
    required this.scale,
    this.height,
    this.width,
  });
  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeProvider>(
      builder: (context, themeData, _) => Image.asset(
        themeData.isDarkMode ? darkImage ?? lightImage : lightImage,
        height: height,
        width: width,
        scale: scale,
      ),
    );
  }
}
