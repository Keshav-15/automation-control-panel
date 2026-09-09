import 'dart:io';

import 'package:app_settings/app_settings.dart';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import 'common_ui_methods.dart';
import 'constants/app_constant.dart';
import 'constants/dic_params.dart';
import 'dialog_utils.dart';
import 'localization/localization.dart';

// Logger
void logger(String log) {
  if (kDebugMode) {
    debugPrint(log);
  }
}

// To Open App Settings
void openSettings(BuildContext context) {
  showAlertDialog(
    message: Localization.of().alertPermissionNotRestricted,
    okButtonTitle: Localization.of().ok,
    okButtonAction: () {
      AppSettings.openAppSettings();
    },
  );
}

// Pick Image From Gallery and Camera
Future<File> getImage({
  required BuildContext context,
  required bool pickFromCamera,
}) async {
  final picker = ImagePicker();
  late File file;
  try {
    final pickedFile = await picker.pickImage(
      source: pickFromCamera ? ImageSource.camera : ImageSource.gallery,
      preferredCameraDevice: CameraDevice.rear,
      imageQuality: imageQuality,
    );
    if (pickedFile != null) {
      file = File(pickedFile.path);
    }
  } on PlatformException catch (e) {
    if (pickFromCamera
        ? e.code == permissionTypeCamera
        : e.code == permissionTypePhotos) {
      openSettings(context);
    }
  }
  return file;
}

// To Get Multiple File
Future<List<PlatformFile>> getMultipleFiles({
  required BuildContext context,
  required bool isMedia,
}) async {
  var pickedFile = <PlatformFile>[];
  var result = await FilePicker.platform.pickFiles(
    type: isMedia ? FileType.media : FileType.any,
    allowMultiple: true,
    compressionQuality: 60,
  );
  if (result != null) {
    pickedFile = result.files;
  }
  return pickedFile;
}

// To Get the Device ID
Future<String> getDeviceId() async {
  final DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
  if (kIsWeb) {
    return "";
  } else {
    if (Platform.isIOS) {
      final IosDeviceInfo iosDeviceInfo = await deviceInfo.iosInfo;
      return iosDeviceInfo.identifierForVendor ?? ""; // unique ID on iOS
    } else {
      final AndroidDeviceInfo androidDeviceInfo = await deviceInfo.androidInfo;
      return androidDeviceInfo.id; // unique ID on Android
    }
  }
}

// Date Picker Method
Future<DateTime?> pickDate({
  required BuildContext context,
  DateTime? initialDate,
  DateTime? firstDate,
  DateTime? lastDate,
}) async {
  final picked = await showDatePicker(
    context: context,
    initialDate: initialDate ?? DateTime.now(),
    firstDate: firstDate ?? DateTime.now(),
    lastDate: lastDate ?? DateTime(DateTime.now().year + lastYear),
    builder: (context, child) {
      return Theme(
        data: 1 == 1 ? darkCalendarTheme() : lightCalendarTheme(),
        child: child!,
      );
    },
  );
  return picked;
}
