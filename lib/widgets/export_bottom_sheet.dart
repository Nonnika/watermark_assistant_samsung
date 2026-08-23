import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../models/frame_watermark_config.dart';
import '../models/image_item.dart';
import '../models/watermark_config.dart';
import '../services/watermark_processor.dart';
import '../utils/media_store_helper.dart';

class ExportBottomSheet extends StatefulWidget {
  final WatermarkType watermarkType;
  final List<ImageItem> images;
  final int currentIndex;
  final ui.Image? watermarkImage;
  final WatermarkConfig pngConfig;
  final ui.Image? logoImage;
  final FrameWatermarkConfig frameConfig;

  final bool isIndividualMode;
  final bool initialExportAll;

  const ExportBottomSheet({
    super.key,
    required this.watermarkType,
    required this.images,
    required this.currentIndex,
    required this.watermarkImage,
    required this.pngConfig,
    required this.logoImage,
    required this.frameConfig,
    this.isIndividualMode = false,
    this.initialExportAll = true,
  });

  @override
  State<ExportBottomSheet> createState() => _ExportBottomSheetState();
}

class _ExportBottomSheetState extends State<ExportBottomSheet> {
  // 黑黄高质感配色定义
  static const Color _bgDark = Color(0xFF141418);
  static const Color _cardDark = Color(0xFF202026);
  static const Color _cardBorder = Color(0xFF2C2C34);
  static const Color _accentYellow = Color(0xFFFFD600);
  static const Color _textPrimary = Color(0xFFF5F5F7);
  static const Color _textSecondary = Color(0xFF9E9EA8);

  final String _format = 'jpg';
  int _jpgQuality = 95;
  bool _exportAll = true; // true: 批量导出, false: 仅当前图
  bool _preserveMotion = true; // 是否保留动态照片
  bool _watermarkMotionVideo = false; // 默认保留原汁原味动态视频（零损耗、原生帧率流畅播放）
  bool _isProcessing = false;
  double _progress = 0.0;
  String _statusText = '';
  final List<String> _exportedPaths = [];
  bool _isFinished = false;

  @override
  void initState() {
    super.initState();
    _exportAll = widget.initialExportAll && widget.images.length > 1;
  }

  Future<void> _startExport() async {
    setState(() {
      _isProcessing = true;
      _progress = 0.0;
      _statusText = '准备导出...';
      _exportedPaths.clear();
    });

    final targetList = _exportAll ? widget.images : [widget.images[widget.currentIndex]];
    final total = targetList.length;

    // 高通 SoC 优化：流水线式预解码下一张全分辨率图片，
    // 让 Snapdragon 大核上的系统级 JPEG 解码与当前图的合成 / 硬件编码并行，缩短批量导出总耗时
    Future<ui.Image>? nextDecode =
        total > 0 ? WatermarkProcessor.decodeFullResolutionImage(targetList[0].bytes) : null;

    try {
      for (int i = 0; i < total; i++) {
        final item = targetList[i];
        final isMotionTranscode = item.isMotionPhoto && _preserveMotion && _watermarkMotionVideo;
        setState(() {
          _statusText = isMotionTranscode
              ? '正在合成图片与动态视频水印 (${i + 1}/$total): ${item.name}'
              : '正在合成并导出 (${i + 1}/$total): ${item.name}';
          _progress = (i) / total;
        });

        // 取出上一轮已预解码的全分辨率图
        final baseImg = await nextDecode!;
        // 立即启动下一张的异步预解码 (与本张合成、MediaStore 落盘并行)
        nextDecode = i + 1 < total
            ? WatermarkProcessor.decodeFullResolutionImage(targetList[i + 1].bytes)
            : null;

        try {
          final WatermarkConfig curPngConfig = widget.isIndividualMode
              ? (item.individualPngConfig ?? widget.pngConfig)
              : widget.pngConfig;

          final FrameWatermarkConfig curFrameConfig = widget.isIndividualMode
              ? (item.individualFrameConfig ?? widget.frameConfig.copyWith(exifInfo: item.exifInfo))
              : widget.frameConfig.copyWith(exifInfo: item.exifInfo);

          final outputBytes = await WatermarkProcessor.compositeFullResolutionUnified(
            baseImage: baseImg,
            type: widget.watermarkType,
            watermarkImage: widget.watermarkImage,
            pngConfig: curPngConfig,
            logoImage: widget.logoImage,
            frameConfig: curFrameConfig,
            outputFormat: _format,
            originalBytes: item.bytes,
            originalPath: item.path,
            quality: _jpgQuality,
            preserveMotionPhoto: _preserveMotion && _format == 'jpg',
            watermarkMotionVideo: _watermarkMotionVideo && _preserveMotion && _format == 'jpg',
          );

          final savedPath = await MediaStoreHelper.saveImageFile(
            bytes: outputBytes,
            originalName: item.name,
            format: _format,
            customPrefix: widget.watermarkType == WatermarkType.frame ? 'FRAME_' : 'WM_',
          );

          _exportedPaths.add(savedPath);
        } finally {
          baseImg.dispose();
        }

        setState(() {
          _progress = (i + 1) / total;
        });
      }

      setState(() {
        _isProcessing = false;
        _isFinished = true;
        _statusText = '全部导出完成！共 ${_exportedPaths.length} 张图片已保存至相册。';
      });
    } catch (e) {
      setState(() {
        _isProcessing = false;
        _statusText = '导出出错: $e';
      });
    } finally {
      // 出错或提前退出时释放尚未消费的预解码结果，避免纹理泄漏
      try {
        final pending = await nextDecode;
        pending?.dispose();
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasHdr = widget.images.any((img) => img.isUltraHdr);
    final hasMotion = widget.images.any((img) => img.isMotionPhoto);

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      decoration: BoxDecoration(
        color: _bgDark,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border.all(color: _cardBorder.withValues(alpha: 0.6), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.6),
            blurRadius: 24,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: _accentYellow.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: _accentYellow.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.file_download_outlined,
                    color: _accentYellow,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _isFinished ? '导出完成' : '导出',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: _textPrimary,
                    letterSpacing: -0.5,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),

            if (!_isProcessing && !_isFinished) ...[
              if (widget.images.length > 1) ...[
                Row(
                  children: [
                    Expanded(
                      child: _buildChoiceChip(
                        title: '仅当前图片 (1 张)',
                        isSelected: !_exportAll,
                        onTap: () => setState(() => _exportAll = false),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _buildChoiceChip(
                        title: '批量导出全部 (${widget.images.length} 张)',
                        isSelected: _exportAll,
                        onTap: () => setState(() => _exportAll = true),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
              ],

              const SizedBox(height: 2),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'JPG 导出画质质量',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: _textPrimary,
                    ),
                  ),
                    Text(
                      '$_jpgQuality%',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: _accentYellow,
                      ),
                    ),
                  ],
                ),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: _accentYellow,
                    inactiveTrackColor: _cardDark,
                    thumbColor: _accentYellow,
                    overlayColor: _accentYellow.withValues(alpha: 0.2),
                    trackHeight: 6,
                  ),
                  child: Slider(
                    value: _jpgQuality.toDouble(),
                    min: 50,
                    max: 100,
                    divisions: 50,
                    onChanged: (val) => setState(() => _jpgQuality = val.toInt()),
                  ),
                ),

                if (hasMotion) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: _buildChoiceChip(
                          title: '动态照片 (保留实况)',
                          isSelected: _preserveMotion,
                          onTap: () => setState(() => _preserveMotion = true),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _buildChoiceChip(
                          title: '静态封面 (普通照片)',
                          isSelected: !_preserveMotion,
                          onTap: () => setState(() => _preserveMotion = false),
                        ),
                      ),
                    ],
                  ),
                  if (_preserveMotion) ...[
                  const SizedBox(height: 10),
                  GestureDetector(
                    onTap: () => setState(() => _watermarkMotionVideo = !_watermarkMotionVideo),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: _cardDark,
                        borderRadius: BorderRadius.circular(30),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _watermarkMotionVideo ? Icons.play_circle_fill_rounded : Icons.play_circle_outline_rounded,
                            size: 22,
                            color: _watermarkMotionVideo ? _accentYellow : _textSecondary,
                          ),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '动态播放同步水印',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: _textPrimary,
                                  ),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  '此功能严重影响导出速度',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                    color: _textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Switch(
                            value: _watermarkMotionVideo,
                            onChanged: (val) => setState(() => _watermarkMotionVideo = val),
                            activeThumbColor: _accentYellow,
                            activeTrackColor: _accentYellow.withValues(alpha: 0.35),
                            inactiveTrackColor: Colors.black26,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.motion_photos_on_rounded, size: 16, color: _accentYellow),
                    SizedBox(width: 6),
                    Text(
                      '加水印后将保留内嵌视频，相册中依然为动态照片',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: _accentYellow,
                      ),
                    ),
                  ],
                ),
              ],

              if (hasHdr) ...[
                const SizedBox(height: 14),
                const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.hdr_on_rounded, size: 18, color: _accentYellow),
                    SizedBox(width: 6),
                    Text(
                      '已保留 Ultra HDR 高动态光影与增益图',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: _accentYellow,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ],
                ),
              ],

              const SizedBox(height: 24),

              ElevatedButton.icon(
                onPressed: _startExport,
                icon: const Icon(Icons.download_done_rounded, color: Colors.black, size: 22),
                label: Text(
                  _exportAll
                      ? '立即批量导出 (${widget.images.length} 张)'
                      : '立即导出当前图片',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Colors.black,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _accentYellow,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: const StadiumBorder(),
                  elevation: 2,
                  shadowColor: _accentYellow.withValues(alpha: 0.3),
                ),
              ),
            ] else if (_isProcessing) ...[
              Column(
                children: [
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: LinearProgressIndicator(
                      value: _progress,
                      minHeight: 10,
                      backgroundColor: _cardDark,
                      valueColor: const AlwaysStoppedAnimation(_accentYellow),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _statusText,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: _textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${(_progress * 100).toInt()}%',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: _accentYellow,
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ] else ...[
              Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: _accentYellow.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.check_circle_rounded, size: 54, color: _accentYellow),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _statusText,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: _textPrimary,
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (_exportedPaths.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: _cardDark,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: _cardBorder),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.folder_outlined, size: 16, color: _accentYellow),
                              SizedBox(width: 6),
                              Text(
                                '相册位置：Pictures/OneWatermark',
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: _accentYellow),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _exportedPaths.first,
                            style: const TextStyle(
                              fontSize: 12,
                              color: _textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _accentYellow,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: const StadiumBorder(),
                    ),
                    child: const Text('完成', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.black)),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildChoiceChip({
    required String title,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? _accentYellow
              : _cardDark,
          borderRadius: BorderRadius.circular(28),
        ),
        alignment: Alignment.center,
        child: Text(
          title,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
            color: isSelected ? Colors.black : _textSecondary,
          ),
        ),
      ),
    );
  }
}
