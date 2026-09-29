import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'motion_photo_composer.dart';
import 'motion_photo_parser.dart';

/// 动态照片平台通道封装：原生高效管线优先，纯 Dart 解析/合成兜底
class MotionPhotoPlatform {
  static const MethodChannel _nativeChannel = MethodChannel('com.example.watermark_samsung/ultra_hdr');

  /// 为动态照片的内嵌 MP4 视频叠加水印图层
  static Future<Uint8List> watermarkMotionVideo({
    required Uint8List videoBytes,
    required Uint8List overlayPngBytes,
  }) async {
    if (!Platform.isAndroid || videoBytes.isEmpty || overlayPngBytes.isEmpty) {
      return videoBytes;
    }

    try {
      final Uint8List? processed = await _nativeChannel.invokeMethod<Uint8List>('watermarkVideo', {
        'videoBytes': videoBytes,
        'overlayBytes': overlayPngBytes,
      });
      return (processed != null && processed.isNotEmpty) ? processed : videoBytes;
    } catch (e) {
      debugPrint('[MotionPhotoService] watermarkVideo error: $e');
      return videoBytes;
    }
  }

  /// 从动态照片中精确提取纯净 MP4 视频流 (支持 Android 原生高效提取与 Dart 兜底)
  static Future<MotionVideoInfo?> extractMotionVideoAsync(
    Uint8List bytes, {
    String? path,
    String? uri,
  }) async {
    if (Platform.isAndroid) {
      try {
        final dynamic res = await _nativeChannel.invokeMethod('extractMotionPhotoNative', {
          'bytes': bytes,
          'path': path,
          'uri': uri,
        });
        if (res is Map && res['isMotionPhoto'] == true) {
          final Uint8List? vBytes = res['videoBytes'] as Uint8List?;
          if (vBytes != null && vBytes.isNotEmpty) {
            return MotionVideoInfo(
              videoBytes: vBytes,
              offset: (res['offset'] as num?)?.toInt() ?? 0,
              length: (res['length'] as num?)?.toInt() ?? vBytes.length,
              presentationTimestampUs: (res['presentationTimestampUs'] as num?)?.toInt() ?? 0,
            );
          }
        }
      } catch (e) {
        debugPrint('[MotionPhotoService] Native extractMotionPhotoNative error: $e, falling back to Dart');
      }
    }

    return MotionPhotoParser.extractMotionVideo(bytes);
  }

  /// 将处理完水印的高清静态 JPEG 与动态视频流 (MP4) 重新组装为原生动态照片 (优先 Android 原生组装)
  static Future<Uint8List> compositeAndPreserveMotionPhotoAsync({
    required Uint8List watermarkedJpgBytes,
    required Uint8List motionVideoBytes,
    int? presentationTimestampUs,
  }) async {
    if (Platform.isAndroid) {
      try {
        final Uint8List? composited = await _nativeChannel.invokeMethod<Uint8List>('compositeMotionPhotoNative', {
          'watermarkedJpgBytes': watermarkedJpgBytes,
          'motionVideoBytes': motionVideoBytes,
          'presentationTimestampUs': presentationTimestampUs ?? 0,
        });
        if (composited != null && composited.isNotEmpty) {
          return composited;
        }
      } catch (e) {
        debugPrint('[MotionPhotoService] Native compositeMotionPhotoNative error: $e, falling back to Dart');
      }
    }

    return MotionPhotoComposer.compositeAndPreserveMotionPhoto(
      watermarkedJpgBytes: watermarkedJpgBytes,
      motionVideoBytes: motionVideoBytes,
      presentationTimestampUs: presentationTimestampUs,
    );
  }
}
