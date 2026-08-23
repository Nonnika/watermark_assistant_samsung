import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Samsung OneUI 风格高性能全屏高斯背景模糊弹窗与抽屉辅助工具 (120 FPS 丝滑优化)
class BlurredDialogHelper {
  /// 弹出 Samsung OneUI 靠下半透明毛玻璃悬浮弹窗 (Bottom Floating Blurred Dialog)
  static Future<T?> showBlurredDialog<T>({
    required BuildContext context,
    required WidgetBuilder builder,
    bool barrierDismissible = true,
    double blurSigma = 16.0,
    Duration duration = const Duration(milliseconds: 220),
  }) {
    HapticFeedback.lightImpact();

    return showGeneralDialog<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      barrierLabel: 'BlurredDialog',
      barrierColor: Colors.transparent,
      transitionDuration: duration,
      // pageBuilder 仅在打开时执行构建一次，杜绝动画每一帧重复重建控件树导致的严重掉帧
      pageBuilder: (ctx, anim, secondaryAnim) {
        return RepaintBoundary(
          child: Material(
            color: Colors.transparent,
            child: builder(ctx),
          ),
        );
      },
      transitionBuilder: (ctx, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );

        return Stack(
          children: [
            // 1. 全屏背景高斯模糊 (固定核尺寸 + 独立 GPU 离屏渲染图层 + Alpha 淡入，杜绝 GPU 着色器反复重建)
            Positioned.fill(
              child: GestureDetector(
                onTap: barrierDismissible ? () => Navigator.pop(ctx) : null,
                child: FadeTransition(
                  opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
                  child: RepaintBoundary(
                    child: BackdropFilter(
                      filter: ui.ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
                      child: Container(
                        color: Colors.black.withValues(alpha: 0.38),
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // 2. 靠下悬浮弹性滑入内容弹窗 (One UI 官方经典靠下悬浮毛玻璃位置)
            SafeArea(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: FadeTransition(
                    opacity: curved,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0, 0.10),
                        end: Offset.zero,
                      ).animate(curved),
                      child: child,
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

  /// 弹出具有全屏高斯背景模糊和底部滑升动效的抽屉面板 (Blurred Bottom Sheet，极致流畅 120 FPS)
  static Future<T?> showBlurredBottomSheet<T>({
    required BuildContext context,
    required WidgetBuilder builder,
    bool isDismissible = true,
    bool isScrollControlled = true,
    double blurSigma = 14.0,
    Duration duration = const Duration(milliseconds: 230),
  }) {
    HapticFeedback.lightImpact();

    return showGeneralDialog<T>(
      context: context,
      barrierDismissible: isDismissible,
      barrierLabel: 'BlurredBottomSheet',
      barrierColor: Colors.transparent,
      transitionDuration: duration,
      pageBuilder: (ctx, anim, secondaryAnim) {
        return RepaintBoundary(
          child: Material(
            color: Colors.transparent,
            child: builder(ctx),
          ),
        );
      },
      transitionBuilder: (ctx, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );

        return Stack(
          children: [
            // 1. 全屏背景高斯模糊与暗色遮罩 (固定 Sigma + RepaintBoundary 硬件加速)
            Positioned.fill(
              child: GestureDetector(
                onTap: isDismissible ? () => Navigator.pop(ctx) : null,
                child: FadeTransition(
                  opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
                  child: RepaintBoundary(
                    child: BackdropFilter(
                      filter: ui.ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
                      child: Container(
                        color: Colors.black.withValues(alpha: 0.42),
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // 2. 底部滑入面板 (直接使用预编译的 child，零重复运算)
            Align(
              alignment: Alignment.bottomCenter,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 1),
                  end: Offset.zero,
                ).animate(curved),
                child: child,
              ),
            ),
          ],
        );
      },
    );
  }
}
