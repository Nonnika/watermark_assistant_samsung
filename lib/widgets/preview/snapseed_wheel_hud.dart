import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../../models/watermark_config.dart';
import '../../services/app_strings.dart';

/// 屏幕中央 Snapseed 风格滚轮 HUD（焦点位置固定在正中央，列表上下滚动通过焦点）
class SnapseedWheelHud extends StatelessWidget {
  final WatermarkType watermarkType;
  final int activeToolIndex;
  final String activeAxis; // Floating Pos: 'X' or 'Y'
  final int frameParamIdx; // Frame Params: 0: 留白, 1: 参数栏高度
  final int fxParamIdx; // Floating FX: 0: 缩放, 1: 不透明度, 2: 旋转角度
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
    List<String> items = [];
    int selectedIndex = 0;

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
      items = [AppStrings.paramScale, AppStrings.paramOpacity, AppStrings.paramRotation];
      selectedIndex = fxParamIdx;
    }

    const double itemHeight = 36.0;
    const double hudHeight = 120.0;
    const double hudWidth = 200.0;
    const double focusCenterTop = (hudHeight - itemHeight) / 2; // 42.0

    return Center(
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 180),
        opacity: visible ? 1.0 : 0.0,
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
                  top: focusCenterTop - selectedIndex * itemHeight + dragVisualDy,
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
}
