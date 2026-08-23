import 'package:flutter/material.dart';

enum WatermarkType {
  frame, // 第一种：边框型 EXIF 水印
  floatingPng, // 第二种：浮动 PNG 水印
}

enum WatermarkMode {
  single, // 单水印定位
  tiled,  // 全屏矩阵平铺
}

enum WatermarkPosition {
  topLeft,
  topCenter,
  topRight,
  centerLeft,
  center,
  centerRight,
  bottomLeft,
  bottomCenter,
  bottomRight,
  custom,
}

extension WatermarkPositionExt on WatermarkPosition {
  String get label {
    switch (this) {
      case WatermarkPosition.topLeft:
        return '左上';
      case WatermarkPosition.topCenter:
        return '中上';
      case WatermarkPosition.topRight:
        return '右上';
      case WatermarkPosition.centerLeft:
        return '左中';
      case WatermarkPosition.center:
        return '正中';
      case WatermarkPosition.centerRight:
        return '右中';
      case WatermarkPosition.bottomLeft:
        return '左下';
      case WatermarkPosition.bottomCenter:
        return '中下';
      case WatermarkPosition.bottomRight:
        return '右下';
      case WatermarkPosition.custom:
        return '自定义';
    }
  }

  Alignment get alignment {
    switch (this) {
      case WatermarkPosition.topLeft:
        return Alignment.topLeft;
      case WatermarkPosition.topCenter:
        return Alignment.topCenter;
      case WatermarkPosition.topRight:
        return Alignment.topRight;
      case WatermarkPosition.centerLeft:
        return Alignment.centerLeft;
      case WatermarkPosition.center:
        return Alignment.center;
      case WatermarkPosition.centerRight:
        return Alignment.centerRight;
      case WatermarkPosition.bottomLeft:
        return Alignment.bottomLeft;
      case WatermarkPosition.bottomCenter:
        return Alignment.bottomCenter;
      case WatermarkPosition.bottomRight:
        return Alignment.bottomRight;
      case WatermarkPosition.custom:
        return Alignment.center;
    }
  }
}

class WatermarkConfig {
  final WatermarkMode mode;
  final WatermarkPosition position;
  final double scale; // 0.05 ~ 0.90 (水印尺寸占目标图比例，等比例缩放)
  final double opacity; // 0.05 ~ 1.0 (不透明度)
  final double rotation; // 旋转角度 (-180° ~ 180°)
  final double margin; // 边缘边距比例 (0.0 ~ 0.20)
  
  // 自定义精确坐标 (0.0 ~ 1.0, 相对主图左上角)
  final double customX;
  final double customY;
  final bool isCustomDrag;

  // 反色开关 (将 PNG 黑白/色彩一键反转，完美适应深浅底图)
  final bool isInverted;

  // 平铺模式参数
  final double tileSpacingX; // 水平间距 (0.1 ~ 1.0)
  final double tileSpacingY; // 垂直间距 (0.1 ~ 1.0)
  final bool tileStaggered;  // 交错平铺

  const WatermarkConfig({
    this.mode = WatermarkMode.single,
    this.position = WatermarkPosition.bottomRight,
    this.scale = 0.25,
    this.opacity = 0.90,
    this.rotation = 0.0,
    this.margin = 0.04,
    this.customX = 0.8,
    this.customY = 0.8,
    this.isCustomDrag = false,
    this.isInverted = false,
    this.tileSpacingX = 0.35,
    this.tileSpacingY = 0.35,
    this.tileStaggered = true,
  });

  WatermarkConfig copyWith({
    WatermarkMode? mode,
    WatermarkPosition? position,
    double? scale,
    double? opacity,
    double? rotation,
    double? margin,
    double? customX,
    double? customY,
    bool? isCustomDrag,
    bool? isInverted,
    double? tileSpacingX,
    double? tileSpacingY,
    bool? tileStaggered,
  }) {
    return WatermarkConfig(
      mode: mode ?? this.mode,
      position: position ?? this.position,
      scale: scale ?? this.scale,
      opacity: opacity ?? this.opacity,
      rotation: rotation ?? this.rotation,
      margin: margin ?? this.margin,
      customX: customX ?? this.customX,
      customY: customY ?? this.customY,
      isCustomDrag: isCustomDrag ?? this.isCustomDrag,
      isInverted: isInverted ?? this.isInverted,
      tileSpacingX: tileSpacingX ?? this.tileSpacingX,
      tileSpacingY: tileSpacingY ?? this.tileSpacingY,
      tileStaggered: tileStaggered ?? this.tileStaggered,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is WatermarkConfig &&
        other.mode == mode &&
        other.position == position &&
        other.scale == scale &&
        other.opacity == opacity &&
        other.rotation == rotation &&
        other.margin == margin &&
        other.customX == customX &&
        other.customY == customY &&
        other.isCustomDrag == isCustomDrag &&
        other.isInverted == isInverted &&
        other.tileSpacingX == tileSpacingX &&
        other.tileSpacingY == tileSpacingY &&
        other.tileStaggered == tileStaggered;
  }

  @override
  int get hashCode => Object.hash(
        mode,
        position,
        scale,
        opacity,
        rotation,
        margin,
        customX,
        customY,
        isCustomDrag,
        isInverted,
        tileSpacingX,
        tileSpacingY,
        tileStaggered,
      );
}
