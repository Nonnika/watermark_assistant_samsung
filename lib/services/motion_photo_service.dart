import 'dart:typed_data';
import 'motion_photo/motion_photo_composer.dart';
import 'motion_photo/motion_photo_parser.dart';
import 'motion_photo/motion_photo_platform.dart';

export 'motion_photo/motion_photo_parser.dart' show MotionVideoInfo;

/// 动态照片 (Motion Photo / Live Photo / MicroVideo) 全流程处理引擎门面：
/// 解析（[MotionPhotoParser]）、合成（[MotionPhotoComposer]）、平台通道
/// （[MotionPhotoPlatform]）的统一对外出口，保持既有 `MotionPhotoService.xxx`
/// 调用点不变。深度支持 Samsung (SEF/SEFT)、Google Pixel (GCamera/MicroVideo)、
/// 小米/OPPO/vivo 等主流 Android 动态照片。
class MotionPhotoService {
  MotionPhotoService._();

  /// 为动态照片的内嵌 MP4 视频叠加水印图层
  static Future<Uint8List> watermarkMotionVideo({
    required Uint8List videoBytes,
    required Uint8List overlayPngBytes,
  }) {
    return MotionPhotoPlatform.watermarkMotionVideo(
      videoBytes: videoBytes,
      overlayPngBytes: overlayPngBytes,
    );
  }

  /// 检查图像字节流是否为真实的动态照片 (Motion Photo)
  static bool isMotionPhoto(Uint8List bytes) => MotionPhotoParser.isMotionPhoto(bytes);

  /// 搜索 MP4 视频流在整个图像字节流中的起始偏移位置 (支持 JPEG 与 HEIC)
  static int findMp4Offset(Uint8List bytes) => MotionPhotoParser.findMp4Offset(bytes);

  /// 从动态照片中精确提取纯净 MP4 视频流 (支持 Android 原生高效提取与 Dart 兜底)
  static Future<MotionVideoInfo?> extractMotionVideoAsync(
    Uint8List bytes, {
    String? path,
    String? uri,
  }) {
    return MotionPhotoPlatform.extractMotionVideoAsync(bytes, path: path, uri: uri);
  }

  /// 从动态照片中精确提取纯净 MP4 视频流 (纯 Dart 同步解析)
  static MotionVideoInfo? extractMotionVideo(Uint8List bytes) {
    return MotionPhotoParser.extractMotionVideo(bytes);
  }

  /// 提取纯净的静态封面主图 JPEG (剔除尾部内嵌 MP4 与 SEF)
  static Uint8List extractPrimaryJpg(Uint8List bytes) {
    return MotionPhotoParser.extractPrimaryJpg(bytes);
  }

  /// 将处理完水印的高清静态 JPEG 与动态视频流 (MP4) 重新组装为原生动态照片 (优先 Android 原生组装)
  static Future<Uint8List> compositeAndPreserveMotionPhotoAsync({
    required Uint8List watermarkedJpgBytes,
    required Uint8List motionVideoBytes,
    int? presentationTimestampUs,
  }) {
    return MotionPhotoPlatform.compositeAndPreserveMotionPhotoAsync(
      watermarkedJpgBytes: watermarkedJpgBytes,
      motionVideoBytes: motionVideoBytes,
      presentationTimestampUs: presentationTimestampUs,
    );
  }

  /// 将处理完水印的高清静态 JPEG 与动态视频流 (MP4) 重新组装为原生动态照片 (纯 Dart 同步装配)
  static Uint8List compositeAndPreserveMotionPhoto({
    required Uint8List watermarkedJpgBytes,
    required Uint8List motionVideoBytes,
    int? presentationTimestampUs,
  }) {
    return MotionPhotoComposer.compositeAndPreserveMotionPhoto(
      watermarkedJpgBytes: watermarkedJpgBytes,
      motionVideoBytes: motionVideoBytes,
      presentationTimestampUs: presentationTimestampUs,
    );
  }
}
