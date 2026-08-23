import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../services/device_photo_service.dart';
import '../../theme/one_ui_theme.dart';

/// 独立的缩略图卡片组件
/// 严格 1:1 正方形直角，首帧直接从内存缓存提取图片，0 延时 0 闪烁
class PhotoThumbnailCard extends StatefulWidget {
  final DevicePhotoModel photo;
  final bool isSelected;
  final bool isMultiSelect;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const PhotoThumbnailCard({
    super.key,
    required this.photo,
    required this.isSelected,
    required this.isMultiSelect,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  State<PhotoThumbnailCard> createState() => _PhotoThumbnailCardState();
}

class _PhotoThumbnailCardState extends State<PhotoThumbnailCard> with AutomaticKeepAliveClientMixin {
  Uint8List? _thumbBytes;
  bool _loading = true;
  bool _isMotionPhoto = false;
  bool _isUltraHdr = false;
  bool _disposed = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    // 立即同步从内存缓存获取（首帧命中即刻展示，0 延时 0 闪烁）
    final cached = DevicePhotoService.getCachedThumbnail(widget.photo, size: 256);
    if (cached != null) {
      _thumbBytes = cached;
      _loading = false;
    }
    final cachedMotion = DevicePhotoService.getCachedMotionPhoto(widget.photo);
    if (cachedMotion != null) {
      _isMotionPhoto = cachedMotion;
    }
    final cachedHdr = DevicePhotoService.getCachedUltraHdr(widget.photo);
    if (cachedHdr != null) {
      _isUltraHdr = cachedHdr;
    }

    if (_thumbBytes == null || cachedMotion == null || cachedHdr == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_disposed) {
          if (_thumbBytes == null) _loadThumbnail();
          if (cachedMotion == null) _checkMotionPhoto();
          if (cachedHdr == null) _checkUltraHdr();
        }
      });
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  Future<void> _loadThumbnail() async {
    final bytes = await DevicePhotoService.getThumbnail(widget.photo, size: 256);
    if (!_disposed && mounted) {
      setState(() {
        _thumbBytes = bytes;
        _loading = false;
      });
    }
  }

  Future<void> _checkMotionPhoto() async {
    final isMotion = await DevicePhotoService.isMotionPhoto(widget.photo);
    if (!_disposed && mounted && isMotion) {
      setState(() {
        _isMotionPhoto = true;
      });
    }
  }

  Future<void> _checkUltraHdr() async {
    final isHdr = await DevicePhotoService.isUltraHdr(widget.photo);
    if (!_disposed && mounted && isHdr) {
      setState(() {
        _isUltraHdr = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return GestureDetector(
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: Container(
        decoration: BoxDecoration(
          border: widget.isSelected
              ? Border.all(color: OneUITheme.primaryBlue, width: 2.5)
              : null,
          color: const Color(0xFF18181E),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 缩略图主体 (直接首帧绘制, gapless 无缝回放，归一化 GPU 纹理显存)
            if (_thumbBytes != null)
              Image.memory(
                _thumbBytes!,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                filterQuality: FilterQuality.low,
                cacheWidth: 256,
                cacheHeight: 256,
              )
            else if (_loading)
              const ColoredBox(color: Color(0xFF1E1E26))
            else
              Container(
                color: const Color(0xFF24242C),
                child: const Icon(Icons.image_not_supported_outlined, color: Colors.white38, size: 20),
              ),

            // 左上角角标徽章（动态照片 + Ultra HDR 角标）
            if (_isMotionPhoto || _isUltraHdr)
              Positioned(
                top: 5,
                left: 5,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 1. 动态照片角标
                    if (_isMotionPhoto)
                      Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.68),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.motion_photos_on_rounded,
                          size: 13,
                          color: Color(0xFFFFD600),
                        ),
                      ),

                    if (_isMotionPhoto && _isUltraHdr)
                      const SizedBox(width: 3.5),

                    // 2. Ultra HDR 角标
                    if (_isUltraHdr)
                      Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.68),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.hdr_on_rounded,
                          size: 13,
                          color: Color(0xFFFFD600),
                        ),
                      ),
                  ],
                ),
              ),

            // 底部暗色渐变与时间/尺寸标签
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.75),
                      Colors.transparent,
                    ],
                  ),
                ),
                child: Text(
                  widget.photo.formattedDate.isNotEmpty ? widget.photo.formattedDate : widget.photo.formattedSize,
                  style: const TextStyle(
                    fontSize: 9,
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    shadows: [Shadow(color: Colors.black, blurRadius: 2)],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),

            // 多选勾选标记 (默认多选，右上角常驻清晰选择圈)
            Positioned(
              top: 5,
              right: 5,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.isSelected ? OneUITheme.primaryBlue : Colors.black.withValues(alpha: 0.4),
                  border: Border.all(
                    color: widget.isSelected ? Colors.white : Colors.white.withValues(alpha: 0.8),
                    width: 1.8,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.3),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: widget.isSelected
                    ? const Icon(Icons.check, size: 14, color: Colors.white)
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
