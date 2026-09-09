import 'package:flutter/material.dart';
import 'package:flutter_boilerplate/src/base/extensions/context_extension.dart';
import 'package:flutter_boilerplate/src/base/utils/constants/fontsize_constant.dart';
import 'package:flutter_boilerplate/src/widgets/themewidgets/theme_text.dart';

class PrimaryButton extends StatelessWidget {
  final String buttonText;
  final Color buttonColor;
  final Color textColor;
  final Function()? onButtonClick;
  final double? width;
  final double? height;
  final IconData? leadingIcon;

  const PrimaryButton({
    super.key,
    required this.buttonText,
    required this.buttonColor,
    this.width,
    this.height,
    required this.onButtonClick,
    this.textColor = Colors.white,
    this.leadingIcon,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: onButtonClick,
      style: TextButton.styleFrom(
        backgroundColor: buttonColor,
        fixedSize: Size(width ?? context.getWidth(), height ?? 50.0),
      ),
      child: ThemeText(
        textAlign: TextAlign.center,
        text: buttonText,
        lightTextColor: textColor,
        fontSize: fontSize16,
      ),
    );
  }
}
