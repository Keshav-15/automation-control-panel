import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class DateConstants {
  static const String apiDateFormat = "yyyy-MM-dd HH:mm:ss";
  static const String apiTimeFormat = "HH:mm:ss";
  static const String commonDateFormat = "dd MMMM, yyyy";
  static const String commonTimeFormat = "hh:mm a";
  static const String dueDateFormat = "dd-MM-yyyy";
  static const String notificationDateRangeFormat = "yyyy-MM-dd";
  static const String boardDateFormat = "dd MMM yyyy";
  static const String calendarDateFormat = "yyyy-MM-dd";
  static const String messageDateFormat = "hh:mm a, dd MMM, yyyy";
  static const String subTaskDateFormat = "dd/MM";
  static const String discussionDateFormat = "dd MMM";
  static const String notificationDateFormat = "dd-MMM-yyyy, hh:mm a";
  static const String timeSheetFormat = "HH : mm";
  static const String timeLogFormat = "dd-MM-yyyy | hh:mm a";
  static const String timeStartFormat = "dd-MM-yyyy, hh:mm a";
}

String dateToString(
  DateTime date, {
  String dateFormat = DateConstants.dueDateFormat,
}) {
  return DateFormat(dateFormat).format(date);
}

String timeToString(
  TimeOfDay time, {
  String timeFormat = DateConstants.commonTimeFormat,
}) {
  final format = DateFormat.Hm();
  return DateFormat(
    timeFormat,
  ).format(format.parse("${time.hour}:${time.minute}"));
}

DateTime stringToDate(
  String dateString, {
  String dateFormat = DateConstants.apiDateFormat,
}) {
  try {
    return DateFormat(dateFormat).parse(dateString);
  } on Exception catch (_) {
    return DateTime.now();
  }
}

TimeOfDay stringToTime(String timeString) {
  final format = DateFormat.Hms();
  return TimeOfDay.fromDateTime(format.parse(timeString));
}

String getOrdinalDateFormat(DateTime dateTime) {
  var formattedDate = DateFormat("d").format(dateTime.toLocal());
  final digit = int.parse(formattedDate);
  if (digit >= 11 && digit <= 13) {
    return "dd'th' MMMM, yyyy";
  }
  switch (digit % 10) {
    case 1:
      return "dd'st' MMMM, yyyy";
    case 2:
      return "dd'nd' MMMM, yyyy";
    case 3:
      return "dd'rd' MMMM, yyyy";
    default:
      return "dd'th' MMMM, yyyy";
  }
}

// convert date from API response to app date format
String getConvertedDate(
  String dateString, {
  String dateFormat = DateConstants.commonDateFormat,
  bool isOrdinal = false,
}) {
  try {
    var dateTime = DateFormat(
      DateConstants.apiDateFormat,
    ).parse(dateString, true);
    var formattedDate = DateFormat(
      isOrdinal ? getOrdinalDateFormat(dateTime) : dateFormat,
    ).format(dateTime.toLocal());
    return formattedDate;
  } on Exception catch (_) {
    return "";
  }
}

/// "just now" / "5m ago" / "3h ago" / "2d ago" — used by the QA Control
/// Center's run history (Phase 5) rather than a full date/time string.
String timeAgo(DateTime time) {
  final diff = DateTime.now().difference(time);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  return '${diff.inDays}d ago';
}

// convert date from API response to app time format
String getConvertedTime(
  String dateString, {
  String dateFormat = DateConstants.commonDateFormat,
  bool isUTC = true,
}) {
  try {
    var dateTime = DateFormat(
      DateConstants.apiDateFormat,
    ).parse(dateString, isUTC);
    var formattedDate = DateFormat(dateFormat).format(dateTime.toLocal());
    return formattedDate;
  } on Exception catch (_) {
    return "";
  }
}
