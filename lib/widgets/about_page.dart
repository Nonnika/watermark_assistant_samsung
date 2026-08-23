import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/app_strings.dart';
import '../utils/blurred_dialog_helper.dart';

/// 三星 One UI 原版风格「关于应用」全屏页面
class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  static Future<void> open(BuildContext context) {
    HapticFeedback.selectionClick();
    return Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => const AboutPage(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );
          return FadeTransition(
            opacity: curved,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0.06, 0),
                end: Offset.zero,
              ).animate(curved),
              child: child,
            ),
          );
        },
        transitionDuration: const Duration(milliseconds: 260),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: const Color(0xFF000000), // 原汁原味纯黑背景
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: SafeArea(
          child: Column(
            children: [
              // 1. 顶部操作栏 (返回键 + 信息图标)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: const Icon(
                        Icons.arrow_back_ios_new_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
                      onPressed: () => Navigator.pop(context),
                      tooltip: '返回',
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.info_outline_rounded,
                        color: Colors.white,
                        size: 24,
                      ),
                      onPressed: () {
                        HapticFeedback.lightImpact();
                        _showAppDetailsDialog(context);
                      },
                      tooltip: '应用详情',
                    ),
                  ],
                ),
              ),

              // 2. 居中靠上主体区 (大标题 + 版本号 + 已安装最新版本)
              const SizedBox(height: 36),
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      AppStrings.appName,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 34,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFEAEAEA),
                        letterSpacing: 0.2,
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      '版本 1.0.00.01',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w400,
                        color: Color(0xFF8E8E93),
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      '已安装最新版本。',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w400,
                        color: Color(0xFF8E8E93),
                        letterSpacing: -0.2,
                      ),
                    ),
                  ],
                ),
              ),

              // 3. 中间留白弹性区域
              const Spacer(),

              // 3. 底部胶囊按钮组 (条款与条件 + 开源许可证)
              Padding(
                padding: EdgeInsets.fromLTRB(48, 0, 48, bottomPadding > 0 ? bottomPadding + 16 : 36),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildCapsuleButton(
                      title: '条款与条件',
                      onTap: () {
                        HapticFeedback.selectionClick();
                        _showTermsDialog(context);
                      },
                    ),
                    const SizedBox(height: 14),
                    _buildCapsuleButton(
                      title: '开源许可证',
                      onTap: () {
                        HapticFeedback.selectionClick();
                        showLicensePage(
                          context: context,
                          applicationName: AppStrings.appName,
                          applicationVersion: '1.0.00.01',
                          applicationLegalese: 'Copyright © 2026 Watermark Assistant. All rights reserved.',
                        );
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
  }

  Widget _buildCapsuleButton({
    required String title,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: Material(
        color: const Color(0xFF222228), // One UI 纯黑暗色模式胶囊背景
        borderRadius: BorderRadius.circular(26),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(26),
          splashColor: Colors.white.withValues(alpha: 0.1),
          highlightColor: Colors.white.withValues(alpha: 0.06),
          child: Center(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 15.5,
                fontWeight: FontWeight.w600,
                color: Color(0xFFF2F2F7),
                letterSpacing: -0.2,
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showAppDetailsDialog(BuildContext context) {
    BlurredDialogHelper.showBlurredDialog(
      context: context,
      builder: (ctx) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 25, sigmaY: 25),
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: const Color(0x662C2C36), // 暗色半透明毛玻璃底板
                borderRadius: BorderRadius.circular(28),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.35),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(24, 26, 24, 22),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '本次更新',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            letterSpacing: -0.2,
                          ),
                        ),
                        SizedBox(height: 12),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            '1. 适配高通 Adreno GPU\n2. 重构主页\n3. 修改了默认 PNG 水印\n4. 删除了 PNG 导出选项，以后不再支持\n5. 支持水印嵌入动图',
                            textAlign: TextAlign.left,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w400,
                              color: Color(0xFFE5E5EA),
                              height: 1.6,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () => Navigator.pop(ctx),
                            borderRadius: BorderRadius.circular(20),
                            child: Container(
                              height: 48,
                              alignment: Alignment.center,
                              child: const Text(
                                '确定',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFFFFD600),
                                ),
                              ),
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

  void _showTermsDialog(BuildContext context) {
    BlurredDialogHelper.showBlurredDialog(
      context: context,
      builder: (ctx) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 25, sigmaY: 25),
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: const Color(0x662C2C36), // 暗色半透明毛玻璃底板
                borderRadius: BorderRadius.circular(28),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.35),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(24, 26, 24, 16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '条款与条件',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            letterSpacing: -0.2,
                          ),
                        ),
                        SizedBox(height: 10),
                        Text(
                          '本应用所有水印合成与图像/视频渲染均在您的设备本地完成，不会将您的任何照片、EXIF 隐私或地理位置上传至任何远程服务器。请安心使用。',
                          textAlign: TextAlign.left,
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w400,
                            color: Color(0xFFE5E5EA),
                            height: 1.45,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () => Navigator.pop(ctx),
                            borderRadius: BorderRadius.circular(20),
                            child: Container(
                              height: 48,
                              alignment: Alignment.center,
                              child: const Text(
                                '确定',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFFFFD600),
                                ),
                              ),
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
