import 'package:flutter/material.dart';
import 'package:flutter_boilerplate/src/providers/theme_provier.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';

class VerticalSkeletonView extends StatelessWidget {
  final double height;
  final double hPadding;
  const VerticalSkeletonView({
    super.key,
    this.height = 144.0,
    this.hPadding = 15.0,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeProvider>(
      builder: (context, themeData, _) => Shimmer.fromColors(
        baseColor: themeData.isDarkMode ? Colors.black : Colors.grey[300]!,
        highlightColor: themeData.isDarkMode ? Colors.grey : Colors.grey[100]!,
        child: ListView.builder(
          padding: EdgeInsets.symmetric(horizontal: hPadding, vertical: 15.0),
          itemCount: 8,
          itemBuilder: (context, index) => Container(
            height: height,
            padding: const EdgeInsets.fromLTRB(20.0, 16.0, 13.0, 20.0),
            margin: const EdgeInsets.only(bottom: 10.0),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10.0),
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}
