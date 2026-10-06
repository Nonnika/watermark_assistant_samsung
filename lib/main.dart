import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'services/runtime_guard.dart';
import 'widgets/app_root.dart';

export 'widgets/app_root.dart' show WatermarkAssistantApp;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 通道查询自带超时，失败时按默认档启动，不阻塞首帧
  await RuntimeGuard.instance.init();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  runApp(const WatermarkAssistantApp());
}
