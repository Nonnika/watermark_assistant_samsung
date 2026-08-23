import 'package:flutter/material.dart';
import '../theme/one_ui_theme.dart';

class AnimatedSubTabs extends StatelessWidget {
  final List<String> labels;
  final List<IconData> icons;
  final int selectedIndex;
  final ValueChanged<int> onTabSelected;

  const AnimatedSubTabs({
    super.key,
    required this.labels,
    required this.icons,
    required this.selectedIndex,
    required this.onTabSelected,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.all(4),
      height: 44,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E22) : const Color(0xFFE8E9F0),
        borderRadius: BorderRadius.circular(22),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final tabWidth = constraints.maxWidth / labels.length;

          return Stack(
            children: [
              // 动画滑动药丸指示器
              AnimatedPositioned(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutCubic,
                left: selectedIndex * tabWidth,
                top: 0,
                bottom: 0,
                width: tabWidth,
                child: Container(
                  decoration: BoxDecoration(
                    color: OneUITheme.primaryBlue,
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
              ),

              // 各 Tab 点击项
              Row(
                children: List.generate(labels.length, (index) {
                  final isSelected = selectedIndex == index;
                  return Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => onTabSelected(index),
                      child: Center(
                        child: AnimatedDefaultTextStyle(
                          duration: const Duration(milliseconds: 200),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                            color: isSelected
                                ? Colors.white
                                : (isDark ? OneUITheme.darkTextSecondary : OneUITheme.lightTextSecondary),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                icons[index],
                                size: 15,
                                color: isSelected
                                    ? Colors.white
                                    : (isDark ? OneUITheme.darkTextSecondary : OneUITheme.lightTextSecondary),
                              ),
                              const SizedBox(width: 4),
                              Text(labels[index]),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ],
          );
        },
      ),
    );
  }
}
