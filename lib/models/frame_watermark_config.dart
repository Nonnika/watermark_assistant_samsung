import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'exif_info.dart';

enum FrameStyle {
  classicWhite, // 经典极简纯白
  obsidianDark, // 曜石质感黑
  polaroid,     // 复古拍立得大底
}

class FrameWatermarkConfig {
  final FrameStyle style;
  final Color backgroundColor;
  final Color textColor;
  final double paddingRatio;   // 四周边距比例 (0.0 ~ 0.12)
  final double bottomBarRatio; // 底部参数栏高度比例 (0.08 ~ 0.35)
  final double logoScale;      // Logo 大小比例 (0.4 ~ 2.2, 默认 1.0)
  final double logoOffsetX;    // Logo 左右偏移比例 (-1.0 ~ 1.0, 默认 0.0)
  final double logoOffsetY;    // Logo 上下偏移比例 (-1.0 ~ 1.0, 默认 0.0)
  final double textOffsetX;    // 右侧文字左右偏移比例 (-1.0 ~ 1.0, 默认 0.0)
  final double textOffsetY;    // 右侧文字上下偏移比例 (-1.0 ~ 1.0, 默认 0.0)
  final double cornerRadius;   // 照片圆角大小比例 (0.0 ~ 0.06, 默认 0.0)
  final double shadowOpacity;  // 照片外阴影不透明度 (0.0 ~ 1.0, 默认 0.0)
  final String selectedLogoId; // 'samsung_blue', 'samsung_black', 'samsung_white', 'custom_xxx'
  final Uint8List? customLogoBytes;
  final ui.Image? customLogoDecoded;
  final bool isLogoInverted;   // 用户添加的 Logo 是否反色
  final ExifInfo exifInfo;
  final bool showParameters;
  final bool showDate;
  final bool roundedCorners;
  final bool isBlurredBg;      // 是否使用图片压暗高斯模糊作为相框背景
  final bool isPaperTextureBg; // 是否使用米黄色模仿纸张纹理效果

  const FrameWatermarkConfig({
    this.style = FrameStyle.classicWhite,
    this.backgroundColor = Colors.white,
    this.textColor = const Color(0xFF1E1E24),
    this.paddingRatio = 0.035,
    this.bottomBarRatio = 0.13,
    this.logoScale = 1.0,
    this.logoOffsetX = 0.0,
    this.logoOffsetY = 0.0,
    this.textOffsetX = 0.0,
    this.textOffsetY = 0.0,
    this.cornerRadius = 0.0,
    this.shadowOpacity = 0.0,
    this.selectedLogoId = 'samsung_blue',
    this.customLogoBytes,
    this.customLogoDecoded,
    this.isLogoInverted = false,
    this.exifInfo = const ExifInfo(),
    this.showParameters = true,
    this.showDate = true,
    this.roundedCorners = false,
    this.isBlurredBg = false,
    this.isPaperTextureBg = false,
  });

  double get effectiveCornerRadius => cornerRadius > 0 ? cornerRadius : (roundedCorners ? 0.02 : 0.0);
  double get effectiveShadowOpacity => shadowOpacity > 0 ? shadowOpacity : (isBlurredBg || isPaperTextureBg ? 0.42 : 0.0);

  FrameWatermarkConfig copyWith({
    FrameStyle? style,
    Color? backgroundColor,
    Color? textColor,
    double? paddingRatio,
    double? bottomBarRatio,
    double? logoScale,
    double? logoOffsetX,
    double? logoOffsetY,
    double? textOffsetX,
    double? textOffsetY,
    double? cornerRadius,
    double? shadowOpacity,
    String? selectedLogoId,
    Uint8List? customLogoBytes,
    ui.Image? customLogoDecoded,
    bool? isLogoInverted,
    ExifInfo? exifInfo,
    bool? showParameters,
    bool? showDate,
    bool? roundedCorners,
    bool? isBlurredBg,
    bool? isPaperTextureBg,
    bool clearCustomLogo = false,
  }) {
    final newLogoId = selectedLogoId ?? this.selectedLogoId;
    final isBuiltin = !newLogoId.startsWith('custom_');

    return FrameWatermarkConfig(
      style: style ?? this.style,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      textColor: textColor ?? this.textColor,
      paddingRatio: paddingRatio ?? this.paddingRatio,
      bottomBarRatio: bottomBarRatio ?? this.bottomBarRatio,
      logoScale: logoScale ?? this.logoScale,
      logoOffsetX: logoOffsetX ?? this.logoOffsetX,
      logoOffsetY: logoOffsetY ?? this.logoOffsetY,
      textOffsetX: textOffsetX ?? this.textOffsetX,
      textOffsetY: textOffsetY ?? this.textOffsetY,
      cornerRadius: cornerRadius ?? this.cornerRadius,
      shadowOpacity: shadowOpacity ?? this.shadowOpacity,
      selectedLogoId: newLogoId,
      customLogoBytes: (clearCustomLogo || isBuiltin)
          ? customLogoBytes
          : (customLogoBytes ?? this.customLogoBytes),
      customLogoDecoded: (clearCustomLogo || isBuiltin)
          ? customLogoDecoded
          : (customLogoDecoded ?? this.customLogoDecoded),
      isLogoInverted: (clearCustomLogo || isBuiltin)
          ? (isLogoInverted ?? false)
          : (isLogoInverted ?? this.isLogoInverted),
      exifInfo: exifInfo ?? this.exifInfo,
      showParameters: showParameters ?? this.showParameters,
      showDate: showDate ?? this.showDate,
      roundedCorners: roundedCorners ?? (cornerRadius != null ? (cornerRadius > 0) : this.roundedCorners),
      isBlurredBg: isBlurredBg ?? this.isBlurredBg,
      isPaperTextureBg: isPaperTextureBg ?? this.isPaperTextureBg,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is FrameWatermarkConfig &&
        other.style == style &&
        other.backgroundColor == backgroundColor &&
        other.textColor == textColor &&
        other.paddingRatio == paddingRatio &&
        other.bottomBarRatio == bottomBarRatio &&
        other.logoScale == logoScale &&
        other.logoOffsetX == logoOffsetX &&
        other.logoOffsetY == logoOffsetY &&
        other.textOffsetX == textOffsetX &&
        other.textOffsetY == textOffsetY &&
        other.cornerRadius == cornerRadius &&
        other.shadowOpacity == shadowOpacity &&
        other.selectedLogoId == selectedLogoId &&
        other.customLogoBytes == customLogoBytes &&
        other.customLogoDecoded == customLogoDecoded &&
        other.isLogoInverted == isLogoInverted &&
        other.exifInfo == exifInfo &&
        other.showParameters == showParameters &&
        other.showDate == showDate &&
        other.roundedCorners == roundedCorners &&
        other.isBlurredBg == isBlurredBg &&
        other.isPaperTextureBg == isPaperTextureBg;
  }

  @override
  int get hashCode => Object.hashAll([
        style,
        backgroundColor,
        textColor,
        paddingRatio,
        bottomBarRatio,
        logoScale,
        logoOffsetX,
        logoOffsetY,
        textOffsetX,
        textOffsetY,
        cornerRadius,
        shadowOpacity,
        selectedLogoId,
        customLogoBytes,
        customLogoDecoded,
        isLogoInverted,
        exifInfo,
        showParameters,
        showDate,
        roundedCorners,
        isBlurredBg,
        isPaperTextureBg,
      ]);
}
