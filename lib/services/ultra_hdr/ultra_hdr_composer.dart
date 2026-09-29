import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import '../exif_service.dart';
import 'ultra_hdr_detector.dart';

/// Ultra HDR 合成：XMP/MPF 标准段构建与 Gainmap 几何适配的原子组装
class UltraHdrComposer {
  static const MethodChannel _nativeChannel = MethodChannel('com.example.watermark_samsung/ultra_hdr');

  /// 生成符合 Adobe / ISO 21496-1 / Google GContainer 标准的主图 Ultra HDR XMP 描述符
  static String generateUltraHdrXmp(UltraHdrMetadata meta, {int gainmapLength = 0}) {
    final buffer = StringBuffer();
    buffer.write('http://ns.adobe.com/xap/1.0/\x00');
    buffer.write('<?xpacket begin="\xEF\xBB\xBF" id="W5M0MpCehiHzreSzNTczkc9d"?>');
    buffer.write('<x:xmpmeta xmlns:x="adobe:ns:meta/">');
    buffer.write('<rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">');
    buffer.write('<rdf:Description rdf:about="" ');
    buffer.write('xmlns:hdrgm="http://ns.adobe.com/hdr-gain-map/1.0/" ');
    buffer.write('hdrgm:Version="1.0" ');
    buffer.write('hdrgm:GainMapMin="${meta.gainMapMin.toStringAsFixed(6)}" ');
    buffer.write('hdrgm:GainMapMax="${meta.gainMapMax.toStringAsFixed(6)}" ');
    buffer.write('hdrgm:Gamma="${meta.gamma.toStringAsFixed(6)}" ');
    buffer.write('hdrgm:OffsetSDR="${meta.offsetSdr.toStringAsFixed(6)}" ');
    buffer.write('hdrgm:OffsetHDR="${meta.offsetHdr.toStringAsFixed(6)}" ');
    buffer.write('hdrgm:HDRCapacityMin="${meta.hdrCapacityMin.toStringAsFixed(6)}" ');
    buffer.write('hdrgm:HDRCapacityMax="${meta.hdrCapacityMax.toStringAsFixed(6)}" ');
    buffer.write('hdrgm:BaseRenditionIsHDR="False"/>');
    if (gainmapLength > 0) {
      buffer.write('<rdf:Description rdf:about="" ');
      buffer.write('xmlns:Container="http://ns.google.com/photos/1.0/container/" ');
      buffer.write('xmlns:Item="http://ns.google.com/photos/1.0/container/item/">');
      buffer.write('<Container:Directory>');
      buffer.write('<rdf:Seq>');
      buffer.write('<rdf:li rdf:parseType="Resource">');
      buffer.write('<Container:Item Item:Mime="image/jpeg" Item:Semantic="Primary" Item:Length="0"/>');
      buffer.write('</rdf:li>');
      buffer.write('<rdf:li rdf:parseType="Resource">');
      buffer.write('<Container:Item Item:Mime="image/jpeg" Item:Semantic="GainMap" Item:Length="$gainmapLength"/>');
      buffer.write('</rdf:li>');
      buffer.write('</rdf:Seq>');
      buffer.write('</Container:Directory>');
      buffer.write('</rdf:Description>');
    }
    buffer.write('</rdf:RDF>');
    buffer.write('</x:xmpmeta>');
    buffer.write('<?xpacket end="w"?>');
    return buffer.toString();
  }

  /// 生成符合 Adobe 标准的 Secondary Gainmap 专用 XMP 描述符
  static String generateSecondaryGainmapXmp(UltraHdrMetadata meta) {
    final buffer = StringBuffer();
    buffer.write('http://ns.adobe.com/xap/1.0/\x00');
    buffer.write('<?xpacket begin="\xEF\xBB\xBF" id="W5M0MpCehiHzreSzNTczkc9d"?>');
    buffer.write('<x:xmpmeta xmlns:x="adobe:ns:meta/">');
    buffer.write('<rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">');
    buffer.write('<rdf:Description rdf:about="" ');
    buffer.write('xmlns:hdrgm="http://ns.adobe.com/hdr-gain-map/1.0/" ');
    buffer.write('hdrgm:Version="1.0" ');
    buffer.write('hdrgm:GainMapMin="${meta.gainMapMin.toStringAsFixed(6)}" ');
    buffer.write('hdrgm:GainMapMax="${meta.gainMapMax.toStringAsFixed(6)}" ');
    buffer.write('hdrgm:Gamma="${meta.gamma.toStringAsFixed(6)}" ');
    buffer.write('hdrgm:OffsetSDR="${meta.offsetSdr.toStringAsFixed(6)}" ');
    buffer.write('hdrgm:OffsetHDR="${meta.offsetHdr.toStringAsFixed(6)}" ');
    buffer.write('hdrgm:HDRCapacityMin="${meta.hdrCapacityMin.toStringAsFixed(6)}" ');
    buffer.write('hdrgm:HDRCapacityMax="${meta.hdrCapacityMax.toStringAsFixed(6)}" ');
    buffer.write('hdrgm:BaseRenditionIsHDR="False"/>');
    buffer.write('</rdf:RDF>');
    buffer.write('</x:xmpmeta>');
    buffer.write('<?xpacket end="w"?>');
    return buffer.toString();
  }

  /// 构建符合 CIPA DC-007 Multi-Picture Format (MPF) 标准的 APP2 标记段
  static Uint8List buildMpfSegment({
    required int primaryImageSize,
    required int gainmapImageSize,
    required int gainmapOffsetFromTiffHeader,
  }) {
    final mpfData = BytesBuilder();

    // 1. MP Format Identifier: 'MPF\0' (4 bytes)
    mpfData.add([0x4D, 0x50, 0x46, 0x00]);

    // 2. TIFF Header (Little Endian 'II', 8 bytes)
    mpfData.add([0x49, 0x49, 0x2A, 0x00, 0x08, 0x00, 0x00, 0x00]);

    // 3. MP Index IFD (Count = 3 tags)
    mpfData.add([0x03, 0x00]);

    // Tag 1: 0xB000 (MPF Version: '0100')
    mpfData.add([
      0x00, 0xB0, 0x07, 0x00, 0x04, 0x00, 0x00, 0x00, 0x30, 0x31, 0x30, 0x30
    ]);

    // Tag 2: 0xB001 (Number of Images: 2)
    mpfData.add([
      0x01, 0xB0, 0x04, 0x00, 0x01, 0x00, 0x00, 0x00, 0x02, 0x00, 0x00, 0x00
    ]);

    // Tag 3: 0xB002 (MP Entry: 16 bytes per image * 2 images = 32 bytes)
    // Offset: 8 (TIFF header) + 2 (tag count) + 3*12 (3 tags) + 4 (next IFD offset) = 50 (0x32, 0x00, 0x00, 0x00)
    mpfData.add([
      0x02, 0xB0, 0x07, 0x00, 0x20, 0x00, 0x00, 0x00, 0x32, 0x00, 0x00, 0x00
    ]);

    // Offset to next IFD: 0 (4 bytes)
    mpfData.add([0x00, 0x00, 0x00, 0x00]);

    // 4. MP Entry Data (32 bytes):
    // Image 1 (Primary): Baseline MP Primary Image
    mpfData.add([
      0x00, 0x00, 0x03, 0x00,
      primaryImageSize & 0xFF,
      (primaryImageSize >> 8) & 0xFF,
      (primaryImageSize >> 16) & 0xFF,
      (primaryImageSize >> 24) & 0xFF,
      0x00, 0x00, 0x00, 0x00,
      0x00, 0x00, 0x00, 0x00,
    ]);

    // Image 2 (Secondary Gainmap): Undefined/Auxiliary Image
    mpfData.add([
      0x00, 0x00, 0x00, 0x00,
      gainmapImageSize & 0xFF,
      (gainmapImageSize >> 8) & 0xFF,
      (gainmapImageSize >> 16) & 0xFF,
      (gainmapImageSize >> 24) & 0xFF,
      gainmapOffsetFromTiffHeader & 0xFF,
      (gainmapOffsetFromTiffHeader >> 8) & 0xFF,
      (gainmapOffsetFromTiffHeader >> 16) & 0xFF,
      (gainmapOffsetFromTiffHeader >> 24) & 0xFF,
      0x00, 0x00, 0x00, 0x00,
    ]);

    final bytes = mpfData.takeBytes();
    final segLen = bytes.length + 2;

    final seg = BytesBuilder();
    seg.add([0xFF, 0xE2, (segLen >> 8) & 0xFF, segLen & 0xFF]);
    seg.add(bytes);
    return seg.takeBytes();
  }

  /// 提取 JPEG 中纯净的量化表与扫描数据 (去除重复的 APP0/APP1/APP2 等，确保标准标记段次序)
  static Uint8List _extractJpegTablesAndScan(Uint8List jpegBytes) {
    if (jpegBytes.length < 2 || jpegBytes[0] != 0xFF || jpegBytes[1] != 0xD8) {
      return jpegBytes;
    }
    int offset = 2;
    while (offset + 4 < jpegBytes.length) {
      if (jpegBytes[offset] != 0xFF) break;
      final marker = jpegBytes[offset + 1];
      // DQT (0xDB), SOF0 (0xC0), SOF2 (0xC2), DHT (0xC4), SOS (0xDA)
      if (marker == 0xDB || marker == 0xC0 || marker == 0xC2 || marker == 0xC4 || marker == 0xDA) {
        break;
      }
      final len = (jpegBytes[offset + 2] << 8) | jpegBytes[offset + 3];
      offset += 2 + len;
    }
    return jpegBytes.sublist(offset);
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
  }) async {
    debugPrint('[UltraHDR] compositeAndPreserveUltraHdr called');
    debugPrint('[UltraHDR]   originalBytes=${originalBytes.length}, sdrBytes=${sdrCompositeBytes.length}');
    debugPrint('[UltraHDR]   photo: left=$photoLeft top=$photoTop w=$photoWidth h=$photoHeight');
    debugPrint('[UltraHDR]   total: w=$totalWidth h=$totalHeight, quality=$quality');
    debugPrint('[UltraHDR]   isAndroid=${Platform.isAndroid}');

    // 1. Android 14+ 优先使用原生全流程管线：
    //    Android 的 JPEG 编码器在 Bitmap 挂载 Gainmap 后会自动正确生成
    //    MPF/XMP/Secondary Image 等所有标准结构，远比手动 Dart 拼接可靠。
    if (Platform.isAndroid) {
      try {
        final Uint8List? nativeResult = await _nativeChannel.invokeMethod<Uint8List>(
          'processUltraHdrImage',
          {
            'originalBytes': originalBytes,
            'sdrCompositeBytes': sdrCompositeBytes,
            'photoLeft': photoLeft,
            'photoTop': photoTop,
            'photoWidth': photoWidth,
            'photoHeight': photoHeight,
            'totalWidth': totalWidth,
            'totalHeight': totalHeight,
            'quality': quality,
          },
        );
        if (nativeResult != null && nativeResult.isNotEmpty) {
          debugPrint('[UltraHDR] Native processUltraHdrImage succeeded: ${nativeResult.length} bytes');
          return nativeResult;
        }
        debugPrint('[UltraHDR] Native processUltraHdrImage returned null, falling back to Dart synthesis');
      } catch (e) {
        debugPrint('[UltraHDR] Native processUltraHdrImage error: $e, falling back to Dart synthesis');
      }
    }

    // 2. 非 Android 平台或原生管线失败时，使用 Dart 手动合成作为兜底
    //    先尝试从原生提取精准的 Gainmap 与曲线参数
    UltraHdrMetadata? nativeMeta;
    Uint8List? nativeGainmapJpeg;
    if (Platform.isAndroid) {
      try {
        final dynamic gainmapResult = await _nativeChannel.invokeMethod('getUltraHdrGainmap', {
          'bytes': originalBytes,
        });
        if (gainmapResult is Map) {
          final gmBytes = gainmapResult['gainmapJpeg'] as Uint8List?;
          if (gmBytes != null && gmBytes.isNotEmpty) {
            nativeGainmapJpeg = gmBytes;
            nativeMeta = UltraHdrMetadata(
              gainMapMin: (gainmapResult['gainMapMin'] as num?)?.toDouble() ?? 0.0,
              gainMapMax: (gainmapResult['gainMapMax'] as num?)?.toDouble() ?? 2.0,
              gamma: (gainmapResult['gamma'] as num?)?.toDouble() ?? 1.0,
              offsetSdr: (gainmapResult['offsetSdr'] as num?)?.toDouble() ?? 0.015625,
              offsetHdr: (gainmapResult['offsetHdr'] as num?)?.toDouble() ?? 0.015625,
              hdrCapacityMin: 0.0,
              hdrCapacityMax: (gainmapResult['gainMapMax'] as num?)?.toDouble() ?? 2.0,
            );
            debugPrint('[UltraHDR] Fallback: Native extracted Gainmap: ${gmBytes.length} bytes');
          }
        }
      } catch (e) {
        debugPrint('[UltraHDR] Fallback: Native getUltraHdrGainmap error: $e');
      }
    }

    return _synthesizeUltraHdrInDart(
      originalBytes: originalBytes,
      sdrCompositeBytes: sdrCompositeBytes,
      photoLeft: photoLeft,
      photoTop: photoTop,
      photoWidth: photoWidth,
      photoHeight: photoHeight,
      totalWidth: totalWidth,
      totalHeight: totalHeight,
      quality: quality,
      injectedGainmapJpeg: nativeGainmapJpeg,
      injectedMetadata: nativeMeta,
    );
  }

  /// 纯 Dart 实现的标准级 Ultra HDR Gainmap 几何适配与 MPF/XMP 注入
  static Future<Uint8List> _synthesizeUltraHdrInDart({
    required Uint8List originalBytes,
    required Uint8List sdrCompositeBytes,
    required double photoLeft,
    required double photoTop,
    required double photoWidth,
    required double photoHeight,
    required double totalWidth,
    required double totalHeight,
    int quality = 95,
    Uint8List? injectedGainmapJpeg,
    UltraHdrMetadata? injectedMetadata,
  }) async {
    final meta = injectedMetadata ?? UltraHdrDetector.parseMetadata(originalBytes);
    final rawGainmap = injectedGainmapJpeg ?? UltraHdrDetector.extractGainmapJpeg(originalBytes);

    img.Image? gainmapImg;
    if (rawGainmap != null) {
      try {
        gainmapImg = img.decodeJpg(rawGainmap);
      } catch (_) {}
    }

    // 1. 构建与目标画幅完美对齐的辅助 Gainmap JPEG
    Uint8List finalGainmapBytes;
    if (gainmapImg != null) {
      // 注意：Gainmap 与主图在 MPF 中是同坐标系配对存储的，
      // Android ImageDecoder 会统一处理主图和 Gainmap 的 EXIF 旋转。
      // 不要单独旋转 Gainmap，否则会破坏高光像素与主图的空间对齐，导致全图异常增亮。
      final targetGw = (totalWidth / 2).clamp(256, 2048).toInt();
      final targetGh = (totalHeight / 2).clamp(256, 2048).toInt();

      final canvasGainmap = img.Image(width: targetGw, height: targetGh);
      // 填充中性基准 0 增益 (SDR 外框区域保持标准亮度，不闪烁刺眼)
      img.fill(canvasGainmap, color: img.ColorRgb8(0, 0, 0));

      final scaleX = targetGw / totalWidth;
      final scaleY = targetGh / totalHeight;
      final dstX = (photoLeft * scaleX).toInt();
      final dstY = (photoTop * scaleY).toInt();
      final dstW = (photoWidth * scaleX).toInt();
      final dstH = (photoHeight * scaleY).toInt();

      final scaledPhotoGainmap = img.copyResize(gainmapImg, width: dstW, height: dstH);
      img.compositeImage(canvasGainmap, scaledPhotoGainmap, dstX: dstX, dstY: dstY);

      final rawJpg = img.encodeJpg(canvasGainmap, quality: 90);
      finalGainmapBytes = Uint8List.fromList(rawJpg);
    } else {
      final defaultGw = 512;
      final defaultGh = (512 * (totalHeight / totalWidth)).toInt().clamp(1, 4096);
      final defaultGm = img.Image(width: defaultGw, height: defaultGh);
      img.fill(defaultGm, color: img.ColorRgb8(0, 0, 0));
      finalGainmapBytes = Uint8List.fromList(img.encodeJpg(defaultGm, quality: 85));
    }

    // 2. 为 Secondary Gainmap JPEG 组装标准的 JPEG 结构 (SOI -> APP1 XMP -> Tables & Scan)
    final secondaryXmpString = generateSecondaryGainmapXmp(meta);
    final secondaryXmpBytes = utf8.encode(secondaryXmpString);
    final secondaryXmpLen = secondaryXmpBytes.length + 2;

    final secondaryTablesAndScan = _extractJpegTablesAndScan(finalGainmapBytes);
    final secondaryBuilder = BytesBuilder();
    secondaryBuilder.add([0xFF, 0xD8]); // Secondary SOI
    secondaryBuilder.add([0xFF, 0xE1, (secondaryXmpLen >> 8) & 0xFF, secondaryXmpLen & 0xFF]);
    secondaryBuilder.add(secondaryXmpBytes);
    secondaryBuilder.add(secondaryTablesAndScan); // contains DQT, SOF, DHT, SOS, scan, and EOI 0xFF 0xD9
    final packagedGainmapBytes = secondaryBuilder.takeBytes();

    // 3. 构建 Primary Image 的 APP1 XMP (包含 GContainer + Adobe HDR Gainmap)
    final primaryXmpString = generateUltraHdrXmp(meta, gainmapLength: packagedGainmapBytes.length);
    final primaryXmpBytes = utf8.encode(primaryXmpString);
    final primaryXmpLen = primaryXmpBytes.length + 2;

    final app1XmpSegment = Uint8List.fromList([
      0xFF, 0xE1,
      (primaryXmpLen >> 8) & 0xFF, primaryXmpLen & 0xFF,
      ...primaryXmpBytes,
    ]);

    // 4. 提取原图可能存在的 EXIF APP1，并归一化 Orientation 为 1
    //    像素和 Gainmap 均已被解码器/Canvas 旋转为正向，EXIF 必须同步重置为 Normal (1)，
    //    否则相册会二次旋转已正向的像素，导致 Gainmap 空间坐标与像素错位（暗部异常增亮）。
    Uint8List? app1ExifSegment = ExifService.extractApp1ExifSegment(originalBytes);
    if (app1ExifSegment != null && app1ExifSegment.isNotEmpty) {
      app1ExifSegment = ExifService.normalizeExifOrientation(app1ExifSegment);
    }

    // 5. 提取 SDR 主图纯净的图像数据与量化表
    final sdrPayload = _extractJpegTablesAndScan(sdrCompositeBytes);

    // 6. 计算 MPF APP2 标记段的精确位置与偏移量
    final dummyMpf = buildMpfSegment(primaryImageSize: 0, gainmapImageSize: 0, gainmapOffsetFromTiffHeader: 0);
    final int mpfLen = dummyMpf.length;

    int primarySizeBeforeMpf = 2; // SOI (2 bytes: 0xFF 0xD8)
    if (app1ExifSegment != null && app1ExifSegment.isNotEmpty) {
      primarySizeBeforeMpf += app1ExifSegment.length;
    }
    primarySizeBeforeMpf += app1XmpSegment.length;

    final int mpfMarkerOffset = primarySizeBeforeMpf;
    // TIFF Header starts 8 bytes into the MPF segment: 0xFF 0xE2 (2B) + len (2B) + 'MPF\0' (4B) = 8 bytes
    final int tiffHeaderOffset = mpfMarkerOffset + 8;

    final int totalPrimarySize = primarySizeBeforeMpf + mpfLen + sdrPayload.length;
    final int gainmapOffsetFromTiff = totalPrimarySize - tiffHeaderOffset;

    final actualMpfSegment = buildMpfSegment(
      primaryImageSize: totalPrimarySize,
      gainmapImageSize: packagedGainmapBytes.length,
      gainmapOffsetFromTiffHeader: gainmapOffsetFromTiff,
    );

    // 7. 组装最终符合国际标准的 Ultra HDR JPEG
    final finalBuilder = BytesBuilder();
    finalBuilder.add([0xFF, 0xD8]); // Primary SOI
    if (app1ExifSegment != null && app1ExifSegment.isNotEmpty) {
      finalBuilder.add(app1ExifSegment); // Primary APP1 EXIF
    }
    finalBuilder.add(app1XmpSegment); // Primary APP1 XMP
    finalBuilder.add(actualMpfSegment); // Primary APP2 MPF
    finalBuilder.add(sdrPayload); // Primary Tables, Scan & Primary EOI 0xFF 0xD9
    finalBuilder.add(packagedGainmapBytes); // Secondary Gainmap Image (SOI, APP1 XMP, Tables, Scan, EOI)

    return finalBuilder.takeBytes();
  }
}
