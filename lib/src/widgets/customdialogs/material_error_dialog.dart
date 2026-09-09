import 'package:flutter/material.dart';
import 'package:flutter_boilerplate/src/base/dependencyinjection/locator.dart';
import 'package:flutter_boilerplate/src/base/utils/localization/localization.dart';
import 'package:flutter_boilerplate/src/base/utils/navigation_utils.dart';

class MaterialErrorDialog extends StatelessWidget {
  final String message;
  final String? okTitle;
  final Function()? okFunction;
  final bool isCancelEnable;

  const MaterialErrorDialog({
    super.key,
    required this.message,
    this.okTitle,
    this.okFunction,
    this.isCancelEnable = false,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(Localization.of().appName),
      content: Text(message),
      actions: isCancelEnable
          ? [_getOkAction(), _getCancelAction()]
          : [_getOkAction()],
    );
  }

  TextButton _getOkAction() {
    return TextButton(
      child: Text(okTitle ?? Localization.of().ok),
      onPressed: () {
        locator<NavigationUtils>().pop();
        if (okFunction != null) {
          okFunction!();
        }
      },
    );
  }

  TextButton _getCancelAction() {
    return TextButton(
      child: Text(Localization.of().cancel),
      onPressed: () {
        locator<NavigationUtils>().pop();
      },
    );
  }
}
