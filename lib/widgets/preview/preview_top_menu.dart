import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/app_strings.dart';

/// 预览区右上角「更多操作」弹出菜单（单张/批量导出，独立修改模式切换）
class PreviewTopMenu {
  static void show({
    required BuildContext context,
    required bool isIndividualMode,
    required int imageCount,
    required ValueChanged<bool> onToggleIndividualMode,
    required ValueChanged<bool> onExport,
  }) {
    HapticFeedback.lightImpact();

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'WatermarkMenu',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (ctx, anim, secondaryAnim) {
        return RepaintBoundary(
          child: Container(
            width: 236,
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E22).withValues(alpha: 0.98),
              borderRadius: BorderRadius.circular(20),
            ),
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: const EdgeInsets.all(7),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 1. 仅编辑当前照片位置 (首项：仅顶部圆角，紧挨下方)
                  Container(
                    decoration: BoxDecoration(
                      color: isIndividualMode
                          ? const Color(0xFFFFD600).withValues(alpha: 0.16)
                          : const Color(0xFF2C2C2E),
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(15)),
                    ),
                    child: InkWell(
                      onTap: () {
                        Navigator.pop(ctx);
                        onToggleIndividualMode(!isIndividualMode);
                      },
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(15)),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        child: Row(
                          children: [
                            Icon(
                              isIndividualMode
                                  ? Icons.check_circle_rounded
                                  : Icons.radio_button_unchecked_rounded,
                              size: 18,
                              color: isIndividualMode ? const Color(0xFFFFD600) : Colors.white38,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                AppStrings.editCurrentOnly,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: isIndividualMode ? FontWeight.w800 : FontWeight.w500,
                                  color: isIndividualMode ? const Color(0xFFFFD600) : Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // 分割线
                  Container(
                    color: const Color(0xFF2C2C2E),
                    child: const Divider(height: 0.6, thickness: 0.6, indent: 42, endIndent: 14, color: Colors.white12),
                  ),

                  // 2. 导出当前照片 (中项：无圆角，紧挨上下)
                  Container(
                    decoration: const BoxDecoration(
                      color: Color(0xFF2C2C2E),
                      borderRadius: BorderRadius.zero,
                    ),
                    child: InkWell(
                      onTap: () {
                        Navigator.pop(ctx);
                        onExport(false);
                      },
                      borderRadius: BorderRadius.zero,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        child: Row(
                          children: [
                            const Icon(Icons.photo_outlined, size: 18, color: Color(0xFFFFD600)),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                AppStrings.exportCurrent,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // 分割线
                  Container(
                    color: const Color(0xFF2C2C2E),
                    child: const Divider(height: 0.6, thickness: 0.6, indent: 42, endIndent: 14, color: Colors.white12),
                  ),

                  // 3. 批量导出全部照片 (尾项：仅底部圆角，紧挨上方)
                  Container(
                    decoration: const BoxDecoration(
                      color: Color(0xFF2C2C2E),
                      borderRadius: BorderRadius.vertical(bottom: Radius.circular(15)),
                    ),
                    child: InkWell(
                      onTap: () {
                        Navigator.pop(ctx);
                        onExport(true);
                      },
                      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(15)),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        child: Row(
                          children: [
                            const Icon(Icons.photo_library_rounded, size: 18, color: Color(0xFFFFD600)),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                AppStrings.exportAll(imageCount),
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
      transitionBuilder: (ctx, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutBack,
          reverseCurve: Curves.easeInCubic,
        );

        return Stack(
          children: [
            // 1. 全屏背景高斯模糊与暗色微光遮罩
            Positioned.fill(
              child: GestureDetector(
                onTap: () => Navigator.pop(ctx),
                child: FadeTransition(
                  opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
                  child: RepaintBoundary(
                    child: BackdropFilter(
                      filter: ui.ImageFilter.blur(sigmaX: 14.0, sigmaY: 14.0),
                      child: Container(
                        color: Colors.black.withValues(alpha: 0.40),
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // 2. 右上角纯净黑曜石弹出菜单面板
            SafeArea(
              child: Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.only(top: 10, right: 14),
                  child: FadeTransition(
                    opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
                    child: ScaleTransition(
                      scale: Tween<double>(begin: 0.65, end: 1.0).animate(curved),
                      alignment: Alignment.topRight,
                      child: Material(
                        color: Colors.transparent,
                        child: child,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
