import 'package:flutter/material.dart';
import 'one_ui_pressable.dart';
import '../theme/one_ui_theme.dart';

class OneUISegmentedPill<T> extends StatelessWidget {
  final List<T> items;
  final List<String> labels;
  final List<IconData>? icons;
  final T selectedItem;
  final ValueChanged<T> onItemSelected;

  const OneUISegmentedPill({
    super.key,
    required this.items,
    required this.labels,
    this.icons,
    required this.selectedItem,
    required this.onItemSelected,
  }) : assert(items.length == labels.length);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: isDark ? OneUITheme.darkCardSubtle : OneUITheme.lightCardSubtle,
        borderRadius: OneUITheme.pillBorderRadius,
      ),
      child: Row(
        children: List.generate(items.length, (index) {
          final item = items[index];
          final label = labels[index];
          final icon = icons != null && index < icons!.length ? icons![index] : null;
          final isSelected = item == selectedItem;

          return Expanded(
            child: OneUIPressable(
              onTap: () => onItemSelected(item),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeInOut,
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: isSelected
                      ? OneUITheme.primaryBlue
                      : Colors.transparent,
                  borderRadius: OneUITheme.pillBorderRadius,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (icon != null) ...[
                      Icon(
                        icon,
                        size: 16,
                        color: isSelected
                            ? Colors.white
                            : (isDark
                                ? OneUITheme.darkTextSecondary
                                : OneUITheme.lightTextSecondary),
                      ),
                      const SizedBox(width: 6),
                    ],
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                        color: isSelected
                            ? Colors.white
                            : (isDark
                                ? OneUITheme.darkTextPrimary
                                : OneUITheme.lightTextPrimary),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}
