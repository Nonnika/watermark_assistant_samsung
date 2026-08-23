import 'package:flutter/material.dart';
import '../../services/app_strings.dart';
import '../../theme/one_ui_theme.dart';
import '../../utils/blurred_dialog_helper.dart';
import '../pebble_icon.dart';

/// 三星 One UI 风格「关于应用」详情弹窗
class AboutSheet {
  static void show(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    BlurredDialogHelper.showBlurredBottomSheet(
      context: context,
      builder: (context) {
        return Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.85,
          ),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF141418) : const Color(0xFFF7F7FA),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border.all(
              color: isDark ? const Color(0xFF2C2C34).withValues(alpha: 0.6) : Colors.black12,
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.6 : 0.15),
                blurRadius: 24,
                offset: const Offset(0, -6),
              ),
            ],
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 1. 顶部拖动手柄
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

                  // 2. 应用鹅卵石矢量图标
                  const Center(
                    child: AppPebbleIcon(
                      size: 64,
                      hasShadow: true,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // 3. 应用名称
                  Text(
                    AppStrings.appName,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: isDark ? OneUITheme.darkTextPrimary : OneUITheme.lightTextPrimary,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 6),

                  // 4. 版本与平台标识胶囊
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3.5),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF202026) : const Color(0xFFE8E8EE),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isDark ? Colors.white12 : Colors.black12,
                        width: 0.8,
                      ),
                    ),
                    child: Text(
                      'v1.0.0 · Galaxy & Snapdragon Edition',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white70 : Colors.black87,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),

                  Text(
                    AppStrings.headerSubtitle,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: isDark ? OneUITheme.darkTextSecondary : OneUITheme.lightTextSecondary,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 5. 核心特性功能卡片列表 (可滚动)
                  Flexible(
                    child: SingleChildScrollView(
                      child: Container(
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF202026) : Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: isDark ? const Color(0xFF2C2C34) : Colors.black.withValues(alpha: 0.06),
                          ),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _buildFeatureTile(
                              icon: Icons.auto_awesome_rounded,
                              iconColor: const Color(0xFF0D6EFD),
                              title: '三星 One UI 旗舰设计',
                              desc: '原版经典边框、EXIF 智能参数排版与 Galaxy 定制水印',
                              isDark: isDark,
                            ),
                            _buildFeatureTile(
                              icon: Icons.hdr_on_rounded,
                              iconColor: const Color(0xFFFFD600),
                              title: '10-bit Ultra HDR 光影',
                              desc: '无损合成并完整保留原生 HDR Gainmap 增益图',
                              isDark: isDark,
                            ),
                            _buildFeatureTile(
                              icon: Icons.motion_photos_on_rounded,
                              iconColor: const Color(0xFF2ECC71),
                              title: 'Motion Photo 实况照片',
                              desc: '保留 MicroVideo 视频容器，相册内支持动态实况播放',
                              isDark: isDark,
                            ),
                            _buildFeatureTile(
                              icon: Icons.speed_rounded,
                              iconColor: const Color(0xFFE67E22),
                              title: '高通 Adreno 专项加速',
                              desc: '0 Relayout 矩阵平移架构与多核调度，丝滑无卡顿',
                              isDark: isDark,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 6. 确定 / 知道了按钮 (固定底部)
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () => Navigator.pop(context),
                      style: FilledButton.styleFrom(
                        backgroundColor: isDark ? const Color(0xFFFFD600) : OneUITheme.primaryBlue,
                        foregroundColor: isDark ? Colors.black : Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        elevation: 0,
                      ),
                      child: const Text(
                        '我知道了',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.2,
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
    );
  }

  static Widget _buildFeatureTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String desc,
    required bool isDark,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: iconColor, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: isDark ? OneUITheme.darkTextPrimary : OneUITheme.lightTextPrimary,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  desc,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                    color: isDark ? OneUITheme.darkTextSecondary : OneUITheme.lightTextSecondary,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
