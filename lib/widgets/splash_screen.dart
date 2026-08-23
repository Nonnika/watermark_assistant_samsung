import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/app_strings.dart';
import 'pebble_icon.dart';

class SplashScreen extends StatefulWidget {
  final VoidCallback onFinish;

  const SplashScreen({super.key, required this.onFinish});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  // 1. 第一阶段：由小变大 (Zoom In)
  late final AnimationController _zoomController;
  late final Animation<double> _scaleZoomAnimation;
  late final Animation<double> _opacityZoomAnimation;

  // 2. 第二阶段：左右上下灵动跳跃 (2D Jumping & Playful Bouncing)
  late final AnimationController _jumpController;
  late final Animation<double> _jumpDxAnimation;
  late final Animation<double> _jumpDyAnimation;
  late final Animation<double> _jumpRotateAnimation;
  late final Animation<double> _jumpScaleXAnimation;
  late final Animation<double> _jumpScaleYAnimation;

  // 3. 第三阶段：落定粒子爆发 (Particle Burst & Sparkles)
  late final AnimationController _particleController;
  late final List<_SplashParticle> _particles;

  // 4. 第四阶段：文字由下至上渐变出现 (Text Slide Up & Fade In)
  late final AnimationController _textController;
  late final Animation<double> _textFadeAnimation;
  late final Animation<Offset> _textSlideAnimation;

  Timer? _navigateTimer;
  bool _hasFinished = false;

  @override
  void initState() {
    super.initState();

    // -------------------------------------------------------------
    // 阶段 1: 图标由极小零点由小变大 (0ms ~ 600ms)
    // -------------------------------------------------------------
    _zoomController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _scaleZoomAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.0, end: 1.18).chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 70,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.18, end: 1.0).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 30,
      ),
    ]).animate(_zoomController);

    _opacityZoomAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _zoomController, curve: const Interval(0.0, 0.6, curve: Curves.easeIn)),
    );

    // -------------------------------------------------------------
    // 阶段 2: 左右上下跳动与形变 (550ms ~ 1400ms)
    // -------------------------------------------------------------
    _jumpController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
    );

    // 左右位移 X: 0 -> -16 -> +18 -> -10 -> +6 -> 0
    _jumpDxAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.0, end: -16.0).chain(CurveTween(curve: Curves.easeOutQuad)),
        weight: 20,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: -16.0, end: 18.0).chain(CurveTween(curve: Curves.easeInOutQuad)),
        weight: 30,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 18.0, end: -10.0).chain(CurveTween(curve: Curves.easeInOutQuad)),
        weight: 25,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: -10.0, end: 6.0).chain(CurveTween(curve: Curves.easeInOutQuad)),
        weight: 15,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 6.0, end: 0.0).chain(CurveTween(curve: Curves.easeOut)),
        weight: 10,
      ),
    ]).animate(_jumpController);

    // 上下位移 Y: 0 -> -28 (起跳) -> +6 (着地缓冲) -> -18 (二次起跳) -> +4 -> 0 (落定)
    _jumpDyAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.0, end: -28.0).chain(CurveTween(curve: Curves.easeOutQuad)),
        weight: 20,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: -28.0, end: 6.0).chain(CurveTween(curve: Curves.easeInQuad)),
        weight: 25,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 6.0, end: -18.0).chain(CurveTween(curve: Curves.easeOutQuad)),
        weight: 22,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: -18.0, end: 4.0).chain(CurveTween(curve: Curves.easeInQuad)),
        weight: 18,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 4.0, end: 0.0).chain(CurveTween(curve: Curves.easeOut)),
        weight: 15,
      ),
    ]).animate(_jumpController);

    // 旋转摇摆 (倾斜跳跃)
    _jumpRotateAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.0, end: -0.09).chain(CurveTween(curve: Curves.easeOut)),
        weight: 20,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: -0.09, end: 0.08).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 30,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.08, end: -0.04).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 25,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: -0.04, end: 0.0).chain(CurveTween(curve: Curves.easeOut)),
        weight: 25,
      ),
    ]).animate(_jumpController);

    // 弹性拉伸与挤压 (Squash & Stretch)
    _jumpScaleXAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween<double>(begin: 1.0, end: 0.90), weight: 20), // 起跳拉长
      TweenSequenceItem(tween: Tween<double>(begin: 0.90, end: 1.12), weight: 25), // 触地压扁
      TweenSequenceItem(tween: Tween<double>(begin: 1.12, end: 0.94), weight: 22), // 弹起拉长
      TweenSequenceItem(tween: Tween<double>(begin: 0.94, end: 1.05), weight: 18), // 回弹
      TweenSequenceItem(tween: Tween<double>(begin: 1.05, end: 1.0), weight: 15),
    ]).animate(_jumpController);

    _jumpScaleYAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween<double>(begin: 1.0, end: 1.12), weight: 20),
      TweenSequenceItem(tween: Tween<double>(begin: 1.12, end: 0.88), weight: 25),
      TweenSequenceItem(tween: Tween<double>(begin: 0.88, end: 1.08), weight: 22),
      TweenSequenceItem(tween: Tween<double>(begin: 1.08, end: 0.95), weight: 18),
      TweenSequenceItem(tween: Tween<double>(begin: 0.95, end: 1.0), weight: 15),
    ]).animate(_jumpController);

    // -------------------------------------------------------------
    // 阶段 3: 结束跳跃时的粒子爆发特效 (1400ms ~ 2300ms)
    // -------------------------------------------------------------
    _particleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _particles = _generateSplashParticles(32);

    // -------------------------------------------------------------
    // 阶段 4: 文字由下至上渐变滑出 (1500ms ~ 2250ms)
    // -------------------------------------------------------------
    _textController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 750),
    );

    _textFadeAnimation = CurvedAnimation(
      parent: _textController,
      curve: Curves.easeIn,
    );

    _textSlideAnimation = Tween<Offset>(
      begin: const Offset(0.0, 0.45),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _textController,
      curve: Curves.easeOutCubic,
    ));

    // -------------------------------------------------------------
    // 编排按序串联运行完整的动画管线
    // -------------------------------------------------------------
    _runAnimationSequence();
  }

  void _runAnimationSequence() async {
    // 1. 由小变大
    await _zoomController.forward();
    if (!mounted) return;

    // 2. 左右上下跳跃
    await _jumpController.forward();
    if (!mounted) return;

    // 3. 图标落定 -> 触发粒子爆炸！
    _particleController.forward();

    // 4. 文字由下至上渐变出现
    await Future.delayed(const Duration(milliseconds: 100));
    if (mounted) {
      _textController.forward();
    }

    // 5. 自动过渡至主工作台
    _navigateTimer = Timer(const Duration(milliseconds: 1600), _finishSplash);
  }

  void _finishSplash() {
    if (_hasFinished) return;
    _hasFinished = true;
    _navigateTimer?.cancel();
    widget.onFinish();
  }

  List<_SplashParticle> _generateSplashParticles(int count) {
    final random = math.Random(42);
    final colors = [
      const Color(0xFF38B6FF), // 浅天蓝
      const Color(0xFF1976D2), // 纯正钴蓝
      const Color(0xFFFFD600), // 耀目金
      const Color(0xFFFFFFFF), // 纯净白
      const Color(0xFF80D8FF), // 冰晶蓝
    ];

    return List.generate(count, (index) {
      final angle = (index * (2 * math.pi / count)) + (random.nextDouble() * 0.4 - 0.2);
      final speed = 70.0 + random.nextDouble() * 95.0; // 爆发半径
      final size = 3.0 + random.nextDouble() * 4.5;
      final color = colors[random.nextInt(colors.length)];
      final isStar = random.nextBool();

      return _SplashParticle(
        angle: angle,
        maxDistance: speed,
        size: size,
        color: color,
        isStar: isStar,
      );
    });
  }

  @override
  void dispose() {
    _navigateTimer?.cancel();
    _zoomController.dispose();
    _jumpController.dispose();
    _particleController.dispose();
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF000000) : const Color(0xFFFFFFFF);
    final textColor = isDark ? const Color(0xFFFFFFFF) : const Color(0xFF000000);
    final subtitleColor = isDark ? const Color(0xFFEEEEEE) : const Color(0xFF000000);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
        systemNavigationBarColor: bgColor,
        systemNavigationBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: bgColor,
        body: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _finishSplash, // 点击屏幕可即时跳过启动图
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Spacer(flex: 3),

                // 1. 图标容器（紧凑 116dp 真实尺寸，Stack clipBehavior: Clip.none 允许粒子向外飞散）
                SizedBox(
                  width: 116,
                  height: 116,
                  child: Stack(
                    alignment: Alignment.center,
                    clipBehavior: Clip.none,
                    children: [
                      // 粒子爆发层 (落定时刻在图标四周绽放，自由扩散)
                      AnimatedBuilder(
                        animation: _particleController,
                        builder: (context, child) {
                          return CustomPaint(
                            size: const Size(116, 116),
                            painter: _SplashParticlePainter(
                              progress: _particleController.value,
                              particles: _particles,
                            ),
                          );
                        },
                      ),

                      // 三星鹅卵石超椭圆图标 (由小变大 + 左右上下跳跃 + 弹性形变)
                      AnimatedBuilder(
                        animation: Listenable.merge([_zoomController, _jumpController]),
                        builder: (context, child) {
                          final zoomScale = _scaleZoomAnimation.value;
                          final zoomOpacity = _opacityZoomAnimation.value;

                          final dx = _jumpDxAnimation.value;
                          final dy = _jumpDyAnimation.value;
                          final rot = _jumpRotateAnimation.value;
                          final scaleX = _jumpScaleXAnimation.value;
                          final scaleY = _jumpScaleYAnimation.value;

                          return Opacity(
                            opacity: zoomOpacity.clamp(0.0, 1.0),
                            child: Transform.translate(
                              offset: Offset(dx, dy),
                              child: Transform.rotate(
                                angle: rot,
                                child: Transform.scale(
                                  scaleX: zoomScale * scaleX,
                                  scaleY: zoomScale * scaleY,
                                  child: child,
                                ),
                              ),
                            ),
                          );
                        },
                        child: const AppPebbleIcon(
                          size: 116.0,
                          hasShadow: false, // 彻底去除开屏图标背景阴影
                          n: 2.85, // 饱满圆润的超椭圆大鹅卵石圆角
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 18), // 紧凑适中的间距，紧跟在图标正下方

                // 2. 文字由下至上渐变出现 (适配深色/浅色模式)
                SlideTransition(
                  position: _textSlideAnimation,
                  child: FadeTransition(
                    opacity: _textFadeAnimation,
                    child: Column(
                      children: [
                        // 软件主名称
                        Text(
                          AppStrings.appName,
                          style: TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.6,
                            color: textColor,
                          ),
                        ),
                        const SizedBox(height: 8),

                        // 加粗小标题
                        Text(
                          AppStrings.headerSubtitle,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.3,
                            color: subtitleColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const Spacer(flex: 4),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// -------------------------------------------------------------
// 粒子爆发模型与绘制器
// -------------------------------------------------------------
class _SplashParticle {
  final double angle;
  final double maxDistance;
  final double size;
  final Color color;
  final bool isStar;

  _SplashParticle({
    required this.angle,
    required this.maxDistance,
    required this.size,
    required this.color,
    required this.isStar,
  });
}

class _SplashParticlePainter extends CustomPainter {
  final double progress;
  final List<_SplashParticle> particles;

  _SplashParticlePainter({
    required this.progress,
    required this.particles,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0.0 || progress >= 1.0) return;

    final center = Offset(size.width / 2, size.height / 2);
    // 缓动膨胀与衰减
    final easeProgress = Curves.easeOutCubic.transform(progress);
    final alpha = (1.0 - progress).clamp(0.0, 1.0);

    for (final p in particles) {
      final distance = 42.0 + (p.maxDistance * easeProgress);
      final currentX = center.dx + math.cos(p.angle) * distance;
      final currentY = center.dy + math.sin(p.angle) * distance;
      final currentPos = Offset(currentX, currentY);

      final currentSize = p.size * (1.0 - progress * 0.45);
      final particlePaint = Paint()
        ..color = p.color.withValues(alpha: alpha * 0.85)
        ..style = PaintingStyle.fill;

      // 粒子外圈微弱弥散光晕
      final glowPaint = Paint()
        ..color = p.color.withValues(alpha: alpha * 0.35)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, currentSize * 0.8);
      canvas.drawCircle(currentPos, currentSize * 1.5, glowPaint);

      if (p.isStar) {
        // 绘制四角微星光芒 ✨
        _drawStar(canvas, currentPos, currentSize * 1.3, particlePaint);
      } else {
        canvas.drawCircle(currentPos, currentSize, particlePaint);
      }
    }
  }

  void _drawStar(Canvas canvas, Offset center, double r, Paint paint) {
    final path = Path();
    path.moveTo(center.dx, center.dy - r);
    path.quadraticBezierTo(center.dx, center.dy, center.dx + r, center.dy);
    path.quadraticBezierTo(center.dx, center.dy, center.dx, center.dy + r);
    path.quadraticBezierTo(center.dx, center.dy, center.dx - r, center.dy);
    path.quadraticBezierTo(center.dx, center.dy, center.dx, center.dy - r);
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _SplashParticlePainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
