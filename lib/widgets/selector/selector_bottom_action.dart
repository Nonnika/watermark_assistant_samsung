import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../models/watermark_config.dart';

/// 照片选择器底部的操作栏
class SelectorBottomAction extends StatelessWidget {
  final bool isVisible;
  final ValueChanged<WatermarkType> onSelectType;

  static final _buttonBlur = ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18);

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
        // 1. 拉长顶部羽化区，让模糊和暗色遮罩缓慢融入照片。
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          height: 210,
          child: IgnorePointer(
            child: Stack(
              children: [
                Positioned.fill(child: _ProgressiveBlurBackdrop()),
                // 黑色渐变阴影：顶部完全透明，向下逐渐压暗保证按钮可读性
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.0),
                          Colors.black.withValues(alpha: 0.015),
                          Colors.black.withValues(alpha: 0.12),
                          Colors.black.withValues(alpha: 0.32),
                          Colors.black.withValues(alpha: 0.58),
                        ],
                        stops: const [0.0, 0.15, 0.40, 0.70, 1.0],
                      ),
                    ),
                  ),
                ),
              ],
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
              // 两个胶囊互不重叠，可共享模糊输入；底部渐进模糊单独处理。
              child: BackdropGroup(
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
        ),
      ],
    );
  }

  Widget _buildActionButton({
    required String title,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    // 亮色半透明高斯模糊毛玻璃胶囊按钮 (BackdropFilter 实时模糊底层照片)
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: BackdropFilter.grouped(
        filter: _buttonBlur,
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

/// Shader/滤镜跟随组件生命周期复用，选择照片时不反复创建 GPU 资源。
class _ProgressiveBlurBackdrop extends StatefulWidget {
  const _ProgressiveBlurBackdrop();

  static final Future<ui.FragmentProgram?> _programLoader =
      ui.FragmentProgram.fromAsset('shaders/progressive_blur.frag')
          .then<ui.FragmentProgram?>((p) => p)
          .catchError((_) => null);

  @override
  State<_ProgressiveBlurBackdrop> createState() =>
      _ProgressiveBlurBackdropState();
}

class _ProgressiveBlurBackdropState extends State<_ProgressiveBlurBackdrop> {
  static const _edgeFade = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color(0x00FFFFFF),
      Color(0x04FFFFFF),
      Color(0x24FFFFFF),
      Color(0x6BFFFFFF),
      Color(0xBDFFFFFF),
      Color(0xF0FFFFFF),
      Color(0xFFFFFFFF),
    ],
    stops: [0.0, 0.15, 0.32, 0.50, 0.68, 0.85, 1.0],
  );

  ui.FragmentShader? _shader;
  ui.ImageFilter _filter = ui.ImageFilter.blur(sigmaX: 22, sigmaY: 22);

  @override
  void initState() {
    super.initState();
    if (ui.ImageFilter.isShaderFilterSupported) _loadShader();
  }

  Future<void> _loadShader() async {
    final program = await _ProgressiveBlurBackdrop._programLoader;
    if (!mounted || program == null) return;
    ui.FragmentShader? shader;
    try {
      // 引擎自动填写前两个 float（输入纹理的物理像素尺寸）及第一个 sampler。
      shader = program.fragmentShader()..setFloat(2, 26.0);
      final filter = ui.ImageFilter.shader(shader);
      setState(() {
        _shader = shader;
        _filter = filter;
      });
    } catch (_) {
      shader?.dispose();
      // 不支持自定义滤镜或加载失败时，高斯模糊也通过同一遮罩羽化。
    }
  }

  @override
  void dispose() {
    _shader?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: _filter,
        // 在滤镜自身的图层内淡出结果，保持外面的原图清晰可见。
        // 遮罩使用组件局部坐标，Shader 加载前和降级时也没有硬裁切边缘。
        child: const DecoratedBox(
          decoration: BoxDecoration(
            gradient: _edgeFade,
            backgroundBlendMode: BlendMode.dstIn,
          ),
          child: SizedBox.expand(),
        ),
      ),
    );
  }
}
