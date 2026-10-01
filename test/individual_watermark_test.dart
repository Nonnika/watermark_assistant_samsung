import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:watermark_samsung/models/watermark_config.dart';
import 'package:watermark_samsung/services/app_strings.dart';
import 'package:watermark_samsung/services/device_photo_service.dart';
import 'package:watermark_samsung/widgets/home_screen.dart';
import 'package:watermark_samsung/widgets/home/landing_pick_screen.dart';
import 'package:watermark_samsung/widgets/home/editing_workspace.dart';
import 'package:watermark_samsung/widgets/export_bottom_sheet.dart';

EditingWorkspace workspace(WidgetTester tester) =>
    tester.widget<EditingWorkspace>(find.byType(EditingWorkspace));

Future<void> loadPhotos(WidgetTester tester, WatermarkType type) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
  await tester.runAsync(() async {
    final bytes = Uint8List.fromList(
      img.encodePng(img.Image(width: 100, height: 100)),
    );
    final landing = tester.widget<LandingPickScreen>(
      find.byType(LandingPickScreen),
    );
    await Function.apply(landing.onImportWithWatermarkType, [
      [
        DevicePhotoModel(
          id: 'A',
          name: 'A.png',
          path: '',
          size: bytes.length,
          directBytes: bytes,
        ),
        DevicePhotoModel(
          id: 'B',
          name: 'B.png',
          path: '',
          size: bytes.length,
          directBytes: bytes,
        ),
      ],
      type,
    ]);
  });
  await tester.pumpAndSettle();
  expect(find.byType(EditingWorkspace), findsOneWidget);
}

void main() {
  setUp(() => AppStrings.currentLanguage.value = AppLanguage.zh);
  tearDown(() => AppStrings.currentLanguage.value = AppLanguage.zh);

  testWidgets('individual frame edits do not change untouched photos', (
    tester,
  ) async {
    await loadPhotos(tester, WatermarkType.frame);
    final original = workspace(tester).activeFrameConfig.backgroundColor;
    workspace(tester).onToggleIndividualMode(true);
    await tester.pump();
    workspace(tester).onFrameConfigChanged(
      workspace(tester).activeFrameConfig.copyWith(backgroundColor: Colors.red),
    );
    await tester.pump();
    workspace(tester).onIndexChanged(1);
    await tester.pump();
    expect(workspace(tester).activeFrameConfig.backgroundColor, original);
    workspace(tester).onToggleIndividualMode(false);
    await tester.pump();
    expect(workspace(tester).activeFrameConfig.backgroundColor, original);
    workspace(tester).onIndexChanged(0);
    await tester.pump();
    workspace(tester).onToggleIndividualMode(true);
    await tester.pump();
    expect(workspace(tester).activeFrameConfig.backgroundColor, Colors.red);
  });

  testWidgets('batch export uses global PNG fallback for untouched photos', (
    tester,
  ) async {
    await loadPhotos(tester, WatermarkType.floatingPng);
    final originalScale = workspace(tester).activePngConfig.scale;
    workspace(tester).onToggleIndividualMode(true);
    await tester.pump();
    workspace(tester).onPngConfigChanged(
      workspace(tester).activePngConfig.copyWith(scale: 0.8),
    );
    await tester.pump();
    workspace(tester).onExport(true);
    await tester.pumpAndSettle();
    final sheet = tester.widget<ExportBottomSheet>(
      find.byType(ExportBottomSheet),
    );
    final untouched = sheet.images[1];
    final configUsedByExport = untouched.individualPngConfig ?? sheet.pngConfig;
    expect(configUsedByExport.scale, originalScale);
    expect(sheet.images[0].individualPngConfig!.scale, 0.8);
  });

  testWidgets(
    'switching photos restores the logo belonging to individual config',
    (tester) async {
      await loadPhotos(tester, WatermarkType.frame);
      ui.Image? originalLogo;
      ui.Image? custom;
      await tester.runAsync(() async {
        final recorder = ui.PictureRecorder();
        Canvas(recorder).drawColor(Colors.blue, BlendMode.src);
        final picture = recorder.endRecording();
        originalLogo = await picture.toImage(2, 2);
        picture.dispose();
        final recorder2 = ui.PictureRecorder();
        Canvas(recorder2).drawColor(Colors.red, BlendMode.src);
        final picture2 = recorder2.endRecording();
        custom = await picture2.toImage(2, 2);
        picture2.dispose();
      });
      addTearDown(() {
        originalLogo?.dispose();
        custom?.dispose();
      });
      workspace(tester).onIndexChanged(1);
      await tester.pump();
      workspace(tester).onToggleIndividualMode(true);
      await tester.pump();
      workspace(tester).onFrameControlsChanged(
        workspace(tester).activeFrameConfig.copyWith(
          selectedLogoId: 'custom_original',
          customLogoDecoded: originalLogo,
        ),
      );
      await tester.pump();
      workspace(tester).onIndexChanged(0);
      await tester.pump();
      workspace(tester).onFrameControlsChanged(
        workspace(tester).activeFrameConfig.copyWith(
          selectedLogoId: 'custom_review',
          customLogoDecoded: custom,
        ),
      );
      await tester.pump();
      workspace(tester).onIndexChanged(1);
      await tester.pump();
      expect(
        workspace(tester).activeFrameConfig.selectedLogoId,
        'custom_original',
      );
      expect(
        identical(workspace(tester).decodedBrandLogo, originalLogo),
        isTrue,
      );
      workspace(tester).onExport(true);
      await tester.pumpAndSettle();
      final sheet = tester.widget<ExportBottomSheet>(
        find.byType(ExportBottomSheet),
      );
      await tester.runAsync(() async {
        expect(
          await sheet.resolveLogoImage(sheet.images[0].individualFrameConfig!),
          same(custom),
        );
        expect(
          await sheet.resolveLogoImage(sheet.images[1].individualFrameConfig!),
          same(originalLogo),
        );
      });
    },
  );

  testWidgets(
    'builtin logo decoding does not apply edits or stale images to another photo',
    (tester) async {
      await loadPhotos(tester, WatermarkType.frame);
      workspace(tester).onToggleIndividualMode(true);
      await tester.pump();
      workspace(tester).onFrameControlsChanged(
        workspace(tester).activeFrameConfig
            .copyWith(selectedLogoId: 'samsung_black'),
      );
      // 在解码完成之前立即切换到未调整的 B。
      workspace(tester).onIndexChanged(1);
      await tester.pump();
      expect(
        workspace(tester).activeFrameConfig.selectedLogoId,
        'samsung_blue',
      );
      workspace(tester).onExport(true);
      await tester.pumpAndSettle();
      final sheet = tester.widget<ExportBottomSheet>(
        find.byType(ExportBottomSheet),
      );
      final configA = sheet.images[0].individualFrameConfig!;
      expect(configA.selectedLogoId, 'samsung_black');
      expect(sheet.images[1].individualFrameConfig, isNull);
      ui.Image? blackLogo;
      ui.Image? blueLogo;
      await tester.runAsync(() async {
        blackLogo = await sheet.resolveLogoImage(configA);
        blueLogo = await sheet.resolveLogoImage(sheet.frameConfig);
      });
      await tester.pumpAndSettle();
      expect(blackLogo, isNotNull);
      expect(blueLogo, isNotNull);
      expect(workspace(tester).decodedBrandLogo, same(blueLogo));
      workspace(tester).onIndexChanged(0);
      await tester.pump();
      expect(workspace(tester).decodedBrandLogo, same(blackLogo));
    },
  );

  testWidgets(
    'batch frame export draws each photo with its own logo and the global fallback',
    (tester) async {
      await loadPhotos(tester, WatermarkType.frame);
      ui.Image? redLogo;
      ui.Image? blueLogo;
      late Directory outputDir;
      await tester.runAsync(() async {
        outputDir = await Directory.systemTemp.createTemp(
          'watermark_export_test_',
        );
        for (final color in [Colors.red, Colors.blue]) {
          final recorder = ui.PictureRecorder();
          Canvas(recorder).drawColor(color, BlendMode.src);
          final picture = recorder.endRecording();
          final logo = await picture.toImage(8, 8);
          picture.dispose();
          if (color == Colors.red) {
            redLogo = logo;
          } else {
            blueLogo = logo;
          }
        }
      });
      const pathChannel = MethodChannel('plugins.flutter.io/path_provider');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            pathChannel,
            (call) async => outputDir.path,
          );
      addTearDown(() async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(pathChannel, null);
        redLogo?.dispose();
        blueLogo?.dispose();
        await outputDir.delete(recursive: true);
      });

      // 全局蓝色 Logo；A 单独使用红色，B 保留全局默认值。
      workspace(tester).onFrameControlsChanged(
        workspace(tester).activeFrameConfig.copyWith(
          selectedLogoId: 'custom_blue',
          customLogoDecoded: blueLogo,
          paddingRatio: 0.1,
          bottomBarRatio: 0.4,
          showParameters: false,
        ),
      );
      await tester.pump();
      workspace(tester).onToggleIndividualMode(true);
      await tester.pump();
      workspace(tester).onFrameControlsChanged(
        workspace(tester).activeFrameConfig.copyWith(
          selectedLogoId: 'custom_red',
          customLogoDecoded: redLogo,
          backgroundColor: Colors.yellow,
        ),
      );
      await tester.pump();
      workspace(tester).onExport(true);
      await tester.pumpAndSettle();
      final exportButton = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, '立即批量导出 (2 张)'),
      );
      await tester.runAsync(() async {
        await Function.apply(exportButton.onPressed!, []);
      });
      await tester.pumpAndSettle();
      expect(find.text('全部导出完成！共 2 张图片已保存至相册。'), findsOneWidget);

      await tester.runAsync(() async {
        final files = await outputDir
            .list()
            .where((entity) => entity is File)
            .cast<File>()
            .toList();
        expect(files, hasLength(2));
        final a = img.decodeJpg(
          await files
              .singleWhere((file) => file.path.contains('FRAME_A_'))
              .readAsBytes(),
        )!;
        final b = img.decodeJpg(
          await files
              .singleWhere((file) => file.path.contains('FRAME_B_'))
              .readAsBytes(),
        )!;
        final aLogo = a.getPixel(23, 130);
        final bLogo = b.getPixel(23, 130);
        expect(aLogo.r, greaterThan(aLogo.b + 100));
        expect(bLogo.b, greaterThan(bLogo.r + 100));
        // 未调节 B 的边框仍然为全局白色。
        final bBorder = b.getPixel(115, 130);
        expect(bBorder.r, greaterThan(240));
        expect(bBorder.g, greaterThan(240));
        expect(bBorder.b, greaterThan(240));
      });
    },
  );
}
