import 'package:flutter/cupertino.dart';
import 'package:flutter_boilerplate/src/base/dependencyinjection/locator.dart';
import 'package:flutter_boilerplate/src/base/utils/localization/localization.dart';
import 'package:flutter_boilerplate/src/base/utils/navigation_utils.dart';

class CupertinoErrorDialog extends StatelessWidget {
  final String message;
  final String? okTitle;
  final Function()? okFunction;
  final bool isCancelEnable;

  const CupertinoErrorDialog({
    super.key,
    required this.message,
    this.okTitle,
    this.okFunction,
    this.isCancelEnable = false,
  });

  @override
  Widget build(BuildContext context) {
    return CupertinoAlertDialog(
      title: Text(Localization.of().appName),
      content: Text(message),
      actions: isCancelEnable
          ? [_getOkAction(), _getCancelAction()]
          : [_getOkAction()],
    );
  }

  CupertinoDialogAction _getOkAction() {
    return CupertinoDialogAction(
      isDefaultAction: true,
      child: Text(okTitle ?? Localization.of().ok),
      onPressed: () {
        locator<NavigationUtils>().pop();
        if (okFunction != null) {
          okFunction!();
        }
      },
    );
  }

  CupertinoDialogAction _getCancelAction() {
    return CupertinoDialogAction(
      isDestructiveAction: true,
      child: Text(Localization.of().cancel),
      onPressed: () {
        locator<NavigationUtils>().pop();
      },
    );
  }
}
