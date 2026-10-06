import 'package:flutter/material.dart';
import '../one_ui_pressable.dart';
import '../../theme/one_ui_theme.dart';
import '../../utils/blurred_dialog_helper.dart';

/// 自定义 PNG 水印导入来源选择底部弹层（系统相册 / 文件管理器）
class PngSourceSheet {
  PngSourceSheet._();

  static void show({
    required BuildContext context,
    required VoidCallback onPickFromGallery,
    required VoidCallback onPickFromFile,
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
                    '导入自定义 PNG 水印',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: isDark ? OneUITheme.darkTextPrimary : OneUITheme.lightTextPrimary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    decoration: BoxDecoration(
                      color: isDark ? OneUITheme.darkCardSubtle : OneUITheme.lightCardSubtle,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        OneUIPressable(
                          onTap: () {
                            Navigator.pop(context);
                            onPickFromGallery();
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                            child: Row(
                              children: [
                                Container(
                                  width: 34,
                                  height: 34,
                                  decoration: const BoxDecoration(
                                    color: OneUITheme.primaryBlue,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.photo_library_rounded, color: Colors.white, size: 17),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text('从手机系统相册选择', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                      const SizedBox(height: 3),
                                      Text('相册里的透明 PNG / 签名图片', style: TextStyle(fontSize: 12, color: isDark ? OneUITheme.darkTextSecondary : OneUITheme.lightTextSecondary)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        OneUIPressable(
                          onTap: () {
                            Navigator.pop(context);
                            onPickFromFile();
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                            child: Row(
                              children: [
                                Container(
                                  width: 34,
                                  height: 34,
                                  decoration: const BoxDecoration(
                                    color: Color(0xFF5E35B1),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.folder_open_rounded, color: Colors.white, size: 17),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text('从文件管理器选择', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                      const SizedBox(height: 3),
                                      Text('手机下载目录选取 PNG / WEBP', style: TextStyle(fontSize: 12, color: isDark ? OneUITheme.darkTextSecondary : OneUITheme.lightTextSecondary)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
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
