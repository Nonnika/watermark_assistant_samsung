import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

class PhotoColorExtractor {
  static final Map<int, List<Color>> _cache = {};
  static const int _maxCacheEntries = 32;

  PhotoColorExtractor._();

  /// 基于内容采样的哈希键：同尺寸连拍照片头部字节几乎相同，
  /// 仅用长度+两个字节做键会发生碰撞并返回错误的调色板。
  static int _contentHash(Uint8List bytes) {
    var h = bytes.length;
    final step = bytes.length > 4096 ? bytes.length ~/ 4096 : 1;
    for (int i = 0; i < bytes.length; i += step) {
      h = (h * 31 + bytes[i]) & 0x3FFFFFFF;
    }
    return h;
  }

  static void _store(int key, List<Color> palette) {
    if (_cache.length >= _maxCacheEntries) {
      _cache.remove(_cache.keys.first);
    }
    _cache[key] = palette;
  }

  static const int _sampleWidth = 128;

  /// 异步提取调色板：优先用引擎原生解码器直接按 128 像素宽降采样解码
  /// （JPEG 走 DCT 缩放，免去 50MP 全尺寸纯 Dart 解码的数秒耗时与数百 MB 内存），
  /// 引擎无法解码时回退到后台 isolate 纯 Dart 解码。
  static Future<List<Color>> extractPaletteFromBytesAsync(Uint8List? bytes) async {
    if (bytes == null || bytes.isEmpty) return [];
    final cacheKey = _contentHash(bytes);
    final cached = _cache[cacheKey];
    if (cached != null) return cached;

    try {
      List<Color> palette;
      try {
        palette = await _extractWithEngineDecoder(bytes);
      } catch (_) {
        final rgbList = await Isolate.run(() => _decodeAndExtractRgb(bytes));
        palette = <Color>[
          for (final rgb in rgbList) Color.fromARGB(255, rgb[0], rgb[1], rgb[2]),
        ];
      }
      _store(cacheKey, palette);
      return palette;
    } catch (_) {
      return [];
    }
  }

  static Future<List<Color>> _extractWithEngineDecoder(Uint8List bytes) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    ui.ImageDescriptor? descriptor;
    ui.Codec? codec;
    ui.Image? image;
    try {
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      codec = await descriptor.instantiateCodec(
        targetWidth: descriptor.width > _sampleWidth ? _sampleWidth : null,
      );
      image = (await codec.getNextFrame()).image;
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null) throw StateError('rawRgba readback failed');
      return extractPaletteFromRgba(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        image.width,
        image.height,
      );
    } finally {
      image?.dispose();
      codec?.dispose();
      descriptor?.dispose();
      buffer.dispose();
    }
  }

  /// 从图片字节流中提取 8 个主要/代表性色调（带缓存）。
  /// 注意：内部会同步解码整张图片，仅供非 UI 关键路径（如测试）使用。
  static List<Color> extractPaletteFromBytes(Uint8List? bytes) {
    if (bytes == null || bytes.isEmpty) return [];

    final cacheKey = _contentHash(bytes);
    final cached = _cache[cacheKey];
    if (cached != null) return cached;

    try {
      final rgbList = _decodeAndExtractRgb(bytes);
      final palette = <Color>[
        for (final rgb in rgbList) Color.fromARGB(255, rgb[0], rgb[1], rgb[2]),
      ];
      _store(cacheKey, palette);
      return palette;
    } catch (_) {
      return [];
    }
  }

  /// 在任意 isolate 中可执行的纯函数：解码、降采样并返回 RGB 列表
  static List<List<int>> _decodeAndExtractRgb(Uint8List bytes) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return [];
    var small = decoded;
    if (decoded.width > 128) {
      small = img.copyResize(decoded, width: 128);
    }
    final palette = extractPalette(small);
    return <List<int>>[
      for (final c in palette)
        [
          (c.r * 255.0).round().clamp(0, 255),
          (c.g * 255.0).round().clamp(0, 255),
          (c.b * 255.0).round().clamp(0, 255),
        ],
    ];
  }

  /// 从解码后的照片中提取 8 个主要/代表性色调
  static List<Color> extractPalette(img.Image? image) {
    if (image == null) return [];

    try {
      final List<Color> sampled = [];
      _forEachSample(image.width, image.height, (x, y) {
        final pixel = image.getPixel(x, y);
        if (pixel.a.toInt() > 128) {
          sampled.add(Color.fromARGB(
              255, pixel.r.toInt(), pixel.g.toInt(), pixel.b.toInt()));
        }
      });
      return _pickDistinct(sampled);
    } catch (_) {
      return [];
    }
  }

  /// 与 [extractPalette] 相同的采样与选色规则，输入为 RGBA8888 像素缓冲
  static List<Color> extractPaletteFromRgba(Uint8List rgba, int width, int height) {
    final List<Color> sampled = [];
    _forEachSample(width, height, (x, y) {
      final i = (y * width + x) * 4;
      if (rgba[i + 3] > 128) {
        sampled.add(Color.fromARGB(255, rgba[i], rgba[i + 1], rgba[i + 2]));
      }
    });
    return _pickDistinct(sampled);
  }

  /// 采样步长，快速抽取 ~300 个像素点
  static void _forEachSample(int width, int height, void Function(int x, int y) visit) {
    final stepX = (width / 20).clamp(1, 100).toInt();
    final stepY = (height / 20).clamp(1, 100).toInt();
    for (int y = 0; y < height; y += stepY) {
      for (int x = 0; x < width; x += stepX) {
        visit(x, y);
      }
    }
  }

  static List<Color> _pickDistinct(List<Color> sampled) {
    if (sampled.isEmpty) return [];

    // 挑选视觉差异明显的代表色
    final List<Color> distinctColors = [];
    for (final color in sampled) {
      bool isDuplicate = false;
      for (final existing in distinctColors) {
        // Color.r/g/b 为 0.0-1.0 归一化通道值，×255 换算回 0-255 通道差后比较
        final dr = (color.r - existing.r) * 255;
        final dg = (color.g - existing.g) * 255;
        final db = (color.b - existing.b) * 255;
        final dist = dr * dr + dg * dg + db * db;
        if (dist < 1600) {
          isDuplicate = true;
          break;
        }
      }
      if (!isDuplicate) {
        distinctColors.add(color);
        if (distinctColors.length >= 8) break;
      }
    }

    return distinctColors;
  }
}
