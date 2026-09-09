import 'package:flutter/material.dart';
import 'package:flutter_boilerplate/src/apis/apimanagers/auth_api_manager.dart';
import 'package:flutter_boilerplate/src/base/dependencyinjection/locator.dart';
import 'package:flutter_boilerplate/src/base/utils/common_methods.dart';
import 'package:flutter_boilerplate/src/models/res_base_model.dart';

class AuthController {
  void loginApiCall({required BuildContext context}) async {
    final value = await locator<AuthApiManager>().login(ResBaseModel());
    logger(value.message ?? "");
    // if (context.mounted) {
    // context.prov<Name of Provider>().methodName();
    // }
  }
}
