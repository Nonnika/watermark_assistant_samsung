import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../../models/frame_watermark_config.dart';
import 'color_grid_picker.dart';

/// 选项卡 1: 相框颜色圆点条 (最左侧彩色圆圈触发方格化色板，次左侧为图片压暗高斯模糊小球，右侧为常用预设)
class FrameColorStrip extends StatelessWidget {
  final FrameWatermarkConfig config;
  final List<Color> photoColors;
  final Uint8List? photoBytes;
  final ValueChanged<FrameWatermarkConfig> onChanged;

  const FrameColorStrip({
    super.key,
    required this.config,
    required this.photoColors,
    this.photoBytes,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    const quickPresets = [
      Color(0xFFFFFFFF), // 纯白
      Color(0xFF18181A), // 纯黑
      Color(0xFFF7F4EB), // 复古米白
      Color(0xFF2C2C30), // 钛金灰
      Color(0xFF0381FE), // 三星蓝
    ];

    final isCustomColor = !config.isBlurredBg && !config.isPaperTextureBg && !quickPresets.any((c) => c == config.backgroundColor);
    final isBlurredSelected = config.isBlurredBg;
    final isPaperTextureSelected = config.isPaperTextureBg;

    return Row(
      key: const ValueKey('slim_frame_color'),
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        // 1. 最左侧彩色圆圈 (纯净渐变色彩虹色轮，点击弹出方格化色板)
        InkWell(
          onTap: () => ColorGridPicker.show(
            context,
            config: config,
            photoColors: photoColors,
            photoBytes: photoBytes,
            onChanged: onChanged,
          ),
          borderRadius: BorderRadius.circular(20),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const SweepGradient(
                colors: [
                  Color(0xFFFF0000),
                  Color(0xFFFF7F00),
                  Color(0xFFFFFF00),
                  Color(0xFF00FF00),
                  Color(0xFF00FFFF),
                  Color(0xFF0000FF),
                  Color(0xFF8B00FF),
                  Color(0xFFFF0000),
                ],
              ),
              border: Border.all(
                color: isCustomColor ? const Color(0xFFFFD600) : Colors.white38,
                width: isCustomColor ? 3.0 : 1.2,
              ),
              boxShadow: isCustomColor
                  ? [
                      BoxShadow(
                        color: const Color(0xFFFFD600).withValues(alpha: 0.35),
                        blurRadius: 6,
                      ),
                    ]
                  : null,
            ),
            child: isCustomColor
                ? Center(
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: config.backgroundColor,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 1.5),
                      ),
                    ),
                  )
                : null,
          ),
        ),

        // 2. 由图片模糊而成的小球 (压暗高斯模糊边框)
        InkWell(
          onTap: () => onChanged(config.copyWith(isBlurredBg: true, isPaperTextureBg: false)),
          borderRadius: BorderRadius.circular(20),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: isBlurredSelected ? const Color(0xFFFFD600) : Colors.white38,
                width: isBlurredSelected ? 3.0 : 1.2,
              ),
              boxShadow: isBlurredSelected
                  ? [
                      BoxShadow(
                        color: const Color(0xFFFFD600).withValues(alpha: 0.35),
                        blurRadius: 6,
                      ),
                    ]
                  : null,
            ),
            child: ClipOval(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (photoBytes != null && photoBytes!.isNotEmpty)
                    ImageFiltered(
                      imageFilter: ui.ImageFilter.blur(sigmaX: 4, sigmaY: 4),
                      child: Image.memory(
                        photoBytes!,
                        fit: BoxFit.cover,
                        cacheWidth: 128, // 36px 圆形色板无需全分辨率纹理
                        gaplessPlayback: true,
                        errorBuilder: (_, _, _) => Container(color: const Color(0xFF3A3A3C)),
                      ),
                    )
                  else if (photoColors.isNotEmpty)
                    Container(
                      color: photoColors.first,
                    )
                  else
                    Container(
                      color: const Color(0xFF3A3A3C),
                    ),
                  // 压暗遮罩
                  Container(
                    color: Colors.black.withValues(alpha: 0.45),
                  ),
                  // 图标指示
                  Center(
                    child: isBlurredSelected
                        ? const Icon(
                            Icons.check_rounded,
                            size: 18,
                            color: Colors.white,
                          )
                        : const Icon(
                            Icons.blur_on_rounded,
                            size: 16,
                            color: Colors.white70,
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),

        // 3. 米黄色纸张纹理效果小球
        InkWell(
          onTap: () => onChanged(config.copyWith(isPaperTextureBg: true, isBlurredBg: false)),
          borderRadius: BorderRadius.circular(20),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFFF7F3E9),
              shape: BoxShape.circle,
              border: Border.all(
                color: isPaperTextureSelected ? const Color(0xFFFFD600) : Colors.white38,
                width: isPaperTextureSelected ? 3.0 : 1.2,
              ),
              boxShadow: isPaperTextureSelected
                  ? [
                      BoxShadow(
                        color: const Color(0xFFFFD600).withValues(alpha: 0.35),
                        blurRadius: 6,
                      ),
                    ]
                  : null,
            ),
            child: Center(
              child: isPaperTextureSelected
                  ? const Icon(
                      Icons.check_rounded,
                      size: 18,
                      color: Color(0xFF3E2723),
                    )
                  : const Icon(
                      Icons.texture_rounded,
                      size: 16,
                      color: Color(0xFF795548),
                    ),
            ),
          ),
        ),

        // 4. 右侧常用预设颜色圆点
        ...quickPresets.map((color) {
          final isSelected = !config.isBlurredBg && !config.isPaperTextureBg && config.backgroundColor == color;

          return InkWell(
            onTap: () => onChanged(config.copyWith(isBlurredBg: false, isPaperTextureBg: false, backgroundColor: color)),
            borderRadius: BorderRadius.circular(20),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? const Color(0xFFFFD600) : Colors.white38,
                  width: isSelected ? 3.0 : 1.2,
                ),
              ),
              child: isSelected
                  ? Icon(
                      Icons.check_rounded,
                      size: 18,
                      color: color.computeLuminance() > 0.5 ? Colors.black : Colors.white,
                    )
                  : null,
            ),
          );
        }),
      ],
    );
  }
}
