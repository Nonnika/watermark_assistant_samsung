import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

class PhotoColorExtractor {
  static final Map<int, List<Color>> _cache = {};

  /// 从图片字节流中提取 8 个主要/代表性色调（带缓存）
  static List<Color> extractPaletteFromBytes(Uint8List? bytes) {
    if (bytes == null || bytes.isEmpty) return [];

    final cacheKey = bytes.length ^ (bytes.isNotEmpty ? bytes[0] : 0) ^ (bytes.length > 50 ? bytes[50] : 0);
    if (_cache.containsKey(cacheKey)) {
      return _cache[cacheKey]!;
    }

    try {
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return [];
      final palette = extractPalette(decoded);
      _cache[cacheKey] = palette;
      return palette;
    } catch (_) {
      return [];
    }
  }

  /// 从解码后的照片中提取 8 个主要/代表性色调
  static List<Color> extractPalette(img.Image? image) {
    if (image == null) return [];

    try {
      final List<Color> sampled = [];
      // 采样步长，快速抽取 ~300 个像素点
      final stepX = (image.width / 20).clamp(1, 100).toInt();
      final stepY = (image.height / 20).clamp(1, 100).toInt();

      for (int y = 0; y < image.height; y += stepY) {
        for (int x = 0; x < image.width; x += stepX) {
          final pixel = image.getPixel(x, y);
          final r = pixel.r.toInt();
          final g = pixel.g.toInt();
          final b = pixel.b.toInt();
          final a = pixel.a.toInt();
          if (a > 128) {
            sampled.add(Color.fromARGB(255, r, g, b));
          }
        }
      }

      if (sampled.isEmpty) return [];

      // 挑选视觉差异明显的代表色
      final List<Color> distinctColors = [];
      for (final color in sampled) {
        bool isDuplicate = false;
        for (final existing in distinctColors) {
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
    } catch (_) {
      return [];
    }
  }
}
