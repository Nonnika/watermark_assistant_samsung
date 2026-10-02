// ignore_for_file: avoid_print
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watermark_samsung/widgets/one_ui_icon_artwork.dart';
import 'package:watermark_samsung/widgets/pebble_icon.dart';

Future<void> _renderPng(
  String path,
  int pixels,
  void Function(Canvas, Size) paint,
) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final size = Size.square(pixels.toDouble());
  paint(canvas, size);
  final picture = recorder.endRecording();
  final image = await picture.toImage(pixels, pixels);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  final file = File(path);
  file.parent.createSync(recursive: true);
  file.writeAsBytesSync(data!.buffer.asUint8List());
  image.dispose();
  picture.dispose();
  print('Generated $path ($pixels × $pixels)');
}

void main() {
  test('Generate One UI launcher icons from shared vector artwork', () async {
    const painter = PebbleShadowAndCardPainter(hasShadow: false, n: 2.85);
    const densities = {
      'mdpi': 48,
      'hdpi': 72,
      'xhdpi': 96,
      'xxhdpi': 144,
      'xxxhdpi': 192,
    };
    const res = 'android/app/src/main/res';
    for (final entry in densities.entries) {
      await _renderPng(
        '$res/mipmap-${entry.key}/ic_launcher_oneui.png',
        entry.value,
        painter.paint,
      );
    }
    await _renderPng('assets/app_icon_oneui.png', 1024, painter.paint);

    // Adaptive layers use 108dp; their central 72dp maps to the legacy artwork.
    // The photo and signature stay within the centered 66dp circular safe zone.
    await _renderPng(
      '$res/drawable-xxxhdpi/ic_launcher_oneui_foreground.png',
      432,
      (canvas, size) {
        final inset = size.width / 6;
        canvas.translate(inset, inset);
        OneUiIconArtwork.paintForeground(canvas, size * (2 / 3));
      },
    );
    await _renderPng(
      '$res/drawable-xxxhdpi/ic_launcher_oneui_background.png',
      432,
      (canvas, size) => OneUiIconArtwork.paintBackground(
        canvas,
        Offset.zero & size,
        gradientBounds: Rect.fromLTWH(
          size.width / 6,
          size.height / 6,
          size.width * 2 / 3,
          size.height * 2 / 3,
        ),
      ),
    );
  });
}
