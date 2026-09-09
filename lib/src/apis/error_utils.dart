import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter_boilerplate/src/base/utils/dialog_utils.dart';
import 'package:flutter_boilerplate/src/base/utils/localization/localization.dart';
import 'package:flutter_boilerplate/src/base/utils/progress_dialog_utils.dart';

Future<void> handleHttpError(DioException e) async {
  switch (e.type) {
    case DioExceptionType.connectionTimeout:
      showAlertDialog(message: Localization.of().poorInternetConnection);
      break;
    case DioExceptionType.badResponse:
      if (e.response?.statusCode == 401) {
        showAlertDialog(message: e.response?.data["message"] ?? "");
      } else {
        showAlertDialog(message: e.response?.data["message"] ?? "");
      }
      break;
    default:
      showAlertDialog(message: e.error.toString());
  }
}

Future<bool> checkInternet() async {
  DateTime date = DateTime.now();
  List<ConnectivityResult> connectivityResult = await (Connectivity()
      .checkConnectivity());

  // If checkConnectivity fails, it will retry for 5 seconds before giving a "no internet connection" error.
  while (connectivityResult.contains(ConnectivityResult.none) &&
      DateTime.now().difference(date).inSeconds < 5) {
    connectivityResult = await (Connectivity().checkConnectivity());
  }
  // Required after upgrading connectivity_plus and device_info_plus package
  if (!connectivityResult.contains(ConnectivityResult.none)) {
    return true;
  }
  showAlertDialog(
    message: Localization.of().internetNotConnected,
    okButtonAction: () {
      ProgressDialogUtils.dismissProgressDialog();
    },
  );
  return false;
}
