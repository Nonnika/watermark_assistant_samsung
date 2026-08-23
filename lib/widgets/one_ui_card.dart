import 'package:flutter/material.dart';
import '../theme/one_ui_theme.dart';

class OneUICard extends StatelessWidget {
  final String? title;
  final Widget? trailing;
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;

  const OneUICard({
    super.key,
    this.title,
    this.trailing,
    required this.child,
    this.padding,
    this.margin,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? OneUITheme.darkCardBg : OneUITheme.lightCardBg;

    return Container(
      margin: margin ?? const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(20),
        boxShadow: isDark ? null : OneUITheme.softShadow,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (title != null || trailing != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (title != null)
                    Text(
                      title!,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: isDark ? OneUITheme.darkTextPrimary : OneUITheme.lightTextPrimary,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ?trailing,
                ],
              ),
            ),
          Padding(
            padding: padding ?? const EdgeInsets.fromLTRB(14, 4, 14, 12),
            child: child,
          ),
        ],
      ),
    );
  }
}
