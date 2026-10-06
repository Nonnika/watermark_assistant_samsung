import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../one_ui_pressable.dart';
import '../../models/saved_preset.dart';
import '../../models/watermark_config.dart';
import '../../theme/one_ui_theme.dart';
import '../../utils/blurred_dialog_helper.dart';
import '../preset_manage_dialog.dart';

/// 资源与预设管理弹窗（继续添加照片、我的预设库、保存当前配置为预设）
class ResourcesSheet {
  static void show({
    required BuildContext context,
    required int imageCount,
    required WatermarkConfig activePngConfig,
    required Uint8List? watermarkBytes,
    required String? presetWatermarkId,
    required VoidCallback onPickMoreImages,
    required ValueChanged<SavedPreset> onApplyPreset,
  }) {
    BlurredDialogHelper.showBlurredBottomSheet(
      context: context,
      builder: (context) {
        return Container(
          decoration: BoxDecoration(
            color: const Color(0xFF141418),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border.all(color: const Color(0xFF2C2C34).withValues(alpha: 0.6), width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.6),
                blurRadius: 24,
                offset: const Offset(0, -6),
              ),
            ],
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
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    '资源与预设管理',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFFF5F5F7),
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF202026),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFF2C2C34)),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // 1. 继续添加照片
                        OneUIPressable(
                          onTap: () {
                            Navigator.pop(context);
                            onPickMoreImages();
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                            child: Row(
                              children: [
                                Container(
                                  width: 36,
                                  height: 36,
                                  decoration: const BoxDecoration(
                                    color: OneUITheme.primaryBlue,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.add_photo_alternate_rounded, color: Colors.white, size: 18),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '继续添加照片 (当前 $imageCount 张)',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                          color: Color(0xFFF5F5F7),
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                      const Text(
                                        '批量选择更多图片加入处理列表',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Color(0xFF9E9EA8),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        // 2. 我的预设库
                        OneUIPressable(
                          onTap: () {
                            Navigator.pop(context);
                            PresetManageDialog.showPresetListSheet(
                              context: context,
                              onApplyPreset: onApplyPreset,
                            );
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                            child: Row(
                              children: [
                                Container(
                                  width: 36,
                                  height: 36,
                                  decoration: const BoxDecoration(
                                    color: Color(0xFF8E44AD),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.bookmarks_rounded, color: Colors.white, size: 18),
                                ),
                                const SizedBox(width: 14),
                                const Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '我的预设库',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                          color: Color(0xFFF5F5F7),
                                        ),
                                      ),
                                      SizedBox(height: 3),
                                      Text(
                                        '查看与套用已保存的水印参数',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Color(0xFF9E9EA8),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        // 3. 保存当前配置为预设
                        OneUIPressable(
                          onTap: () {
                            Navigator.pop(context);
                            PresetManageDialog.showSavePresetDialog(
                              context: context,
                              config: activePngConfig,
                              watermarkBytes: watermarkBytes,
                              presetId: presetWatermarkId,
                              onSaved: () {},
                            );
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                            child: Row(
                              children: [
                                Container(
                                  width: 36,
                                  height: 36,
                                  decoration: const BoxDecoration(
                                    color: Color(0xFF00897B),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.bookmark_add_rounded, color: Colors.white, size: 18),
                                ),
                                const SizedBox(width: 14),
                                const Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '保存当前配置为预设',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                          color: Color(0xFFF5F5F7),
                                        ),
                                      ),
                                      SizedBox(height: 3),
                                      Text(
                                        '保存当前水印图片与全部参数到本地',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Color(0xFF9E9EA8),
                                        ),
                                      ),
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
