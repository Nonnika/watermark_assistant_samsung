import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/watermark_config.dart';
import '../../services/device_photo_service.dart';
import '../about_page.dart';
import '../custom_photo_selector.dart';
import '../hero_poster_banner.dart';

/// 落地选图页：顶部海报轮播 + 底部可拖拽展开的照片选择器 + 右上角关于按钮 + 导入加载遮罩
class LandingPickScreen extends StatelessWidget {
  final bool isLoading;
  final VoidCallback onPickPresetWatermark;
  final VoidCallback onOpenQuickOptions;
  final void Function(List<DevicePhotoModel> photoList, WatermarkType type) onImportWithWatermarkType;
  final ValueChanged<DevicePhotoModel> onPhotoSelected;
  final ValueChanged<List<DevicePhotoModel>> onMultiplePhotosSelected;

  const LandingPickScreen({
    super.key,
    required this.isLoading,
    required this.onPickPresetWatermark,
    required this.onOpenQuickOptions,
    required this.onImportWithWatermarkType,
    required this.onPhotoSelected,
    required this.onMultiplePhotosSelected,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final topPadding = MediaQuery.of(context).padding.top;

    return Stack(
      children: [
        // 1. 顶部大图海报轮播 (独立渲染层, 拖拽底部面板时不触发重绘)
        Positioned.fill(
          child: RepaintBoundary(
            child: HeroPosterBanner(
              onActionButtonTap: onPickPresetWatermark,
              onMoreOptionsTap: onOpenQuickOptions,
            ),
          ),
        ),

        // 2. 底部可向上拖拽全屏的自制照片选择器 (独立渲染层)
        RepaintBoundary(
          child: CustomPhotoSelector(
            onImportWithWatermarkType: onImportWithWatermarkType,
            onPhotoSelected: onPhotoSelected,
            onMultiplePhotosSelected: onMultiplePhotosSelected,
          ),
        ),

        // 3. 顶部右上角「关于」按钮
        Positioned(
          top: (topPadding > 0 ? topPadding : 16) + 8,
          right: 16,
          child: _TopAboutButton(isDark: isDark),
        ),

        // 4. 图片导入加载中遮罩
        if (isLoading)
          Positioned.fill(
            child: Container(
              color: Colors.black45,
              child: const Center(
                child: CircularProgressIndicator(
                  color: Color(0xFFFFD600),
                  strokeWidth: 2.5,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// 右上角「关于」胶囊按钮
class _TopAboutButton extends StatelessWidget {
  final bool isDark;

  const _TopAboutButton({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          AboutPage.open(context);
        },
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.42),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.info_outline_rounded,
                size: 16,
                color: Colors.white,
              ),
              SizedBox(width: 5),
              Text(
                '关于',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  letterSpacing: -0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
