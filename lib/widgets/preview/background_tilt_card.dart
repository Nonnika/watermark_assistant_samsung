import 'package:flutter/material.dart';

import '../../models/image_item.dart';

/// 倾斜背景卡片渲染（扑克牌堆叠效果）
class BackgroundTiltCard extends StatelessWidget {
  final ImageItem item;
  final Rect renderRect;
  final double scale;
  final double offsetX;
  final double offsetY;
  final double rotation;
  final bool isDark;

  const BackgroundTiltCard({
    super.key,
    required this.item,
    required this.renderRect,
    required this.scale,
    required this.offsetX,
    required this.offsetY,
    required this.rotation,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    const opacity = AlwaysStoppedAnimation<double>(0.55);
    final image = item.decodedImage;
    final pixelRatio = MediaQuery.devicePixelRatioOf(context);
    return Positioned(
      left: renderRect.left,
      top: renderRect.top,
      width: renderRect.width,
      height: renderRect.height,
      child: Transform.translate(
        offset: Offset(offsetX, offsetY),
        child: Transform.rotate(
          angle: rotation,
          child: Transform.scale(
            scale: scale,
            child: RepaintBoundary(
              child: Container(
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF141416)
                      : const Color(0xFFD0D2DC),
                  borderRadius: BorderRadius.circular(2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(
                        alpha: isDark ? 0.45 : 0.2,
                      ),
                      blurRadius: 10,
                      offset: Offset(offsetX * 0.4, 4),
                    ),
                  ],
                  border: Border.all(
                    color: isDark ? Colors.white12 : Colors.black12,
                    width: 1.0,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                // 复用编辑器预览纹理；透明度直接由图片画笔处理，无需 Opacity 离屏图层。
                child: image != null
                    ? RawImage(
                        image: image,
                        fit: BoxFit.cover,
                        opacity: opacity,
                        filterQuality: FilterQuality.low,
                      )
                    : Image(
                        image: ResizeImage(
                          MemoryImage(item.bytes),
                          width: (renderRect.width * pixelRatio)
                              .clamp(1.0, 1440.0)
                              .ceil(),
                          height: (renderRect.height * pixelRatio)
                              .clamp(1.0, 1440.0)
                              .ceil(),
                          policy: ResizeImagePolicy.fit,
                        ),
                        fit: BoxFit.cover,
                        opacity: opacity,
                        filterQuality: FilterQuality.low,
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
