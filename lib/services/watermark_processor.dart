import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;

import '../models/frame_watermark_config.dart';
import '../models/image_item.dart';
import '../models/watermark_config.dart';
import 'canvas/floating_png_renderer.dart';
import 'canvas/frame_canvas_renderer.dart';
import 'exif_service.dart';
import 'motion_photo_service.dart';
import 'ultra_hdr_service.dart';

/// 水印核心处理器：负责图片预解码、Canvas 水印合成与全分辨率文件导出
class WatermarkProcessor {
  static const MethodChannel _nativeChannel = MethodChannel(
    'com.example.watermark_samsung/ultra_hdr',
  );

  // RGB 反色滤镜矩阵 (保持 Alpha 透明度不变)
  static const ColorFilter invertColorFilter =
      FloatingPngRenderer.invertColorFilter;

  /// 将原始图片字节安全解码为 ui.Image (支持限制预览纹理最大边长，防止多张大图 OOM 闪退)
  static Future<ui.Image> decodeImageFromBytes(
    Uint8List bytes, {
    int? maxDimension = 1600,
  }) async {
    if (maxDimension != null && maxDimension <= 0) {
      throw ArgumentError.value(
        maxDimension,
        'maxDimension',
        'Must be positive',
      );
    }
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    ui.ImageDescriptor? descriptor;
    ui.Codec? codec;
    try {
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      int? targetWidth;
      int? targetHeight;
      // 限制长边，竖图同样受限；小照片和 Logo 保留原尺寸，避免放大纹理。
      if (maxDimension != null) {
        if (descriptor.width >= descriptor.height &&
            descriptor.width > maxDimension) {
          targetWidth = maxDimension;
        } else if (descriptor.height > maxDimension) {
          targetHeight = maxDimension;
        }
      }
      codec = await descriptor.instantiateCodec(
        targetWidth: targetWidth,
        targetHeight: targetHeight,
      );
      return (await codec.getNextFrame()).image;
    } finally {
      codec?.dispose();
      descriptor?.dispose();
      buffer.dispose();
    }
  }

  /// 解码 1:1 无损全分辨率图片（仅在导出合成阶段使用）
  static Future<ui.Image> decodeFullResolutionImage(Uint8List bytes) async {
    return decodeImageFromBytes(bytes, maxDimension: null);
  }

  /// 创建 ImageItem 并预解码尺寸与 EXIF (低内存安全模式，自动检测 Ultra HDR 与 动态照片)
  static Future<ImageItem> createImageItem({
    required String id,
    required String name,
    required String path,
    required Uint8List bytes,
  }) async {
    final exifInfo = await ExifService.extractExifAsync(bytes, path: path);
    final isUltraHdr = await UltraHdrService.checkIsUltraHdr(bytes);
    final motionInfo = await MotionPhotoService.extractMotionVideoAsync(
      bytes,
      path: path,
    );
    final isMotion = motionInfo != null && motionInfo.videoBytes.isNotEmpty;
    final previewDecoded = await decodeImageFromBytes(
      bytes,
      maxDimension: 1600,
    );

    return ImageItem(
      id: id,
      name: name,
      path: path,
      bytes: bytes,
      width: previewDecoded.width,
      height: previewDecoded.height,
      fileSize: bytes.length,
      decodedImage: previewDecoded,
      exifInfo: exifInfo,
      isUltraHdr: isUltraHdr,
      isMotionPhoto: isMotion,
      motionVideoBytes: motionInfo?.videoBytes,
      motionVideoLength: motionInfo?.length,
      motionTimestampUs: motionInfo?.presentationTimestampUs,
    );
  }

  /// 绘制浮动 PNG 水印到 Canvas (委托给 FloatingPngRenderer)
  static void drawFloatingPngCanvas({
    required Canvas canvas,
    required ui.Image baseImage,
    required ui.Image watermarkImage,
    required WatermarkConfig config,
    required double canvasWidth,
    required double canvasHeight,
    FilterQuality filterQuality = FilterQuality.high,
  }) {
    FloatingPngRenderer.draw(
      canvas: canvas,
      baseImage: baseImage,
      watermarkImage: watermarkImage,
      config: config,
      canvasWidth: canvasWidth,
      canvasHeight: canvasHeight,
      filterQuality: filterQuality,
    );
  }

  /// 绘制边框型 EXIF 相框水印到 Canvas (委托给 FrameCanvasRenderer)
  static void drawFrameExifCanvas({
    required Canvas canvas,
    required ui.Image baseImage,
    required ui.Image? logoImage,
    required FrameWatermarkConfig config,
    required double totalWidth,
    required double totalHeight,
    FilterQuality filterQuality = FilterQuality.high,
  }) {
    FrameCanvasRenderer.draw(
      canvas: canvas,
      baseImage: baseImage,
      logoImage: logoImage,
      config: config,
      totalWidth: totalWidth,
      totalHeight: totalHeight,
      filterQuality: filterQuality,
    );
  }

  /// 为视频合成生成透明水印图层 PNG (按视频 1080P/2K 规格高效生成，避免 50MP 巨型 PNG 编码耗时)
  static Future<Uint8List> generateWatermarkOverlayBytes({
    required WatermarkType type,
    required ui.Image? watermarkImage,
    required WatermarkConfig pngConfig,
    required ui.Image? logoImage,
    required FrameWatermarkConfig frameConfig,
    required double width,
    required double height,
  }) async {
    // 约束视频水印图层最大边长为 1920（适配 1080P/2K 动态视频），消除超高像素 PNG 编码带来的数秒级延迟
    double targetW = width;
    double targetH = height;
    const double maxVideoDimension = 1920.0;
    if (targetW > maxVideoDimension || targetH > maxVideoDimension) {
      if (targetW > targetH) {
        targetH = (targetH * maxVideoDimension / targetW).roundToDouble();
        targetW = maxVideoDimension;
      } else {
        targetW = (targetW * maxVideoDimension / targetH).roundToDouble();
        targetH = maxVideoDimension;
      }
    }

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, targetW, targetH));

    if (type == WatermarkType.frame) {
      FrameCanvasRenderer.drawOverlayOnly(
        canvas: canvas,
        logoImage: logoImage,
        config: frameConfig,
        totalWidth: targetW,
        totalHeight: targetH,
      );
    } else {
      if (watermarkImage != null) {
        FloatingPngRenderer.drawOverlayOnly(
          canvas: canvas,
          watermarkImage: watermarkImage,
          config: pngConfig,
          canvasWidth: targetW,
          canvasHeight: targetH,
        );
      }
    }

    final picture = recorder.endRecording();
    final ui.Image image;
    try {
      image = await picture.toImage(targetW.toInt(), targetH.toInt());
    } finally {
      picture.dispose();
    }
    try {
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      return byteData!.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  }

  /// 1:1 无损合成并输出全分辨率文件 (支持保持 Ultra HDR Gainmap 与 动态照片，及动态播放视频水印)
  static Future<Uint8List> compositeFullResolutionUnified({
    required ui.Image baseImage,
    required WatermarkType type,
    required ui.Image? watermarkImage,
    required WatermarkConfig pngConfig,
    required ui.Image? logoImage,
    required FrameWatermarkConfig frameConfig,
    required String outputFormat,
    Uint8List? originalBytes,
    String? originalPath,
    int quality = 95,
    bool preserveMotionPhoto = true,
    bool watermarkMotionVideo = false,
  }) async {
    final double originalW = baseImage.width.toDouble();
    final double originalH = baseImage.height.toDouble();

    double finalW = originalW;
    double finalH = originalH;
    double pad = 0.0;

    if (type == WatermarkType.frame) {
      pad = originalW * frameConfig.paddingRatio;
      final bottomBarH = originalH * frameConfig.bottomBarRatio;
      finalW = originalW + pad * 2;
      finalH = originalH + pad + bottomBarH;
    }

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, finalW, finalH));

    if (type == WatermarkType.frame) {
      drawFrameExifCanvas(
        canvas: canvas,
        baseImage: baseImage,
        logoImage: logoImage,
        config: frameConfig,
        totalWidth: finalW,
        totalHeight: finalH,
      );
    } else {
      if (watermarkImage != null) {
        drawFloatingPngCanvas(
          canvas: canvas,
          baseImage: baseImage,
          watermarkImage: watermarkImage,
          config: pngConfig,
          canvasWidth: finalW,
          canvasHeight: finalH,
        );
      } else {
        final src = Rect.fromLTWH(0, 0, originalW, originalH);
        final dst = Rect.fromLTWH(0, 0, finalW, finalH);
        canvas.drawImageRect(
          baseImage,
          src,
          dst,
          Paint()..filterQuality = FilterQuality.high,
        );
      }
    }

    final picture = recorder.endRecording();
    final ui.Image renderedImage;
    try {
      renderedImage = await picture.toImage(finalW.toInt(), finalH.toInt());
    } finally {
      picture.dispose();
    }

    if (outputFormat.toLowerCase() == 'png') {
      final ByteData? byteData;
      try {
        byteData = await renderedImage.toByteData(
          format: ui.ImageByteFormat.png,
        );
      } finally {
        renderedImage.dispose();
      }
      final pngBytes = byteData!.buffer.asUint8List();

      if (originalBytes != null) {
        return ExifService.preserveExif(
          outputBytes: pngBytes,
          originalBytes: originalBytes,
          format: 'png',
        );
      }
      return pngBytes;
    } else {
      final width = renderedImage.width;
      final height = renderedImage.height;
      final ByteData? byteData;
      try {
        byteData = await renderedImage.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );
      } finally {
        renderedImage.dispose();
      }
      final rgbaBytes = byteData!.buffer.asUint8List();

      Uint8List? jpgBytes;
      // 优先调用 Android 系统底层硬件加速 JPEG 编码器 (Qualcomm NEON / libjpeg-turbo 硬件加速)
      if (Platform.isAndroid) {
        try {
          final nativeJpg = await _nativeChannel.invokeMethod<Uint8List>(
            'compressRgbaToJpeg',
            {
              'rgba': rgbaBytes,
              'width': width,
              'height': height,
              'quality': quality,
            },
          );
          if (nativeJpg != null && nativeJpg.isNotEmpty) {
            jpgBytes = nativeJpg;
          }
        } catch (e) {
          debugPrint('[WatermarkProcessor] Hardware JPEG encode fallback: $e');
        }
      }

      if (jpgBytes == null) {
        final image = img.Image.fromBytes(
          width: width,
          height: height,
          bytes: rgbaBytes.buffer,
          order: img.ChannelOrder.rgba,
        );
        jpgBytes = Uint8List.fromList(img.encodeJpg(image, quality: quality));
      }
      Uint8List finalJpgBytes = jpgBytes;

      // 1. 若原图是 Ultra HDR 且输出 JPEG，则合成保持 Ultra HDR Gainmap 与 EXIF
      bool isHdr = false;
      if (originalBytes != null) {
        // 采用统一检测结果，避免再次扫描覆盖原生的 SDR 判定
        isHdr = await UltraHdrService.checkIsUltraHdr(originalBytes);
      }
      if (isHdr && originalBytes != null) {
        final double photoLeft = type == WatermarkType.frame ? pad : 0.0;
        final double photoTop = type == WatermarkType.frame ? pad : 0.0;
        final double photoW = originalW;
        final double photoH = originalH;

        final hdrResult = await UltraHdrService.compositeAndPreserveUltraHdr(
          originalBytes: originalBytes,
          sdrCompositeBytes: jpgBytes,
          photoLeft: photoLeft,
          photoTop: photoTop,
          photoWidth: photoW,
          photoHeight: photoH,
          totalWidth: finalW,
          totalHeight: finalH,
          quality: quality,
        );

        if (preserveMotionPhoto) {
          final motionInfo = await MotionPhotoService.extractMotionVideoAsync(
            originalBytes,
            path: originalPath,
          );
          if (motionInfo != null) {
            Uint8List videoBytesToEmbed = motionInfo.videoBytes;

            if (watermarkMotionVideo) {
              final overlayBytes = await generateWatermarkOverlayBytes(
                type: type,
                watermarkImage: watermarkImage,
                pngConfig: pngConfig,
                logoImage: logoImage,
                frameConfig: frameConfig,
                width: finalW,
                height: finalH,
              );
              videoBytesToEmbed = await MotionPhotoService.watermarkMotionVideo(
                videoBytes: motionInfo.videoBytes,
                overlayPngBytes: overlayBytes,
              );
            }

            return await MotionPhotoService.compositeAndPreserveMotionPhotoAsync(
              watermarkedJpgBytes: hdrResult,
              motionVideoBytes: videoBytesToEmbed,
              presentationTimestampUs: motionInfo.presentationTimestampUs,
            );
          }
        }

        return hdrResult;
      }

      // 2. 普通 SDR 图片保留原图完整 EXIF 拍摄参数元数据
      if (originalBytes != null) {
        finalJpgBytes = ExifService.preserveExif(
          outputBytes: finalJpgBytes,
          originalBytes: originalBytes,
          format: 'jpg',
        );
      }

      // 3. 动态照片 (Motion Photo) 重新组装与保留
      if (preserveMotionPhoto && originalBytes != null) {
        final motionInfo = await MotionPhotoService.extractMotionVideoAsync(
          originalBytes,
          path: originalPath,
        );
        if (motionInfo != null) {
          Uint8List videoBytesToEmbed = motionInfo.videoBytes;

          if (watermarkMotionVideo) {
            final overlayBytes = await generateWatermarkOverlayBytes(
              type: type,
              watermarkImage: watermarkImage,
              pngConfig: pngConfig,
              logoImage: logoImage,
              frameConfig: frameConfig,
              width: finalW,
              height: finalH,
            );
            videoBytesToEmbed = await MotionPhotoService.watermarkMotionVideo(
              videoBytes: motionInfo.videoBytes,
              overlayPngBytes: overlayBytes,
            );
          }

          return await MotionPhotoService.compositeAndPreserveMotionPhotoAsync(
            watermarkedJpgBytes: finalJpgBytes,
            motionVideoBytes: videoBytesToEmbed,
            presentationTimestampUs: motionInfo.presentationTimestampUs,
          );
        }
      }

      return finalJpgBytes;
    }
  }
}
