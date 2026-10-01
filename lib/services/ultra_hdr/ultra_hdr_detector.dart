import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
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
  static const MethodChannel _nativeChannel = MethodChannel(
    'com.example.watermark_samsung/ultra_hdr',
  );

  @visibleForTesting
  static bool? debugOverrideIsAndroid;

  /// null 表示平台不支持或解码失败；false 是成功解码后的 SDR 结果。
  static Future<bool?> checkNativeGainmap({
    Uint8List? bytes,
    String? path,
    String? uri,
  }) async {
    if (!(debugOverrideIsAndroid ?? Platform.isAndroid)) return null;
    try {
      return await _nativeChannel.invokeMethod<bool>('hasGainmap', {
        'bytes': ?bytes,
        'path': ?path,
        'uri': ?uri,
      });
    } catch (_) {
      return null;
    }
  }

  /// 优先采用 Android 解码结果，仅在平台无法判定时解析 JPEG 增益图。
  static Future<bool> checkIsUltraHdr(Uint8List bytes) async {
    return await checkNativeGainmap(bytes: bytes) ?? isUltraHdr(bytes);
  }

  /// HDR 必须包含增益图，普通 XMP 容器、MPF 或动态照片 SEF 不构成证据。
  static bool isUltraHdr(Uint8List bytes) => extractGainmapJpeg(bytes) != null;

  /// 只提取带 HDR 元数据的附加 JPEG，或 SEF 目录明确命名的增益图。
  static Uint8List? extractGainmapJpeg(Uint8List bytes) {
    final primary = _readJpeg(bytes, 0);
    if (primary == null) return null;

    final sefGainmap = _extractSefGainmap(bytes, primary.end);
    if (sefGainmap != null) return sefGainmap;

    // 从主图真正的 EOI 开始，跳过 APP1 内的 EXIF 缩略图。
    // 不依赖 MPF 偏移：动态照片重新封装 XMP 后，旧偏移可能失效。
    for (var start = primary.end; start + 2 < bytes.length; start++) {
      if (bytes[start] != 0xff || bytes[start + 1] != 0xd8) continue;
      final auxiliary = _readJpeg(bytes, start);
      if (auxiliary == null) continue;
      if (primary.hasHdrMetadata || auxiliary.hasHdrMetadata) {
        return Uint8List.sublistView(bytes, start, auxiliary.end);
      }
      start = auxiliary.end - 1;
    }
    return null;
  }

  /// 解析 JPEG 标记与熵编码，验证完整扫描与 EOI，不把嵌入缩略图当主图。
  static ({int end, bool hasHdrMetadata})? _readJpeg(
    Uint8List bytes,
    int start,
  ) {
    if (start + 2 > bytes.length ||
        bytes[start] != 0xff ||
        bytes[start + 1] != 0xd8) {
      return null;
    }
    var offset = start + 2;
    var inScan = false;
    var hasScan = false;
    var hasFrame = false;
    var hasHdrMetadata = false;
    while (offset < bytes.length) {
      if (bytes[offset] != 0xff) {
        if (!inScan) return null;
        offset++;
        continue;
      }
      while (offset < bytes.length && bytes[offset] == 0xff) {
        offset++;
      }
      if (offset >= bytes.length) return null;
      final marker = bytes[offset++];
      if (marker == 0x00 || (marker >= 0xd0 && marker <= 0xd7)) {
        if (!inScan) return null;
        continue;
      }
      if (marker == 0xd9) {
        return hasScan && hasFrame
            ? (end: offset, hasHdrMetadata: hasHdrMetadata)
            : null;
      }
      if (marker == 0xd8) return null;
      if (marker == 0x01) continue;
      if (offset + 2 > bytes.length) return null;
      final length = (bytes[offset] << 8) | bytes[offset + 1];
      final end = offset + length;
      if (length < 2 || end > bytes.length) return null;
      if (marker == 0xe1 || marker == 0xe2) {
        final payload = latin1.decode(
          Uint8List.sublistView(bytes, offset + 2, end),
        );
        if (marker == 0xe1 &&
            payload.startsWith('http://ns.adobe.com/xap/1.0/\x00')) {
          hasHdrMetadata |=
              payload.contains('http://ns.adobe.com/hdr-gain-map/1.0/') ||
              payload.contains('http://ns.apple.com/HDRGainMap/1.0/');
        } else if (marker == 0xe2 &&
            payload.startsWith('urn:iso:std:iso:ts:21496:-1\x00')) {
          hasHdrMetadata |=
              payload.length > 'urn:iso:std:iso:ts:21496:-1\x00'.length;
        }
      }
      if (marker >= 0xc0 &&
          marker <= 0xcf &&
          marker != 0xc4 &&
          marker != 0xc8 &&
          marker != 0xcc) {
        hasFrame = true;
      }
      inScan = marker == 0xda;
      hasScan |= inScan;
      offset = end;
    }
    return null;
  }

  static Uint8List? _extractSefGainmap(Uint8List bytes, int primaryEnd) {
    if (bytes.length < 28 ||
        latin1.decode(bytes.sublist(bytes.length - 4)) != 'SEFT') {
      return null;
    }
    final data = ByteData.sublistView(bytes);
    int r32(int offset) => data.getUint32(offset, Endian.little);
    final directory = bytes.length - 8 - r32(bytes.length - 8);
    if (directory < primaryEnd ||
        directory + 12 > bytes.length - 8 ||
        latin1.decode(bytes.sublist(directory, directory + 4)) != 'SEFH') {
      return null;
    }
    final count = r32(directory + 8);
    if (count > (bytes.length - 8 - directory - 12) ~/ 12) return null;
    for (var i = 0; i < count; i++) {
      final entry = directory + 12 + i * 12;
      final field = directory - r32(entry + 4);
      final fieldEnd = field + r32(entry + 8);
      if (field < primaryEnd || field + 8 > fieldEnd || fieldEnd > directory) {
        continue;
      }
      final nameEnd = field + 8 + r32(field + 4);
      if (nameEnd > fieldEnd) continue;
      final name = latin1.decode(bytes.sublist(field + 8, nameEnd));
      if (name != 'DualShot_GainMap' && name != 'HdrGainMap') continue;
      final jpeg = _readJpeg(bytes, nameEnd);
      if (jpeg != null && jpeg.end <= fieldEnd) {
        return Uint8List.sublistView(bytes, nameEnd, jpeg.end);
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
        final reg = RegExp(
          '$key="([^"]+)"|<hdrgm:$key>([^<]+)</hdrgm:$key>|<apgain:$key>([^<]+)</apgain:$key>',
        );
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

    final minG = getDoubleVal([
      'GainMapMin',
      'HDRGainMapMin',
      'HDRGainMapCapacityMin',
    ], 0.0);
    final maxG = getDoubleVal([
      'GainMapMax',
      'HDRGainMapMax',
      'HDRGainMapCapacityMax',
    ], 2.0);
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
