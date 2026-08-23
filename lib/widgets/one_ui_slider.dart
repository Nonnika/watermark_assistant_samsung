import 'package:flutter/material.dart';
import '../theme/one_ui_theme.dart';

class OneUISlider extends StatelessWidget {
  final String label;
  final IconData? icon;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final String Function(double)? valueFormatter;
  final ValueChanged<double> onChanged;

  const OneUISlider({
    super.key,
    required this.label,
    this.icon,
    required this.value,
    required this.min,
    required this.max,
    this.divisions,
    this.valueFormatter,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final displayValue = valueFormatter != null
        ? valueFormatter!(value)
        : '${(value * 100).toInt()}%';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(
                  icon,
                  size: 15,
                  color: isDark ? OneUITheme.darkTextSecondary : OneUITheme.lightTextSecondary,
                ),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isDark ? OneUITheme.darkTextPrimary : OneUITheme.lightTextPrimary,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                decoration: BoxDecoration(
                  color: OneUITheme.primaryBlue.withValues(alpha: isDark ? 0.2 : 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  displayValue,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: OneUITheme.primaryBlue,
                  ),
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderThemeData(
              trackHeight: 3.5,
              activeTrackColor: OneUITheme.primaryBlue,
              inactiveTrackColor: isDark ? const Color(0xFF2C2C30) : const Color(0xFFE2E4EB),
              thumbColor: OneUITheme.primaryBlue,
              overlayColor: OneUITheme.primaryBlue.withValues(alpha: 0.15),
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
            ),
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              divisions: divisions,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}
