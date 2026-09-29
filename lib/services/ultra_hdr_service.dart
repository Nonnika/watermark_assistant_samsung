import 'dart:typed_data';
import 'ultra_hdr/ultra_hdr_composer.dart';
import 'ultra_hdr/ultra_hdr_detector.dart';
import 'ultra_hdr/ultra_hdr_display.dart';

export 'ultra_hdr/ultra_hdr_detector.dart' show UltraHdrMetadata;

/// Ultra HDR 能力门面：屏幕显示状态（[UltraHdrDisplay]）、图像检测与
/// Gainmap 提取（[UltraHdrDetector]）、XMP/MPF 构建与合成（[UltraHdrComposer]）
/// 的统一对外出口，保持既有 `UltraHdrService.xxx` 调用点不变。
class UltraHdrService {
  UltraHdrService._();

  /// 检查当前设备屏幕是否支持硬件级 HDR / Ultra HDR 显示
  static Future<bool> isHdrDisplaySupported() => UltraHdrDisplay.isHdrDisplaySupported();

  /// 获取当前屏幕的 HDR/SDR 动态亮度提升比例
  static Future<double> getHdrSdrRatio() => UltraHdrDisplay.getHdrSdrRatio();

  /// 动态启用/关闭窗口级 Ultra HDR 显示色彩模式 (COLOR_MODE_HDR)
  static Future<bool> setHdrDisplayMode(bool enable) => UltraHdrDisplay.setHdrDisplayMode(enable);

  /// 异步全方位检测是否为 Ultra HDR 图像 (优先请求 Android 14+ 系统级底层 Gainmap 解码器)
  static Future<bool> checkIsUltraHdr(Uint8List bytes) => UltraHdrDetector.checkIsUltraHdr(bytes);

  /// 检测字节流是否为 Ultra HDR 图像 (包含 Gainmap 增益图 / XMP / SEF 描述符)
  static bool isUltraHdr(Uint8List bytes) => UltraHdrDetector.isUltraHdr(bytes);

  /// 提取 JPEG 中的 Gainmap 辅助增益图像字节流
  static Uint8List? extractGainmapJpeg(Uint8List bytes) {
    return UltraHdrDetector.extractGainmapJpeg(bytes);
  }

  /// 从 XMP 中提取 Ultra HDR 参数
  static UltraHdrMetadata parseMetadata(Uint8List bytes) => UltraHdrDetector.parseMetadata(bytes);

  /// 生成符合 Adobe / ISO 21496-1 / Google GContainer 标准的主图 Ultra HDR XMP 描述符
  static String generateUltraHdrXmp(UltraHdrMetadata meta, {int gainmapLength = 0}) {
    return UltraHdrComposer.generateUltraHdrXmp(meta, gainmapLength: gainmapLength);
  }

  /// 生成符合 Adobe 标准的 Secondary Gainmap 专用 XMP 描述符
  static String generateSecondaryGainmapXmp(UltraHdrMetadata meta) {
    return UltraHdrComposer.generateSecondaryGainmapXmp(meta);
  }

  /// 构建符合 CIPA DC-007 Multi-Picture Format (MPF) 标准的 APP2 标记段
  static Uint8List buildMpfSegment({
    required int primaryImageSize,
    required int gainmapImageSize,
    required int gainmapOffsetFromTiffHeader,
  }) {
    return UltraHdrComposer.buildMpfSegment(
      primaryImageSize: primaryImageSize,
      gainmapImageSize: gainmapImageSize,
      gainmapOffsetFromTiffHeader: gainmapOffsetFromTiffHeader,
    );
  }

  /// 合成并保持 Ultra HDR (Gainmap 与 EXIF 完整原子组装)
  static Future<Uint8List> compositeAndPreserveUltraHdr({
    required Uint8List originalBytes,
    required Uint8List sdrCompositeBytes,
    required double photoLeft,
    required double photoTop,
    required double photoWidth,
    required double photoHeight,
    required double totalWidth,
    required double totalHeight,
    int quality = 95,
  }) {
    return UltraHdrComposer.compositeAndPreserveUltraHdr(
      originalBytes: originalBytes,
      sdrCompositeBytes: sdrCompositeBytes,
      photoLeft: photoLeft,
      photoTop: photoTop,
      photoWidth: photoWidth,
      photoHeight: photoHeight,
      totalWidth: totalWidth,
      totalHeight: totalHeight,
      quality: quality,
    );
  }
}
