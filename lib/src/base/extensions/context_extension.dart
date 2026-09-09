import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

extension ContextExtension on BuildContext {
  double getWidth([double percentage = 1.0]) {
    return MediaQuery.of(this).size.width * percentage;
  }

  double getHeight([double percentage = 1.0]) {
    return MediaQuery.of(this).size.height * percentage;
  }

  double getViewInsetsBottom() {
    return MediaQuery.of(this).viewInsets.bottom;
  }

  double getTopSafeArea([double percentage = 1.0]) {
    return MediaQuery.of(this).padding.top * percentage;
  }

  double getBottomSafeArea([double percentage = 1.0]) {
    return MediaQuery.of(this).padding.bottom * percentage;
  }

  T prov<T>({bool listen = false}) {
    return Provider.of<T>(this, listen: listen);
  }
}
