import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../models/frame_watermark_config.dart';
import '../models/image_item.dart';
import '../models/watermark_config.dart';
import '../services/watermark_processor.dart';

class InteractivePreview extends StatelessWidget {
  final WatermarkType watermarkType;
  final ImageItem imageItem;
  final ui.Image? watermarkImage;
  final WatermarkConfig config;
  final ui.Image? logoImage;
  final FrameWatermarkConfig frameConfig;
  final Function(double relX, double relY) onWatermarkDragged;

  const InteractivePreview({
    super.key,
    required this.watermarkType,
    required this.imageItem,
    required this.watermarkImage,
    required this.config,
    required this.logoImage,
    required this.frameConfig,
    required this.onWatermarkDragged,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
      height: 330,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF141416) : const Color(0xFFE4E5EB),
        borderRadius: BorderRadius.zero,
      ),
      clipBehavior: Clip.hardEdge,
      child: Stack(
        alignment: Alignment.center,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final containerW = constraints.maxWidth;
              final containerH = constraints.maxHeight;

              double contentW = imageItem.width.toDouble();
              double contentH = imageItem.height.toDouble();

              if (watermarkType == WatermarkType.frame) {
                final pad = contentW * frameConfig.paddingRatio;
                final bottomBarH = contentH * frameConfig.bottomBarRatio;
                contentW = contentW + pad * 2;
                contentH = contentH + pad + bottomBarH;
              }

              final contentAspect = contentW / contentH;
              final containerAspect = containerW / containerH;

              double renderW;
              double renderH;
              double leftOffset;
              double topOffset;

              if (contentAspect > containerAspect) {
                renderW = containerW;
                renderH = containerW / contentAspect;
                leftOffset = 0;
                topOffset = (containerH - renderH) / 2;
              } else {
                renderH = containerH;
                renderW = containerH * contentAspect;
                leftOffset = (containerW - renderW) / 2;
                topOffset = 0;
              }

              final renderRect = Rect.fromLTWH(leftOffset, topOffset, renderW, renderH);

              return GestureDetector(
                onPanDown: (details) {
                  if (watermarkType == WatermarkType.floatingPng && config.mode == WatermarkMode.single) {
                    _handleDrag(details.localPosition, renderRect);
                  }
                },
                onPanUpdate: (details) {
                  if (watermarkType == WatermarkType.floatingPng && config.mode == WatermarkMode.single) {
                    _handleDrag(details.localPosition, renderRect);
                  }
                },
                child: SizedBox(
                  width: containerW,
                  height: containerH,
                  child: CustomPaint(
                    painter: _UnifiedWatermarkPreviewPainter(
                      watermarkType: watermarkType,
                      baseImage: imageItem.decodedImage,
                      watermarkImage: watermarkImage,
                      config: config,
                      logoImage: logoImage,
                      frameConfig: frameConfig,
                      renderRect: renderRect,
                    ),
                  ),
                ),
              );
            },
          ),

          // 顶部信息徽标
          Positioned(
            top: 12,
            left: 14,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.65),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    watermarkType == WatermarkType.frame
                        ? Icons.filter_frames_rounded
                        : Icons.photo_size_select_actual_outlined,
                    size: 14,
                    color: Colors.white70,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    watermarkType == WatermarkType.frame
                        ? '${imageItem.resolutionString} · 边框模式'
                        : '${imageItem.resolutionString} · PNG 浮动',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white),
                  ),
                ],
              ),
            ),
          ),

          // 浮动模式拖拽提示
          if (watermarkType == WatermarkType.floatingPng && config.mode == WatermarkMode.single)
            Positioned(
              bottom: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.touch_app_outlined, size: 13, color: Colors.white70),
                    SizedBox(width: 4),
                    Text(
                      '在画面中触摸拖拽可自由微调位置 (X/Y)',
                      style: TextStyle(fontSize: 11, color: Colors.white70),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _handleDrag(Offset localPos, Rect imageRect) {
    if (!imageRect.contains(localPos)) return;
    final double relX = ((localPos.dx - imageRect.left) / imageRect.width).clamp(0.0, 1.0);
    final double relY = ((localPos.dy - imageRect.top) / imageRect.height).clamp(0.0, 1.0);
    onWatermarkDragged(relX, relY);
  }
}

class _UnifiedWatermarkPreviewPainter extends CustomPainter {
  final WatermarkType watermarkType;
  final ui.Image? baseImage;
  final ui.Image? watermarkImage;
  final WatermarkConfig config;
  final ui.Image? logoImage;
  final FrameWatermarkConfig frameConfig;
  final Rect renderRect;

  _UnifiedWatermarkPreviewPainter({
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
        );
      } else {
        final src = Rect.fromLTWH(0, 0, baseImage!.width.toDouble(), baseImage!.height.toDouble());
        final dst = Rect.fromLTWH(0, 0, renderRect.width, renderRect.height);
        canvas.drawImageRect(baseImage!, src, dst, Paint()..filterQuality = FilterQuality.high);
      }
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _UnifiedWatermarkPreviewPainter oldDelegate) {
    return oldDelegate.watermarkType != watermarkType ||
        oldDelegate.baseImage != baseImage ||
        oldDelegate.watermarkImage != watermarkImage ||
        oldDelegate.config != config ||
        oldDelegate.logoImage != logoImage ||
        oldDelegate.frameConfig != frameConfig ||
        oldDelegate.renderRect != renderRect;
  }
}
