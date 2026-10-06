import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watermark_samsung/main.dart';

void main() {
  testWidgets('Top-right About button renders on Home and opens Samsung OneUI AboutPage', (WidgetTester tester) async {
    tester.platformDispatcher.localeTestValue = const Locale('zh', 'CN');
    addTearDown(tester.platformDispatcher.clearLocaleTestValue);

    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const WatermarkAssistantApp(showSplashOnInit: false),
    );
    await tester.pump(const Duration(milliseconds: 400));

    // Verify top-right About button is visible
    final aboutBtn = find.text('关于');
    expect(aboutBtn, findsOneWidget);

    // Tap About button
    await tester.tap(aboutBtn);
    for (int i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    // Verify Samsung One UI AboutPage content
    expect(find.text('水印助手'), findsWidgets);
    expect(find.text('版本 2.1.0 (2)'), findsOneWidget);
    expect(find.text('已安装最新版本。'), findsOneWidget);
    expect(find.text('条款与条件'), findsOneWidget);
    expect(find.text('开源许可证'), findsOneWidget);

    // Test Terms and Conditions OneUI bottom-floating dialog
    await tester.tap(find.text('条款与条件'));
    for (int i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(find.text('本应用所有水印合成与图像/视频渲染均在您的设备本地完成，不会将您的任何照片、EXIF 隐私或地理位置上传至任何远程服务器。请安心使用。'), findsOneWidget);
    expect(find.text('确定'), findsOneWidget);

    // Dismiss dialog via '确定'
    await tester.tap(find.text('确定'));
    for (int i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('确定'), findsNothing);

    // Test App Details info dialog
    final infoBtn = find.byTooltip('应用详情');
    expect(infoBtn, findsOneWidget);
    await tester.tap(infoBtn);
    for (int i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('本次更新'), findsOneWidget);
    expect(find.textContaining('1. 适配高通 Adreno GPU'), findsOneWidget);
    await tester.tap(find.text('确定'));
    for (int i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('本次更新'), findsNothing);

    // Pop AboutPage with back button
    final backBtn = find.byTooltip('返回');
    expect(backBtn, findsOneWidget);
    await tester.tap(backBtn);
    // PredictiveBackPageTransitionsBuilder 的退场动画比旧版 260ms 自定义转场更长，
    // 需要泵足 1s 才能完全移除路由（落地页有无限循环动画，不能用 pumpAndSettle）
    for (int i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(find.text('已安装最新版本。'), findsNothing);
  });
}
