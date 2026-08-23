import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'exif_service.dart';

/// Ultra HDR 增益图 (Gainmap) 与元数据封装
class UltraHdrMetadata {
  final double gainMapMin;
  final double gainMapMax;
  final double gamma;
  final double offsetSdr;
  final double offsetHdr;
  final double hdrCapacityMin;
  final double hdrCapacityMax;
  final bool baseRenditionIsHdr;
  final String rawXmp;

  const UltraHdrMetadata({
    this.gainMapMin = 0.0,
    this.gainMapMax = 2.0,
    this.gamma = 1.0,
    this.offsetSdr = 0.015625,
    this.offsetHdr = 0.015625,
    this.hdrCapacityMin = 0.0,
    this.hdrCapacityMax = 2.0,
    this.baseRenditionIsHdr = false,
    this.rawXmp = '',
  });
}

/// Ultra HDR 完整高动态范围图像解析与合成服务
class UltraHdrService {
  static const MethodChannel _nativeChannel = MethodChannel('com.example.watermark_samsung/ultra_hdr');

  /// 检查当前设备屏幕是否支持硬件级 HDR / Ultra HDR 显示
  static Future<bool> isHdrDisplaySupported() async {
    if (!Platform.isAndroid) return false;
    try {
      final supported = await _nativeChannel.invokeMethod<bool>('isHdrDisplaySupported');
      return supported ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 获取当前屏幕的 HDR/SDR 动态亮度提升比例 (1.0 代表标准无提升，>1.0 代表开启 HDR 峰值高光)
  static Future<double> getHdrSdrRatio() async {
    if (!Platform.isAndroid) return 1.0;
    try {
      final ratio = await _nativeChannel.invokeMethod<double>('getHdrSdrRatio');
      return ratio ?? 1.0;
    } catch (_) {
      return 1.0;
    }
  }

  /// 动态启用/关闭窗口级 Ultra HDR 显示色彩模式 (COLOR_MODE_HDR)
  static Future<bool> setHdrDisplayMode(bool enable) async {
    if (!Platform.isAndroid) return false;
    try {
      final ok = await _nativeChannel.invokeMethod<bool>('setHdrDisplayMode', {'enable': enable});
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 异步全方位检测是否为 Ultra HDR 图像 (优先请求 Android 14+ 系统级底层 Gainmap 解码器)
  static Future<bool> checkIsUltraHdr(Uint8List bytes) async {
    if (Platform.isAndroid) {
      try {
        final has = await _nativeChannel.invokeMethod<bool>('hasGainmap', {'bytes': bytes});
        if (has == true) return true;
      } catch (_) {}
    }
    return isUltraHdr(bytes);
  }

  /// 检测字节流是否为 Ultra HDR 图像 (包含 Gainmap 增益图 / XMP / SEF 描述符)
  static bool isUltraHdr(Uint8List bytes) {
    if (bytes.length < 100) return false;

    // 1. 扫描头部 512KB 与尾部 512KB (涵盖 Samsung SEFT 扩展区与 Google GContainer)
    final headLen = bytes.length > 524288 ? 524288 : bytes.length;
    final headStr = utf8.decode(bytes.sublist(0, headLen), allowMalformed: true);

    final tailStart = bytes.length > 524288 ? bytes.length - 524288 : 0;
    final tailStr = utf8.decode(bytes.sublist(tailStart), allowMalformed: true);

    if (headStr.contains('http://ns.adobe.com/hdr-gain-map/1.0/') ||
        headStr.contains('http://ns.apple.com/HDRGainMap/1.0/') ||
        headStr.contains('urn:iso:std:iso:ts:21496:-1') ||
        headStr.contains('hdrgm:Version') ||
        headStr.contains('hdrgm:GainMapMin') ||
        headStr.contains('Container:Directory') ||
        headStr.contains('GContainer:Directory') ||
        headStr.contains('DualShot_GainMap') ||
        headStr.contains('HdrGainMap') ||
        tailStr.contains('DualShot_GainMap') ||
        tailStr.contains('HdrGainMap') ||
        tailStr.contains('GainMap_Info') ||
        tailStr.contains('SEFT') ||
        tailStr.contains('http://ns.adobe.com/hdr-gain-map/1.0/')) {
      return true;
    }

    // 2. 检查 JPEG 是否包含多图格式 MPF 标记 (0xFF 0xE2 + 'MPF\0')
    if (bytes[0] == 0xFF && bytes[1] == 0xD8) {
      int offset = 2;
      while (offset + 4 < bytes.length) {
        if (bytes[offset] != 0xFF) break;
        final marker = bytes[offset + 1];
        if (marker == 0xDA || marker == 0xD9) break; // SOS or EOI

        final len = (bytes[offset + 2] << 8) | bytes[offset + 3];
        if (marker == 0xE2 && offset + 4 + 4 <= bytes.length) {
          final tag = String.fromCharCodes(bytes.sublist(offset + 4, offset + 8));
          if (tag == 'MPF\x00') {
            return true;
          }
        }
        offset += 2 + len;
      }

      // 3. 检查是否有主图 EOI 后紧随的第二个 JPEG SOI
      for (int i = 2; i < bytes.length - 3; i++) {
        if (bytes[i] == 0xFF && bytes[i + 1] == 0xD9) {
          for (int j = i + 2; j < bytes.length - 1; j++) {
            if (bytes[j] == 0xFF && bytes[j + 1] == 0xD8) {
              return true;
            }
          }
        }
      }
    }

    return false;
  }

  /// 提取 JPEG 中的 Gainmap 辅助增益图像字节流
  static Uint8List? extractGainmapJpeg(Uint8List bytes) {
    if (bytes.length < 100 || bytes[0] != 0xFF || bytes[1] != 0xD8) {
      return null;
    }

    // 1. 动态遍历 JPEG 标记寻找 APP2 MPF 并精准解析 Image 2
    int offset = 2;
    while (offset + 4 < bytes.length) {
      if (bytes[offset] != 0xFF) break;
      final marker = bytes[offset + 1];
      if (marker == 0xDA || marker == 0xD9) break;

      final len = (bytes[offset + 2] << 8) | bytes[offset + 3];
      if (marker == 0xE2 && offset + 8 <= bytes.length) {
        final tag = String.fromCharCodes(bytes.sublist(offset + 4, offset + 8));
        if (tag == 'MPF\x00') {
          final tiffOffset = offset + 8; // TIFF Header begins after 'MPF\0' (4 bytes)
          try {
            final isLe = bytes[tiffOffset] == 0x49 && bytes[tiffOffset + 1] == 0x49;
            final isBe = bytes[tiffOffset] == 0x4D && bytes[tiffOffset + 1] == 0x4D;
            if (isLe || isBe) {
              int r16(int p) => isLe
                  ? (bytes[p] | (bytes[p + 1] << 8))
                  : ((bytes[p] << 8) | bytes[p + 1]);
              int r32(int p) => isLe
                  ? (bytes[p] | (bytes[p + 1] << 8) | (bytes[p + 2] << 16) | (bytes[p + 3] << 24))
                  : ((bytes[p] << 24) | (bytes[p + 1] << 16) | (bytes[p + 2] << 8) | bytes[p + 3]);

              final ifdOffset = r32(tiffOffset + 4);
              final numTags = r16(tiffOffset + ifdOffset);
              int tagPos = tiffOffset + ifdOffset + 2;

              for (int t = 0; t < numTags; t++) {
                final tagId = r16(tagPos);
                if (tagId == 0xB002) { // MP Entry
                  final entryOffset = r32(tagPos + 8);
                  final entryAbsPos = tiffOffset + entryOffset;
                  // Image 2 entry starts 16 bytes into MP Entry (Image 1 is 16 bytes)
                  final img2Size = r32(entryAbsPos + 16 + 4);
                  final img2Offset = r32(entryAbsPos + 16 + 8);
                  final gainmapAbsOffset = tiffOffset + img2Offset;

                  if (gainmapAbsOffset + img2Size <= bytes.length &&
                      bytes[gainmapAbsOffset] == 0xFF &&
                      bytes[gainmapAbsOffset + 1] == 0xD8) {
                    return bytes.sublist(gainmapAbsOffset, gainmapAbsOffset + img2Size);
                  }
                }
                tagPos += 12;
              }
            }
          } catch (_) {}
        }
      }
      offset += 2 + len;
    }

    // 2. 扫描 Samsung SEFT 扩展尾部 (Samsung Galaxy 专有 DualShot_GainMap / HdrGainMap)
    if (bytes.length > 32) {
      final len = bytes.length;
      if (bytes[len - 4] == 0x53 &&
          bytes[len - 3] == 0x45 &&
          bytes[len - 2] == 0x46 &&
          bytes[len - 1] == 0x54) { // 'SEFT'
        final sefLen = bytes[len - 8] | (bytes[len - 7] << 8) | (bytes[len - 6] << 16) | (bytes[len - 5] << 24);
        if (sefLen > 8 && sefLen < len) {
          final sefStart = len - sefLen;
          final sefBytes = bytes.sublist(sefStart, len - 8);
          // 在 SEFT 区域寻找内嵌的 Gainmap JPEG
          for (int i = 0; i < sefBytes.length - 4; i++) {
            if (sefBytes[i] == 0xFF && sefBytes[i + 1] == 0xD8 && sefBytes[i + 2] == 0xFF) {
              for (int j = sefBytes.length - 2; j > i; j--) {
                if (sefBytes[j] == 0xFF && sefBytes[j + 1] == 0xD9) {
                  return sefBytes.sublist(i, j + 2);
                }
              }
              return sefBytes.sublist(i);
            }
          }
        }
      }
    }

    // 3. 扫描 Google GContainer 目录声明的 GainMap 长度
    final strHead = utf8.decode(bytes.sublist(0, bytes.length > 65536 ? 65536 : bytes.length), allowMalformed: true);
    final gmReg = RegExp(r'Item:Semantic="GainMap"[^>]*Item:Length="(\d+)"|Item:Length="(\d+)"[^>]*Item:Semantic="GainMap"');
    final gmMatch = gmReg.firstMatch(strHead);
    if (gmMatch != null) {
      final lenStr = gmMatch.group(1) ?? gmMatch.group(2);
      final gmLen = int.tryParse(lenStr ?? '');
      if (gmLen != null && gmLen > 0 && gmLen < bytes.length) {
        final startPos = bytes.length - gmLen;
        if (startPos >= 0 && bytes[startPos] == 0xFF && bytes[startPos + 1] == 0xD8) {
          return bytes.sublist(startPos);
        }
      }
    }

    // 4. 备用方式：寻找主图 EOI (0xFF 0xD9) 之后紧随的第二个 SOI (0xFF 0xD8)
    for (int i = 2; i < bytes.length - 3; i++) {
      if (bytes[i] == 0xFF && bytes[i + 1] == 0xD9) {
        for (int j = i + 2; j < bytes.length - 10; j++) {
          if (bytes[j] == 0xFF && bytes[j + 1] == 0xD8 && bytes[j + 2] == 0xFF) {
            return bytes.sublist(j);
          }
        }
      }
    }

    // 5. 全局从文件尾部向前扫描最后一个有效 JPEG SOI
    for (int i = bytes.length - 20; i >= 100; i--) {
      if (bytes[i] == 0xFF && bytes[i + 1] == 0xD8) {
        if (bytes[i + 2] == 0xFF &&
            (bytes[i + 3] == 0xDB || bytes[i + 3] == 0xC0 || bytes[i + 3] == 0xE1 || bytes[i + 3] == 0xE0 || bytes[i + 3] == 0xC2)) {
          return bytes.sublist(i);
        }
      }
    }

    return null;
  }

  /// 从 XMP 中提取 Ultra HDR 参数
  static UltraHdrMetadata parseMetadata(Uint8List bytes) {
    final strSample = utf8.decode(
      bytes.sublist(0, bytes.length > 131072 ? 131072 : bytes.length),
      allowMalformed: true,
    );

    double getDoubleVal(List<String> keys, double fallback) {
      for (final key in keys) {
        final reg = RegExp('$key="([^"]+)"|<hdrgm:$key>([^<]+)</hdrgm:$key>|<apgain:$key>([^<]+)</apgain:$key>');
        final match = reg.firstMatch(strSample);
        if (match != null) {
          final val = match.group(1) ?? match.group(2) ?? match.group(3);
          if (val != null) {
            final parsed = double.tryParse(val);
            if (parsed != null) return parsed;
          }
        }
      }
      return fallback;
    }

    final minG = getDoubleVal(['GainMapMin', 'HDRGainMapMin', 'HDRGainMapCapacityMin'], 0.0);
    final maxG = getDoubleVal(['GainMapMax', 'HDRGainMapMax', 'HDRGainMapCapacityMax'], 2.0);
    final finalMaxG = maxG > minG ? maxG : 2.0;

    return UltraHdrMetadata(
      gainMapMin: minG,
      gainMapMax: finalMaxG,
      gamma: getDoubleVal(['Gamma', 'HDRGainMapGamma'], 1.0),
      offsetSdr: getDoubleVal(['OffsetSDR', 'HDRGainMapOffsetSDR'], 0.015625),
      offsetHdr: getDoubleVal(['OffsetHDR', 'HDRGainMapOffsetHDR'], 0.015625),
      hdrCapacityMin: getDoubleVal(['HDRCapacityMin'], 0.0),
      hdrCapacityMax: getDoubleVal(['HDRCapacityMax'], finalMaxG),
      rawXmp: strSample,
    );
  }

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
    final meta = injectedMetadata ?? parseMetadata(originalBytes);
    final rawGainmap = injectedGainmapJpeg ?? extractGainmapJpeg(originalBytes);

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
