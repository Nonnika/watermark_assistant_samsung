import 'dart:math' as math;

import 'package:flutter/material.dart';

/// One UI 风格的圆润超椭圆遮罩。
class SamsungSquircleClipper extends CustomClipper<Path> {
  final double n;

  const SamsungSquircleClipper({this.n = 2.85});

  @override
  Path getClip(Size size) {
    return createSamsungSquirclePath(size, n: n);
  }

  @override
  bool shouldReclip(covariant SamsungSquircleClipper oldClipper) =>
      oldClipper.n != n;

  /// 生成数学级平滑无折角的三星超椭圆鹅卵石路径 (|x/a|^n + |y/b|^n = 1)
  static Path createSamsungSquirclePath(Size size, {double n = 2.85}) {
    final path = Path();
    final double a = size.width / 2;
    final double b = size.height / 2;
    final double cx = a;
    final double cy = b;
    const int steps = 360;

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

/// 应用图标（与 Android 启动图标同源，由 `tool/generate_icons.py` 生成）。
class AppPebbleIcon extends StatelessWidget {
  static const asset = AssetImage('assets/logo/app_icon.png');

  final double size;
  final bool hasShadow;

  const AppPebbleIcon({super.key, this.size = 104.0, this.hasShadow = false});

  @override
  Widget build(BuildContext context) {
    final image = Image(
      image: asset,
      width: size,
      height: size,
      filterQuality: FilterQuality.medium,
      gaplessPlayback: true,
    );
    if (!hasShadow) return image;
    return CustomPaint(
      painter: const _PebbleShadowPainter(),
      child: image,
    );
  }
}

class _PebbleShadowPainter extends CustomPainter {
  const _PebbleShadowPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final squircle = SamsungSquircleClipper.createSamsungSquirclePath(
      size,
      n: 3.75,
    );
    canvas.drawPath(
      squircle.shift(Offset(0, size.height * 0.05)),
      Paint()
        ..color = const Color(0xFF3D55D9).withValues(alpha: 0.24)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, size.width * 0.09),
    );
  }

  @override
  bool shouldRepaint(covariant _PebbleShadowPainter oldDelegate) => false;
}
