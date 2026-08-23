// ignore_for_file: avoid_print
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watermark_samsung/widgets/pebble_icon.dart';

void main() {
  test('Generate high resolution launcher icons from AppPebbleIcon vector painter', () async {
    final sizes = {
      'mipmap-mdpi': 48,
      'mipmap-hdpi': 72,
      'mipmap-xhdpi': 96,
      'mipmap-xxhdpi': 144,
      'mipmap-xxxhdpi': 192,
    };

    final resDir = Directory('android/app/src/main/res');

    for (final entry in sizes.entries) {
      final size = entry.value.toDouble();
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, size, size));

      final painter = PebbleShadowAndCardPainter(hasShadow: false, n: 2.85);
      painter.paint(canvas, Size(size, size));

      final picture = recorder.endRecording();
      final image = await picture.toImage(size.toInt(), size.toInt());
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final pngBytes = byteData!.buffer.asUint8List();

      final folder = Directory('${resDir.path}/${entry.key}');
      if (!folder.existsSync()) {
        folder.createSync(recursive: true);
      }
      File('${folder.path}/ic_launcher.png').writeAsBytesSync(pngBytes);
      File('${folder.path}/ic_launcher_round.png').writeAsBytesSync(pngBytes);
      print('Generated ${entry.key}/ic_launcher.png and ic_launcher_round.png ($size x $size)');
    }

    // Generate 512x512 Master Asset Icon
    const masterSize = 512.0;
    final recorder512 = ui.PictureRecorder();
    final canvas512 = Canvas(recorder512, const Rect.fromLTWH(0, 0, masterSize, masterSize));
    final painter512 = PebbleShadowAndCardPainter(hasShadow: false, n: 2.85);
    painter512.paint(canvas512, const Size(masterSize, masterSize));

    final picture512 = recorder512.endRecording();
    final image512 = await picture512.toImage(masterSize.toInt(), masterSize.toInt());
    final byteData512 = await image512.toByteData(format: ui.ImageByteFormat.png);
    final pngBytes512 = byteData512!.buffer.asUint8List();

    final assetsDir = Directory('assets');
    if (!assetsDir.existsSync()) {
      assetsDir.createSync(recursive: true);
    }
    File('assets/app_icon.png').writeAsBytesSync(pngBytes512);
    print('Generated assets/app_icon.png (512x512)');
  });
}
