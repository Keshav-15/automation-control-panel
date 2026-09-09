import 'package:flutter/material.dart';
import 'package:flutter_boilerplate/src/base/utils/constants/app_constant.dart';
import 'package:flutter_boilerplate/src/base/utils/localization/localization.dart';
import 'package:intl/intl.dart';

import '../utils/constants/color_constant.dart';

extension StringExtension on String {
  String capitalizeFirst() {
    if (isEmpty) return this;
    return this[0].toUpperCase() + substring(1);
  }

  String withoutLeadingPlus() {
    if (isEmpty) return this;
    return startsWith('+') ? substring(1) : this;
  }

  String lastChars(int count) {
    if (isEmpty) return this;
    return length <= count ? this : substring(length - count);
  }

  String getInitials() => isNotEmpty
      ? trim().split(' ').map((e) => e[0]).take(2).join().toUpperCase()
      : '';

  Color hexToColor() =>
      isEmpty ? secondaryColor : Color(int.parse(replaceAll('#', "0xff")));

  bool _emailValidation(String value) {
    return RegExp(validEmailRegex).hasMatch(value);
  }

  // Check Email Validation
  String? isValidEmail() {
    if (trim().isEmpty) {
      return Localization.of().msgEmailEmpty;
    } else if (!_emailValidation(trim())) {
      return Localization.of().msgEmailInvalid;
    } else {
      return null;
    }
  }

  // Empty Field Validation
  String? isFieldEmpty(String message) {
    if (trim().isEmpty) {
      return message;
    } else {
      return null;
    }
  }

  bool _passwordValidation(String value) {
    return RegExp(validPasswordRegex).hasMatch(value);
  }

  // Check Password Validation
  String? isValidPassword() {
    if (trim().isEmpty) {
      return Localization.of().msgPasswordEmpty;
    } else if (!_passwordValidation(trim())) {
      return Localization.of().msgPasswordError;
    } else {
      return null;
    }
  }

  // Check Valid Confirm Password
  String? isValidConfirmPassword(String newPassword) {
    if (newPassword.trim() != trim()) {
      return Localization.of().msgPasswordNotMatch;
    } else {
      return null;
    }
  }
}

extension ColorExtension on Color {
  String colorToHex() {
    String toHex(double value) =>
        (value * 255).toInt().toRadixString(16).padLeft(2, '0');
    return "#${toHex(r)}${toHex(g)}${toHex(b)}".toUpperCase();
  }
}

extension NumExtension on num {
  String currency() {
    try {
      final formattedPrice = NumberFormat.currency(
        symbol: '\$',
        decimalDigits: 2,
      ).format(this);
      return formattedPrice;
    } catch (e) {
      return toString();
    }
  }
}
