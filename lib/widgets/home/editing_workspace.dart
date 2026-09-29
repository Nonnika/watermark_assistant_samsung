import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../../models/frame_watermark_config.dart';
import '../../models/image_item.dart';
import '../../models/watermark_config.dart';
import '../card_stack_preview.dart';
import '../floating_controls.dart';
import '../frame_controls.dart';

/// 编辑工作区：全屏照片预览卡片 + 底部工具操作条 (Frame / Floating 双模式切换)
/// 纯展示装配组件，所有应用状态与业务回调仍由 HomeScreen 持有。
class EditingWorkspace extends StatelessWidget {
  final List<ImageItem> images;
  final int selectedImageIndex;
  final WatermarkType watermarkType;
  final int activeToolIndex;
  final ui.Image? decodedWatermark;
  final WatermarkConfig activePngConfig;
  final ui.Image? decodedBrandLogo;
  final FrameWatermarkConfig activeFrameConfig;
  final bool isIndividualMode;
  final bool isAdjusting;
  final String adjustingParamName;
  final String adjustingParamValue;
  final double adjustingProgress;
  final Uint8List? watermarkBytes;
  final String watermarkName;
  final String? presetWatermarkId;
  final List<Color> photoPalette;

  final ValueChanged<bool> onToggleIndividualMode;
  final ValueChanged<int> onIndexChanged;
  final void Function(double relX, double relY) onWatermarkDragged;
  final ValueChanged<WatermarkConfig> onPngConfigChanged;
  final ValueChanged<FrameWatermarkConfig> onFrameConfigChanged;
  final void Function(FrameWatermarkConfig newCfg) onFrameControlsChanged;
  final void Function(String name, String valStr, double progress) onParamAdjusting;
  final VoidCallback onParamAdjustEnd;
  final void Function(bool exportAll) onExport;
  final VoidCallback onBack;
  final VoidCallback onPickCustomWatermark;
  final VoidCallback onPickPresetWatermark;

  const EditingWorkspace({
    super.key,
    required this.images,
    required this.selectedImageIndex,
    required this.watermarkType,
    required this.activeToolIndex,
    required this.decodedWatermark,
    required this.activePngConfig,
    required this.decodedBrandLogo,
    required this.activeFrameConfig,
    required this.isIndividualMode,
    required this.isAdjusting,
    required this.adjustingParamName,
    required this.adjustingParamValue,
    required this.adjustingProgress,
    required this.watermarkBytes,
    required this.watermarkName,
    required this.presetWatermarkId,
    required this.photoPalette,
    required this.onToggleIndividualMode,
    required this.onIndexChanged,
    required this.onWatermarkDragged,
    required this.onPngConfigChanged,
    required this.onFrameConfigChanged,
    required this.onFrameControlsChanged,
    required this.onParamAdjusting,
    required this.onParamAdjustEnd,
    required this.onExport,
    required this.onBack,
    required this.onPickCustomWatermark,
    required this.onPickPresetWatermark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF000000),
      child: Column(
        children: [
          // 1. 照片全屏预览区 (纯黑背景，占满全屏)
          Expanded(
            child: CardStackPreview(
              images: images,
              currentIndex: selectedImageIndex,
              watermarkType: watermarkType,
              activeToolIndex: activeToolIndex,
              watermarkImage: decodedWatermark,
              pngConfig: activePngConfig,
              logoImage: decodedBrandLogo,
              frameConfig: activeFrameConfig,
              isIndividualMode: isIndividualMode,
              onToggleIndividualMode: onToggleIndividualMode,
              onIndexChanged: onIndexChanged,
              onWatermarkDragged: onWatermarkDragged,
              onPngConfigChanged: onPngConfigChanged,
              onFrameConfigChanged: onFrameConfigChanged,
              onParamAdjusting: onParamAdjusting,
              onParamAdjustEnd: onParamAdjustEnd,
              onExport: onExport,
              onBack: onBack,
            ),
          ),

          // 2. 超薄单行工具操作条 (纯黑背景，深灰胶囊，浅灰选中，平滑切换)
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 260),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) {
              return FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 0.2),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              );
            },
            child: watermarkType == WatermarkType.frame
                ? KeyedSubtree(
                    key: const ValueKey('frame_controls_container'),
                    child: FrameControls(
                      activeToolIndex: activeToolIndex,
                      config: activeFrameConfig,
                      photoColors: photoPalette,
                      photoBytes: images.isNotEmpty && selectedImageIndex < images.length
                          ? images[selectedImageIndex].bytes
                          : null,
                      isAdjusting: isAdjusting,
                      adjustingParamName: adjustingParamName,
                      adjustingParamValue: adjustingParamValue,
                      adjustingProgress: adjustingProgress,
                      onChanged: onFrameControlsChanged,
                    ),
                  )
                : KeyedSubtree(
                    key: const ValueKey('floating_controls_container'),
                    child: FloatingControls(
                      activeToolIndex: activeToolIndex,
                      config: activePngConfig,
                      watermarkBytes: watermarkBytes,
                      decodedWatermark: decodedWatermark,
                      watermarkName: watermarkName,
                      presetWatermarkId: presetWatermarkId,
                      isAdjusting: isAdjusting,
                      adjustingParamName: adjustingParamName,
                      adjustingParamValue: adjustingParamValue,
                      adjustingProgress: adjustingProgress,
                      onPickCustomWatermark: onPickCustomWatermark,
                      onPickPresetWatermark: onPickPresetWatermark,
                      onChanged: (newCfg) => onPngConfigChanged(newCfg),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
