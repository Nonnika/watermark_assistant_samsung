import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../../models/frame_watermark_config.dart';

/// 负责在 Canvas 上绘制 EXIF 摄影相框水印的渲染器
class FrameCanvasRenderer {
  /// 绘制边框型 EXIF 相框水印到 Canvas
  static void draw({
    required Canvas canvas,
    required ui.Image baseImage,
    required ui.Image? logoImage,
    required FrameWatermarkConfig config,
    required double totalWidth,
    required double totalHeight,
  }) {
    // 1. 绘制相框底色背景
    if (config.isBlurredBg) {
      final bgSrcRect = Rect.fromLTWH(0, 0, baseImage.width.toDouble(), baseImage.height.toDouble());
      final bgDstRect = Rect.fromLTWH(0, 0, totalWidth, totalHeight);

      // 高斯模糊渲染原图作为背景
      final blurPaint = Paint()
        ..filterQuality = FilterQuality.high
        ..imageFilter = ui.ImageFilter.blur(sigmaX: 45.0, sigmaY: 45.0, tileMode: TileMode.clamp);

      canvas.save();
      canvas.clipRect(bgDstRect);
      canvas.drawImageRect(baseImage, bgSrcRect, bgDstRect, blurPaint);

      // 压暗遮罩 (52% 黑色压暗半透明遮罩，使文字和照片主体极致清晰)
      final dimPaint = Paint()..color = Colors.black.withValues(alpha: 0.52);
      canvas.drawRect(bgDstRect, dimPaint);
      canvas.restore();
    } else if (config.isPaperTextureBg) {
      drawPaperTexture(canvas, Rect.fromLTWH(0, 0, totalWidth, totalHeight));
    } else {
      final bgPaint = Paint()..color = config.backgroundColor;
      canvas.drawRect(Rect.fromLTWH(0, 0, totalWidth, totalHeight), bgPaint);
    }

    final double pad = totalWidth * (config.paddingRatio / (1 + config.paddingRatio * 2));
    final double bottomBarH = totalHeight * (config.bottomBarRatio / (1 + config.paddingRatio + config.bottomBarRatio));
    final double photoW = totalWidth - pad * 2;
    final double photoH = totalHeight - pad - bottomBarH;

    final photoRect = Rect.fromLTWH(pad, pad, photoW, photoH);
    final baseSrcRect = Rect.fromLTWH(0, 0, baseImage.width.toDouble(), baseImage.height.toDouble());

    // 2. 绘制照片 (支持自定义外阴影与平滑圆角)
    final double effectiveRadius = config.effectiveCornerRadius;
    final double shadowAlpha = config.effectiveShadowOpacity;

    canvas.save();
    // 绘制照片立体外阴影 (当 shadowOpacity > 0 或使用模糊/纸张背景时生效)
    if (shadowAlpha > 0) {
      final double blurSigma = 16.0 * (0.5 + shadowAlpha * 0.8);
      final double dy = (photoW * 0.007 * (0.6 + shadowAlpha * 0.8)).clamp(2.0, 18.0);
      final shadowColor = config.isPaperTextureBg
          ? const Color(0xFF5D4530).withValues(alpha: (shadowAlpha * 0.30).clamp(0.0, 0.35))
          : Colors.black.withValues(alpha: shadowAlpha.clamp(0.0, 0.85));
      final shadowPaint = Paint()
        ..color = shadowColor
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, blurSigma);

      if (effectiveRadius > 0) {
        final rrect = RRect.fromRectAndRadius(
          photoRect.shift(Offset(0, dy)),
          Radius.circular(photoW * effectiveRadius),
        );
        canvas.drawRRect(rrect, shadowPaint);
      } else {
        canvas.drawRect(photoRect.shift(Offset(0, dy)), shadowPaint);
      }
    }

    // 裁切圆角并绘制照片主体
    if (effectiveRadius > 0) {
      final rrect = RRect.fromRectAndRadius(
        photoRect,
        Radius.circular(photoW * effectiveRadius),
      );
      canvas.clipRRect(rrect);
    }
    canvas.drawImageRect(baseImage, baseSrcRect, photoRect, Paint()..filterQuality = FilterQuality.high);
    canvas.restore();

    // 3. 绘制底部参数信息栏
    drawBottomBar(
      canvas: canvas,
      logoImage: logoImage,
      config: config,
      totalWidth: totalWidth,
      pad: pad,
      photoH: photoH,
      bottomBarH: bottomBarH,
    );
  }

  /// 绘制完整的边框水印图层 (全幅边框背景 + 底部 EXIF 参数栏 + 品牌 Logo，中间照片视窗镂空透明)
  static void drawOverlayOnly({
    required Canvas canvas,
    required ui.Image? logoImage,
    required FrameWatermarkConfig config,
    required double totalWidth,
    required double totalHeight,
  }) {
    final double pad = totalWidth * (config.paddingRatio / (1 + config.paddingRatio * 2));
    final double bottomBarH = totalHeight * (config.bottomBarRatio / (1 + config.paddingRatio + config.bottomBarRatio));
    final double photoW = totalWidth - pad * 2;
    final double photoH = totalHeight - pad - bottomBarH;
    final photoRect = Rect.fromLTWH(pad, pad, photoW, photoH);

    // 1. 绘制全幅边框背景 (纸张纹理 / 纯色 / 渐变)
    final fullRect = Rect.fromLTWH(0, 0, totalWidth, totalHeight);
    if (config.isPaperTextureBg) {
      drawPaperTexture(canvas, fullRect);
    } else {
      final bgPaint = Paint()..color = config.backgroundColor;
      canvas.drawRect(fullRect, bgPaint);
    }

    // 2. 将中间照片播放区域镂空为透明 (BlendMode.clear)，支持圆角
    final double effectiveRadius = config.cornerRadius.clamp(0.0, 0.5);
    final clearPaint = Paint()..blendMode = BlendMode.clear;
    if (effectiveRadius > 0) {
      final rrect = RRect.fromRectAndRadius(
        photoRect,
        Radius.circular(photoW * effectiveRadius),
      );
      canvas.drawRRect(rrect, clearPaint);
    } else {
      canvas.drawRect(photoRect, clearPaint);
    }

    // 3. 绘制底部 EXIF 信息栏与品牌 Logo
    drawBottomBar(
      canvas: canvas,
      logoImage: logoImage,
      config: config,
      totalWidth: totalWidth,
      pad: pad,
      photoH: photoH,
      bottomBarH: bottomBarH,
    );
  }

  /// 绘制底部 EXIF 信息栏与品牌 Logo
  static void drawBottomBar({
    required Canvas canvas,
    required ui.Image? logoImage,
    required FrameWatermarkConfig config,
    required double totalWidth,
    required double pad,
    required double photoH,
    required double bottomBarH,
  }) {
    final double barTop = pad + photoH;
    final double barCenterY = barTop + bottomBarH / 2;
    final isDarkBg = config.isBlurredBg || (!config.isPaperTextureBg && config.backgroundColor.computeLuminance() < 0.4);
    final textColor = isDarkBg
        ? Colors.white
        : (config.isPaperTextureBg ? const Color(0xFF2C241D) : const Color(0xFF1E1E24));
    final subTextColor = isDarkBg
        ? Colors.white70
        : (config.isPaperTextureBg ? const Color(0xFF7A6B5D) : const Color(0xFF6E6E78));

    final double logoShiftX = totalWidth * 0.20 * config.logoOffsetX;
    final double logoShiftY = bottomBarH * (config.logoOffsetY * 0.45);
    final double textShiftX = totalWidth * 0.20 * config.textOffsetX;
    final double textShiftY = bottomBarH * (config.textOffsetY * 0.45);

    // 左侧：品牌 Logo 或机型大标题 (支持自由左右与上下位置调节)
    if (logoImage != null) {
      final double effectiveScale = config.logoScale.clamp(0.4, 2.5);
      final double logoMaxH = bottomBarH * 0.42 * effectiveScale;
      final double logoMaxW = totalWidth * 0.38 * effectiveScale;
      final double logoRatio = logoImage.width / logoImage.height;

      double targetLogoH = logoMaxH;
      double targetLogoW = targetLogoH * logoRatio;
      if (targetLogoW > logoMaxW) {
        targetLogoW = logoMaxW;
        targetLogoH = targetLogoW / logoRatio;
      }

      final logoRect = Rect.fromLTWH(pad * 1.5 + logoShiftX, barCenterY - targetLogoH / 2 + logoShiftY, targetLogoW, targetLogoH);
      final logoSrc = Rect.fromLTWH(0, 0, logoImage.width.toDouble(), logoImage.height.toDouble());
      final logoPaint = Paint()..filterQuality = FilterQuality.high;
      final isCustomLogo = config.selectedLogoId.startsWith('custom_') || config.selectedLogoId == 'custom';
      if (config.isLogoInverted && isCustomLogo) {
        logoPaint.colorFilter = const ColorFilter.matrix([
          -1.0,  0.0,  0.0, 0.0, 255.0,
           0.0, -1.0,  0.0, 0.0, 255.0,
           0.0,  0.0, -1.0, 0.0, 255.0,
           0.0,  0.0,  0.0, 1.0,   0.0,
        ]);
      }
      canvas.drawImageRect(logoImage, logoSrc, logoRect, logoPaint);
    } else if (config.exifInfo.displayModelName.isNotEmpty) {
      final titlePainter = TextPainter(
        text: TextSpan(
          text: config.exifInfo.displayModelName.toUpperCase(),
          style: TextStyle(
            color: textColor,
            fontSize: bottomBarH * 0.22,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.5,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      titlePainter.paint(canvas, Offset(pad * 1.5 + logoShiftX, barCenterY - titlePainter.height / 2 + logoShiftY));
    }

    // 右侧：EXIF 参数与时间（仅当有实际参数或时间时绘制，支持自由左右与上下位置调节）
    if (config.showParameters) {
      final paramLine1 = config.exifInfo.parametersString;
      final paramLine2 = config.exifInfo.dateTime;

      final p1Painter = paramLine1.isNotEmpty
          ? (TextPainter(
              text: TextSpan(
                text: paramLine1,
                style: TextStyle(
                  color: textColor,
                  fontSize: bottomBarH * 0.18,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
              textDirection: TextDirection.ltr,
            )..layout())
          : null;

      final p2Painter = paramLine2.isNotEmpty
          ? (TextPainter(
              text: TextSpan(
                text: paramLine2,
                style: TextStyle(
                  color: subTextColor,
                  fontSize: bottomBarH * 0.13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              textDirection: TextDirection.ltr,
            )..layout())
          : null;
      final double rightMargin = (totalWidth - pad * 1.5) + textShiftX;

      if (p1Painter != null && p2Painter != null) {
        final double totalTextHeight = p1Painter.height + 4 + p2Painter.height;
        final double textStartY = barCenterY - totalTextHeight / 2 + textShiftY;
        p1Painter.paint(canvas, Offset(rightMargin - p1Painter.width, textStartY));
        p2Painter.paint(canvas, Offset(rightMargin - p2Painter.width, textStartY + p1Painter.height + 4));
      } else if (p1Painter != null) {
        p1Painter.paint(canvas, Offset(rightMargin - p1Painter.width, barCenterY - p1Painter.height / 2 + textShiftY));
      } else if (p2Painter != null) {
        p2Painter.paint(canvas, Offset(rightMargin - p2Painter.width, barCenterY - p2Painter.height / 2 + textShiftY));
      }
    }
  }

  /// 绘制米黄色复古手作纸张纹理背景 (全幅暖米黄纸浆底色 + 微妙纸张光影 + 纸浆纤维微粒)
  static void drawPaperTexture(Canvas canvas, Rect rect) {
    // 1. 暖米黄色纯正手作纸浆底色 (全幅统一温润纸张底色)
    const baseColor = Color(0xFFFAF6EE); // 温润手作棉纸底色
    const shadeColor = Color(0xFFF2EBDC); // 微弱纸浆自然色泽

    // 2. 均匀全幅温润纸张底色与极微弱微光
    final bgPaint = Paint()..color = baseColor;
    canvas.drawRect(rect, bgPaint);

    final paperGradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: const [baseColor, shadeColor, baseColor],
      stops: const [0.0, 0.5, 1.0],
    );
    final gradientPaint = Paint()
      ..shader = paperGradient.createShader(rect)
      ..color = Colors.white.withValues(alpha: 0.65);
    canvas.drawRect(rect, gradientPaint);

    // 3. 确定性轻微随机纸浆纤维杂质与微粒 (覆盖全图，均匀自然)
    final double w = rect.width;
    final double h = rect.height;
    final double step = math.max(10.0, math.min(w, h) / 70.0);

    final dotPaintLight = Paint()
      ..color = const Color(0xFFFFFFFF).withValues(alpha: 0.55)
      ..style = PaintingStyle.fill;

    final dotPaintDark = Paint()
      ..color = const Color(0xFF8D7A68).withValues(alpha: 0.045)
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(0.5, step * 0.035)
      ..strokeCap = StrokeCap.round;

    final fiberPaint = Paint()
      ..color = const Color(0xFF7D6752).withValues(alpha: 0.038)
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(0.7, step * 0.045)
      ..strokeCap = StrokeCap.round;

    for (double x = 0; x < w; x += step) {
      for (double y = 0; y < h; y += step) {
        // 使用数学 Hash 函数计算确定性伪随机数 (0.0 ~ 1.0)
        final double n1 = ((math.sin(x * 12.9898 + y * 78.233) * 43758.5453) % 1.0).abs();
        final double n2 = ((math.cos(x * 93.9898 + y * 67.345) * 23421.631) % 1.0).abs();
        final double n3 = ((math.sin((x + y) * 37.123) * 54321.987) % 1.0).abs();

        final double px = x + (n1 - 0.5) * step * 0.8;
        final double py = y + (n2 - 0.5) * step * 0.8;

        if (n3 > 0.65) {
          // 微小的浅色反光亮斑
          canvas.drawCircle(Offset(px, py), math.max(0.4, step * 0.04), dotPaintLight);
        } else if (n3 > 0.35) {
          // 纸浆暗色小斑点
          canvas.drawCircle(Offset(px, py), math.max(0.35, step * 0.03), dotPaintDark);
        }

        // 有机纸张短纤维丝 (约 15% 概率生成一段微弱弯折短纤维)
        if (n1 > 0.82) {
          final double angle = n2 * math.pi * 2;
          final double len = step * (0.3 + n3 * 0.45);
          final double ex = px + math.cos(angle) * len;
          final double ey = py + math.sin(angle) * len;
          canvas.drawLine(Offset(px, py), Offset(ex, ey), fiberPaint);
        }
      }
    }
  }
}
