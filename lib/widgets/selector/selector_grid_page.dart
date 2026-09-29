import 'package:flutter/material.dart';
import '../../services/device_photo_service.dart';
import '../../theme/one_ui_theme.dart';
import 'photo_thumbnail_card.dart';

/// 相册 1:1 正方形网格分页：加载态 / 空态（无权限或无照片）/ 缩略图九宫格，
/// 折叠态下支持竖直拖拽与过冲回弹驱动面板收起
class SelectorGridPage extends StatelessWidget {
  final List<DevicePhotoModel> items;
  final ScrollController scrollController;
  final bool isExpanded;
  final bool isLoading;
  final bool hasPermission;
  final String? loadingTitle;
  final String emptyTitle;
  final IconData emptyIcon;
  final Set<String> selectedIds;
  final ValueChanged<DevicePhotoModel> onTogglePhoto;
  final VoidCallback onRequestPermission;
  final VoidCallback onRefresh;
  final VoidCallback onCollapseRequest;
  final GestureDragStartCallback? onDragStart;
  final GestureDragUpdateCallback? onDragUpdate;
  final GestureDragEndCallback? onDragEnd;

  const SelectorGridPage({
    super.key,
    required this.items,
    required this.scrollController,
    required this.isExpanded,
    required this.isLoading,
    required this.hasPermission,
    required this.emptyTitle,
    required this.emptyIcon,
    required this.selectedIds,
    required this.onTogglePhoto,
    required this.onRequestPermission,
    required this.onRefresh,
    required this.onCollapseRequest,
    this.onDragStart,
    this.onDragUpdate,
    this.onDragEnd,
    this.loadingTitle,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading && items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2.2,
                color: loadingTitle != null ? const Color(0xFFFFD600) : Colors.white.withValues(alpha: 0.4),
              ),
            ),
            if (loadingTitle != null) ...[
              const SizedBox(height: 10),
              Text(
                loadingTitle!,
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ],
          ],
        ),
      );
    }

    if (items.isEmpty) {
      final isNoPerm = !hasPermission;
      final displayTitle = isNoPerm ? '未获得相册访问权限' : emptyTitle;
      final displayIcon = isNoPerm ? Icons.lock_outline_rounded : emptyIcon;

      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF16161C),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white12),
        ),
        child: Center(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(displayIcon, color: Colors.white54, size: 22),
              const SizedBox(width: 10),
              Text(
                displayTitle,
                style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: isNoPerm ? onRequestPermission : onRefresh,
                child: Text(
                  isNoPerm ? '申请权限' : '刷新',
                  style: TextStyle(
                    color: isNoPerm ? const Color(0xFFFFD600) : OneUITheme.primaryBlue,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is OverscrollNotification && notification.overscroll < 0) {
          onCollapseRequest();
          return true;
        }
        if (notification is ScrollUpdateNotification &&
            notification.metrics.pixels <= 0 &&
            (notification.scrollDelta ?? 0) < -12) {
          onCollapseRequest();
          return true;
        }
        return false;
      },
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onVerticalDragStart: !isExpanded ? onDragStart : null,
        onVerticalDragUpdate: !isExpanded ? onDragUpdate : null,
        onVerticalDragEnd: !isExpanded ? onDragEnd : null,
        child: GridView.builder(
          controller: scrollController,
          physics: isExpanded
              ? const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics())
              : const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(16, 0, 16, selectedIds.isNotEmpty ? 84 : 24),
          // ignore: deprecated_member_use
          cacheExtent: 180,
          addRepaintBoundaries: false, // 专为 Adreno 优化：避免为每个卡片分配独立离屏 Texture
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            childAspectRatio: 1.0,
          ),
          itemCount: items.length,
          itemBuilder: (context, index) {
            final photo = items[index];
            final isSelected = selectedIds.contains(photo.id);

            return PhotoThumbnailCard(
              key: ValueKey('photo_${photo.id}'),
              photo: photo,
              isSelected: isSelected,
              isMultiSelect: true,
              onTap: () => onTogglePhoto(photo),
              onLongPress: () => onTogglePhoto(photo),
            );
          },
        ),
      ),
    );
  }
}
