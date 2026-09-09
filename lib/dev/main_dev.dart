import 'package:flutter_dotenv/flutter_dotenv.dart';

import '../src/main.dart';

void main() async {
  await dotenv.load(fileName: ".env.dev");
  mainDelegate();
}
