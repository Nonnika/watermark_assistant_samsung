import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:watermark_samsung/models/frame_watermark_config.dart';
import 'package:watermark_samsung/services/canvas/frame_canvas_renderer.dart';
import 'package:watermark_samsung/services/canvas/tiled_jpeg_encoder.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.example.watermark_samsung/ultra_hdr');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() {
    TiledJpegEncoder.debugOverrideIsAndroid = null;
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('planTiles covers the canvas exactly within Adreno-safe limits', () {
    for (final (w, h) in [
      (8160, 6120),
      (6120, 8160),
      (17000, 300),
      (1, 1),
      (4097, 3),
    ]) {
      final tiles = TiledJpegEncoder.planTiles(w, h);
      var area = 0;
      for (final t in tiles) {
        expect(t.width, lessThanOrEqualTo(TiledJpegEncoder.maxTileWidth));
        expect(t.x + t.width, lessThanOrEqualTo(w));
        expect(t.y + t.height, lessThanOrEqualTo(h));
        expect(
          t.width * t.height * 4,
          lessThanOrEqualTo(TiledJpegEncoder.maxTileBytes),
        );
        area += t.width * t.height;
      }
      expect(area, w * h, reason: '${w}x$h');
    }
    final tiles50mp = TiledJpegEncoder.planTiles(8160, 6120);
    expect(tiles50mp.first, const RenderTile(0, 0, 4080, 1028));
  });

  test(
    'Tiled rendering of blurred background and shadow has no seams',
    () async {
      final diff = await _compareTiledWithFull(
        const FrameWatermarkConfig(
          paddingRatio: 0.05,
          bottomBarRatio: 0.2,
          shadowOpacity: 0.5,
          isBlurredBg: true,
        ),
      );
      expect(diff.maxDiff, lessThanOrEqualTo(2));
    },
  );

  test(
    'Tiled rounded-corner clip only differs within the anti-aliased edge',
    () async {
      // 圆角裁剪部分越出块边界时，光栅器对弧线边缘的 AA 覆盖率估算略有不同（仅 1px 宽边缘）
      final diff = await _compareTiledWithFull(
        const FrameWatermarkConfig(
          paddingRatio: 0.05,
          bottomBarRatio: 0.2,
          cornerRadius: 0.05,
          shadowOpacity: 0.5,
          isBlurredBg: true,
        ),
      );
      expect(diff.differingPixels, lessThan(diff.totalPixels ~/ 500));
    },
  );

  test(
    'Android streams tiles to native session and returns native JPEG',
    () async {
      TiledJpegEncoder.debugOverrideIsAndroid = true;
      final calls = <MethodCall>[];
      final nativeJpeg = Uint8List.fromList([0xff, 0xd8, 1, 2, 3, 0xff, 0xd9]);
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        switch (call.method) {
          case 'tiledJpegBegin':
            return 7;
          case 'tiledJpegFinish':
            return nativeJpeg;
        }
        return null;
      });
      final picture = _solidPicture(64, 48);
      addTearDown(picture.dispose);

      final out = await TiledJpegEncoder.encode(
        picture,
        width: 64,
        height: 48,
        quality: 90,
      );
      expect(out, nativeJpeg);
      expect(calls.first.method, 'tiledJpegBegin');
      expect(calls.first.arguments, {'width': 64, 'height': 48});
      final writes = calls.where((c) => c.method == 'tiledJpegWrite').toList();
      expect(writes, isNotEmpty);
      for (final w in writes) {
        final args = w.arguments as Map;
        expect(args['session'], 7);
        expect(
          (args['rgba'] as Uint8List).length,
          (args['width'] as int) * (args['height'] as int) * 4,
        );
      }
      expect(calls.last.method, 'tiledJpegFinish');
      expect(calls.last.arguments, {'session': 7, 'quality': 90});
      expect(calls.any((c) => c.method == 'tiledJpegAbort'), isFalse);
    },
  );

  test(
    'Native failure aborts the session and falls back to Dart JPEG',
    () async {
      TiledJpegEncoder.debugOverrideIsAndroid = true;
      final methods = <String>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        methods.add(call.method);
        if (call.method == 'tiledJpegBegin') return 3;
        if (call.method == 'tiledJpegWrite') {
          throw PlatformException(code: 'WRITE_FAILED');
        }
        return null;
      });
      final picture = _solidPicture(32, 16);
      addTearDown(picture.dispose);

      final out = await TiledJpegEncoder.encode(
        picture,
        width: 32,
        height: 16,
        quality: 90,
      );
      expect(methods, contains('tiledJpegAbort'));
      expect(methods, isNot(contains('tiledJpegFinish')));
      final decoded = img.decodeJpg(out)!;
      expect(decoded.width, 32);
      expect(decoded.height, 16);
      final p = decoded.getPixel(16, 8);
      expect(p.r.toInt(), closeTo(30, 6));
      expect(p.g.toInt(), closeTo(120, 6));
      expect(p.b.toInt(), closeTo(220, 6));
    },
  );
}

ui.Picture _solidPicture(int w, int h) {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(
    Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
    Paint()..color = const Color(0xFF1E78DC),
  );
  return recorder.endRecording();
}

/// 将同一画面整幅渲染与强制多列多行分块渲染后逐像素比较
Future<({int maxDiff, int differingPixels, int totalPixels})>
_compareTiledWithFull(FrameWatermarkConfig config) async {
  final base = await _gradientImage(240, 160);
  const width = 264;
  const height = 204;
  final recorder = ui.PictureRecorder();
  FrameCanvasRenderer.draw(
    canvas: Canvas(recorder),
    baseImage: base,
    logoImage: null,
    config: config,
    totalWidth: width.toDouble(),
    totalHeight: height.toDouble(),
  );
  final picture = recorder.endRecording();
  try {
    final full = await picture.toImage(width, height);
    final fullRgba = (await full.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    ))!.buffer.asUint8List();
    full.dispose();

    final tiles = TiledJpegEncoder.planTiles(
      width,
      height,
      maxWidth: 100,
      maxBytes: 100 * 37 * 4,
    );
    expect(tiles.length, greaterThan(6));
    final assembled = Uint8List(width * height * 4);
    for (final tile in tiles) {
      final rgba = await TiledJpegEncoder.renderTile(picture, tile);
      for (var row = 0; row < tile.height; row++) {
        final dst = ((tile.y + row) * width + tile.x) * 4;
        assembled.setRange(
          dst,
          dst + tile.width * 4,
          rgba,
          row * tile.width * 4,
        );
      }
    }

    var maxDiff = 0;
    var differing = 0;
    for (var p = 0; p < width * height; p++) {
      var pixelDiff = 0;
      for (var c = 0; c < 4; c++) {
        final d = (fullRgba[p * 4 + c] - assembled[p * 4 + c]).abs();
        if (d > pixelDiff) pixelDiff = d;
      }
      if (pixelDiff > maxDiff) maxDiff = pixelDiff;
      if (pixelDiff > 2) differing++;
    }
    return (
      maxDiff: maxDiff,
      differingPixels: differing,
      totalPixels: width * height,
    );
  } finally {
    picture.dispose();
    base.dispose();
  }
}

Future<ui.Image> _gradientImage(int w, int h) async {
  final recorder = ui.PictureRecorder();
  final rect = Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble());
  Canvas(recorder).drawRect(
    rect,
    Paint()
      ..shader = const LinearGradient(
        colors: [Colors.red, Colors.yellow, Colors.blue],
      ).createShader(rect),
  );
  final picture = recorder.endRecording();
  try {
    return await picture.toImage(w, h);
  } finally {
    picture.dispose();
  }
}
