import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import '../../models/watermark_config.dart';

/// 照片选择器底部的操作栏
class SelectorBottomAction extends StatelessWidget {
  final bool isVisible;
  final ValueChanged<WatermarkType> onSelectType;

  /// 渐进式模糊 Fragment Shader（单次加载，全局缓存）
  static final Future<ui.FragmentProgram?> _programLoader =
      ui.FragmentProgram.fromAsset('shaders/progressive_blur.frag')
          .then<ui.FragmentProgram?>((p) => p)
          .catchError((_) => null);

  const SelectorBottomAction({
    super.key,
    required this.isVisible,
    required this.onSelectType,
  });

  @override
  Widget build(BuildContext context) {
    if (!isVisible) {
      return const SizedBox.shrink();
    }

    return Stack(
      children: [
        // 1. 底部渐进式模糊 (自定义 Fragment Shader：单图层、sigma 随高度逐像素衰减，边缘天然羽化) + 白色渐变阴影
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          height: 150,
          child: IgnorePointer(
            child: FutureBuilder<ui.FragmentProgram?>(
              future: _programLoader,
              builder: (context, snapshot) {
                return Stack(
                  children: [
                    Positioned.fill(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          return ClipRect(
                            child: BackdropFilter(
                              filter: _createBlurFilter(
                                snapshot.data,
                                constraints.maxWidth,
                                constraints.maxHeight,
                              ),
                              child: const SizedBox.expand(),
                            ),
                          );
                        },
                      ),
                    ),
                    // 黑色渐变阴影：顶部完全透明，向下逐渐压暗保证按钮可读性
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.black.withValues(alpha: 0.0),
                              Colors.black.withValues(alpha: 0.35),
                              Colors.black.withValues(alpha: 0.60),
                            ],
                            stops: const [0.0, 0.45, 1.0],
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),

        // 2. 底部叠加层：居中并排的「边框水印」与「叠加水印」高级质感胶囊按钮
        Positioned(
          bottom: 18,
          left: 0,
          right: 0,
          child: SafeArea(
            top: false,
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 按钮 1: 「边框水印」
                  _buildActionButton(
                    title: '边框水印',
                    icon: Icons.crop_square_rounded,
                    onTap: () => onSelectType(WatermarkType.frame),
                  ),
                  const SizedBox(width: 14),

                  // 按钮 2: 「叠加水印」
                  _buildActionButton(
                    title: '叠加水印',
                    icon: Icons.layers_rounded,
                    onTap: () => onSelectType(WatermarkType.floatingPng),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// 优先使用渐进模糊 Shader（逐像素衰减 sigma，边缘羽化）；
  /// Shader 不支持或加载失败时回退到普通单层高斯模糊
  ui.ImageFilter _createBlurFilter(ui.FragmentProgram? program, double width, double height) {
    if (program != null && ui.ImageFilter.isShaderFilterSupported) {
      try {
        final shader = program.fragmentShader()
          ..setFloat(0, width)
          ..setFloat(1, height)
          ..setFloat(2, 26.0); // u_max_radius
        return ui.ImageFilter.shader(shader);
      } catch (_) {
        // fall through to classic blur
      }
    }
    return ui.ImageFilter.blur(sigmaX: 22, sigmaY: 22);
  }

  Widget _buildActionButton({
    required String title,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    // 亮色半透明高斯模糊毛玻璃胶囊按钮 (BackdropFilter 实时模糊底层照片)
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Material(
          color: Colors.white.withValues(alpha: 0.38),
          child: InkWell(
            onTap: onTap,
            splashColor: Colors.black12,
            highlightColor: Colors.black.withValues(alpha: 0.06),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 16, color: const Color(0xFFFFD600)),
                  const SizedBox(width: 6),
                  Text(
                    title,
                    style: const TextStyle(
                      color: Color(0xFF1E1E24),
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
