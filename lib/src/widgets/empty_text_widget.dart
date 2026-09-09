import 'package:flutter/material.dart';

import '../base/utils/constants/fontsize_constant.dart';

class EmptyTextWidget extends StatelessWidget {
  final String topLine;
  final String bottomLine;

  const EmptyTextWidget({
    super.key,
    required this.topLine,
    required this.bottomLine,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 34.0),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _getText(text: topLine),
            _getText(text: bottomLine),
          ],
        ),
      ),
    );
  }

  Widget _getText({required String text}) {
    return Text(
      text,
      style: const TextStyle(
        color: Colors.grey,
        fontSize: fontSize14,
        fontWeight: fontWeightRegular,
        height: 1.4,
      ),
    );
  }
}
