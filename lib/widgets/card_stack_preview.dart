import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../models/frame_watermark_config.dart';
import '../models/image_item.dart';
import '../models/watermark_config.dart';
import '../theme/one_ui_theme.dart';
import 'preview/active_photo_painter.dart';
import 'preview/background_tilt_card.dart';
import 'preview/preview_top_bar.dart';
import 'preview/preview_top_menu.dart';
import 'preview/snapseed_param_mixin.dart';
import 'preview/snapseed_wheel_hud.dart';

class CardStackPreview extends StatefulWidget {
  final List<ImageItem> images;
  final int currentIndex;
  final WatermarkType watermarkType;
  final int activeToolIndex;
  final ui.Image? watermarkImage;
  final WatermarkConfig pngConfig;
  final ui.Image? logoImage;
  final FrameWatermarkConfig frameConfig;
  final bool isIndividualMode;
  final ValueChanged<bool> onToggleIndividualMode;
  final ValueChanged<int> onIndexChanged;
  final Function(double relX, double relY) onWatermarkDragged;
  final Function(WatermarkConfig newConfig) onPngConfigChanged;
  final Function(FrameWatermarkConfig newConfig) onFrameConfigChanged;
  final Function(String name, String valStr, double progress) onParamAdjusting;
  final VoidCallback onParamAdjustEnd;
  final Function(bool exportAll) onExport;
  final VoidCallback onBack;

  const CardStackPreview({
    super.key,
    required this.images,
    required this.currentIndex,
    required this.watermarkType,
    required this.activeToolIndex,
    required this.watermarkImage,
    required this.pngConfig,
    required this.logoImage,
    required this.frameConfig,
    required this.isIndividualMode,
    required this.onToggleIndividualMode,
    required this.onIndexChanged,
    required this.onWatermarkDragged,
    required this.onPngConfigChanged,
    required this.onFrameConfigChanged,
    required this.onParamAdjusting,
    required this.onParamAdjustEnd,
    required this.onExport,
    required this.onBack,
  });

  @override
  State<CardStackPreview> createState() => _CardStackPreviewState();
}

class _CardStackPreviewState extends State<CardStackPreview>
    with SingleTickerProviderStateMixin, SnapseedParamHandling {
  late AnimationController _animController;
  late Animation<double> _slideAnimation;
  double _dragOffsetDx = 0.0;
  bool _isFlinging = false;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );
    _slideAnimation = Tween<double>(begin: 0, end: 0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic),
    );
  }

  @override
  void didUpdateWidget(covariant CardStackPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.activeToolIndex != widget.activeToolIndex ||
        oldWidget.watermarkType != widget.watermarkType) {
      paramAdjustTimer?.cancel();
      wheelFadeTimer?.cancel();
      isVerticalSwitching = false;
    }
  }

  @override
  void dispose() {
    paramAdjustTimer?.cancel();
    wheelFadeTimer?.cancel();
    _animController.dispose();
    super.dispose();
  }

  void _triggerCardFlip(int targetIndex, bool forward) {
    if (_isFlinging || widget.images.length <= 1) return;

    final total = widget.images.length;
    final validIndex = (targetIndex % total + total) % total;

    _isFlinging = true;
    final endOffset = forward ? -340.0 : 340.0;

    _slideAnimation = Tween<double>(begin: _dragOffsetDx, end: endOffset).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeInCubic),
    );

    _animController.forward(from: 0).then((_) {
      widget.onIndexChanged(validIndex);
      _slideAnimation = Tween<double>(begin: -endOffset * 0.25, end: 0).animate(
        CurvedAnimation(parent: _animController, curve: Curves.easeOutBack),
      );
      _animController.forward(from: 0).then((_) {
        _isFlinging = false;
        _dragOffsetDx = 0.0;
      });
    });
  }

  void _springBack() {
    _slideAnimation = Tween<double>(begin: _dragOffsetDx, end: 0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutBack),
    );
    _animController.forward(from: 0).then((_) {
      _dragOffsetDx = 0.0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final total = widget.images.length;
    final activeItem = widget.images[widget.currentIndex];

    return ClipRect(
      child: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          color: Color(0xFF000000),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final containerW = constraints.maxWidth;
            final containerH = constraints.maxHeight;

            double contentW = activeItem.width.toDouble();
            double contentH = activeItem.height.toDouble();

            if (contentW <= 0 || contentH <= 0) {
              contentW = 1080;
              contentH = 1920;
            }

            if (widget.watermarkType == WatermarkType.frame) {
              final pad = contentW * widget.frameConfig.paddingRatio;
              final bottomBarH = contentH * widget.frameConfig.bottomBarRatio;
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

            return Stack(
              alignment: Alignment.center,
              children: [
                // 1. 底层倾斜背景卡牌 2 (若照片数 > 2)
                if (total > 2)
                  BackgroundTiltCard(
                    item: widget.images[(widget.currentIndex + 2) % total],
                    renderRect: renderRect,
                    scale: 0.91,
                    offsetX: -10,
                    offsetY: -10,
                    rotation: -0.045,
                    isDark: isDark,
                  ),

                // 2. 底层倾斜背景卡牌 1 (若照片数 > 1)
                if (total > 1)
                  BackgroundTiltCard(
                    item: widget.images[(widget.currentIndex + 1) % total],
                    renderRect: renderRect,
                    scale: 0.96,
                    offsetX: 8,
                    offsetY: -5,
                    rotation: 0.038,
                    isDark: isDark,
                  ),

                // 3. 顶层主编辑卡片 (带平滑滑动切牌与物理倾角)
                Positioned.fill(
                  child: AnimatedBuilder(
                    animation: _animController,
                    builder: (context, child) {
                      final double currentOffset = _animController.isAnimating
                          ? _slideAnimation.value
                          : (isSnapseedMode ? 0.0 : _dragOffsetDx);
                      final double tiltAngle = currentOffset * 0.0005;

                      return Transform.translate(
                        offset: Offset(currentOffset, 0),
                        child: Transform.rotate(
                          angle: tiltAngle,
                          child: child,
                        ),
                      );
                    },
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapUp: (details) {
                        if (widget.watermarkType == WatermarkType.floatingPng && widget.activeToolIndex == 1) {
                          handleTapPreset(details.localPosition, renderRect);
                        }
                      },
                      onHorizontalDragStart: (details) {
                        lastHapticMilestone = -1;
                      },
                      onHorizontalDragUpdate: (details) {
                        if (isSnapseedMode) {
                          handleSnapseedHorizontalDragUpdate(details);
                        } else {
                          if (total <= 1) return;
                          setState(() {
                            _dragOffsetDx += details.primaryDelta ?? 0;
                          });
                        }
                      },
                      onHorizontalDragEnd: (details) {
                        lastHapticMilestone = -1;
                        if (isSnapseedMode) {
                          paramAdjustTimer?.cancel();
                          paramAdjustTimer = Timer(const Duration(milliseconds: 650), () {
                            if (mounted) widget.onParamAdjustEnd();
                          });
                        } else {
                          if (total <= 1) return;
                          final vel = details.primaryVelocity ?? 0;
                          if (_dragOffsetDx < -60 || vel < -300) {
                            _triggerCardFlip((widget.currentIndex + 1) % total, true);
                          } else if (_dragOffsetDx > 60 || vel > 300) {
                            _triggerCardFlip((widget.currentIndex - 1 + total) % total, false);
                          } else {
                            _springBack();
                          }
                        }
                      },
                      onVerticalDragUpdate: (details) {
                        if (isSnapseedMode) {
                          handleSnapseedVerticalDragUpdate(details);
                        }
                      },
                      onVerticalDragEnd: (details) {
                        if (isSnapseedMode) {
                          setState(() {
                            verticalAccumulator = 0.0;
                            dragVisualDy = 0.0;
                          });

                          wheelFadeTimer?.cancel();
                          wheelFadeTimer = Timer(const Duration(milliseconds: 550), () {
                            if (mounted) {
                              setState(() => isVerticalSwitching = false);
                            }
                          });

                          paramAdjustTimer?.cancel();
                          paramAdjustTimer = Timer(const Duration(milliseconds: 650), () {
                            if (mounted) widget.onParamAdjustEnd();
                          });
                        }
                      },
                      child: SizedBox(
                        width: containerW,
                        height: containerH,
                        // 切牌只变换此图层，避免每帧重新绘制照片、相框和模糊背景。
                        child: RepaintBoundary(
                          child: CustomPaint(
                            size: Size(containerW, containerH),
                            isComplex: true,
                            painter: ActivePhotoPainter(
                              watermarkType: widget.watermarkType,
                              baseImage: activeItem.decodedImage,
                              watermarkImage: widget.watermarkImage,
                              config: widget.pngConfig,
                              logoImage: widget.logoImage,
                              frameConfig: widget.frameConfig,
                              renderRect: renderRect,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                // 4. 屏幕中央 Snapseed 参数切换指示器 (上下滑动时浮现，焦点在正中央)
                if (isSnapseedMode)
                  SnapseedWheelHud(
                    watermarkType: widget.watermarkType,
                    activeToolIndex: widget.activeToolIndex,
                    activeAxis: activeAxis,
                    frameParamIdx: frameParamIdx,
                    fxParamIdx: fxParamIdx,
                    visible: isVerticalSwitching,
                    dragVisualDy: dragVisualDy,
                  ),

                // 5. 点击 10 点吸附时的波纹视觉
                if (tapFeedbackOffset != null)
                  Positioned(
                    left: tapFeedbackOffset!.dx - 16,
                    top: tapFeedbackOffset!.dy - 16,
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: OneUITheme.primaryBlue.withValues(alpha: 0.4),
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                    ),
                  ),

                // 6. 顶部悬浮控制栏（左侧纯图标返回主界面 + 右侧三个点菜单，均支持高斯背景模糊）
                PreviewTopBar(
                  onBack: widget.onBack,
                  onOpenMenu: () => _openTopRightMenu(context),
                  isMotionPhoto: activeItem.isMotionPhoto,
                  isUltraHdr: activeItem.isUltraHdr,
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// 打造顶级丝滑 120 FPS 的 Samsung OneUI 全背景高斯模糊与纯净黑曜石弹出菜单
  void _openTopRightMenu(BuildContext context) {
    PreviewTopMenu.show(
      context: context,
      isIndividualMode: widget.isIndividualMode,
      imageCount: widget.images.length,
      onToggleIndividualMode: widget.onToggleIndividualMode,
      onExport: widget.onExport,
    );
  }
}
