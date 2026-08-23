import 'package:flutter/material.dart';
import '../../models/saved_preset.dart';
import '../../services/app_strings.dart';
import '../../theme/one_ui_theme.dart';
import '../../utils/blurred_dialog_helper.dart';
import '../preset_manage_dialog.dart';
import '../about_page.dart';

/// 主界面左上角快捷选项面板（切换语言、管理预设库）
class QuickOptionsSheet {
  static void show({
    required BuildContext context,
    required ValueChanged<SavedPreset> onApplyPreset,
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
                    '快捷选项与设置',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: isDark ? OneUITheme.darkTextPrimary : OneUITheme.lightTextPrimary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Material(
                    color: isDark ? OneUITheme.darkCardSubtle : OneUITheme.lightCardSubtle,
                    borderRadius: BorderRadius.circular(20),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ListTile(
                          leading: const Icon(Icons.language_rounded, color: OneUITheme.primaryBlue),
                          title: Text(AppStrings.toggleLang, style: const TextStyle(fontWeight: FontWeight.w600)),
                          onTap: () {
                            Navigator.pop(context);
                            AppStrings.toggleLanguage();
                          },
                        ),
                        ListTile(
                          leading: const Icon(Icons.bookmarks_rounded, color: Color(0xFF8E44AD)),
                          title: const Text('管理预设库', style: TextStyle(fontWeight: FontWeight.w600)),
                          onTap: () {
                            Navigator.pop(context);
                            PresetManageDialog.showPresetListSheet(
                              context: context,
                              onApplyPreset: onApplyPreset,
                            );
                          },
                        ),
                        ListTile(
                          leading: const Icon(Icons.info_outline_rounded, color: Color(0xFFFFD600)),
                          title: const Text('关于水印助手', style: TextStyle(fontWeight: FontWeight.w600)),
                          onTap: () {
                            Navigator.pop(context);
                            AboutPage.open(context);
                          },
                        ),
                      ],
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
