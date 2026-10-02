import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../../models/watermark_config.dart';

/// 负责在 Canvas 上绘制浮动/平铺 PNG 水印的渲染器
class FloatingPngRenderer {
  // RGB 反色滤镜矩阵 (保持 Alpha 透明度不变)
  static const ColorFilter invertColorFilter = ColorFilter.matrix(<double>[
    -1,  0,  0, 0, 255,
     0, -1,  0, 0, 255,
     0,  0, -1, 0, 255,
     0,  0,  0, 1,   0,
  ]);

  /// 绘制浮动 PNG 水印到 Canvas (包含底图绘制)
  static void draw({
    required Canvas canvas,
    required ui.Image baseImage,
    required ui.Image watermarkImage,
    required WatermarkConfig config,
    required double canvasWidth,
    required double canvasHeight,
    FilterQuality filterQuality = FilterQuality.high,
  }) {
    // 1. 绘制底图
    final srcRect = Rect.fromLTWH(0, 0, baseImage.width.toDouble(), baseImage.height.toDouble());
    final dstRect = Rect.fromLTWH(0, 0, canvasWidth, canvasHeight);
    canvas.drawImageRect(baseImage, srcRect, dstRect, Paint()..filterQuality = filterQuality);

    // 2. 绘制水印图层
    drawOverlayOnly(
      canvas: canvas,
      watermarkImage: watermarkImage,
      config: config,
      canvasWidth: canvasWidth,
      canvasHeight: canvasHeight,
      filterQuality: filterQuality,
    );
  }

  /// 仅绘制浮动 PNG 水印图层本身 (透明背景, 用于动态视频合成)
  static void drawOverlayOnly({
    required Canvas canvas,
    required ui.Image watermarkImage,
    required WatermarkConfig config,
    required double canvasWidth,
    required double canvasHeight,
    FilterQuality filterQuality = FilterQuality.high,
  }) {
    // 准备水印画笔 (含反色与透明度)
    final wmPaint = Paint()
      ..color = Colors.white.withValues(alpha: config.opacity)
      ..filterQuality = filterQuality;

    if (config.isInverted) {
      wmPaint.colorFilter = invertColorFilter;
    }

    final double wmOriginalW = watermarkImage.width.toDouble();
    final double wmOriginalH = watermarkImage.height.toDouble();
    final double targetW = canvasWidth * config.scale;
    final double targetH = targetW * (wmOriginalH / wmOriginalW);

    if (config.mode == WatermarkMode.single) {
      double targetX;
      double targetY;

      if (config.isCustomDrag || config.position == WatermarkPosition.custom) {
        targetX = canvasWidth * config.customX - (targetW / 2);
        targetY = canvasHeight * config.customY - (targetH / 2);
      } else {
        final marginH = canvasWidth * config.margin;
        final marginV = canvasHeight * config.margin;

        switch (config.position) {
          case WatermarkPosition.topLeft:
            targetX = marginH;
            targetY = marginV;
            break;
          case WatermarkPosition.topCenter:
            targetX = (canvasWidth - targetW) / 2;
            targetY = marginV;
            break;
          case WatermarkPosition.topRight:
            targetX = canvasWidth - targetW - marginH;
            targetY = marginV;
            break;
          case WatermarkPosition.centerLeft:
            targetX = marginH;
            targetY = (canvasHeight - targetH) / 2;
            break;
          case WatermarkPosition.center:
            targetX = (canvasWidth - targetW) / 2;
            targetY = (canvasHeight - targetH) / 2;
            break;
          case WatermarkPosition.centerRight:
            targetX = canvasWidth - targetW - marginH;
            targetY = (canvasHeight - targetH) / 2;
            break;
          case WatermarkPosition.bottomLeft:
            targetX = marginH;
            targetY = canvasHeight - targetH - marginV;
            break;
          case WatermarkPosition.bottomCenter:
            targetX = (canvasWidth - targetW) / 2;
            targetY = canvasHeight - targetH - marginV;
            break;
          case WatermarkPosition.bottomRight:
          case WatermarkPosition.custom:
            targetX = canvasWidth - targetW - marginH;
            targetY = canvasHeight - targetH - marginV;
            break;
        }
      }

      canvas.save();
      final centerX = targetX + targetW / 2;
      final centerY = targetY + targetH / 2;
      canvas.translate(centerX, centerY);
      if (config.rotation != 0) {
        canvas.rotate(config.rotation * (math.pi / 180.0));
      }
      final wmSrcRect = Rect.fromLTWH(0, 0, wmOriginalW, wmOriginalH);
      final wmDstRect = Rect.fromLTWH(-targetW / 2, -targetH / 2, targetW, targetH);
      canvas.drawImageRect(watermarkImage, wmSrcRect, wmDstRect, wmPaint);
      canvas.restore();
    } else {
      // 平铺模式
      final double spacingX = targetW * (config.tileSpacingX / 100.0);
      final double spacingY = targetH * (config.tileSpacingY / 100.0);
      final double stepX = targetW + spacingX;
      final double stepY = targetH + spacingY;

      int row = 0;
      for (double y = -targetH; y < canvasHeight + targetH; y += stepY) {
        final double offsetX = (config.tileStaggered && (row % 2 == 1)) ? (stepX / 2) : 0.0;
        for (double x = -targetW - offsetX; x < canvasWidth + targetW; x += stepX) {
          canvas.save();
          final cx = x + targetW / 2;
          final cy = y + targetH / 2;
          canvas.translate(cx, cy);
          if (config.rotation != 0) {
            canvas.rotate(config.rotation * (math.pi / 180.0));
          }
          final wmSrcRect = Rect.fromLTWH(0, 0, wmOriginalW, wmOriginalH);
          final wmDstRect = Rect.fromLTWH(-targetW / 2, -targetH / 2, targetW, targetH);
          canvas.drawImageRect(watermarkImage, wmSrcRect, wmDstRect, wmPaint);
          canvas.restore();
        }
        row++;
      }
    }
  }
}
