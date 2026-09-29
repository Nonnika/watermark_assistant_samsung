import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'widgets/app_root.dart';

export 'widgets/app_root.dart' show WatermarkAssistantApp;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  runApp(const WatermarkAssistantApp());
}
