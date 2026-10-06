import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import '../one_ui_pressable.dart';

import '../../services/app_strings.dart';

/// 预览页顶部悬浮控制栏：左侧纯图标返回主界面 + 中间动态照片/Ultra HDR 徽章 +
/// 右侧三个点菜单，均支持高斯背景模糊。自身即 [Positioned]（top:10, left/right:14）。
class PreviewTopBar extends StatelessWidget {
  static final _blurFilter = ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16);
  final VoidCallback onBack;
  final VoidCallback onOpenMenu;
  final bool isMotionPhoto;
  final bool isUltraHdr;

  const PreviewTopBar({
    super.key,
    required this.onBack,
    required this.onOpenMenu,
    required this.isMotionPhoto,
    required this.isUltraHdr,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 10,
      left: 14,
      right: 14,
      // 非重叠控件共享背景输入，引擎可合并同一高斯模糊计算。
      child: BackdropGroup(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // 左侧：纯图标返回主界面按钮（带高斯背景模糊）
            ClipOval(
              child: BackdropFilter.grouped(
                filter: _blurFilter,
                child: Material(
                  color: Colors.transparent,
                  child: OneUIPressable(
                    onTap: onBack,
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.38),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.22),
                          width: 1.0,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.25),
                            blurRadius: 10,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.arrow_back_rounded,
                        size: 20,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // 中间：Ultra HDR 与 动态照片 标识（带高斯背景模糊胶囊）
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isMotionPhoto)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: BackdropFilter.grouped(
                      filter: _blurFilter,
                      child: Container(
                        margin: const EdgeInsets.only(right: 6),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.38),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: const Color(0xFFFFD600)
                                .withValues(alpha: 0.55),
                            width: 1.0,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.2),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.motion_photos_on_rounded,
                              size: 16,
                              color: Color(0xFFFFD600),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              AppStrings.motionPhotoBadge,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFFFFD600),
                                letterSpacing: 0.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                if (isUltraHdr)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: BackdropFilter.grouped(
                      filter: _blurFilter,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.38),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: const Color(0xFFFFD600)
                                .withValues(alpha: 0.55),
                            width: 1.0,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.2),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.hdr_on_rounded,
                              size: 16,
                              color: Color(0xFFFFD600),
                            ),
                            SizedBox(width: 4),
                            Text(
                              'Ultra HDR',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFFFFD600),
                                letterSpacing: 0.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),

            // 右侧：三个点菜单（带高斯背景模糊）
            ClipOval(
              child: BackdropFilter.grouped(
                filter: _blurFilter,
                child: Material(
                  color: Colors.transparent,
                  child: OneUIPressable(
                    onTap: onOpenMenu,
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.38),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.22),
                          width: 1.0,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.25),
                            blurRadius: 10,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.more_vert_rounded,
                        size: 20,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
