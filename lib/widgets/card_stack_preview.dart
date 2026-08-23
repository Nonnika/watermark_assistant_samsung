import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/frame_watermark_config.dart';
import '../models/image_item.dart';
import '../models/watermark_config.dart';
import '../services/app_strings.dart';
import '../theme/one_ui_theme.dart';
import 'preview/active_photo_painter.dart';
import 'preview/preview_top_menu.dart';

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

class _CardStackPreviewState extends State<CardStackPreview> with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _slideAnimation;
  double _dragOffsetDx = 0.0;
  bool _isFlinging = false;
  Timer? _paramAdjustTimer;
  Timer? _wheelFadeTimer;

  // Snapseed 当前参数模式
  String _activeAxis = 'X'; // Floating Pos: 'X' or 'Y'
  int _frameParamIdx = 0; // Frame Params: 0: 留白, 1: 参数栏高度
  int _fxParamIdx = 0;    // Floating FX: 0: 缩放, 1: 不透明度, 2: 旋转角度
  bool _isVerticalSwitching = false;
  double _verticalAccumulator = 0.0;
  double _dragVisualDy = 0.0;
  int _lastHapticMilestone = -1;
  Offset? _tapFeedbackOffset;

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
      _paramAdjustTimer?.cancel();
      _wheelFadeTimer?.cancel();
      _isVerticalSwitching = false;
    }
  }

  @override
  void dispose() {
    _paramAdjustTimer?.cancel();
    _wheelFadeTimer?.cancel();
    _animController.dispose();
    super.dispose();
  }

  bool get _isSnapseedMode {
    if (widget.watermarkType == WatermarkType.frame) {
      return widget.activeToolIndex == 2; // 相框留白与高度
    } else {
      return widget.activeToolIndex == 1 || widget.activeToolIndex == 2; // 坐标 或 尺寸特效
    }
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

  static const List<Map<String, dynamic>> _tenPresetPoints = [
    {'name': '左上', 'x': 0.12, 'y': 0.12},
    {'name': '中上', 'x': 0.50, 'y': 0.12},
    {'name': '右上', 'x': 0.88, 'y': 0.12},
    {'name': '左中', 'x': 0.12, 'y': 0.50},
    {'name': '正中', 'x': 0.50, 'y': 0.50},
    {'name': '右中', 'x': 0.88, 'y': 0.50},
    {'name': '左下', 'x': 0.12, 'y': 0.88},
    {'name': '中下', 'x': 0.50, 'y': 0.88},
    {'name': '右下', 'x': 0.88, 'y': 0.88},
    {'name': '底标', 'x': 0.50, 'y': 0.80},
  ];

  void _handleTapPreset(Offset localPos, Rect imageRect) {
    if (!imageRect.contains(localPos)) return;

    final double relX = (localPos.dx - imageRect.left) / imageRect.width;
    final double relY = (localPos.dy - imageRect.top) / imageRect.height;

    Map<String, dynamic> nearest = _tenPresetPoints.first;
    double minDistance = double.infinity;

    for (final point in _tenPresetPoints) {
      final double px = point['x'] as double;
      final double py = point['y'] as double;
      final double dist = (relX - px) * (relX - px) + (relY - py) * (relY - py);
      if (dist < minDistance) {
        minDistance = dist;
        nearest = point;
      }
    }

    final double snapX = nearest['x'] as double;
    final double snapY = nearest['y'] as double;

    widget.onWatermarkDragged(snapX, snapY);
    widget.onParamAdjusting('吸附预设', '${nearest['name']} (${(snapX * 100).toInt()}%, ${(snapY * 100).toInt()}%)', 1.0);

    setState(() {
      _tapFeedbackOffset = localPos;
    });

    _paramAdjustTimer?.cancel();
    _paramAdjustTimer = Timer(const Duration(milliseconds: 650), () {
      if (mounted) {
        setState(() => _tapFeedbackOffset = null);
        widget.onParamAdjustEnd();
      }
    });
  }

  void _broadcastCurrentParam() {
    if (widget.watermarkType == WatermarkType.frame) {
      double pad = widget.frameConfig.paddingRatio;
      double h = widget.frameConfig.bottomBarRatio;
      double scale = widget.frameConfig.logoScale;
      double logoX = widget.frameConfig.logoOffsetX;
      double logoY = widget.frameConfig.logoOffsetY;
      double textX = widget.frameConfig.textOffsetX;
      double textY = widget.frameConfig.textOffsetY;
      double corner = widget.frameConfig.cornerRadius;
      double shadow = widget.frameConfig.shadowOpacity;

      String name = '';
      String valStr = '';
      double progress = 0.0;
      if (_frameParamIdx == 0) {
        name = AppStrings.paramPadding;
        valStr = '${(pad * 100).toInt()}%';
        progress = pad / 0.12;
      } else if (_frameParamIdx == 1) {
        name = AppStrings.paramBottomBar;
        valStr = '${(h * 100).toInt()}%';
        progress = (h - 0.08) / (0.35 - 0.08);
      } else if (_frameParamIdx == 2) {
        name = AppStrings.paramLogoScale;
        valStr = '${(scale * 100).toInt()}%';
        progress = (scale - 0.4) / (2.2 - 0.4);
      } else if (_frameParamIdx == 3) {
        name = AppStrings.paramLogoOffsetX;
        valStr = '${logoX > 0 ? '+' : ''}${(logoX * 100).toInt()}%';
        progress = (logoX + 1.0) / 2.0;
      } else if (_frameParamIdx == 4) {
        name = AppStrings.paramLogoOffsetY;
        valStr = '${logoY > 0 ? '+' : ''}${(logoY * 100).toInt()}%';
        progress = (logoY + 1.0) / 2.0;
      } else if (_frameParamIdx == 5) {
        name = AppStrings.paramTextOffsetX;
        valStr = '${textX > 0 ? '+' : ''}${(textX * 100).toInt()}%';
        progress = (textX + 1.0) / 2.0;
      } else if (_frameParamIdx == 6) {
        name = AppStrings.paramTextOffsetY;
        valStr = '${textY > 0 ? '+' : ''}${(textY * 100).toInt()}%';
        progress = (textY + 1.0) / 2.0;
      } else if (_frameParamIdx == 7) {
        name = AppStrings.paramCornerRadius;
        valStr = '${(corner / 0.06 * 100).toInt()}%';
        progress = corner / 0.06;
      } else {
        name = AppStrings.paramShadow;
        valStr = '${(shadow * 100).toInt()}%';
        progress = shadow;
      }
      widget.onParamAdjusting(name, valStr, progress.clamp(0.0, 1.0));
    } else if (widget.activeToolIndex == 1) {
      final name = _activeAxis == 'X' ? AppStrings.paramCustomX : AppStrings.paramCustomY;
      final val = _activeAxis == 'X' ? widget.pngConfig.customX : widget.pngConfig.customY;
      widget.onParamAdjusting(name, '${(val * 100).toInt()}%', val.clamp(0.0, 1.0));
    } else {
      String name = '';
      String valStr = '';
      double progress = 0.0;
      if (_fxParamIdx == 0) {
        name = AppStrings.paramScale;
        valStr = '${(widget.pngConfig.scale * 100).toInt()}%';
        progress = widget.pngConfig.scale / 0.85;
      } else if (_fxParamIdx == 1) {
        name = AppStrings.paramOpacity;
        valStr = '${(widget.pngConfig.opacity * 100).toInt()}%';
        progress = widget.pngConfig.opacity;
      } else {
        name = AppStrings.paramRotation;
        valStr = '${widget.pngConfig.rotation.toInt()}°';
        progress = (widget.pngConfig.rotation + 180) / 360;
      }
      widget.onParamAdjusting(name, valStr, progress.clamp(0.0, 1.0));
    }
  }

  void _handleSnapseedVerticalDragUpdate(DragUpdateDetails details) {
    final dy = details.delta.dy;
    _verticalAccumulator += dy;

    _wheelFadeTimer?.cancel();
    if (!_isVerticalSwitching) {
      setState(() => _isVerticalSwitching = true);
    }

    const double stepThreshold = 24.0;
    bool changed = false;

    if (_verticalAccumulator < -stepThreshold) {
      // 向上滑动 -> 切换到下一项 (不循环，到达最后一项则停止)
      if (widget.watermarkType == WatermarkType.frame) {
        if (_frameParamIdx < 8) {
          _frameParamIdx++;
          changed = true;
        }
      } else if (widget.activeToolIndex == 1) {
        if (_activeAxis == 'X') {
          _activeAxis = 'Y';
          changed = true;
        }
      } else {
        if (_fxParamIdx < 2) {
          _fxParamIdx++;
          changed = true;
        }
      }

      if (changed) {
        _verticalAccumulator = 0.0;
        _dragVisualDy = 0.0;
        HapticFeedback.selectionClick();
        setState(() {});
        _broadcastCurrentParam();
      } else {
        _verticalAccumulator = -stepThreshold;
        setState(() {
          _dragVisualDy = -6.0; // 边缘轻微阻尼
        });
      }
    } else if (_verticalAccumulator > stepThreshold) {
      // 向下滑动 -> 切换到上一项 (不循环，到达首项则停止)
      if (widget.watermarkType == WatermarkType.frame) {
        if (_frameParamIdx > 0) {
          _frameParamIdx--;
          changed = true;
        }
      } else if (widget.activeToolIndex == 1) {
        if (_activeAxis == 'Y') {
          _activeAxis = 'X';
          changed = true;
        }
      } else {
        if (_fxParamIdx > 0) {
          _fxParamIdx--;
          changed = true;
        }
      }

      if (changed) {
        _verticalAccumulator = 0.0;
        _dragVisualDy = 0.0;
        HapticFeedback.selectionClick();
        setState(() {});
        _broadcastCurrentParam();
      } else {
        _verticalAccumulator = stepThreshold;
        setState(() {
          _dragVisualDy = 6.0; // 边缘轻微阻尼
        });
      }
    } else {
      setState(() {
        _dragVisualDy = (_verticalAccumulator * 0.3).clamp(-10.0, 10.0);
      });
    }
  }

  void _triggerMilestoneHaptic(double progress) {
    final int milestone = (progress.clamp(0.0, 1.0) * 10).round();
    if (_lastHapticMilestone != -1 && _lastHapticMilestone != milestone) {
      HapticFeedback.selectionClick();
    }
    _lastHapticMilestone = milestone;
  }

  void _handleSnapseedHorizontalDragUpdate(DragUpdateDetails details) {
    final dx = details.delta.dx;

    if (_isVerticalSwitching) {
      setState(() => _isVerticalSwitching = false);
    }

    if (widget.watermarkType == WatermarkType.frame && widget.activeToolIndex == 2) {
      double pad = widget.frameConfig.paddingRatio;
      double h = widget.frameConfig.bottomBarRatio;
      double scale = widget.frameConfig.logoScale;
      double logoX = widget.frameConfig.logoOffsetX;
      double logoY = widget.frameConfig.logoOffsetY;
      double textX = widget.frameConfig.textOffsetX;
      double textY = widget.frameConfig.textOffsetY;
      double corner = widget.frameConfig.cornerRadius;
      double shadow = widget.frameConfig.shadowOpacity;

      if (dx.abs() > 0.3) {
        if (_frameParamIdx == 0) {
          pad = (pad + dx * 0.0006).clamp(0.0, 0.12);
          widget.onFrameConfigChanged(widget.frameConfig.copyWith(paddingRatio: pad));
        } else if (_frameParamIdx == 1) {
          h = (h + dx * 0.0012).clamp(0.08, 0.35);
          widget.onFrameConfigChanged(widget.frameConfig.copyWith(bottomBarRatio: h));
        } else if (_frameParamIdx == 2) {
          scale = (scale + dx * 0.005).clamp(0.4, 2.2);
          widget.onFrameConfigChanged(widget.frameConfig.copyWith(logoScale: scale));
        } else if (_frameParamIdx == 3) {
          logoX = (logoX + dx * 0.005).clamp(-1.0, 1.0);
          widget.onFrameConfigChanged(widget.frameConfig.copyWith(logoOffsetX: logoX));
        } else if (_frameParamIdx == 4) {
          logoY = (logoY + dx * 0.005).clamp(-1.0, 1.0);
          widget.onFrameConfigChanged(widget.frameConfig.copyWith(logoOffsetY: logoY));
        } else if (_frameParamIdx == 5) {
          textX = (textX + dx * 0.005).clamp(-1.0, 1.0);
          widget.onFrameConfigChanged(widget.frameConfig.copyWith(textOffsetX: textX));
        } else if (_frameParamIdx == 6) {
          textY = (textY + dx * 0.005).clamp(-1.0, 1.0);
          widget.onFrameConfigChanged(widget.frameConfig.copyWith(textOffsetY: textY));
        } else if (_frameParamIdx == 7) {
          corner = (corner + dx * 0.0004).clamp(0.0, 0.06);
          widget.onFrameConfigChanged(widget.frameConfig.copyWith(cornerRadius: corner, roundedCorners: corner > 0));
        } else {
          shadow = (shadow + dx * 0.005).clamp(0.0, 1.0);
          widget.onFrameConfigChanged(widget.frameConfig.copyWith(shadowOpacity: shadow));
        }
      }

      String name = '';
      String valStr = '';
      double progress = 0.0;

      if (_frameParamIdx == 0) {
        name = AppStrings.paramPadding;
        valStr = '${(pad * 100).toInt()}%';
        progress = (pad / 0.12).clamp(0.0, 1.0);
      } else if (_frameParamIdx == 1) {
        name = AppStrings.paramBottomBar;
        valStr = '${(h * 100).toInt()}%';
        progress = ((h - 0.08) / (0.35 - 0.08)).clamp(0.0, 1.0);
      } else if (_frameParamIdx == 2) {
        name = AppStrings.paramLogoScale;
        valStr = '${(scale * 100).toInt()}%';
        progress = ((scale - 0.4) / (2.2 - 0.4)).clamp(0.0, 1.0);
      } else if (_frameParamIdx == 3) {
        name = AppStrings.paramLogoOffsetX;
        valStr = '${logoX > 0 ? '+' : ''}${(logoX * 100).toInt()}%';
        progress = ((logoX + 1.0) / 2.0).clamp(0.0, 1.0);
      } else if (_frameParamIdx == 4) {
        name = AppStrings.paramLogoOffsetY;
        valStr = '${logoY > 0 ? '+' : ''}${(logoY * 100).toInt()}%';
        progress = ((logoY + 1.0) / 2.0).clamp(0.0, 1.0);
      } else if (_frameParamIdx == 5) {
        name = AppStrings.paramTextOffsetX;
        valStr = '${textX > 0 ? '+' : ''}${(textX * 100).toInt()}%';
        progress = ((textX + 1.0) / 2.0).clamp(0.0, 1.0);
      } else if (_frameParamIdx == 6) {
        name = AppStrings.paramTextOffsetY;
        valStr = '${textY > 0 ? '+' : ''}${(textY * 100).toInt()}%';
        progress = ((textY + 1.0) / 2.0).clamp(0.0, 1.0);
      } else if (_frameParamIdx == 7) {
        name = AppStrings.paramCornerRadius;
        valStr = '${(corner / 0.06 * 100).toInt()}%';
        progress = (corner / 0.06).clamp(0.0, 1.0);
      } else {
        name = AppStrings.paramShadow;
        valStr = '${(shadow * 100).toInt()}%';
        progress = shadow.clamp(0.0, 1.0);
      }

      _triggerMilestoneHaptic(progress);
      widget.onParamAdjusting(name, valStr, progress);
      return;
    }

    if (widget.watermarkType == WatermarkType.floatingPng && widget.activeToolIndex == 1) {
      double newX = widget.pngConfig.customX;
      double newY = widget.pngConfig.customY;

      if (dx.abs() > 0.3) {
        final double deltaVal = dx * 0.003;
        if (_activeAxis == 'X') {
          newX = (newX + deltaVal).clamp(0.0, 1.0);
        } else {
          newY = (newY + deltaVal).clamp(0.0, 1.0);
        }
        widget.onWatermarkDragged(newX, newY);
      }

      final name = _activeAxis == 'X' ? AppStrings.paramCustomX : AppStrings.paramCustomY;
      final valStr = '${((_activeAxis == 'X' ? newX : newY) * 100).toInt()}%';
      final progress = (_activeAxis == 'X' ? newX : newY).clamp(0.0, 1.0);
      _triggerMilestoneHaptic(progress);
      widget.onParamAdjusting(name, valStr, progress);
      return;
    }

    if (widget.watermarkType == WatermarkType.floatingPng && widget.activeToolIndex == 2) {
      double scale = widget.pngConfig.scale;
      double opacity = widget.pngConfig.opacity;
      double rot = widget.pngConfig.rotation;

      if (dx.abs() > 0.3) {
        if (_fxParamIdx == 0) {
          scale = (scale + dx * 0.003).clamp(0.05, 0.85);
          widget.onPngConfigChanged(widget.pngConfig.copyWith(scale: scale));
        } else if (_fxParamIdx == 1) {
          opacity = (opacity + dx * 0.004).clamp(0.05, 1.0);
          widget.onPngConfigChanged(widget.pngConfig.copyWith(opacity: opacity));
        } else {
          rot = (rot + dx * 0.8).clamp(-180.0, 180.0);
          widget.onPngConfigChanged(widget.pngConfig.copyWith(rotation: rot));
        }
      }

      String name = '';
      String valStr = '';
      double progress = 0.0;

      if (_fxParamIdx == 0) {
        name = AppStrings.paramScale;
        valStr = '${(scale * 100).toInt()}%';
        progress = (scale / 0.85).clamp(0.0, 1.0);
      } else if (_fxParamIdx == 1) {
        name = AppStrings.paramOpacity;
        valStr = '${(opacity * 100).toInt()}%';
        progress = opacity.clamp(0.0, 1.0);
      } else {
        name = AppStrings.paramRotation;
        valStr = '${rot.toInt()}°';
        progress = ((rot + 180) / 360).clamp(0.0, 1.0);
      }
      _triggerMilestoneHaptic(progress);
      widget.onParamAdjusting(name, valStr, progress);
    }
  }

  /// 屏幕中央 Snapseed 风格滚轮 HUD（焦点位置固定在正中央，列表上下滚动通过焦点）
  Widget _buildSnapseedCenterWheel() {
    List<String> items = [];
    int selectedIndex = 0;

    if (widget.watermarkType == WatermarkType.frame) {
      items = [
        AppStrings.paramPadding,
        AppStrings.paramBottomBar,
        AppStrings.paramLogoScale,
        AppStrings.paramLogoOffsetX,
        AppStrings.paramLogoOffsetY,
        AppStrings.paramTextOffsetX,
        AppStrings.paramTextOffsetY,
        AppStrings.paramCornerRadius,
        AppStrings.paramShadow,
      ];
      selectedIndex = _frameParamIdx;
    } else if (widget.activeToolIndex == 1) {
      items = [AppStrings.paramCustomX, AppStrings.paramCustomY];
      selectedIndex = _activeAxis == 'X' ? 0 : 1;
    } else {
      items = [AppStrings.paramScale, AppStrings.paramOpacity, AppStrings.paramRotation];
      selectedIndex = _fxParamIdx;
    }

    const double itemHeight = 36.0;
    const double hudHeight = 120.0;
    const double hudWidth = 200.0;
    const double focusCenterTop = (hudHeight - itemHeight) / 2; // 42.0

    return Center(
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 180),
        opacity: _isVerticalSwitching ? 1.0 : 0.0,
        child: IgnorePointer(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                width: hudWidth,
                height: hudHeight,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.65),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.22), width: 1.0),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.4),
                      blurRadius: 20,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                // 1. 固定在正中央的焦点框（位置恒定在 Y=focusCenterTop，永不位移）
                Positioned(
                  top: focusCenterTop,
                  left: 10,
                  right: 10,
                  height: itemHeight,
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFD600).withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFFFD600), width: 1.2),
                    ),
                  ),
                ),

                // 2. 上下滚动的列表 (列表位移随当前选中项滚动，使得当前项刚好置于中央焦点框中)
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOutCubic,
                  top: focusCenterTop - selectedIndex * itemHeight + _dragVisualDy,
                  left: 0,
                  right: 0,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: List.generate(items.length, (idx) {
                      final isSelected = idx == selectedIndex;
                      return Container(
                        height: itemHeight,
                        alignment: Alignment.center,
                        child: AnimatedDefaultTextStyle(
                          duration: const Duration(milliseconds: 160),
                          style: TextStyle(
                            fontSize: isSelected ? 15 : 12,
                            fontWeight: isSelected ? FontWeight.w900 : FontWeight.w500,
                            color: isSelected ? const Color(0xFFFFD600) : Colors.white38,
                            letterSpacing: isSelected ? 0.6 : 0.2,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (isSelected) ...[
                                const Icon(Icons.arrow_right_rounded, size: 18, color: Color(0xFFFFD600)),
                                const SizedBox(width: 2),
                              ],
                              Text(items[idx]),
                            ],
                          ),
                        ),
                      );
                    }),
                  ),
                ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

  /// 倾斜背景卡片渲染（扑克牌堆叠效果）
  Widget _buildBackgroundTiltCard({
    required ImageItem item,
    required Rect renderRect,
    required double scale,
    required double offsetX,
    required double offsetY,
    required double rotation,
    required bool isDark,
  }) {
    return Positioned(
      left: renderRect.left,
      top: renderRect.top,
      width: renderRect.width,
      height: renderRect.height,
      child: Transform.translate(
        offset: Offset(offsetX, offsetY),
        child: Transform.rotate(
          angle: rotation,
          child: Transform.scale(
            scale: scale,
            child: Container(
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF141416) : const Color(0xFFD0D2DC),
                borderRadius: BorderRadius.circular(2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.2),
                    blurRadius: 10,
                    offset: Offset(offsetX * 0.4, 4),
                  ),
                ],
                border: Border.all(
                  color: isDark ? Colors.white12 : Colors.black12,
                  width: 1.0,
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: Opacity(
                opacity: 0.55,
                child: Image.memory(
                  item.bytes,
                  fit: BoxFit.cover,
                ),
              ),
            ),
          ),
        ),
      ),
    );
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
                  _buildBackgroundTiltCard(
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
                  _buildBackgroundTiltCard(
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
                          : (_isSnapseedMode ? 0.0 : _dragOffsetDx);
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
                          _handleTapPreset(details.localPosition, renderRect);
                        }
                      },
                      onHorizontalDragStart: (details) {
                        _lastHapticMilestone = -1;
                      },
                      onHorizontalDragUpdate: (details) {
                        if (_isSnapseedMode) {
                          _handleSnapseedHorizontalDragUpdate(details);
                        } else {
                          if (total <= 1) return;
                          setState(() {
                            _dragOffsetDx += details.primaryDelta ?? 0;
                          });
                        }
                      },
                      onHorizontalDragEnd: (details) {
                        _lastHapticMilestone = -1;
                        if (_isSnapseedMode) {
                          _paramAdjustTimer?.cancel();
                          _paramAdjustTimer = Timer(const Duration(milliseconds: 650), () {
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
                        if (_isSnapseedMode) {
                          _handleSnapseedVerticalDragUpdate(details);
                        }
                      },
                      onVerticalDragEnd: (details) {
                        if (_isSnapseedMode) {
                          setState(() {
                            _verticalAccumulator = 0.0;
                            _dragVisualDy = 0.0;
                          });

                          _wheelFadeTimer?.cancel();
                          _wheelFadeTimer = Timer(const Duration(milliseconds: 550), () {
                            if (mounted) {
                              setState(() => _isVerticalSwitching = false);
                            }
                          });

                          _paramAdjustTimer?.cancel();
                          _paramAdjustTimer = Timer(const Duration(milliseconds: 650), () {
                            if (mounted) widget.onParamAdjustEnd();
                          });
                        }
                      },
                      child: SizedBox(
                        width: containerW,
                        height: containerH,
                        child: CustomPaint(
                          size: Size(containerW, containerH),
                          painter: ActivePhotoPainter(
                            watermarkType: widget.watermarkType,
                            baseImage: activeItem.decodedImage,
                            rawBytes: activeItem.bytes,
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

                // 4. 屏幕中央 Snapseed 参数切换指示器 (上下滑动时浮现，焦点在正中央)
                if (_isSnapseedMode)
                  _buildSnapseedCenterWheel(),

                // 5. 点击 10 点吸附时的波纹视觉
                if (_tapFeedbackOffset != null)
                  Positioned(
                    left: _tapFeedbackOffset!.dx - 16,
                    top: _tapFeedbackOffset!.dy - 16,
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
                Positioned(
                  top: 10,
                  left: 14,
                  right: 14,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // 左侧：纯图标返回主界面按钮（带高斯背景模糊）
                      ClipOval(
                        child: BackdropFilter(
                          filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: widget.onBack,
                              child: Container(
                                width: 38,
                                height: 38,
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.38),
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white.withValues(alpha: 0.22), width: 1.0),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.25),
                                      blurRadius: 10,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: const Icon(Icons.arrow_back_rounded, size: 20, color: Colors.white),
                              ),
                            ),
                          ),
                        ),
                      ),

                      // 中间：Ultra HDR 与 动态照片 标识（带高斯背景模糊胶囊）
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (activeItem.isMotionPhoto)
                            ClipRRect(
                              borderRadius: BorderRadius.circular(20),
                              child: BackdropFilter(
                                filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                                child: Container(
                                  margin: const EdgeInsets.only(right: 6),
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.38),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(color: const Color(0xFFFFD600).withValues(alpha: 0.55), width: 1.0),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(alpha: 0.2),
                                        blurRadius: 8,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.motion_photos_on_rounded, size: 16, color: Color(0xFFFFD600)),
                                      const SizedBox(width: 4),
                                      Text(
                                        AppStrings.motionPhotoBadge,
                                        style: const TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w800,
                                          color: Color(0xFFFFD600),
                                          letterSpacing: 0.4,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          if (activeItem.isUltraHdr)
                            ClipRRect(
                              borderRadius: BorderRadius.circular(20),
                              child: BackdropFilter(
                                filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.38),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(color: const Color(0xFFFFD600).withValues(alpha: 0.55), width: 1.0),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(alpha: 0.2),
                                        blurRadius: 8,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.hdr_on_rounded, size: 16, color: Color(0xFFFFD600)),
                                      SizedBox(width: 4),
                                      Text(
                                        'Ultra HDR',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w800,
                                          color: Color(0xFFFFD600),
                                          letterSpacing: 0.4,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),

                      // 右侧：三个点菜单（带高斯背景模糊）
                      ClipOval(
                        child: BackdropFilter(
                          filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: () => _openTopRightMenu(context),
                              child: Container(
                                width: 38,
                                height: 38,
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.38),
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white.withValues(alpha: 0.22), width: 1.0),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.25),
                                      blurRadius: 10,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: const Icon(Icons.more_vert_rounded, size: 20, color: Colors.white),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
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
