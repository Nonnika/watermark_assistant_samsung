import 'package:flutter/material.dart';
import 'one_ui_pressable.dart';
import '../models/watermark_config.dart';
import '../theme/one_ui_theme.dart';

class OneUINineGrid extends StatelessWidget {
  final WatermarkPosition currentPosition;
  final bool isCustomDrag;
  final ValueChanged<WatermarkPosition> onPositionSelected;

  const OneUINineGrid({
    super.key,
    required this.currentPosition,
    required this.isCustomDrag,
    required this.onPositionSelected,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final gridItems = [
      [WatermarkPosition.topLeft, WatermarkPosition.topCenter, WatermarkPosition.topRight],
      [WatermarkPosition.centerLeft, WatermarkPosition.center, WatermarkPosition.centerRight],
      [WatermarkPosition.bottomLeft, WatermarkPosition.bottomCenter, WatermarkPosition.bottomRight],
    ];

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: isDark ? OneUITheme.darkCardSubtle : OneUITheme.lightCardSubtle,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: gridItems.map((row) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: row.map((pos) {
              final isSelected = !isCustomDrag && currentPosition == pos;
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(3.0),
                  child: OneUIPressable(
                    onTap: () => onPositionSelected(pos),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      height: 44,
                      decoration: BoxDecoration(
                        color: isSelected
                            ? OneUITheme.primaryBlue
                            : (isDark ? const Color(0xFF232326) : Colors.white),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected
                              ? OneUITheme.primaryBlue
                              : (isDark
                                  ? Colors.white.withValues(alpha: 0.06)
                                  : Colors.black.withValues(alpha: 0.04)),
                          width: isSelected ? 2.0 : 1.0,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        pos.label,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                          color: isSelected
                              ? Colors.white
                              : (isDark
                                  ? OneUITheme.darkTextPrimary
                                  : OneUITheme.lightTextPrimary),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          );
        }).toList(),
      ),
    );
  }
}
