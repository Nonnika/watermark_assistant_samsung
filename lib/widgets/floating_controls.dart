import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../models/watermark_config.dart';

class FloatingControls extends StatelessWidget {
  final int activeToolIndex; // 0: 来源, 1: 坐标(Snapseed), 2: 尺寸特效(Snapseed)
  final WatermarkConfig config;
  final Uint8List? watermarkBytes;
  final ui.Image? decodedWatermark;
  final String watermarkName;
  final String? presetWatermarkId;
  final bool isAdjusting;
  final String adjustingParamName;
  final String adjustingParamValue;
  final double adjustingProgress;
  final VoidCallback onPickCustomWatermark;
  final VoidCallback onPickPresetWatermark;
  final ValueChanged<WatermarkConfig> onChanged;

  const FloatingControls({
    super.key,
    required this.activeToolIndex,
    required this.config,
    required this.watermarkBytes,
    required this.decodedWatermark,
    required this.watermarkName,
    required this.presetWatermarkId,
    this.isAdjusting = false,
    this.adjustingParamName = '',
    this.adjustingParamValue = '',
    this.adjustingProgress = 0.0,
    required this.onPickCustomWatermark,
    required this.onPickPresetWatermark,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final showProgressBar = isAdjusting && (activeToolIndex == 1 || activeToolIndex == 2);

    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      color: Colors.transparent,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 140),
        child: showProgressBar
            ? _buildSnapseedProgressBar()
            : _buildActiveSlimPanel(context),
      ),
    );
  }

  /// 用户操作时嵌入在面板内的 Snapseed 进度条 (黄色焦点)
  Widget _buildSnapseedProgressBar() {
    const accentYellow = Color(0xFFFFD600);

    return Padding(
      key: const ValueKey('embedded_snapseed_bar_floating'),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                adjustingParamName,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: accentYellow),
              ),
              Text(
                adjustingParamValue,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: accentYellow),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: adjustingProgress.clamp(0.0, 1.0),
              backgroundColor: const Color(0xFF2C2C2E),
              valueColor: const AlwaysStoppedAnimation<Color>(accentYellow),
              minHeight: 4.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveSlimPanel(BuildContext context) {
    Widget content;
    switch (activeToolIndex) {
      case 0:
        content = _buildSourceStrip(context);
        break;
      case 1:
        content = _buildPositionStrip(context);
        break;
      case 2:
      default:
        content = _buildEffectsStrip(context);
        break;
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0.04, 0),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        );
      },
      child: KeyedSubtree(
        key: ValueKey('floating_tool_strip_$activeToolIndex'),
        child: content,
      ),
    );
  }

  /// 选项卡 0: 水印来源单行横条 (深灰胶囊)
  Widget _buildSourceStrip(BuildContext context) {
    return Row(
      key: const ValueKey('slim_floating_source'),
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E22),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white24),
          ),
          padding: const EdgeInsets.all(3),
          child: watermarkBytes != null
              ? Image.memory(watermarkBytes!, fit: BoxFit.contain)
              : const Icon(Icons.image_not_supported_rounded, color: Colors.white54, size: 16),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            watermarkName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(width: 8),
        InkWell(
          onTap: onPickPresetWatermark,
          borderRadius: BorderRadius.circular(13),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E22),
              borderRadius: BorderRadius.circular(13),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.auto_awesome_rounded, size: 14, color: Colors.white70),
                SizedBox(width: 4),
                Text('模版', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white70)),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        InkWell(
          onTap: onPickCustomWatermark,
          borderRadius: BorderRadius.circular(13),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFE2E2E8),
              borderRadius: BorderRadius.circular(13),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.file_upload_rounded, size: 15, color: Color(0xFF111113)),
                SizedBox(width: 4),
                Text(
                  '导入PNG',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: Color(0xFF111113)),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// 选项卡 1: 坐标 Snapseed 提示与重置
  Widget _buildPositionStrip(BuildContext context) {
    return Row(
      key: const ValueKey('slim_floating_pos'),
      children: [
        const Icon(Icons.touch_app_rounded, size: 18, color: Color(0xFFFFD600)),
        const SizedBox(width: 8),
        const Expanded(
          child: Text(
            '在照片上：上下滑切X/Y，左右滑调坐标，轻触吸附',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              color: Colors.white70,
            ),
          ),
        ),
        const SizedBox(width: 8),
        InkWell(
          onTap: () {
            onChanged(
              config.copyWith(
                customX: 0.85,
                customY: 0.85,
                isCustomDrag: true,
                position: WatermarkPosition.bottomRight,
              ),
            );
          },
          borderRadius: BorderRadius.circular(13),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E22),
              borderRadius: BorderRadius.circular(13),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.replay_rounded, size: 14, color: Colors.white70),
                SizedBox(width: 4),
                Text('重置右下', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white70)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// 选项卡 2: 尺寸与特效 (深灰胶囊，浅灰选中)
  Widget _buildEffectsStrip(BuildContext context) {
    return Row(
      key: const ValueKey('slim_floating_fx'),
      children: [
        const Icon(Icons.tune_rounded, size: 18, color: Color(0xFFFFD600)),
        const SizedBox(width: 8),
        const Expanded(
          child: Text(
            '在照片上：上下滑切参数，左右滑增减',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              color: Colors.white70,
            ),
          ),
        ),
        const SizedBox(width: 8),
        InkWell(
          onTap: () => onChanged(config.copyWith(isInverted: !config.isInverted)),
          borderRadius: BorderRadius.circular(13),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: config.isInverted ? const Color(0xFFE2E2E8) : const Color(0xFF1E1E22),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.invert_colors_rounded,
                  size: 15,
                  color: config.isInverted ? const Color(0xFF111113) : Colors.white60,
                ),
                const SizedBox(width: 4),
                Text(
                  '反色',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: config.isInverted ? const Color(0xFF111113) : Colors.white60,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
