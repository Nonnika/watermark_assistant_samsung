import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;

/// 导出画面中的一个矩形渲染块
@immutable
class RenderTile {
  final int x;
  final int y;
  final int width;
  final int height;

  const RenderTile(this.x, this.y, this.width, this.height);

  @override
  bool operator ==(Object other) =>
      other is RenderTile &&
      other.x == x &&
      other.y == y &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(x, y, width, height);

  @override
  String toString() => 'RenderTile($x, $y, ${width}x$height)';
}

/// 分块渲染 + 流式 JPEG 编码。
///
/// 全分辨率导出不再一次性 `toImage` 出整幅离屏纹理再整幅 `toByteData` 回读：
/// Adreno 与系统共享内存，50MP 画面的离屏目标与回读缓冲各约 200MB，且 Vulkan
/// 单边上限为 16384。改为按小块渲染/回读，并逐块推送到原生 Bitmap，
/// GPU 渲染下一块与原生拷贝上一块并行，整幅 RGBA 不再出现在 Dart 堆和 Java 堆上。
class TiledJpegEncoder {
  TiledJpegEncoder._();

  static const MethodChannel _nativeChannel = MethodChannel(
    'com.example.watermark_samsung/ultra_hdr',
  );

  /// 单块最大边长，远低于 Adreno 的 16384 纹理上限
  static const int maxTileWidth = 4096;

  /// 单块 RGBA 目标字节数，控制每次回读与跨通道消息的体积
  static const int maxTileBytes = 16 * 1024 * 1024;

  @visibleForTesting
  static bool? debugOverrideIsAndroid;

  /// 将画面划分为等宽列 × 行的渲染块，按行优先顺序返回
  static List<RenderTile> planTiles(
    int width,
    int height, {
    int maxWidth = maxTileWidth,
    int maxBytes = maxTileBytes,
  }) {
    if (width <= 0 || height <= 0) {
      throw ArgumentError('Invalid size ${width}x$height');
    }
    final columns = (width + maxWidth - 1) ~/ maxWidth;
    final tileW = (width + columns - 1) ~/ columns;
    final tileH = (maxBytes ~/ (tileW * 4)).clamp(1, height);
    return [
      for (var y = 0; y < height; y += tileH)
        for (var x = 0; x < width; x += tileW)
          RenderTile(
            x,
            y,
            x + tileW > width ? width - x : tileW,
            y + tileH > height ? height - y : tileH,
          ),
    ];
  }

  /// 将 [picture] 以 width×height 分块渲染并编码为 JPEG。
  /// Android 上流式交给原生编码，失败时回退为 Dart 拼接 + 纯 Dart 编码。
  static Future<Uint8List> encode(
    ui.Picture picture, {
    required int width,
    required int height,
    required int quality,
  }) async {
    final tiles = planTiles(width, height);
    if (debugOverrideIsAndroid ?? Platform.isAndroid) {
      try {
        return await _encodeNative(picture, tiles, width, height, quality);
      } catch (e) {
        debugPrint('[TiledJpegEncoder] Native tiled encode fallback: $e');
      }
    }
    final rgba = Uint8List(width * height * 4);
    for (final tile in tiles) {
      final tileRgba = await renderTile(picture, tile);
      _blit(tileRgba, tile, rgba, width);
    }
    final image = img.Image.fromBytes(
      width: width,
      height: height,
      bytes: rgba.buffer,
      order: img.ChannelOrder.rgba,
    );
    return img.encodeJpg(image, quality: quality);
  }

  static Future<Uint8List> _encodeNative(
    ui.Picture picture,
    List<RenderTile> tiles,
    int width,
    int height,
    int quality,
  ) async {
    final session = await _nativeChannel.invokeMethod<int>('tiledJpegBegin', {
      'width': width,
      'height': height,
    });
    if (session == null) throw StateError('tiledJpegBegin returned null');

    Future<void>? pendingWrite;
    try {
      for (final tile in tiles) {
        final tileRgba = await renderTile(picture, tile);
        // 最多一块在途：GPU 渲染/回读本块时原生仍在拼接上一块，内存上限约两块
        await pendingWrite;
        pendingWrite = _nativeChannel.invokeMethod<void>('tiledJpegWrite', {
          'session': session,
          'x': tile.x,
          'y': tile.y,
          'width': tile.width,
          'height': tile.height,
          'rgba': tileRgba,
        });
      }
      await pendingWrite;
      pendingWrite = null;
      final jpeg = await _nativeChannel.invokeMethod<Uint8List>(
        'tiledJpegFinish',
        {'session': session, 'quality': quality},
      );
      if (jpeg == null || jpeg.isEmpty) {
        throw StateError('tiledJpegFinish returned empty');
      }
      return jpeg;
    } catch (_) {
      // 吞掉在途写入的错误，避免未处理的异步异常；随后释放原生 Bitmap
      await pendingWrite?.catchError((_) {});
      try {
        await _nativeChannel.invokeMethod<void>('tiledJpegAbort', {
          'session': session,
        });
      } catch (_) {}
      rethrow;
    }
  }

  /// 在 GPU 上只渲染 [tile] 覆盖的区域并回读为预乘 RGBA
  @visibleForTesting
  static Future<Uint8List> renderTile(ui.Picture picture, RenderTile tile) async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.translate(-tile.x.toDouble(), -tile.y.toDouble());
    canvas.drawPicture(picture);
    final tilePicture = recorder.endRecording();
    final ui.Image image;
    try {
      image = await tilePicture.toImage(tile.width, tile.height);
    } finally {
      tilePicture.dispose();
    }
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null) throw StateError('rawRgba readback failed for $tile');
      return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    } finally {
      image.dispose();
    }
  }

  static void _blit(
    Uint8List tileRgba,
    RenderTile tile,
    Uint8List dst,
    int dstWidth,
  ) {
    final rowBytes = tile.width * 4;
    for (var row = 0; row < tile.height; row++) {
      final dstOffset = ((tile.y + row) * dstWidth + tile.x) * 4;
      dst.setRange(dstOffset, dstOffset + rowBytes, tileRgba, row * rowBytes);
    }
  }
}
