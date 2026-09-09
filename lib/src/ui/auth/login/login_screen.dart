import 'package:flutter/material.dart';
import 'package:flutter_boilerplate/src/base/dependencyinjection/locator.dart';
import 'package:flutter_boilerplate/src/base/extensions/context_extension.dart';
import 'package:flutter_boilerplate/src/base/extensions/string_extension.dart';
import 'package:flutter_boilerplate/src/base/utils/constants/image_constant.dart';
import 'package:flutter_boilerplate/src/base/utils/localization/localization.dart';
import 'package:flutter_boilerplate/src/controllers/auth/auth_controller.dart';
import 'package:flutter_boilerplate/src/widgets/primary_text_field.dart';

import '../../../base/extensions/scaffold_extension.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();
  final _formKey = GlobalKey<FormState>();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Image.asset(imgAppLogo, height: context.getHeight(0.3)),
            _getEmailTextField(),
            const SizedBox(height: 8.0),
            _getPasswordTextField(),
            _getLoginButton(),
          ],
        ),
      ),
    ).authContainerScaffold(context: context);
  }

  Widget _getEmailTextField() {
    return PrimaryTextField(
      hint: Localization.of().email,
      focusNode: _emailFocus,
      type: TextInputType.emailAddress,
      textInputAction: TextInputAction.next,
      controller: _emailController,
      onFieldSubmitted: (value) {
        _emailFocus.unfocus();
        _passwordFocus.requestFocus();
      },
      validateFunction: (value) {
        return value!.isValidEmail();
      },
    );
  }

  Widget _getPasswordTextField() {
    return PrimaryTextField(
      hint: Localization.of().password,
      focusNode: _passwordFocus,
      type: TextInputType.visiblePassword,
      textInputAction: TextInputAction.done,
      controller: _passwordController,
      onFieldSubmitted: (value) {
        _passwordFocus.unfocus();
      },
      validateFunction: (value) {
        return value!.isValidPassword();
      },
    );
  }

  Widget _getLoginButton() {
    return TextButton(
      onPressed: () {
        if (_formKey.currentState!.validate()) {
          FocusScope.of(context).unfocus();
          locator<AuthController>().loginApiCall(context: context);
        }
      },
      child: const Text("Login"),
    );
  }
}
