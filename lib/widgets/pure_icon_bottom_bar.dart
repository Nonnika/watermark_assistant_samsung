import 'package:flutter/material.dart';
import '../models/watermark_config.dart';
import '../services/app_strings.dart';

/// 64dp 纯图标底部工具栏 (黄色焦点高亮，无大阴影，直接使用纯黑界面背景)
class PureIconBottomBar extends StatelessWidget {
  final WatermarkType watermarkType;
  final int activeToolIndex;
  final ValueChanged<int> onToolSelected;
  final VoidCallback onOpenResources;

  const PureIconBottomBar({
    super.key,
    required this.watermarkType,
    required this.activeToolIndex,
    required this.onToolSelected,
    required this.onOpenResources,
  });

  @override
  Widget build(BuildContext context) {
    const activeYellow = Color(0xFFFFD600); // 焦点黄色
    const inactiveColor = Color(0xFF8E8E93); // 未选中灰白

    final toolIcons = watermarkType == WatermarkType.frame
        ? [
            {'icon': Icons.branding_watermark_rounded, 'tooltip': AppStrings.toolBrandLogo},
            {'icon': Icons.palette_rounded, 'tooltip': AppStrings.toolFrameColor},
            {'icon': Icons.crop_free_rounded, 'tooltip': AppStrings.toolFrameParams},
            {'icon': Icons.camera_alt_rounded, 'tooltip': AppStrings.toolExifParams},
          ]
        : [
            {'icon': Icons.folder_open_rounded, 'tooltip': AppStrings.toolPngLibrary},
            {'icon': Icons.grid_view_rounded, 'tooltip': AppStrings.toolPngPosition},
            {'icon': Icons.auto_awesome_rounded, 'tooltip': AppStrings.toolPngEffects},
          ];

    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      color: Colors.transparent,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          // 工具项 (黄色焦点，无水波纹，动态缩放)
          ...List.generate(toolIcons.length, (idx) {
            final isSelected = activeToolIndex == idx;
            final item = toolIcons[idx];

            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onToolSelected(idx),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                child: TweenAnimationBuilder<double>(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutBack,
                  tween: Tween<double>(begin: 1.0, end: isSelected ? 1.15 : 1.0),
                  builder: (context, scale, child) {
                    return Transform.scale(
                      scale: scale,
                      child: Icon(
                        item['icon'] as IconData,
                        size: 22,
                        color: isSelected ? activeYellow : inactiveColor,
                      ),
                    );
                  },
                ),
              ),
            );
          }),

          // 资源与预设
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onOpenResources,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: const Icon(Icons.folder_special_outlined, size: 22, color: inactiveColor),
            ),
          ),
        ],
      ),
    );
  }
}
