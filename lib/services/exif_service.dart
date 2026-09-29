import 'dart:typed_data';
import '../models/exif_info.dart';
import 'exif/exif_injector.dart';
import 'exif/exif_reader.dart';
import 'exif/tiff_container_extractor.dart';

/// EXIF 能力门面：读取解析（[ExifReader]）、容器剥离与 Orientation 处理
/// （[TiffContainerExtractor]）、注入回写（[ExifInjector]）的统一对外出口，
/// 保持既有 `ExifService.xxx` 调用点不变。
class ExifService {
  ExifService._();

  /// 异步提取 EXIF 信息（结合纯 Dart 提取器与 Android 原生 ExifInterface 双重保障）
  static Future<ExifInfo> extractExifAsync(
    Uint8List bytes, {
    String? path,
    String? uri,
  }) {
    return ExifReader.extractExifAsync(bytes, path: path, uri: uri);
  }

  /// 从图片字节流中解析 EXIF 拍摄参数（支持 JPEG、WebP、PNG、HEIC/HEIF、TIFF/DNG）
  static ExifInfo extractExif(Uint8List bytes) => ExifReader.extractExif(bytes);

  /// 标准化摄影快门速度 (支持各种分数/比率、十进制秒、APEX Tv 转换与智能约分)
  static String formatExposureTime(dynamic expVal, [dynamic shutterSpeedVal]) {
    return ExifReader.formatExposureTime(expVal, shutterSpeedVal);
  }

  /// 从各类图像容器中精准剥离 TIFF EXIF 数据块
  static Uint8List? extractTiffBytes(Uint8List bytes) {
    return TiffContainerExtractor.extractTiffBytes(bytes);
  }

  /// 获取原始图片 EXIF 中的 Orientation 方向值 (1~8, 默认 1)
  static int getExifOrientation(Uint8List bytes) {
    return TiffContainerExtractor.getExifOrientation(bytes);
  }

  /// 将 APP1 EXIF 段或 TIFF 结构中的 Orientation 旋转标签重置为 1 (正常朝向)
  static Uint8List normalizeExifOrientation(Uint8List app1OrTiffBytes) {
    return TiffContainerExtractor.normalizeExifOrientation(app1OrTiffBytes);
  }

  /// 从 JPEG 字节流中直接提取完整的 APP1 EXIF 数据段
  static Uint8List? extractApp1ExifSegment(Uint8List bytes) {
    return ExifInjector.extractApp1ExifSegment(bytes);
  }

  /// 将纯 TIFF EXIF 字节封装为标准的 JPEG APP1 EXIF 数据段
  static Uint8List createJpegApp1ExifSegment(Uint8List tiffBytes) {
    return ExifInjector.createJpegApp1ExifSegment(tiffBytes);
  }

  /// 将 APP1 EXIF 数据段安全注入到导出的 JPEG 图片流中 (紧随 SOI 之后)
  static Uint8List injectExifToJpeg(Uint8List jpegBytes, Uint8List app1Segment) {
    return ExifInjector.injectExifToJpeg(jpegBytes, app1Segment);
  }

  /// 将 EXIF TIFF 字节封装为 PNG eXIf chunk 注入到导出的 PNG 图片流中
  static Uint8List injectExifToPng(Uint8List pngBytes, Uint8List tiffBytes) {
    return ExifInjector.injectExifToPng(pngBytes, tiffBytes);
  }

  /// 从原图字节中提取 EXIF 并完整写回合成导出的图片中 (支持 JPG 与 PNG)
  static Uint8List preserveExif({
    required Uint8List outputBytes,
    required Uint8List originalBytes,
    required String format,
  }) {
    return ExifInjector.preserveExif(
      outputBytes: outputBytes,
      originalBytes: originalBytes,
      format: format,
    );
  }

  /// 标准 CRC-32 计算 (IEEE 802.3 多项式 0xEDB88320)
  static int calculateCrc32(List<int> bytes) => ExifInjector.calculateCrc32(bytes);
}
