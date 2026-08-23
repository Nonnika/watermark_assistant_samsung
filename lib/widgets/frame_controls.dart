import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../models/frame_watermark_config.dart';
import 'frame_controls/frame_color_strip.dart';
import 'frame_controls/frame_exif_strip.dart';
import 'frame_controls/frame_logo_strip.dart';
import 'frame_controls/frame_snapseed_strip.dart';

/// 边框水印控制面板：负责调度 Logo、颜色、留白手势与 EXIF 四大功能条
class FrameControls extends StatelessWidget {
  final int activeToolIndex; // 0: Logo, 1: 颜色, 2: 留白参数(Snapseed), 3: EXIF
  final FrameWatermarkConfig config;
  final List<Color> photoColors;
  final Uint8List? photoBytes;
  final bool isAdjusting;
  final String adjustingParamName;
  final String adjustingParamValue;
  final double adjustingProgress;
  final ValueChanged<FrameWatermarkConfig> onChanged;

  const FrameControls({
    super.key,
    required this.activeToolIndex,
    required this.config,
    required this.photoColors,
    this.photoBytes,
    required this.isAdjusting,
    required this.adjustingParamName,
    required this.adjustingParamValue,
    required this.adjustingProgress,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final showProgressBar = isAdjusting && activeToolIndex == 2;

    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      color: Colors.transparent,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 140),
        child: showProgressBar
            ? FrameSnapseedProgressBar(
                paramName: adjustingParamName,
                paramValue: adjustingParamValue,
                progress: adjustingProgress,
              )
            : _buildActiveSlimPanel(context),
      ),
    );
  }

  Widget _buildActiveSlimPanel(BuildContext context) {
    Widget content;
    switch (activeToolIndex) {
      case 0:
        content = FrameLogoStrip(
          config: config,
          onChanged: onChanged,
        );
        break;
      case 1:
        content = FrameColorStrip(
          config: config,
          photoColors: photoColors,
          photoBytes: photoBytes,
          onChanged: onChanged,
        );
        break;
      case 2:
        content = const FrameSnapseedStrip();
        break;
      case 3:
      default:
        content = FrameExifStrip(
          config: config,
          onChanged: onChanged,
        );
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
        key: ValueKey('frame_tool_strip_$activeToolIndex'),
        child: content,
      ),
    );
  }
}
