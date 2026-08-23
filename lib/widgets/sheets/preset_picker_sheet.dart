import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../services/preset_watermarks.dart';
import '../../services/watermark_processor.dart';
import '../../theme/one_ui_theme.dart';
import '../../utils/blurred_dialog_helper.dart';

typedef OnPresetSelected = void Function(Uint8List bytes, dynamic decoded, String title, String presetId);

/// 内置精选水印选择面板
class PresetPickerSheet {
  static void show({
    required BuildContext context,
    required String currentWatermarkName,
    required OnPresetSelected onPresetSelected,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    BlurredDialogHelper.showBlurredBottomSheet(
      context: context,
      builder: (context) {
        return Container(
          decoration: BoxDecoration(
            color: isDark ? OneUITheme.darkCardBg : OneUITheme.lightCardBg,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white24 : Colors.black12,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '选择内置精选水印',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: isDark ? OneUITheme.darkTextPrimary : OneUITheme.lightTextPrimary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Flexible(
                    child: Container(
                      decoration: BoxDecoration(
                        color: isDark ? OneUITheme.darkCardSubtle : OneUITheme.lightCardSubtle,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: PresetWatermarkService.presets.length,
                        separatorBuilder: (_, _) => Divider(
                          height: 0.5,
                          thickness: 0.5,
                          indent: 64,
                          endIndent: 16,
                          color: isDark ? Colors.white12 : Colors.black12,
                        ),
                        itemBuilder: (context, index) {
                          final preset = PresetWatermarkService.presets[index];
                          final isSelected = currentWatermarkName == preset.title;

                          return InkWell(
                            onTap: () async {
                              Navigator.pop(context);
                              final bytes = await preset.generateBytes();
                              final decoded = await WatermarkProcessor.decodeImageFromBytes(bytes);
                              onPresetSelected(bytes, decoded, preset.title, preset.id);
                            },
                            child: Container(
                              color: isSelected ? OneUITheme.primaryBlue.withValues(alpha: 0.12) : Colors.transparent,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                              child: Row(
                                children: [
                                  Container(
                                    width: 34,
                                    height: 34,
                                    decoration: BoxDecoration(
                                      color: isSelected ? const Color(0xFFFFD600) : OneUITheme.primaryBlue,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      Icons.verified_rounded,
                                      color: isSelected ? Colors.black : Colors.white,
                                      size: 17,
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          preset.title,
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w700,
                                            color: isSelected ? OneUITheme.primaryBlue : (isDark ? OneUITheme.darkTextPrimary : OneUITheme.lightTextPrimary),
                                          ),
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          preset.description,
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: isDark ? OneUITheme.darkTextSecondary : OneUITheme.lightTextSecondary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (isSelected)
                                    const Icon(Icons.check_circle_rounded, color: OneUITheme.primaryBlue, size: 20),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
