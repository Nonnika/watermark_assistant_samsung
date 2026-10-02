import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/app_strings.dart';
import '../theme/one_ui_theme.dart';
import 'pebble_icon.dart';

class SplashScreen extends StatefulWidget {
  final VoidCallback onFinish;

  const SplashScreen({super.key, required this.onFinish});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _arrival;
  late final Animation<double> _details;
  late final Animation<double> _text;
  Timer? _reducedMotionTimer;
  bool _hasStarted = false;
  bool _hasFinished = false;
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _controller =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 1800),
        )..addStatusListener((status) {
          if (status == AnimationStatus.completed && !_reduceMotion) {
            _finishSplash();
          }
        });
    _arrival = _interval(0, 0.42, Curves.easeOutCubic);
    _details = _interval(0.05, 0.52, Curves.easeOutCubic);
    _text = _interval(0.20, 0.62, Curves.easeOutCubic);
  }

  Animation<double> _interval(double begin, double end, Curve curve) {
    return _controller.drive(
      CurveTween(curve: Interval(begin, end, curve: curve)),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_hasStarted) return;
    _hasStarted = true;
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (_reduceMotion) {
      _controller.value = 1;
      _reducedMotionTimer = Timer(
        const Duration(milliseconds: 400),
        _finishSplash,
      );
    } else {
      _controller.forward();
    }
  }

  void _finishSplash() {
    if (!mounted || _hasFinished) return;
    _hasFinished = true;
    _controller.stop();
    _reducedMotionTimer?.cancel();
    widget.onFinish();
  }

  @override
  void dispose() {
    _reducedMotionTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarBrightness: Brightness.dark,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: OneUITheme.landingBackground,
        systemNavigationBarIconBrightness: Brightness.light,
        systemNavigationBarContrastEnforced: false,
      ),
      child: Scaffold(
        backgroundColor: OneUITheme.landingBackground,
        body: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _finishSplash,
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Keep the first icon centered like the native launch window,
              // then make room for the title with one gentle upward movement.
              final lift = math.min(48.0, constraints.maxHeight * 0.12);
              return Stack(
                fit: StackFit.expand,
                children: [
                  RepaintBoundary(
                    child: FadeTransition(
                      opacity: _details,
                      child: const CustomPaint(
                        painter: _SplashBackdropPainter(),
                      ),
                    ),
                  ),
                  Center(
                    child: AnimatedBuilder(
                      animation: _controller,
                      builder: (context, child) {
                        return Transform.translate(
                          offset: Offset(0, -lift * _arrival.value),
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              FadeTransition(
                                opacity: _details,
                                child: Transform.scale(
                                  scale: 0.94 + 0.06 * _arrival.value,
                                  child: const SizedBox(
                                    width: 260,
                                    height: 220,
                                    child: RepaintBoundary(
                                      child: CustomPaint(
                                        painter: _PhotoFramesPainter(),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              Transform.scale(
                                scale:
                                    1 +
                                    0.06 * math.sin(_arrival.value * math.pi),
                                child: child,
                              ),
                            ],
                          ),
                        );
                      },
                      child: const RepaintBoundary(
                        child: AppPebbleIcon(size: 112, hasShadow: true),
                      ),
                    ),
                  ),
                  Positioned(
                    top: constraints.maxHeight / 2 + 36,
                    left: 32,
                    right: 32,
                    child: SlideTransition(
                      position: _text.drive(
                        Tween<Offset>(
                          begin: const Offset(0, 0.16),
                          end: Offset.zero,
                        ),
                      ),
                      child: FadeTransition(
                        opacity: _text,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              AppStrings.appName,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 30,
                                height: 1.25,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.6,
                                color: Color(0xFFF5F6FA),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              AppStrings.headerSubtitle,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 15,
                                height: 1.5,
                                fontWeight: FontWeight.w400,
                                color: Color(0xFF9496A8),
                              ),
                            ),
                            const SizedBox(height: 24),
                            Container(
                              width: 28,
                              height: 3,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(2),
                                gradient: const LinearGradient(
                                  colors: [
                                    Color(0xFF38BDF5),
                                    Color(0xFF6430EB),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Broad, faint light echoes the icon gradient without a full-screen blur.
class _SplashBackdropPainter extends CustomPainter {
  const _SplashBackdropPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2 - 48);
    final radius = math.min(size.width * 0.85, 360.0);
    final bounds = Rect.fromCircle(center: center, radius: radius);
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0x242D66C8), Color(0x102D3D78), Color(0x002D3D78)],
          stops: [0, 0.48, 1],
        ).createShader(bounds),
    );
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader =
            const RadialGradient(colors: [Color(0x166430EB), Color(0x006430EB)])
                .createShader(
                  Rect.fromCircle(
                    center: center + const Offset(70, 50),
                    radius: radius * 0.72,
                  ),
                ),
    );
  }

  @override
  bool shouldRepaint(covariant _SplashBackdropPainter oldDelegate) => false;
}

/// Quiet photo silhouettes connect the launch artwork to the editing canvas.
class _PhotoFramesPainter extends CustomPainter {
  const _PhotoFramesPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    _paintFrame(
      canvas,
      center + const Offset(-26, -3),
      -0.20,
      const Color(0xFF65ABFA),
    );
    _paintFrame(
      canvas,
      center + const Offset(24, 5),
      0.16,
      const Color(0xFF9D82EF),
    );
  }

  void _paintFrame(Canvas canvas, Offset center, double angle, Color color) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(angle);
    final frame = RRect.fromRectAndRadius(
      const Rect.fromLTWH(-63, -73, 126, 146),
      const Radius.circular(24),
    );
    canvas.drawRRect(frame, Paint()..color = color.withValues(alpha: 0.025));
    canvas.drawRRect(
      frame,
      Paint()
        ..color = color.withValues(alpha: 0.12)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _PhotoFramesPainter oldDelegate) => false;
}
