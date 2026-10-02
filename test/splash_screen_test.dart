import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watermark_samsung/services/app_strings.dart';
import 'package:watermark_samsung/theme/one_ui_theme.dart';
import 'package:watermark_samsung/widgets/splash_screen.dart';

void main() {
  setUp(() => AppStrings.currentLanguage.value = AppLanguage.zh);
  tearDown(() => AppStrings.currentLanguage.value = AppLanguage.zh);

  Widget splash(VoidCallback onFinish, {bool reduceMotion = false}) {
    return MaterialApp(
      theme: OneUITheme.lightTheme(),
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduceMotion),
        child: SplashScreen(onFinish: onFinish),
      ),
    );
  }

  testWidgets('Completes automatically and only calls onFinish once', (
    tester,
  ) async {
    var finishes = 0;
    await tester.pumpWidget(splash(() => finishes++));
    await tester.pump();
    // Completion is reported on the frame after the animation's final value.
    await tester.pump(const Duration(milliseconds: 1850));
    expect(finishes, 1);

    await tester.tap(find.byType(SplashScreen));
    await tester.pump(const Duration(seconds: 2));
    expect(finishes, 1);
  });

  testWidgets('Skipping midway cancels the remaining animation', (
    tester,
  ) async {
    var finishes = 0;
    await tester.pumpWidget(splash(() => finishes++));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.byType(SplashScreen));
    expect(finishes, 1);

    await tester.pump(const Duration(seconds: 2));
    expect(finishes, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Disposing midway does not trigger navigation', (tester) async {
    var finishes = 0;
    await tester.pumpWidget(splash(() => finishes++));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
    expect(finishes, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Reduced motion shows a static splash and finishes promptly', (
    tester,
  ) async {
    var finishes = 0;
    await tester.pumpWidget(splash(() => finishes++, reduceMotion: true));
    expect(finishes, 0);
    expect(find.text('水印助手').hitTestable(), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 400));
    expect(finishes, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Disposing a reduced-motion splash cancels its timer', (
    tester,
  ) async {
    var finishes = 0;
    await tester.pumpWidget(splash(() => finishes++, reduceMotion: true));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    expect(finishes, 0);
  });
}
