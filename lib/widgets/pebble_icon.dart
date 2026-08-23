import 'dart:math' as math;
import 'package:flutter/material.dart';

/// 三星 OneUI 官方正统超椭圆鹅卵石 (Samsung Pebble Superellipse, n=2.85 经典圆润大圆角) 遮罩裁切器
class SamsungSquircleClipper extends CustomClipper<Path> {
  final double n;

  const SamsungSquircleClipper({this.n = 2.85});

  @override
  Path getClip(Size size) {
    return createSamsungSquirclePath(size, n: n);
  }

  @override
  bool shouldReclip(covariant SamsungSquircleClipper oldClipper) => oldClipper.n != n;

  /// 生成数学级平滑无折角的三星超椭圆鹅卵石路径 (|x/a|^n + |y/b|^n = 1)
  static Path createSamsungSquirclePath(Size size, {double n = 2.85}) {
    final path = Path();
    final double a = size.width / 2;
    final double b = size.height / 2;
    final double cx = a;
    final double cy = b;
    const int steps = 144;

    for (int i = 0; i <= steps; i++) {
      final double theta = i * 2 * math.pi / steps;
      final double cosT = math.cos(theta);
      final double sinT = math.sin(theta);

      final double x = cx + a * cosT.sign * math.pow(cosT.abs(), 2.0 / n);
      final double y = cy + b * sinT.sign * math.pow(sinT.abs(), 2.0 / n);

      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    return path;
  }
}

/// 三星 OneUI 风格鹅卵石 (Pebble Squircle) 水印助手矢量图标
/// 背景采用高鲜艳度电光蓝至极光蓝紫色渐变，前景为两个纯白与淡灰色堆叠圆角矩形
class AppPebbleIcon extends StatelessWidget {
  final double size;
  final bool hasShadow;
  final double n;

  const AppPebbleIcon({
    super.key,
    this.size = 104.0,
    this.hasShadow = false,
    this.n = 2.85,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: PebbleShadowAndCardPainter(hasShadow: hasShadow, n: n),
      ),
    );
  }
}

class PebbleShadowAndCardPainter extends CustomPainter {
  final bool hasShadow;
  final double n;

  PebbleShadowAndCardPainter({required this.hasShadow, required this.n});

  @override
  void paint(Canvas canvas, Size size) {
    final squirclePath = SamsungSquircleClipper.createSamsungSquirclePath(size, n: n);

    // 1. 绘制鹅卵石外层微光多重弥散阴影
    if (hasShadow) {
      final shadowPaint1 = Paint()
        ..color = const Color(0xFF7000FF).withValues(alpha: 0.36)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, size.width * 0.18);

      final shadowPath1 = Path()
        ..addPath(squirclePath, Offset(0, size.height * 0.08));
      canvas.drawPath(shadowPath1, shadowPaint1);

      final shadowPaint2 = Paint()
        ..color = const Color(0xFF00A2FF).withValues(alpha: 0.28)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, size.width * 0.10);
      final shadowPath2 = Path()
        ..addPath(squirclePath, Offset(0, size.height * 0.02));
      canvas.drawPath(shadowPath2, shadowPaint2);
    }

    // 2. 裁切为三星鹅卵石超椭圆遮罩并绘制高鲜艳度蓝到蓝紫色渐变背景
    canvas.save();
    canvas.clipPath(squirclePath);

    final bgPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color(0xFF00A2FF), // 高鲜艳电光蓝
          Color(0xFF3D5AFE), // 纯正皇家钴蓝
          Color(0xFF7000FF), // 鲜艳极光蓝紫色
        ],
        stops: [0.0, 0.45, 1.0],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

    // 3. 绘制前景：向左倾斜、一大一小两个淡灰色圆角矩形堆叠（删除圆圈）
    final double w = size.width;
    final double h = size.height;

    _drawStackedTiltedRectangles(canvas, w, h);

    canvas.restore();
  }

  void _drawStackedTiltedRectangles(Canvas canvas, double w, double h) {
    // -------------------------------------------------------------
    // 底层大矩形 (Large Card - 向左倾斜 ~15 度，淡灰底卡)
    // -------------------------------------------------------------
    final double largeW = w * 0.34;
    final double largeH = h * 0.44;
    final double largeR = w * 0.052;
    final Offset largeCenter = Offset(w * 0.465, h * 0.52);
    const double largeAngle = -15.0 * math.pi / 180.0;

    canvas.save();
    canvas.translate(largeCenter.dx, largeCenter.dy);
    canvas.rotate(largeAngle);

    final largeShadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.22)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, w * 0.035);
    final RRect largeShadowRRect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(0, h * 0.015), width: largeW, height: largeH),
      Radius.circular(largeR),
    );
    canvas.drawRRect(largeShadowRRect, largeShadowPaint);

    // 大矩形主体 (纯白底卡)
    final largePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.88)
      ..style = PaintingStyle.fill;
    final RRect largeRRect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset.zero, width: largeW, height: largeH),
      Radius.circular(largeR),
    );
    canvas.drawRRect(largeRRect, largePaint);

    // 大矩形内部淡灰色块
    final largeInnerPaint = Paint()
      ..color = const Color(0xFFEEEEEE)
      ..style = PaintingStyle.fill;
    final RRect largeInnerRRect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(0, -largeH * 0.06), width: largeW * 0.82, height: largeH * 0.70),
      Radius.circular(largeR * 0.65),
    );
    canvas.drawRRect(largeInnerRRect, largeInnerPaint);

    canvas.restore();

    // -------------------------------------------------------------
    // 上层小矩形 (Small Card - 叠加在其上，向左倾斜 ~7 度，纯白+淡灰色，无圆圈)
    // -------------------------------------------------------------
    final double smallW = w * 0.29;
    final double smallH = h * 0.38;
    final double smallR = w * 0.045;
    final Offset smallCenter = Offset(w * 0.575, h * 0.48);
    const double smallAngle = -7.0 * math.pi / 180.0;

    canvas.save();
    canvas.translate(smallCenter.dx, smallCenter.dy);
    canvas.rotate(smallAngle);

    // 小矩形立体阴影
    final smallShadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.26)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, w * 0.038);
    final RRect smallShadowRRect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(-w * 0.012, h * 0.02), width: smallW, height: smallH),
      Radius.circular(smallR),
    );
    canvas.drawRRect(smallShadowRRect, smallShadowPaint);

    // 小矩形主体 (纯白卡片)
    final smallPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    final RRect smallRRect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset.zero, width: smallW, height: smallH),
      Radius.circular(smallR),
    );
    canvas.drawRRect(smallRRect, smallPaint);

    // 小矩形内部淡灰色相片层 (清透淡灰)
    final smallInnerPaint = Paint()
      ..color = const Color(0xFFE0E0E0)
      ..style = PaintingStyle.fill;
    final RRect smallInnerRRect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(0, -smallH * 0.08), width: smallW * 0.80, height: smallH * 0.62),
      Radius.circular(smallR * 0.65),
    );
    canvas.drawRRect(smallInnerRRect, smallInnerPaint);

    // 小矩形底部淡灰色条纹
    final linePaint = Paint()
      ..color = const Color(0xFFBDBDBD)
      ..strokeWidth = w * 0.015
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(-smallW * 0.28, smallH * 0.32),
      Offset(smallW * 0.15, smallH * 0.32),
      linePaint,
    );

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
