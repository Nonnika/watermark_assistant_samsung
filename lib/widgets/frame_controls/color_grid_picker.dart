import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../one_ui_pressable.dart';
import '../../models/frame_watermark_config.dart';
import '../../services/app_strings.dart';
import '../../utils/blurred_dialog_helper.dart';

/// 方格化色板底部弹层：照片自动色板 + 单色/复古/莫兰迪/品牌/暗色五组预设，
/// 顶部横幅实时预览当前「颜色 / 模糊 / 纸张纹理」状态
class ColorGridPicker {
  ColorGridPicker._();

  static void show(
    BuildContext context, {
    required FrameWatermarkConfig config,
    required List<Color> photoColors,
    required Uint8List? photoBytes,
    required ValueChanged<FrameWatermarkConfig> onChanged,
  }) {
    final paletteGroups = <String, List<Color>>{
      AppStrings.paletteMonochrome: const [
        Color(0xFFFFFFFF),
        Color(0xFFF2F2F7),
        Color(0xFFE5E5EA),
        Color(0xFFD1D1D6),
        Color(0xFF8E8E93),
        Color(0xFF48484A),
        Color(0xFF2C2C2E),
        Color(0xFF1C1C1E),
        Color(0xFF000000),
      ],
      AppStrings.paletteVintage: const [
        Color(0xFFFAF8F5),
        Color(0xFFF7F4EB),
        Color(0xFFECE7DE),
        Color(0xFFDDD5C7),
        Color(0xFFC8BCAC),
        Color(0xFFB0A290),
        Color(0xFF8D7B68),
        Color(0xFF5D4E3C),
        Color(0xFF382F24),
      ],
      AppStrings.paletteMorandi: const [
        Color(0xFFE0BBE4),
        Color(0xFF957DAD),
        Color(0xFFD291BC),
        Color(0xFFFEC8D8),
        Color(0xFFFFDFD3),
        Color(0xFFB5EAD7),
        Color(0xFFC7CEEA),
        Color(0xFFE2F0CB),
        Color(0xFFFFDAC1),
      ],
      AppStrings.paletteBrands: const [
        Color(0xFF0381FE), // 三星蓝
        Color(0xFFE4002B), // 徕卡红
        Color(0xFFFFAA00), // 柯达黄
        Color(0xFF00A3E0), // 蔡司蓝
        Color(0xFF43B02A), // 富士绿
        Color(0xFFFF6900), // 哈苏橙
        Color(0xFFFF2D55), // 樱花粉
        Color(0xFF5856D6), // 索尼紫
        Color(0xFF00C7BE), // 青绿
      ],
      AppStrings.paletteDark: const [
        Color(0xFF0A192F),
        Color(0xFF1A1B2F),
        Color(0xFF162447),
        Color(0xFF1F4068),
        Color(0xFF1B1A17),
        Color(0xFF222831),
        Color(0xFF2D4059),
        Color(0xFF0F4C81),
        Color(0xFF121212),
      ],
    };

    final Map<String, List<Color>> allGroups = {
      if (photoColors.isNotEmpty) AppStrings.palettePhotoGroup: photoColors,
      ...paletteGroups,
    };

    BlurredDialogHelper.showBlurredBottomSheet(
      context: context,
      builder: (context) {
        return RepaintBoundary(
          child: Container(
            decoration: const BoxDecoration(
              color: Color(0xFF1C1C1E),
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 顶部把手
                    Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // 标题与当前状态预览徽章
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          AppStrings.paletteTitle,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF2C2C2E),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.white24),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (config.isBlurredBg) ...[
                                const Icon(Icons.blur_on_rounded, size: 14, color: Color(0xFFFFD600)),
                                const SizedBox(width: 6),
                                const Text(
                                  '模糊背景',
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white),
                                ),
                              ] else if (config.isPaperTextureBg) ...[
                                Container(
                                  width: 14,
                                  height: 14,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF7F3E9),
                                    shape: BoxShape.circle,
                                    border: Border.all(color: Colors.white38),
                                  ),
                                  child: const Center(
                                    child: Icon(Icons.texture_rounded, size: 10, color: Color(0xFF6D4C41)),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                const Text(
                                  '纸张纹理',
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white),
                                ),
                              ] else ...[
                                Container(
                                  width: 14,
                                  height: 14,
                                  decoration: BoxDecoration(
                                    color: config.backgroundColor,
                                    shape: BoxShape.circle,
                                    border: Border.all(color: Colors.white38),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  '#${config.backgroundColor.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontFamily: 'monospace',
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // 方格化色板滚动区域
                    Flexible(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // 顶部始终展示的「当前颜色 / 效果」专属横幅
                            Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF2C2C2E),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: const Color(0xFFFFD600), width: 1.5),
                                ),
                                child: Row(
                                  children: [
                                    if (config.isBlurredBg)
                                      Container(
                                        width: 32,
                                        height: 32,
                                        decoration: const BoxDecoration(shape: BoxShape.circle),
                                        child: ClipOval(
                                          child: Stack(
                                            fit: StackFit.expand,
                                            children: [
                                              if (photoBytes != null && photoBytes.isNotEmpty)
                                                ImageFiltered(
                                                  imageFilter: ui.ImageFilter.blur(sigmaX: 4, sigmaY: 4),
                                                  child: Image.memory(
                                                    photoBytes,
                                                    fit: BoxFit.cover,
                                                    cacheWidth: 96, // 32px 圆形色板无需全分辨率纹理
                                                    gaplessPlayback: true,
                                                    errorBuilder: (_, _, _) => Container(color: const Color(0xFF3A3A3C)),
                                                  ),
                                                )
                                              else
                                                Container(color: const Color(0xFF3A3A3C)),
                                              Container(color: Colors.black.withValues(alpha: 0.45)),
                                              const Center(
                                                child: Icon(Icons.blur_on_rounded, size: 16, color: Colors.white),
                                              ),
                                            ],
                                          ),
                                        ),
                                      )
                                    else if (config.isPaperTextureBg)
                                      Container(
                                        width: 32,
                                        height: 32,
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFF7F3E9),
                                          shape: BoxShape.circle,
                                          border: Border.all(color: Colors.white38, width: 1.5),
                                        ),
                                        child: const Center(
                                          child: Icon(Icons.texture_rounded, size: 16, color: Color(0xFF6D4C41)),
                                        ),
                                      )
                                    else
                                      Container(
                                        width: 32,
                                        height: 32,
                                        decoration: BoxDecoration(
                                          color: config.backgroundColor,
                                          shape: BoxShape.circle,
                                          border: Border.all(color: Colors.white38, width: 1.5),
                                        ),
                                      ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            config.isBlurredBg
                                                ? '图片模糊压暗背景'
                                                : (config.isPaperTextureBg ? '米黄色纸张纹理' : '当前相框颜色'),
                                            style: const TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w700,
                                              color: Colors.white,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            config.isBlurredBg
                                                ? '原图高斯模糊与压暗背景'
                                                : (config.isPaperTextureBg
                                                    ? '复古手作纸浆底色与纸纤维质感'
                                                    : '#${config.backgroundColor.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}'),
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontFamily: (!config.isBlurredBg && !config.isPaperTextureBg) ? 'monospace' : null,
                                              fontWeight: FontWeight.w600,
                                              color: Colors.white70,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const Icon(
                                      Icons.check_circle_rounded,
                                      color: Color(0xFFFFD600),
                                      size: 20,
                                    ),
                                  ],
                                ),
                              ),
                            ),

                            ...allGroups.entries.map((entry) {
                              final isPhotoGroup = entry.key.contains('来自当前照片');
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 14),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text(
                                          entry.key,
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: isPhotoGroup ? FontWeight.w800 : FontWeight.w600,
                                            color: isPhotoGroup ? const Color(0xFFFFD600) : Colors.white60,
                                          ),
                                        ),
                                        if (isPhotoGroup) ...[
                                          const SizedBox(width: 6),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFFFD600).withValues(alpha: 0.18),
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: const Text(
                                              'Auto Palette',
                                              style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Color(0xFFFFD600)),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Wrap(
                                      spacing: 10,
                                      runSpacing: 10,
                                      children: entry.value.map((col) {
                                        final isSelected = !config.isBlurredBg && !config.isPaperTextureBg && config.backgroundColor.toARGB32() == col.toARGB32();
                                        return ClipOval(
                                          child: OneUIPressable(
                                            onTap: () {
                                              onChanged(config.copyWith(isBlurredBg: false, isPaperTextureBg: false, backgroundColor: col));
                                              Navigator.pop(context);
                                            },
                                            child: Container(
                                              width: 38,
                                              height: 38,
                                              decoration: BoxDecoration(
                                                color: col,
                                                shape: BoxShape.circle,
                                                border: Border.all(
                                                  color: isSelected ? const Color(0xFFFFD600) : Colors.white24,
                                                  width: isSelected ? 3.0 : 1.0,
                                                ),
                                              ),
                                              child: isSelected
                                                  ? Icon(
                                                      Icons.check_rounded,
                                                      size: 20,
                                                      color: col.computeLuminance() > 0.5
                                                          ? Colors.black
                                                          : Colors.white,
                                                    )
                                                  : null,
                                            ),
                                          ),
                                        );
                                      }).toList(),
                                    ),
                                  ],
                                ),
                              );
                            }),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
