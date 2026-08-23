import 'dart:typed_data';
import 'dart:ui' as ui;
import 'exif_info.dart';
import 'frame_watermark_config.dart';
import 'watermark_config.dart';

class ImageItem {
  final String id;
  final String name;
  final String path;
  final Uint8List bytes;
  final int width;
  final int height;
  final int fileSize;
  final ui.Image? decodedImage;
  final ExifInfo exifInfo;
  final bool isUltraHdr;
  final bool isMotionPhoto;
  final Uint8List? motionVideoBytes;
  final int? motionVideoLength;
  final int? motionTimestampUs;

  // 单独调节模式下的专属配置 (如果为 null 则使用全局设置)
  final WatermarkConfig? individualPngConfig;
  final FrameWatermarkConfig? individualFrameConfig;

  const ImageItem({
    required this.id,
    required this.name,
    required this.path,
    required this.bytes,
    required this.width,
    required this.height,
    required this.fileSize,
    this.decodedImage,
    this.exifInfo = const ExifInfo(),
    this.isUltraHdr = false,
    this.isMotionPhoto = false,
    this.motionVideoBytes,
    this.motionVideoLength,
    this.motionTimestampUs,
    this.individualPngConfig,
    this.individualFrameConfig,
  });

  ImageItem copyWith({
    String? id,
    String? name,
    String? path,
    Uint8List? bytes,
    int? width,
    int? height,
    int? fileSize,
    ui.Image? decodedImage,
    ExifInfo? exifInfo,
    bool? isUltraHdr,
    bool? isMotionPhoto,
    Uint8List? motionVideoBytes,
    int? motionVideoLength,
    int? motionTimestampUs,
    WatermarkConfig? individualPngConfig,
    FrameWatermarkConfig? individualFrameConfig,
  }) {
    return ImageItem(
      id: id ?? this.id,
      name: name ?? this.name,
      path: path ?? this.path,
      bytes: bytes ?? this.bytes,
      width: width ?? this.width,
      height: height ?? this.height,
      fileSize: fileSize ?? this.fileSize,
      decodedImage: decodedImage ?? this.decodedImage,
      exifInfo: exifInfo ?? this.exifInfo,
      isUltraHdr: isUltraHdr ?? this.isUltraHdr,
      isMotionPhoto: isMotionPhoto ?? this.isMotionPhoto,
      motionVideoBytes: motionVideoBytes ?? this.motionVideoBytes,
      motionVideoLength: motionVideoLength ?? this.motionVideoLength,
      motionTimestampUs: motionTimestampUs ?? this.motionTimestampUs,
      individualPngConfig: individualPngConfig ?? this.individualPngConfig,
      individualFrameConfig: individualFrameConfig ?? this.individualFrameConfig,
    );
  }

  String get sizeString {
    if (fileSize < 1024) return '$fileSize B';
    if (fileSize < 1024 * 1024) {
      return '${(fileSize / 1024).toStringAsFixed(1)} KB';
    }
    return '${(fileSize / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  String get resolutionString => '${width}x$height';
}
