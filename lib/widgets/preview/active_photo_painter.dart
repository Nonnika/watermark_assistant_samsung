import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../../models/frame_watermark_config.dart';
import '../../models/watermark_config.dart';
import '../../services/watermark_processor.dart';

/// 负责实时在预览区域绘制相框/水印的画笔
class ActivePhotoPainter extends CustomPainter {
  final WatermarkType watermarkType;
  final ui.Image? baseImage;
  final ui.Image? watermarkImage;
  final WatermarkConfig config;
  final ui.Image? logoImage;
  final FrameWatermarkConfig frameConfig;
  final Rect renderRect;

  ActivePhotoPainter({
    required this.watermarkType,
    required this.baseImage,
    required this.watermarkImage,
    required this.config,
    required this.logoImage,
    required this.frameConfig,
    required this.renderRect,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (baseImage == null) return;

    canvas.save();
    canvas.clipRect(renderRect);
    canvas.translate(renderRect.left, renderRect.top);

    if (watermarkType == WatermarkType.frame) {
      WatermarkProcessor.drawFrameExifCanvas(
        canvas: canvas,
        baseImage: baseImage!,
        logoImage: logoImage,
        config: frameConfig,
        totalWidth: renderRect.width,
        totalHeight: renderRect.height,
        filterQuality: FilterQuality.medium,
      );
    } else {
      if (watermarkImage != null) {
        WatermarkProcessor.drawFloatingPngCanvas(
          canvas: canvas,
          baseImage: baseImage!,
          watermarkImage: watermarkImage!,
          config: config,
          canvasWidth: renderRect.width,
          canvasHeight: renderRect.height,
          filterQuality: FilterQuality.medium,
        );
      } else {
        final src = Rect.fromLTWH(0, 0, baseImage!.width.toDouble(), baseImage!.height.toDouble());
        final dst = Rect.fromLTWH(0, 0, renderRect.width, renderRect.height);
        canvas.drawImageRect(baseImage!, src, dst, Paint()..filterQuality = FilterQuality.medium);
      }
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant ActivePhotoPainter oldDelegate) {
    return oldDelegate.watermarkType != watermarkType ||
        oldDelegate.baseImage != baseImage ||
        oldDelegate.watermarkImage != watermarkImage ||
        oldDelegate.config != config ||
        oldDelegate.logoImage != logoImage ||
        oldDelegate.frameConfig != frameConfig ||
        oldDelegate.renderRect != renderRect;
  }
}
