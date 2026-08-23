import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../models/frame_watermark_config.dart';
import '../../services/app_strings.dart';
import '../../services/brand_logos.dart';
import '../../services/watermark_processor.dart';
import '../../utils/blurred_dialog_helper.dart';

/// 选项卡 0: Logo 选择条 (内置品牌 + 用户自定义Logo + 添加按钮 + 反色开关，带平移滑块)
class FrameLogoStrip extends StatelessWidget {
  final FrameWatermarkConfig config;
  final ValueChanged<FrameWatermarkConfig> onChanged;

  const FrameLogoStrip({
    super.key,
    required this.config,
    required this.onChanged,
  });

  Future<void> _pickCustomLogo(BuildContext context) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['png', 'jpg', 'jpeg', 'webp', 'svg'],
      withData: true,
    );

    if (result != null && result.files.isNotEmpty) {
      final file = result.files.first;
      Uint8List? bytes = file.bytes;
      if (bytes == null && file.path != null) {
        bytes = await File(file.path!).readAsBytes();
      }

      if (bytes != null && context.mounted) {
        final decoded = await WatermarkProcessor.decodeImageFromBytes(bytes);
        if (context.mounted) {
          final fileName = file.name.replaceAll(RegExp(r'\.[^.]+$'), '');
          _showAddCustomLogoDialog(context, bytes, decoded, fileName.isNotEmpty ? fileName : '自定义Logo');
        }
      }
    }
  }

  void _showAddCustomLogoDialog(
    BuildContext context,
    Uint8List bytes,
    ui.Image? decoded,
    String defaultName,
  ) {
    final nameController = TextEditingController(text: defaultName);
    bool dialogInverted = config.isLogoInverted;

    BlurredDialogHelper.showBlurredDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1C1C1E),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              title: Text(
                AppStrings.addCustomLogoTitle,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Logo 缩略图预览 (支持反色预览)
                  Container(
                    height: 60,
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2C2C2E),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.white24),
                    ),
                    alignment: Alignment.center,
                    child: ColorFiltered(
                      colorFilter: dialogInverted
                          ? const ColorFilter.matrix([
                              -1.0,  0.0,  0.0, 0.0, 255.0,
                               0.0, -1.0,  0.0, 0.0, 255.0,
                               0.0,  0.0, -1.0, 0.0, 255.0,
                               0.0,  0.0,  0.0, 1.0,   0.0,
                            ])
                          : const ColorFilter.mode(Colors.transparent, BlendMode.dst),
                      child: Image.memory(bytes, fit: BoxFit.contain),
                    ),
                  ),
                  const SizedBox(height: 10),
                  // 反色开关
                  InkWell(
                    onTap: () {
                      setDialogState(() {
                        dialogInverted = !dialogInverted;
                      });
                    },
                    borderRadius: BorderRadius.circular(10),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                      child: Row(
                        children: [
                          Icon(
                            dialogInverted ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                            size: 18,
                            color: dialogInverted ? const Color(0xFFFFD600) : Colors.white38,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            AppStrings.autoInvertLogo,
                            style: const TextStyle(fontSize: 12, color: Colors.white70),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: nameController,
                    autofocus: true,
                    style: const TextStyle(fontSize: 13, color: Colors.white),
                    decoration: InputDecoration(
                      labelText: AppStrings.logoLabelName,
                      labelStyle: const TextStyle(color: Colors.white60, fontSize: 12),
                      hintText: AppStrings.logoLabelHint,
                      hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      filled: true,
                      fillColor: const Color(0xFF2C2C2E),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(AppStrings.cancel, style: const TextStyle(color: Colors.white60)),
                ),
                FilledButton(
                  onPressed: () {
                    final customName = nameController.text.trim().isNotEmpty
                        ? nameController.text.trim()
                        : defaultName;
                    final newId = 'custom_${DateTime.now().millisecondsSinceEpoch}';
                    final newLogo = CustomLogoItem(
                      id: newId,
                      name: customName,
                      bytes: bytes,
                      decodedImage: decoded,
                    );
                    BrandLogoService.addUserLogo(newLogo);
                    onChanged(
                      config.copyWith(
                        selectedLogoId: newId,
                        customLogoBytes: bytes,
                        customLogoDecoded: decoded,
                        isLogoInverted: dialogInverted,
                      ),
                    );
                    Navigator.pop(context);
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFFFD600),
                    foregroundColor: Colors.black,
                  ),
                  child: Text(AppStrings.confirmAdd, style: const TextStyle(fontWeight: FontWeight.w900)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _confirmDeleteCustomLogo(BuildContext context, String id, String name) {
    BlurredDialogHelper.showBlurredDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1C1C1E),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Text(
            AppStrings.deleteLogoConfirm(name),
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(AppStrings.cancel, style: const TextStyle(color: Colors.white60)),
            ),
            FilledButton(
              onPressed: () {
                BrandLogoService.removeUserLogo(id);
                if (config.selectedLogoId == id) {
                  onChanged(config.copyWith(
                    selectedLogoId: BrandLogoService.brands.first.id,
                    customLogoBytes: null,
                    customLogoDecoded: null,
                    isLogoInverted: false,
                    clearCustomLogo: true,
                  ));
                }
                Navigator.pop(context);
              },
              style: FilledButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white,
              ),
              child: Text(AppStrings.delete, style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final curLogo = config.selectedLogoId;
    final builtinBrands = BrandLogoService.brands;
    final customLogos = BrandLogoService.userCustomLogos;
    final isCustomActive = curLogo.startsWith('custom_');

    final allItems = <Map<String, dynamic>>[
      ...builtinBrands.map((b) => {'id': b.id, 'name': b.name, 'isAdd': false}),
      ...customLogos.map((c) => {'id': c.id, 'name': c.name, 'isAdd': false}),
      {'id': '__add__', 'name': '添加', 'isAdd': true},
    ];

    int activeIdx = allItems.indexWhere((item) => item['id'] == curLogo);
    if (activeIdx < 0) activeIdx = 0;

    return Row(
      key: const ValueKey('slim_frame_logo'),
      children: [
        // 1. Logo 平移切换条
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final totalWidth = constraints.maxWidth;
              const pad = 3.5;
              final innerWidth = (totalWidth - pad * 2).clamp(0.0, double.infinity);
              final count = allItems.length;
              final bool fitsInScreen = count <= 4;
              final double itemWidth = fitsInScreen
                  ? innerWidth / count
                  : (innerWidth / count).clamp(52.0, 85.0);
              final contentWidth = itemWidth * count;

              final stackContent = SizedBox(
                width: fitsInScreen ? innerWidth : contentWidth,
                height: 37,
                child: Stack(
                  children: [
                    // 焦点平移动画胶囊背景
                    if (activeIdx < count - 1)
                      AnimatedPositioned(
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOutCubic,
                        left: activeIdx * itemWidth,
                        top: 0,
                        width: itemWidth,
                        height: 37,
                        child: Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFFE2E2E8),
                            borderRadius: BorderRadius.circular(13),
                            boxShadow: const [
                              BoxShadow(
                                color: Colors.black26,
                                blurRadius: 4,
                                offset: Offset(0, 1),
                              ),
                            ],
                          ),
                        ),
                      ),

                    // 选项文字与图标
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: allItems.map((item) {
                        final isAdd = item['isAdd'] as bool;
                        final id = item['id'] as String;
                        final name = item['name'] as String;
                        final isSelected = curLogo == id;

                        if (isAdd) {
                          return SizedBox(
                            width: itemWidth,
                            child: InkWell(
                              onTap: () => _pickCustomLogo(context),
                              borderRadius: BorderRadius.circular(13),
                              child: Container(
                                height: 37,
                                alignment: Alignment.center,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.add_rounded, size: 16, color: Colors.white70),
                                    const SizedBox(width: 2),
                                    Text(
                                      AppStrings.logoAdd,
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white70,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }

                        final isCustom = id.startsWith('custom_');

                        return SizedBox(
                          width: itemWidth,
                          child: InkWell(
                            onTap: () {
                              if (isCustom) {
                                final customItem = BrandLogoService.userCustomLogos.firstWhere((c) => c.id == id);
                                onChanged(config.copyWith(
                                  selectedLogoId: id,
                                  customLogoBytes: customItem.bytes,
                                  customLogoDecoded: customItem.decodedImage,
                                ));
                              } else {
                                onChanged(config.copyWith(
                                  selectedLogoId: id,
                                  clearCustomLogo: true,
                                ));
                              }
                            },
                            onLongPress: isCustom
                                ? () => _confirmDeleteCustomLogo(context, id, name)
                                : null,
                            borderRadius: BorderRadius.circular(13),
                            child: Container(
                              height: 37,
                              alignment: Alignment.center,
                              child: Text(
                                name,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: isSelected ? FontWeight.w900 : FontWeight.w500,
                                  color: isSelected ? const Color(0xFF111113) : Colors.white60,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              );

              return Container(
                height: 44,
                padding: const EdgeInsets.all(pad),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E22),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: fitsInScreen
                    ? stackContent
                    : SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        physics: const BouncingScrollPhysics(),
                        child: stackContent,
                      ),
              );
            },
          ),
        ),

        // 2. 自定义 Logo 反色快捷开关按钮
        if (isCustomActive) ...[
          const SizedBox(width: 8),
          InkWell(
            onTap: () => onChanged(config.copyWith(isLogoInverted: !config.isLogoInverted)),
            borderRadius: BorderRadius.circular(16),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 11),
              decoration: BoxDecoration(
                color: config.isLogoInverted ? const Color(0xFFE2E2E8) : const Color(0xFF1E1E22),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.invert_colors_rounded,
                    size: 15,
                    color: config.isLogoInverted ? const Color(0xFF111113) : const Color(0xFFFFD600),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    AppStrings.logoInvert,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      color: config.isLogoInverted ? const Color(0xFF111113) : Colors.white70,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}
