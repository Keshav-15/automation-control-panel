// Last Year
const int lastYear = 50;

// Debounce timer
const Duration debounceTimer = Duration(milliseconds: 500);

//AppBar size
const double appBarSize = 100.0;

// Image Picked Quality
const int imageQuality = 80;

// Regex Pattern
const String validEmailRegex =
    r'^(([^<>()[\]\\.,;:\s@\"]+(\.[^<>()[\]\\.,;:\s@\"]+)*)|(\".+\"))@((\[[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\])|(([a-zA-Z\-0-9]+\.)+[a-zA-Z]{2,}))$';
const String validPasswordRegex =
    r'^(?=.*?[A-Z])(?=.*?[a-z])(?=.*?[0-9])(?=.*?[!@#\$&*~%]).{8,32}$';
const String validMobileRegex = r'(^(?:[+0]9)?[0-9]{10,12}$)';
