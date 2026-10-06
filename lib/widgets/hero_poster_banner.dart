import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../services/app_strings.dart';
import 'frame_controls/frame_snapseed_strip.dart';

class HeroPosterItem {
  final String id;
  final String title;
  final String subtitle;
  final String imageAsset;
  final String backgroundAsset;
  final bool isFinishedPhoto;
  final Color primaryColor;
  final List<Color> gradientColors;

  const HeroPosterItem({
    required this.id,
    required this.title,
    required this.subtitle,
    this.imageAsset = '',
    this.backgroundAsset = '',
    this.isFinishedPhoto = false,
    this.primaryColor = const Color(0xFF0D6EFD),
    this.gradientColors = const [Color(0xFF2C3E50), Color(0xFF000000)],
  });
}

class HeroPosterBanner extends StatefulWidget {
  final VoidCallback? onActionButtonTap;
  final VoidCallback? onMoreOptionsTap;
  final ValueChanged<int>? onPageChanged;

  const HeroPosterBanner({
    super.key,
    this.onActionButtonTap,
    this.onMoreOptionsTap,
    this.onPageChanged,
  });

  @override
  State<HeroPosterBanner> createState() => _HeroPosterBannerState();
}

class _HeroPosterBannerState extends State<HeroPosterBanner> {
  static final _photoBlur = ui.ImageFilter.blur(
    sigmaX: 20,
    sigmaY: 20,
    tileMode: ui.TileMode.clamp,
  );

  final PageController _pageController = PageController(initialPage: 0);
  int _currentPage = 0;

  List<HeroPosterItem> get _posters => [
    HeroPosterItem(
      id: 'frame_watermark',
      title: AppStrings.bannerFrameTitle,
      subtitle: AppStrings.bannerFrameSubtitle,
      imageAsset: 'assets/images/banner_frame_scenery.jpg',
      backgroundAsset: 'assets/images/banner_frame_background.jpg',
      isFinishedPhoto: true,
      gradientColors: [Color(0xFF3A4B58), Color(0xFF1E2830), Color(0xFF101418)],
    ),
    HeroPosterItem(
      id: 'overlay_watermark',
      title: AppStrings.bannerOverlayTitle,
      subtitle: AppStrings.bannerOverlaySubtitle,
      imageAsset: 'assets/images/banner_classic_vintage.jpg',
      backgroundAsset: 'assets/images/banner_overlay_background.jpg',
      isFinishedPhoto: true,
      gradientColors: [Color(0xFF1A365D), Color(0xFF0F172A), Color(0xFF020617)],
    ),
    HeroPosterItem(
      id: 'gesture_control',
      title: AppStrings.bannerGestureTitle,
      subtitle: AppStrings.bannerGestureSubtitle,
      imageAsset: 'assets/images/banner_gesture_minimal.jpg',
      backgroundAsset: 'assets/images/banner_gesture_background.jpg',
      isFinishedPhoto: true,
      gradientColors: [Color(0xFF4A4A52), Color(0xFF232328), Color(0xFF0A0A0C)],
    ),
    HeroPosterItem(
      id: 'dynamic_photo',
      title: AppStrings.bannerMotionTitle,
      subtitle: AppStrings.bannerMotionSubtitle,
      imageAsset: 'assets/images/banner_dynamic_photo.jpeg',
      backgroundAsset: 'assets/images/banner_motion_background.jpg',
      isFinishedPhoto: true,
      gradientColors: [Color(0xFF2D3748), Color(0xFF1A202C), Color(0xFF0F172A)],
    ),
  ];

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final posters = _posters;
    return Stack(
      children: [
        // 1. 轮播海报主体 (PageView)
        PageView.builder(
          controller: _pageController,
          itemCount: posters.length,
          onPageChanged: (idx) {
            setState(() => _currentPage = idx);
            widget.onPageChanged?.call(idx);
          },
          itemBuilder: (context, index) {
            final poster = posters[index];
            return _buildPosterSlide(poster, index);
          },
        ),

        // 3. 底部三点轮播指示器 (● ○ ○)
        Positioned(
          bottom: 18,
          left: 0,
          right: 0,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(posters.length, (idx) {
              final isCurrent = idx == _currentPage;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeOutCubic,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                width: isCurrent ? 8 : 7,
                height: isCurrent ? 8 : 7,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isCurrent
                      ? Colors.white
                      : Colors.white.withValues(alpha: 0.38),
                  boxShadow: isCurrent
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.4),
                            blurRadius: 4,
                            offset: const Offset(0, 1),
                          ),
                        ]
                      : null,
                ),
              );
            }),
          ),
        ),
      ],
    );
  }

  Widget _buildPosterSlide(HeroPosterItem poster, int index) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF131519),
        gradient: poster.isFinishedPhoto
            ? null
            : LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: poster.gradientColors,
              ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // The original photo fills the screen behind its sharp finished
          // watermark example. Decode this blurred layer at a modest size.
          if (poster.backgroundAsset.isNotEmpty)
            ClipRect(
              child: ImageFiltered(
                imageFilter: _photoBlur,
                child: Image.asset(
                  poster.backgroundAsset,
                  fit: BoxFit.cover,
                  cacheWidth: 360,
                  filterQuality: FilterQuality.low,
                ),
              ),
            ),

          // 1. 实景摄影高清大图背景
          if (poster.isFinishedPhoto)
            _buildFinishedPhoto(poster, index)
          else if (poster.imageAsset.isNotEmpty)
            Image.asset(
              poster.imageAsset,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                return CustomPaint(
                  painter: _ArchitecturalPosterPainter(seed: index),
                );
              },
            )
          else
            CustomPaint(painter: _ArchitecturalPosterPainter(seed: index)),

          // 2. 电影级暗色渐变遮罩 (保证标题高可读性与底部暗黑衔接)
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: poster.isFinishedPhoto
                    ? [
                        Colors.black.withValues(alpha: 0.45),
                        Colors.transparent,
                        Colors.transparent,
                      ]
                    : [
                        Colors.black.withValues(alpha: 0.55),
                        Colors.black.withValues(alpha: 0.18),
                        Colors.black.withValues(alpha: 0.80),
                      ],
                stops: poster.isFinishedPhoto
                    ? const [0.0, 0.32, 1.0]
                    : const [0.0, 0.40, 1.0],
              ),
            ),
          ),

          // 3. 左侧主要文案 (处于上移 1/4 的黄金视觉分割区)
          Positioned(
            top:
                MediaQuery.of(context).padding.top +
                MediaQuery.of(context).size.height * 0.12,
            left: poster.isFinishedPhoto ? 56 : 28,
            right: 56,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  poster.title,
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: -0.5,
                    height: 1.2,
                    shadows: [
                      Shadow(
                        color: Colors.black87,
                        offset: Offset(0, 2),
                        blurRadius: 10,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  poster.subtitle,
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.45,
                    fontWeight: FontWeight.w500,
                    color: Colors.white.withValues(alpha: 0.95),
                    shadows: const [
                      Shadow(
                        color: Colors.black87,
                        offset: Offset(0, 1),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFinishedPhoto(HeroPosterItem poster, int index) {
    const widths = [0.83, 0.82, 0.80, 0.83];
    const angles = [-0.025, 0.020, -0.018, 0.025];
    const offsets = [-4.0, 5.0, 2.0, -3.0];
    final aspectRatio = poster.id == 'overlay_watermark' ? 3 / 4 : 1162 / 1674;
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableHeight = math.max(
          1.0,
          constraints.maxHeight * 2 / 3 -
              MediaQuery.paddingOf(context).top -
              48,
        );
        final width = math.min(
          constraints.maxWidth * widths[index],
          availableHeight * aspectRatio,
        );
        final height = width / aspectRatio;
        return Stack(
          children: [
            Positioned(
              left: (constraints.maxWidth - width) / 2 + offsets[index],
              bottom: constraints.maxHeight / 3 + 28,
              width: width,
              height: height,
              child: Transform.rotate(
                angle: angles[index],
                child: RepaintBoundary(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.22),
                          blurRadius: 32,
                          spreadRadius: -4,
                          offset: const Offset(0, 12),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: ShaderMask(
                        blendMode: BlendMode.dstIn,
                        shaderCallback: (bounds) => const LinearGradient(
                          colors: [
                            Colors.transparent,
                            Colors.white,
                            Colors.white,
                            Colors.transparent,
                          ],
                          stops: [0, 0.020, 0.980, 1],
                        ).createShader(bounds),
                        child: ShaderMask(
                          blendMode: BlendMode.dstIn,
                          shaderCallback: (bounds) => const LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Colors.white,
                              Colors.white,
                              Colors.transparent,
                            ],
                            stops: [0, 0.014, 0.986, 1],
                          ).createShader(bounds),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              Image.asset(
                                poster.imageAsset,
                                fit: BoxFit.contain,
                              ),
                              if (poster.id == 'gesture_control')
                                Positioned(
                                  left: 16,
                                  right: 16,
                                  bottom: height * 0.15,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF222225)
                                          .withValues(alpha: 0.88),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: FrameSnapseedProgressBar(
                                      paramName: AppStrings.paramBottomBar,
                                      paramValue: '13%',
                                      progress: (0.13 - 0.08) / (0.35 - 0.08),
                                    ),
                                  ),
                                ),
                              if (poster.id == 'dynamic_photo')
                                Positioned(
                                  left: 16,
                                  bottom: height * 0.15,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 5,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withValues(
                                        alpha: 0.38,
                                      ),
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(
                                        color: const Color(0xFFFFD600)
                                            .withValues(alpha: 0.55),
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(
                                          Icons.motion_photos_on_rounded,
                                          size: 16,
                                          color: Color(0xFFFFD600),
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          AppStrings.motionPhotoBadge,
                                          style: const TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w800,
                                            color: Color(0xFFFFD600),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// 绘制高质感几何与建筑立面线条的画笔
class _ArchitecturalPosterPainter extends CustomPainter {
  final int seed;

  _ArchitecturalPosterPainter({required this.seed});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = Colors.white.withValues(alpha: 0.12);

    final fillPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = Colors.white.withValues(alpha: 0.04);

    // 绘制富有层次感的斜向建筑窗格与立面透视
    final path = Path();
    if (seed == 0) {
      // 胶片建筑窗格质感
      for (double y = 40; y < size.height; y += 70) {
        canvas.drawLine(
          Offset(size.width * 0.35, y),
          Offset(size.width, y + 40),
          paint,
        );
        canvas.drawRect(
          Rect.fromLTWH(size.width * 0.45, y + 10, size.width * 0.45, 45),
          fillPaint,
        );
      }
    } else if (seed == 1) {
      // 几何透视框
      for (double r = 60; r < size.width * 0.8; r += 50) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
              center: Offset(size.width * 0.65, size.height * 0.5),
              width: r * 1.5,
              height: r * 2,
            ),
            const Radius.circular(20),
          ),
          paint,
        );
      }
    } else {
      // 经典暗房光影分割
      path.moveTo(0, size.height * 0.8);
      path.lineTo(size.width, size.height * 0.2);
      path.lineTo(size.width, size.height);
      path.lineTo(0, size.height);
      path.close();
      canvas.drawPath(path, fillPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _ArchitecturalPosterPainter oldDelegate) =>
      oldDelegate.seed != seed;
}
