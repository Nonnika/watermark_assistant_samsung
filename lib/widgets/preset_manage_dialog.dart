import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../models/saved_preset.dart';
import '../models/watermark_config.dart';
import '../services/preset_storage_service.dart';
import '../theme/one_ui_theme.dart';
import '../utils/blurred_dialog_helper.dart';

class PresetManageDialog {
  static const Color _bgDark = Color(0xFF141418);
  static const Color _cardDark = Color(0xFF202026);
  static const Color _cardBorder = Color(0xFF2C2C34);
  static const Color _textPrimary = Color(0xFFF5F5F7);
  static const Color _textSecondary = Color(0xFF9E9EA8);

  /// 弹出保存当前配置为预设的对话框 (带全屏高斯背景模糊，暗色主题)
  static Future<void> showSavePresetDialog({
    required BuildContext context,
    required WatermarkConfig config,
    Uint8List? watermarkBytes,
    String? presetId,
    required VoidCallback onSaved,
  }) async {
    final controller = TextEditingController(
      text: '自定义预设 ${DateTime.now().month}月${DateTime.now().day}日',
    );

    await BlurredDialogHelper.showBlurredDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: _bgDark,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
          title: const Text(
            '保存当前水印为预设',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: _textPrimary,
              letterSpacing: -0.5,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '保存后可快速将此水印（包含位置坐标、缩放大小、反色设置等）一键复用到其他照片。',
                style: TextStyle(
                  fontSize: 13,
                  color: _textSecondary,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 18),
              TextField(
                controller: controller,
                autofocus: true,
                style: const TextStyle(
                  fontSize: 15,
                  color: _textPrimary,
                  fontWeight: FontWeight.w600,
                ),
                decoration: InputDecoration(
                  labelText: '预设名称',
                  labelStyle: const TextStyle(color: _textSecondary),
                  prefixIcon: const Icon(Icons.bookmark_border_rounded, size: 20, color: _textSecondary),
                  filled: true,
                  fillColor: _cardDark,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: _cardBorder),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: _cardBorder),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: OneUITheme.primaryBlue, width: 2),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消', style: TextStyle(color: _textSecondary)),
            ),
            FilledButton(
              onPressed: () async {
                final name = controller.text.trim();
                if (name.isEmpty) return;

                final preset = SavedPreset(
                  id: DateTime.now().millisecondsSinceEpoch.toString(),
                  name: name,
                  createdAt: DateTime.now(),
                  watermarkBase64: watermarkBytes != null ? base64Encode(watermarkBytes) : null,
                  presetId: presetId,
                  scale: config.scale,
                  opacity: config.opacity,
                  rotation: config.rotation,
                  customX: config.customX,
                  customY: config.customY,
                  isInverted: config.isInverted,
                  mode: config.mode == WatermarkMode.single ? 'single' : 'tiled',
                  tileSpacingX: config.tileSpacingX,
                  tileSpacingY: config.tileSpacingY,
                  tileStaggered: config.tileStaggered,
                );

                await PresetStorageService.savePreset(preset);
                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('已成功保存预设「$name」')),
                  );
                  onSaved();
                }
              },
              style: FilledButton.styleFrom(
                backgroundColor: OneUITheme.primaryBlue,
                shape: const StadiumBorder(),
              ),
              child: const Text('保存预设', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  /// 打开已保存预设列表底部抽屉 (暗色主题)
  static void showPresetListSheet({
    required BuildContext context,
    required Function(SavedPreset preset) onApplyPreset,
  }) {
    BlurredDialogHelper.showBlurredBottomSheet(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return FutureBuilder<List<SavedPreset>>(
              future: PresetStorageService.loadPresets(),
              builder: (context, snapshot) {
                final presets = snapshot.data ?? [];

                return Container(
                  decoration: BoxDecoration(
                    color: _bgDark,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                    border: Border.all(color: _cardBorder.withValues(alpha: 0.6), width: 1),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.6),
                        blurRadius: 24,
                        offset: const Offset(0, -6),
                      ),
                    ],
                  ),
                  child: SafeArea(
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.of(context).size.height * 0.75,
                      ),
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
                            '我的预设库',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: _textPrimary,
                              letterSpacing: -0.5,
                            ),
                          ),
                          const SizedBox(height: 16),
                          if (presets.isEmpty)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 40),
                              child: Column(
                                children: [
                                  Icon(Icons.bookmark_outline_rounded, size: 48, color: Colors.white24),
                                  SizedBox(height: 12),
                                  Text(
                                    '暂无保存的预设',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                      color: _textPrimary,
                                    ),
                                  ),
                                  SizedBox(height: 4),
                                  Text(
                                    '调整好水印参数后，点击「保存预设」即可添加',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: _textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          else
                            Flexible(
                              child: Material(
                                color: _cardDark,
                                borderRadius: BorderRadius.circular(20),
                                clipBehavior: Clip.antiAlias,
                                child: ListView.separated(
                                  shrinkWrap: true,
                                  itemCount: presets.length,
                                  separatorBuilder: (_, _) => const Divider(
                                    height: 0.5,
                                    thickness: 0.5,
                                    indent: 72,
                                    endIndent: 14,
                                    color: _cardBorder,
                                  ),
                                  itemBuilder: (context, index) {
                                    final preset = presets[index];
                                    final bytes = preset.watermarkBytes;

                                    return ListTile(
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                                      leading: Container(
                                        width: 44,
                                        height: 44,
                                        decoration: BoxDecoration(
                                          color: Colors.black38,
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(color: _cardBorder),
                                        ),
                                        padding: const EdgeInsets.all(4),
                                        child: bytes != null
                                            ? Image.memory(bytes, fit: BoxFit.contain)
                                            : const Icon(Icons.water_drop_rounded, color: OneUITheme.primaryBlue),
                                      ),
                                      title: Text(
                                        preset.name,
                                        style: const TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w700,
                                          color: _textPrimary,
                                        ),
                                      ),
                                      subtitle: Text(
                                        '大小 ${(preset.scale * 100).toInt()}% · 不透明度 ${(preset.opacity * 100).toInt()}%${preset.isInverted ? ' · 反色' : ''}',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: _textSecondary,
                                        ),
                                      ),
                                      trailing: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          IconButton(
                                            icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 20),
                                            onPressed: () async {
                                              await PresetStorageService.deletePreset(preset.id);
                                              setSheetState(() {});
                                            },
                                          ),
                                          FilledButton.tonal(
                                            onPressed: () {
                                              Navigator.pop(context);
                                              onApplyPreset(preset);
                                            },
                                            style: FilledButton.styleFrom(
                                              backgroundColor: Colors.white12,
                                              foregroundColor: _textPrimary,
                                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                              visualDensity: VisualDensity.compact,
                                              shape: const StadiumBorder(),
                                            ),
                                            child: const Text('套用', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                          ),
                                        ],
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
          },
        );
      },
    );
  }
}
