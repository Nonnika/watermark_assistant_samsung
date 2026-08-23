import 'package:flutter/material.dart';
import '../models/image_item.dart';
import '../theme/one_ui_theme.dart';

class ImageStrip extends StatelessWidget {
  final List<ImageItem> images;
  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final VoidCallback onAddMore;
  final ValueChanged<int> onRemove;

  const ImageStrip({
    super.key,
    required this.images,
    required this.selectedIndex,
    required this.onSelect,
    required this.onAddMore,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      height: 94,
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: images.length + 1,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          if (index == 0) {
            // “+ 添加更多” 卡片
            return InkWell(
              onTap: onAddMore,
              borderRadius: BorderRadius.circular(16),
              child: Container(
                width: 76,
                decoration: BoxDecoration(
                  color: isDark ? OneUITheme.darkCardBg : OneUITheme.lightCardBg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: OneUITheme.primaryBlue.withValues(alpha: 0.4),
                    width: 1.5,
                    strokeAlign: BorderSide.strokeAlignInside,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.add_photo_alternate_rounded, color: OneUITheme.primaryBlue, size: 26),
                    const SizedBox(height: 4),
                    Text(
                      '添加',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isDark ? OneUITheme.darkTextPrimary : OneUITheme.lightTextPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          final imgIndex = index - 1;
          final item = images[imgIndex];
          final isSelected = imgIndex == selectedIndex;

          return Stack(
            clipBehavior: Clip.none,
            children: [
              GestureDetector(
                onTap: () => onSelect(imgIndex),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 76,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isSelected ? OneUITheme.primaryBlue : Colors.transparent,
                      width: 2.5,
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Image.memory(
                    item.bytes,
                    fit: BoxFit.cover,
                  ),
                ),
              ),

              // 右上角删除按钮
              Positioned(
                top: -4,
                right: -4,
                child: GestureDetector(
                  onTap: () => onRemove(imgIndex),
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: const BoxDecoration(
                      color: Colors.black87,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.close_rounded, size: 13, color: Colors.white),
                  ),
                ),
              ),

              // 左上角动态照片标识角标
              if (item.isMotionPhoto)
                Positioned(
                  top: 4,
                  left: 4,
                  child: Container(
                    padding: const EdgeInsets.all(2.5),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.65),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.motion_photos_on_rounded,
                      size: 11,
                      color: Color(0xFFFFD600),
                    ),
                  ),
                ),

              // 底部尺寸角标
              Positioned(
                bottom: 4,
                left: 4,
                right: 4,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '${imgIndex + 1}/${images.length}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 9, color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
