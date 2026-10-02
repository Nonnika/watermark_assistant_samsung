import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Shared artwork for the in-app icon and generated Android launcher layers.
/// Coordinates use a 100 × 100 canvas; the foreground fits an adaptive safe zone.
abstract final class OneUiIconArtwork {
  static const backgroundGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF38BDF5), Color(0xFF2861F9), Color(0xFF6430EB)],
    stops: [0, 0.48, 1],
  );

  static void paintBackground(
    Canvas canvas,
    Rect bounds, {
    Rect? gradientBounds,
  }) {
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = backgroundGradient.createShader(gradientBounds ?? bounds),
    );
  }

  static void paintForeground(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 100, size.height / 100);
    _paintRearCard(canvas);
    _paintPhoto(canvas);
    canvas.restore();
  }

  static void _paintRearCard(Canvas canvas) {
    canvas.save();
    canvas.translate(43, 49);
    canvas.rotate(-16 * math.pi / 180);
    final card = RRect.fromRectAndRadius(
      const Rect.fromLTWH(-23, -27, 46, 54),
      const Radius.circular(8),
    );
    _paintCardShadow(canvas, card, alpha: 0.12);
    canvas.drawRRect(
      card,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFF1F2FF), Color(0xFFCED3F8)],
        ).createShader(card.outerRect),
    );
    canvas.restore();
  }

  static void _paintPhoto(Canvas canvas) {
    canvas.save();
    canvas.translate(55, 51);
    canvas.rotate(7 * math.pi / 180);
    final card = RRect.fromRectAndRadius(
      const Rect.fromLTWH(-27, -29, 54, 58),
      const Radius.circular(8),
    );
    _paintCardShadow(canvas, card, alpha: 0.20);
    canvas.drawRRect(
      card,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.white, Color(0xFFF5F6FF)],
        ).createShader(card.outerRect),
    );

    final window = RRect.fromRectAndRadius(
      const Rect.fromLTWH(-22, -24, 44, 38),
      const Radius.circular(5.5),
    );
    canvas.save();
    canvas.clipRRect(window);
    canvas.drawRect(
      window.outerRect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF52B8F6), Color(0xFFACE8F8)],
        ).createShader(window.outerRect),
    );
    canvas.drawCircle(
      const Offset(11.5, -12.5),
      4.7,
      Paint()..color = const Color(0xFFFFE78C),
    );

    final rearMountain = Path()
      ..moveTo(-25, 2)
      ..cubicTo(-18, -1, -12, -8, -7, -7)
      ..cubicTo(-1, -7, 4, 3, 13, 6)
      ..lineTo(25, 17)
      ..lineTo(-25, 17)
      ..close();
    canvas.drawPath(
      rearMountain,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF67DBDF), Color(0xFF26BBD4)],
        ).createShader(window.outerRect),
    );
    final frontMountain = Path()
      ..moveTo(-25, 15)
      ..cubicTo(-15, 10, -6, 7, 2, 1)
      ..cubicTo(11, -6, 13, -5, 25, 3)
      ..lineTo(25, 17)
      ..lineTo(-25, 17)
      ..close();
    canvas.drawPath(
      frontMountain,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1EC3D2), Color(0xFF078CC1)],
        ).createShader(window.outerRect),
    );
    canvas.restore();

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(-21, 19, 24, 3.6),
        const Radius.circular(1.8),
      ),
      Paint()..color = const Color(0xFFADC8FC),
    );
    _paintWatermark(canvas);
    canvas.restore();
  }

  static void _paintCardShadow(
    Canvas canvas,
    RRect card, {
    required double alpha,
  }) {
    canvas.drawRRect(
      card.shift(const Offset(0, 2)),
      Paint()
        ..color = const Color(0xFF14268D).withValues(alpha: alpha)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.3),
    );
  }

  static void _paintWatermark(Canvas canvas) {
    canvas.save();
    canvas.translate(21, 12);
    canvas.rotate(-7 * math.pi / 180);
    final sparkle = Path()
      ..moveTo(0, -7)
      ..cubicTo(1.5, -7, 1.4, -3, 3.4, -1.8)
      ..cubicTo(5.4, -0.6, 7, -0.8, 7, 0.5)
      ..cubicTo(7, 1.8, 3.8, 2.1, 2.4, 3.7)
      ..cubicTo(1, 5.3, 1.4, 7.5, 0, 7.5)
      ..cubicTo(-1.4, 7.5, -1.2, 4.3, -3.1, 2.8)
      ..cubicTo(-5, 1.3, -7, 1.8, -7, 0.5)
      ..cubicTo(-7, -0.8, -3.7, -1.4, -2.3, -3.1)
      ..cubicTo(-0.9, -4.8, -1.5, -7, 0, -7)
      ..close();
    canvas.drawPath(
      sparkle.shift(const Offset(0, 1.3)),
      Paint()
        ..color = const Color(0xFF263EB0).withValues(alpha: 0.18)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.4
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.4),
    );
    canvas.drawPath(
      sparkle,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawPath(
      sparkle,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF48A8FF), Color(0xFF6430F2)],
        ).createShader(const Rect.fromLTWH(-7, -7, 14, 14.5)),
    );
    canvas.restore();
  }
}
