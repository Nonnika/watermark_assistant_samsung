import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class BrandLogoItem {
  final String id;
  final String name;
  final Color primaryColor;
  final String assetPath;

  const BrandLogoItem({
    required this.id,
    required this.name,
    required this.primaryColor,
    required this.assetPath,
  });
}

class CustomLogoItem {
  final String id;
  final String name;
  final Uint8List bytes;
  final ui.Image? decodedImage;

  const CustomLogoItem({
    required this.id,
    required this.name,
    required this.bytes,
    this.decodedImage,
  });
}

class BrandLogoService {
  // 原版官方 Logo 预设（精简名称，移除前缀字样）
  static const List<BrandLogoItem> brands = [
    BrandLogoItem(
      id: 'samsung_blue',
      name: '蓝标',
      primaryColor: Color(0xFF0381FE),
      assetPath: 'res/Samsung_Orig_Wordmark_BLUE_RGB.png',
    ),
    BrandLogoItem(
      id: 'samsung_black',
      name: '黑标',
      primaryColor: Color(0xFF18181A),
      assetPath: 'res/Samsung_Orig_Wordmark_BLACK_RGB_副本.png',
    ),
    BrandLogoItem(
      id: 'samsung_white',
      name: '白标',
      primaryColor: Color(0xFFFFFFFF),
      assetPath: 'res/Samsung_Orig_Wordmark_WHITE_RGB.png',
    ),
  ];

  /// 用户自主添加的自定义 Logo 列表
  static final List<CustomLogoItem> userCustomLogos = [];

  static void addUserLogo(CustomLogoItem item) {
    userCustomLogos.removeWhere((c) => c.id == item.id);
    userCustomLogos.add(item);
  }

  static void removeUserLogo(String id) {
    userCustomLogos.removeWhere((c) => c.id == id);
  }

  static CustomLogoItem? getUserLogo(String id) {
    try {
      return userCustomLogos.firstWhere((c) => c.id == id);
    } catch (_) {
      return null;
    }
  }

  static Future<Uint8List> getLogoBytes(String brandId, {Uint8List? customBytes}) async {
    // 1. 如果是用户自定义 Logo，从内存或传入的 customBytes 中提取
    if (brandId.startsWith('custom_') || brandId == 'custom') {
      if (customBytes != null) {
        return customBytes;
      }
      final customLogo = getUserLogo(brandId);
      if (customLogo != null) {
        return customLogo.bytes;
      }
    }

    // 2. 否则按官方内置品牌加载
    final item = brands.firstWhere(
      (b) => b.id == brandId,
      orElse: () => brands.first,
    );

    try {
      final byteData = await rootBundle.load(item.assetPath);
      return byteData.buffer.asUint8List();
    } catch (_) {
      return _generateFallbackSamsungLogo();
    }
  }

  static Future<Uint8List> _generateFallbackSamsungLogo() async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, 240, 60));
    final textPainter = TextPainter(
      text: const TextSpan(
        text: 'SAMSUNG',
        style: TextStyle(
          color: Color(0xFF0381FE),
          fontSize: 32,
          fontWeight: FontWeight.w900,
          letterSpacing: 2,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    textPainter.paint(canvas, const Offset(10, 10));
    final picture = recorder.endRecording();
    final img = await picture.toImage(240, 60);
    final pngBytes = await img.toByteData(format: ui.ImageByteFormat.png);
    return pngBytes!.buffer.asUint8List();
  }
}
