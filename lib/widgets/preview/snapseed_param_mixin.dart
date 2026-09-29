import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/watermark_config.dart';
import '../../services/app_strings.dart';
import '../card_stack_preview.dart';

/// Snapseed 风格滚轮调参行为：参数项切换（竖直拖拽）、参数值调整（水平拖拽）、
/// 10 点吸附预设与 HUD 进度广播。
///
/// 成员使用公开命名：这些成员会被宿主 `_CardStackPreviewState`（不同库）直接访问，
/// Dart 的下划线私有符号按库隔离，无法跨库共享。
mixin SnapseedParamHandling on State<CardStackPreview> {
  // Snapseed 当前参数模式
  String activeAxis = 'X'; // Floating Pos: 'X' or 'Y'
  int frameParamIdx = 0; // Frame Params: 0: 留白, 1: 参数栏高度
  int fxParamIdx = 0; // Floating FX: 0: 缩放, 1: 不透明度, 2: 旋转角度
  bool isVerticalSwitching = false;
  double verticalAccumulator = 0.0;
  double dragVisualDy = 0.0;
  int lastHapticMilestone = -1;
  Offset? tapFeedbackOffset;
  Timer? paramAdjustTimer;
  Timer? wheelFadeTimer;

  bool get isSnapseedMode {
    if (widget.watermarkType == WatermarkType.frame) {
      return widget.activeToolIndex == 2; // 相框留白与高度
    } else {
      return widget.activeToolIndex == 1 || widget.activeToolIndex == 2; // 坐标 或 尺寸特效
    }
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

  void handleTapPreset(Offset localPos, Rect imageRect) {
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
      tapFeedbackOffset = localPos;
    });

    paramAdjustTimer?.cancel();
    paramAdjustTimer = Timer(const Duration(milliseconds: 650), () {
      if (mounted) {
        setState(() => tapFeedbackOffset = null);
        widget.onParamAdjustEnd();
      }
    });
  }

  void broadcastCurrentParam() {
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
      if (frameParamIdx == 0) {
        name = AppStrings.paramPadding;
        valStr = '${(pad * 100).toInt()}%';
        progress = pad / 0.12;
      } else if (frameParamIdx == 1) {
        name = AppStrings.paramBottomBar;
        valStr = '${(h * 100).toInt()}%';
        progress = (h - 0.08) / (0.35 - 0.08);
      } else if (frameParamIdx == 2) {
        name = AppStrings.paramLogoScale;
        valStr = '${(scale * 100).toInt()}%';
        progress = (scale - 0.4) / (2.2 - 0.4);
      } else if (frameParamIdx == 3) {
        name = AppStrings.paramLogoOffsetX;
        valStr = '${logoX > 0 ? '+' : ''}${(logoX * 100).toInt()}%';
        progress = (logoX + 1.0) / 2.0;
      } else if (frameParamIdx == 4) {
        name = AppStrings.paramLogoOffsetY;
        valStr = '${logoY > 0 ? '+' : ''}${(logoY * 100).toInt()}%';
        progress = (logoY + 1.0) / 2.0;
      } else if (frameParamIdx == 5) {
        name = AppStrings.paramTextOffsetX;
        valStr = '${textX > 0 ? '+' : ''}${(textX * 100).toInt()}%';
        progress = (textX + 1.0) / 2.0;
      } else if (frameParamIdx == 6) {
        name = AppStrings.paramTextOffsetY;
        valStr = '${textY > 0 ? '+' : ''}${(textY * 100).toInt()}%';
        progress = (textY + 1.0) / 2.0;
      } else if (frameParamIdx == 7) {
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
      final name = activeAxis == 'X' ? AppStrings.paramCustomX : AppStrings.paramCustomY;
      final val = activeAxis == 'X' ? widget.pngConfig.customX : widget.pngConfig.customY;
      widget.onParamAdjusting(name, '${(val * 100).toInt()}%', val.clamp(0.0, 1.0));
    } else {
      String name = '';
      String valStr = '';
      double progress = 0.0;
      if (fxParamIdx == 0) {
        name = AppStrings.paramScale;
        valStr = '${(widget.pngConfig.scale * 100).toInt()}%';
        progress = widget.pngConfig.scale / 0.85;
      } else if (fxParamIdx == 1) {
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

  void handleSnapseedVerticalDragUpdate(DragUpdateDetails details) {
    final dy = details.delta.dy;
    verticalAccumulator += dy;

    wheelFadeTimer?.cancel();
    if (!isVerticalSwitching) {
      setState(() => isVerticalSwitching = true);
    }

    const double stepThreshold = 24.0;
    bool changed = false;

    if (verticalAccumulator < -stepThreshold) {
      // 向上滑动 -> 切换到下一项 (不循环，到达最后一项则停止)
      if (widget.watermarkType == WatermarkType.frame) {
        if (frameParamIdx < 8) {
          frameParamIdx++;
          changed = true;
        }
      } else if (widget.activeToolIndex == 1) {
        if (activeAxis == 'X') {
          activeAxis = 'Y';
          changed = true;
        }
      } else {
        if (fxParamIdx < 2) {
          fxParamIdx++;
          changed = true;
        }
      }

      if (changed) {
        verticalAccumulator = 0.0;
        dragVisualDy = 0.0;
        HapticFeedback.selectionClick();
        setState(() {});
        broadcastCurrentParam();
      } else {
        verticalAccumulator = -stepThreshold;
        setState(() {
          dragVisualDy = -6.0; // 边缘轻微阻尼
        });
      }
    } else if (verticalAccumulator > stepThreshold) {
      // 向下滑动 -> 切换到上一项 (不循环，到达首项则停止)
      if (widget.watermarkType == WatermarkType.frame) {
        if (frameParamIdx > 0) {
          frameParamIdx--;
          changed = true;
        }
      } else if (widget.activeToolIndex == 1) {
        if (activeAxis == 'Y') {
          activeAxis = 'X';
          changed = true;
        }
      } else {
        if (fxParamIdx > 0) {
          fxParamIdx--;
          changed = true;
        }
      }

      if (changed) {
        verticalAccumulator = 0.0;
        dragVisualDy = 0.0;
        HapticFeedback.selectionClick();
        setState(() {});
        broadcastCurrentParam();
      } else {
        verticalAccumulator = stepThreshold;
        setState(() {
          dragVisualDy = 6.0; // 边缘轻微阻尼
        });
      }
    } else {
      setState(() {
        dragVisualDy = (verticalAccumulator * 0.3).clamp(-10.0, 10.0);
      });
    }
  }

  void _triggerMilestoneHaptic(double progress) {
    final int milestone = (progress.clamp(0.0, 1.0) * 10).round();
    if (lastHapticMilestone != -1 && lastHapticMilestone != milestone) {
      HapticFeedback.selectionClick();
    }
    lastHapticMilestone = milestone;
  }

  void handleSnapseedHorizontalDragUpdate(DragUpdateDetails details) {
    final dx = details.delta.dx;

    if (isVerticalSwitching) {
      setState(() => isVerticalSwitching = false);
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
        if (frameParamIdx == 0) {
          pad = (pad + dx * 0.0006).clamp(0.0, 0.12);
          widget.onFrameConfigChanged(widget.frameConfig.copyWith(paddingRatio: pad));
        } else if (frameParamIdx == 1) {
          h = (h + dx * 0.0012).clamp(0.08, 0.35);
          widget.onFrameConfigChanged(widget.frameConfig.copyWith(bottomBarRatio: h));
        } else if (frameParamIdx == 2) {
          scale = (scale + dx * 0.005).clamp(0.4, 2.2);
          widget.onFrameConfigChanged(widget.frameConfig.copyWith(logoScale: scale));
        } else if (frameParamIdx == 3) {
          logoX = (logoX + dx * 0.005).clamp(-1.0, 1.0);
          widget.onFrameConfigChanged(widget.frameConfig.copyWith(logoOffsetX: logoX));
        } else if (frameParamIdx == 4) {
          logoY = (logoY + dx * 0.005).clamp(-1.0, 1.0);
          widget.onFrameConfigChanged(widget.frameConfig.copyWith(logoOffsetY: logoY));
        } else if (frameParamIdx == 5) {
          textX = (textX + dx * 0.005).clamp(-1.0, 1.0);
          widget.onFrameConfigChanged(widget.frameConfig.copyWith(textOffsetX: textX));
        } else if (frameParamIdx == 6) {
          textY = (textY + dx * 0.005).clamp(-1.0, 1.0);
          widget.onFrameConfigChanged(widget.frameConfig.copyWith(textOffsetY: textY));
        } else if (frameParamIdx == 7) {
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

      if (frameParamIdx == 0) {
        name = AppStrings.paramPadding;
        valStr = '${(pad * 100).toInt()}%';
        progress = (pad / 0.12).clamp(0.0, 1.0);
      } else if (frameParamIdx == 1) {
        name = AppStrings.paramBottomBar;
        valStr = '${(h * 100).toInt()}%';
        progress = ((h - 0.08) / (0.35 - 0.08)).clamp(0.0, 1.0);
      } else if (frameParamIdx == 2) {
        name = AppStrings.paramLogoScale;
        valStr = '${(scale * 100).toInt()}%';
        progress = ((scale - 0.4) / (2.2 - 0.4)).clamp(0.0, 1.0);
      } else if (frameParamIdx == 3) {
        name = AppStrings.paramLogoOffsetX;
        valStr = '${logoX > 0 ? '+' : ''}${(logoX * 100).toInt()}%';
        progress = ((logoX + 1.0) / 2.0).clamp(0.0, 1.0);
      } else if (frameParamIdx == 4) {
        name = AppStrings.paramLogoOffsetY;
        valStr = '${logoY > 0 ? '+' : ''}${(logoY * 100).toInt()}%';
        progress = ((logoY + 1.0) / 2.0).clamp(0.0, 1.0);
      } else if (frameParamIdx == 5) {
        name = AppStrings.paramTextOffsetX;
        valStr = '${textX > 0 ? '+' : ''}${(textX * 100).toInt()}%';
        progress = ((textX + 1.0) / 2.0).clamp(0.0, 1.0);
      } else if (frameParamIdx == 6) {
        name = AppStrings.paramTextOffsetY;
        valStr = '${textY > 0 ? '+' : ''}${(textY * 100).toInt()}%';
        progress = ((textY + 1.0) / 2.0).clamp(0.0, 1.0);
      } else if (frameParamIdx == 7) {
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
        if (activeAxis == 'X') {
          newX = (newX + deltaVal).clamp(0.0, 1.0);
        } else {
          newY = (newY + deltaVal).clamp(0.0, 1.0);
        }
        widget.onWatermarkDragged(newX, newY);
      }

      final name = activeAxis == 'X' ? AppStrings.paramCustomX : AppStrings.paramCustomY;
      final valStr = '${((activeAxis == 'X' ? newX : newY) * 100).toInt()}%';
      final progress = (activeAxis == 'X' ? newX : newY).clamp(0.0, 1.0);
      _triggerMilestoneHaptic(progress);
      widget.onParamAdjusting(name, valStr, progress);
      return;
    }

    if (widget.watermarkType == WatermarkType.floatingPng && widget.activeToolIndex == 2) {
      double scale = widget.pngConfig.scale;
      double opacity = widget.pngConfig.opacity;
      double rot = widget.pngConfig.rotation;

      if (dx.abs() > 0.3) {
        if (fxParamIdx == 0) {
          scale = (scale + dx * 0.003).clamp(0.05, 0.85);
          widget.onPngConfigChanged(widget.pngConfig.copyWith(scale: scale));
        } else if (fxParamIdx == 1) {
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

      if (fxParamIdx == 0) {
        name = AppStrings.paramScale;
        valStr = '${(scale * 100).toInt()}%';
        progress = (scale / 0.85).clamp(0.0, 1.0);
      } else if (fxParamIdx == 1) {
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
}
