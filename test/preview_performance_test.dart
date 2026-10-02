import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:watermark_samsung/models/frame_watermark_config.dart';
import 'package:watermark_samsung/models/image_item.dart';
import 'package:watermark_samsung/models/watermark_config.dart';
import 'package:watermark_samsung/services/watermark_processor.dart';
import 'package:watermark_samsung/widgets/card_stack_preview.dart';
import 'package:watermark_samsung/widgets/preview/active_photo_painter.dart';
import 'package:watermark_samsung/widgets/preview/background_tilt_card.dart';

Uint8List photoBytes(int width, int height) {
  final image = img.Image(width: width, height: height);
  img.fill(image, color: img.ColorRgb8(30, 90, 180));
  return img.encodePng(image);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final size in [(72, 216), (216, 72), (216, 216)]) {
    test('Preview bounds both edges for ${size.$1} x ${size.$2}', () async {
      final image = await WatermarkProcessor.decodeImageFromBytes(
        photoBytes(size.$1, size.$2),
        maxDimension: 108,
      );
      addTearDown(image.dispose);

      expect(image.width, size.$1 ~/ 2);
      expect(image.height, size.$2 ~/ 2);
      // The returned image must remain usable after its decoder is released.
      final pixels = await image.toByteData();
      expect(pixels!.lengthInBytes, image.width * image.height * 4);
    });
  }

  test(
    'Small photos and logos are not upscaled into larger textures',
    () async {
      final image = await WatermarkProcessor.decodeImageFromBytes(
        photoBytes(24, 48),
      );
      addTearDown(image.dispose);
      expect((image.width, image.height), (24, 48));
    },
  );

  test(
    'Export decoding preserves resolution above the preview limit',
    () async {
      final bytes = photoBytes(30, 1800);
      final preview = await WatermarkProcessor.decodeImageFromBytes(bytes);
      final export = await WatermarkProcessor.decodeFullResolutionImage(bytes);
      addTearDown(preview.dispose);
      addTearDown(export.dispose);

      expect(preview.height, 1600);
      expect(preview.width, lessThanOrEqualTo(30));
      expect((export.width, export.height), (30, 1800));
    },
  );

  test('Invalid preview bounds fail before decoding', () async {
    for (final bound in [0, -1]) {
      await expectLater(
        WatermarkProcessor.decodeImageFromBytes(
          photoBytes(8, 8),
          maxDimension: bound,
        ),
        throwsArgumentError,
      );
    }
  });

  test('A failed decode does not prevent subsequent decodes', () async {
    await expectLater(
      WatermarkProcessor.decodeImageFromBytes(Uint8List.fromList([1, 2, 3])),
      throwsException,
    );
    final image = await WatermarkProcessor.decodeImageFromBytes(
      photoBytes(8, 8),
    );
    addTearDown(image.dispose);
    expect(image.width, 8);
  });

  testWidgets(
    'Background cards reuse the decoded photo without reading its bytes',
    (tester) async {
      final image = await tester.runAsync(
        () => WatermarkProcessor.decodeImageFromBytes(photoBytes(24, 48)),
      );
      addTearDown(image!.dispose);
      // Deliberately invalid encoded bytes reveal any accidental second decode.
      final item = ImageItem(
        id: 'preview',
        name: 'preview.png',
        path: '',
        bytes: Uint8List.fromList([1, 2, 3]),
        width: 24,
        height: 48,
        fileSize: 3,
        decodedImage: image,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Stack(
            children: [
              BackgroundTiltCard(
                item: item,
                renderRect: const Rect.fromLTWH(0, 0, 100, 200),
                scale: 0.96,
                offsetX: 8,
                offsetY: -5,
                rotation: 0.038,
                isDark: true,
              ),
            ],
          ),
        ),
      );

      final raw = tester.widget<RawImage>(find.byType(RawImage));
      expect(raw.image, same(image));
      expect(raw.opacity!.value, 0.55);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Card motion retains the painted photo layer and parameter changes repaint it',
    (tester) async {
      final bytes = photoBytes(24, 48);
      final image = await tester.runAsync(
        () => WatermarkProcessor.decodeImageFromBytes(bytes),
      );
      addTearDown(image!.dispose);
      final items = List.generate(
        2,
        (i) => ImageItem(
          id: '$i',
          name: '$i.png',
          path: '',
          bytes: bytes,
          width: 24,
          height: 48,
          fileSize: bytes.length,
          decodedImage: image,
        ),
      );
      var frameConfig = const FrameWatermarkConfig();
      late StateSetter update;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return CardStackPreview(
                images: items,
                currentIndex: 0,
                watermarkType: WatermarkType.frame,
                activeToolIndex: 0,
                watermarkImage: null,
                pngConfig: const WatermarkConfig(),
                logoImage: null,
                frameConfig: frameConfig,
                isIndividualMode: false,
                onToggleIndividualMode: (_) {},
                onIndexChanged: (_) {},
                onWatermarkDragged: (_, _) {},
                onPngConfigChanged: (_) {},
                onFrameConfigChanged: (_) {},
                onParamAdjusting: (_, _, _) {},
                onParamAdjustEnd: () {},
                onExport: (_) {},
                onBack: () {},
              );
            },
          ),
        ),
      );
      await tester.pump();

      final photo = find.byWidgetPredicate(
        (widget) =>
            widget is CustomPaint && widget.painter is ActivePhotoPainter,
      );
      final render = tester.renderObject<RenderCustomPaint>(photo);
      final boundary = render.parent! as RenderRepaintBoundary;
      final layer = boundary.debugLayer;
      boundary.debugResetMetrics();

      final gesture = await tester.startGesture(tester.getCenter(photo));
      await gesture.moveBy(const Offset(40, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(35, 0));
      await tester.pump();
      expect(boundary.debugLayer, same(layer));
      expect(boundary.debugSymmetricPaintCount, 0);
      expect(boundary.debugAsymmetricPaintCount, greaterThan(0));

      await gesture.up();
      await tester.pumpAndSettle();
      boundary.debugResetMetrics();
      update(
        () => frameConfig = frameConfig.copyWith(backgroundColor: Colors.red),
      );
      await tester.pump();
      expect(
        boundary.debugSymmetricPaintCount + boundary.debugAsymmetricPaintCount,
        greaterThan(0),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
