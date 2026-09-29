import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';

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

/// Ultra HDR 图像检测：签名识别、Gainmap 提取与 XMP 参数解析
class UltraHdrDetector {
  static const MethodChannel _nativeChannel = MethodChannel('com.example.watermark_samsung/ultra_hdr');

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
    // SEF 布局: [主图][内嵌 Gainmap JPEG][SEFH 目录][sefDataSize(4)][SEFT(4)]
    // Gainmap 位于 SEFH 目录之前，而非目录内部
    if (bytes.length > 40) {
      final len = bytes.length;
      if (bytes[len - 4] == 0x53 &&
          bytes[len - 3] == 0x45 &&
          bytes[len - 2] == 0x46 &&
          bytes[len - 1] == 0x54) { // 'SEFT'
        final sefDataSize = (bytes[len - 8] & 0xFF) |
            ((bytes[len - 7] & 0xFF) << 8) |
            ((bytes[len - 6] & 0xFF) << 16) |
            ((bytes[len - 5] & 0xFF) << 24);
        if (sefDataSize > 0 && sefDataSize <= 65536 && len - 8 - sefDataSize > 2) {
          final sefhAbs = len - 8 - sefDataSize;
          // 从 SEFH 目录起点向前寻找最后一个内嵌 JPEG SOI，即为 Gainmap 起始
          final scanStart = sefhAbs > (4 << 20) ? sefhAbs - (4 << 20) : 2;
          for (int i = sefhAbs - 3; i >= scanStart; i--) {
            if (bytes[i] == 0xFF && bytes[i + 1] == 0xD8 && bytes[i + 2] == 0xFF) {
              return bytes.sublist(i, sefhAbs);
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
}
