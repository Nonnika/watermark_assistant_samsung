import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:watermark_samsung/main.dart';
import 'package:watermark_samsung/models/frame_watermark_config.dart';
import 'package:watermark_samsung/models/watermark_config.dart';
import 'package:watermark_samsung/services/device_photo_service.dart';
import 'package:watermark_samsung/widgets/custom_photo_selector.dart';
import 'package:watermark_samsung/widgets/frame_controls.dart';
import 'package:watermark_samsung/widgets/hero_poster_banner.dart';
import 'package:watermark_samsung/widgets/selector/selector_bottom_action.dart';
import 'package:watermark_samsung/widgets/splash_screen.dart';

void main() {
  testWidgets('Watermark Assistant App launches with animated splash screen and transitions to Home', (WidgetTester tester) async {
    // Set system locale to zh for test
    tester.platformDispatcher.localeTestValue = const Locale('zh', 'CN');
    addTearDown(tester.platformDispatcher.clearLocaleTestValue);

    await tester.pumpWidget(const WatermarkAssistantApp(showSplashOnInit: true));
    await tester.pump(const Duration(milliseconds: 600));

    // In Splash Screen
    expect(find.text('水印助手'), findsOneWidget);
    expect(find.text('感受更强大的水印体验'), findsOneWidget);

    // Tap to finish splash and transition to Home
    await tester.tap(find.byType(SplashScreen));
    await tester.pump(const Duration(milliseconds: 500));

    // Now in HomeScreen
    expect(find.byType(HeroPosterBanner), findsOneWidget);
    expect(find.byType(CustomPhotoSelector), findsOneWidget);
  });

  testWidgets('FrameControls color strip renders blurred ball and switches background correctly', (WidgetTester tester) async {
    FrameWatermarkConfig currentConfig = const FrameWatermarkConfig();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              return FrameControls(
                activeToolIndex: 1, // Color tool
                config: currentConfig,
                photoColors: const [Color(0xFF123456), Color(0xFF654321)],
                photoBytes: img.encodePng(img.Image(width: 8, height: 8)),
                isAdjusting: false,
                adjustingParamName: '',
                adjustingParamValue: '',
                adjustingProgress: 0.0,
                onChanged: (newCfg) {
                  setState(() {
                    currentConfig = newCfg;
                  });
                },
              );
            },
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Verify slim frame color strip is present
    expect(find.byKey(const ValueKey('slim_frame_color')), findsOneWidget);
    expect(currentConfig.isBlurredBg, isFalse);

    // Tap on the blurred background ball (second child in row)
    final blurBallFinder = find.byIcon(Icons.blur_on_rounded);
    expect(blurBallFinder, findsOneWidget);
    await tester.tap(blurBallFinder);
    await tester.pumpAndSettle();

    expect(currentConfig.isBlurredBg, isTrue);
    expect(currentConfig.isPaperTextureBg, isFalse);

    // Tap on the paper texture ball (third child in row)
    final paperBallFinder = find.byIcon(Icons.texture_rounded);
    expect(paperBallFinder, findsOneWidget);
    await tester.tap(paperBallFinder);
    await tester.pumpAndSettle();

    expect(currentConfig.isPaperTextureBg, isTrue);
    expect(currentConfig.isBlurredBg, isFalse);
  });

  testWidgets('SelectorBottomAction renders action buttons when visible and triggers callbacks', (WidgetTester tester) async {
    WatermarkType? selectedType;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SelectorBottomAction(
            isVisible: true,
            onSelectType: (type) {
              selectedType = type;
            },
          ),
        ),
      ),
    );

    expect(find.text('边框水印'), findsOneWidget);
    expect(find.text('叠加水印'), findsOneWidget);

    await tester.tap(find.text('边框水印'));
    await tester.pump();
    expect(selectedType, WatermarkType.frame);

    await tester.tap(find.text('叠加水印'));
    await tester.pump();
    expect(selectedType, WatermarkType.floatingPng);
  });

  testWidgets('CustomPhotoSelector renders with GPU matrix translation and displays empty state with refresh/permission button', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    DevicePhotoService.debugOverrideIsAndroid = true;
    addTearDown(() => DevicePhotoService.debugOverrideIsAndroid = null);

    // 1. Mock channel returning permission = true
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('com.example.watermark_samsung/ultra_hdr'),
      (MethodCall methodCall) async {
        if (methodCall.method == 'checkStoragePermission') return true;
        if (methodCall.method == 'requestStoragePermission') return true;
        if (methodCall.method == 'getRecentPhotos') return [];
        return null;
      },
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CustomPhotoSelector(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('照片'), findsOneWidget);
    expect(find.text('动态照片'), findsOneWidget);
    expect(find.text('暂未发现相册照片'), findsOneWidget);
    expect(find.text('刷新'), findsOneWidget);

    // 2. Mock channel returning permission = false
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('com.example.watermark_samsung/ultra_hdr'),
      (MethodCall methodCall) async {
        if (methodCall.method == 'checkStoragePermission') return false;
        if (methodCall.method == 'requestStoragePermission') return true;
        if (methodCall.method == 'getRecentPhotos') return [];
        return null;
      },
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CustomPhotoSelector(key: ValueKey('no_perm')),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('未获得相册访问权限'), findsOneWidget);
    expect(find.text('申请权限'), findsOneWidget);

    // Tap 申请权限
    await tester.tap(find.text('申请权限'), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 300));

    // Reset handler
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('com.example.watermark_samsung/ultra_hdr'),
      null,
    );
  });
}
