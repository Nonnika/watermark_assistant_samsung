import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../models/watermark_config.dart';
import '../../services/app_strings.dart';

/// 屏幕中央的参数滚轮：焦点固定，参数随上下手势经过焦点。
class SnapseedWheelHud extends StatelessWidget {
  final WatermarkType watermarkType;
  final int activeToolIndex;
  final String activeAxis;
  final int frameParamIdx;
  final int fxParamIdx;
  final bool visible;
  final double dragVisualDy;

  const SnapseedWheelHud({
    super.key,
    required this.watermarkType,
    required this.activeToolIndex,
    required this.activeAxis,
    required this.frameParamIdx,
    required this.fxParamIdx,
    required this.visible,
    required this.dragVisualDy,
  });

  @override
  Widget build(BuildContext context) {
    List<String> items;
    int selectedIndex;

    if (watermarkType == WatermarkType.frame) {
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
      selectedIndex = frameParamIdx;
    } else if (activeToolIndex == 1) {
      items = [AppStrings.paramCustomX, AppStrings.paramCustomY];
      selectedIndex = activeAxis == 'X' ? 0 : 1;
    } else {
      items = [
        AppStrings.paramScale,
        AppStrings.paramOpacity,
        AppStrings.paramRotation,
      ];
      selectedIndex = fxParamIdx;
    }

    const itemHeight = 40.0;
    const hudHeight = 136.0;
    const focusTop = (hudHeight - itemHeight) / 2;
    const accent = Color(0xFFFFDE59);
    final radius = BorderRadius.circular(12);

    return Center(
      child: IgnorePointer(
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 180),
          opacity: visible ? 1 : 0,
          child: DecoratedBox(
            // 阴影放在裁剪外，避免被磨砂卡片自身裁掉。
            decoration: BoxDecoration(
              borderRadius: radius,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.16),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: radius,
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Container(
                  width: 216,
                  height: hudHeight,
                  decoration: BoxDecoration(
                    borderRadius: radius,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        const Color(0xFF262629).withValues(alpha: 0.90),
                        const Color(0xFF1D1D20).withValues(alpha: 0.92),
                      ],
                    ),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.09),
                    ),
                  ),
                  child: Stack(
                    children: [
                      Positioned(
                        top: focusTop,
                        left: 12,
                        right: 12,
                        height: itemHeight,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.08),
                            ),
                          ),
                        ),
                      ),
                      // 只让滚轮文字在边缘渐隐，焦点框和卡片轮廓保持清晰。
                      Positioned.fill(
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
                            stops: [0, 0.30, 0.70, 1],
                          ).createShader(bounds),
                          child: Stack(
                            children: [
                              AnimatedPositioned(
                                duration: const Duration(milliseconds: 200),
                                curve: Curves.easeOutCubic,
                                top:
                                    focusTop -
                                    selectedIndex * itemHeight +
                                    dragVisualDy,
                                left: 20,
                                right: 20,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: List.generate(items.length, (idx) {
                                    final isSelected = idx == selectedIndex;
                                    return SizedBox(
                                      height: itemHeight,
                                      child: Center(
                                        child: AnimatedDefaultTextStyle(
                                          duration: const Duration(
                                            milliseconds: 160,
                                          ),
                                          style: TextStyle(
                                            fontSize: isSelected ? 14 : 12,
                                            fontWeight: isSelected
                                                ? FontWeight.w700
                                                : FontWeight.w500,
                                            color: isSelected
                                                ? accent
                                                : Colors.white60,
                                          ),
                                          child: Text(
                                            items[idx],
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            textAlign: TextAlign.center,
                                          ),
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
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
