import 'package:flutter/material.dart';

extension ScaffoldExtension on Widget {
  Scaffold authContainerScaffold({required BuildContext context}) {
    return Scaffold(body: SafeArea(child: this));
  }

  Dialog dialogContainer({double height = 350}) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.0)),
      elevation: 20.0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 25.0),
      child: Container(
        height: height,
        padding: const EdgeInsets.all(20.0),
        child: this,
      ),
    );
  }
}
