import 'package:flutter/material.dart';
import 'package:flutter_boilerplate/src/base/dependencyinjection/locator.dart';

import 'constants/color_constant.dart';
import 'navigation_utils.dart';

class ProgressDialogUtils {
  ProgressDialogUtils._();
  static bool _isLoading = false;

  static void dismissProgressDialog() {
    if (_isLoading) {
      locator<NavigationUtils>().pop();
      _isLoading = false;
    }
  }

  static void showProgressDialog() async {
    _isLoading = true;
    await showDialog(
      context: locator<NavigationUtils>().getCurrentContext,
      barrierDismissible: false,
      builder: (context) {
        return const SimpleDialog(
          elevation: 0.0,
          backgroundColor: Colors.transparent,
          children: <Widget>[
            Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
              ),
            ),
          ],
        );
      },
    );
  }
}
