import 'package:flutter_boilerplate/src/base/utils/constants/preference_key_constant.dart';
import 'package:flutter_boilerplate/src/base/utils/preference_utils.dart';

extension ContextExtension on int {
  String formatCount() {
    if (this >= 1000000000) {
      return '${(this / 1000000000).toStringAsFixed(1).replaceAll('.0', '')}B';
    } else if (this >= 1000000) {
      return '${(this / 1000000).toStringAsFixed(1).replaceAll('.0', '')}M';
    } else if (this >= 1000) {
      return '${(this / 1000).toStringAsFixed(1).replaceAll('.0', '')}k';
    } else {
      return toString();
    }
  }
}

extension IntExtension on int? {
  bool isMyId() {
    if (this != null && this == getInt(prefkeyId)) {
      return true;
    }
    return false;
  }
}
