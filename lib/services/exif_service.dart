import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import '../models/exif_info.dart';

class ExifService {
  static const MethodChannel _nativeChannel = MethodChannel('com.example.watermark_samsung/ultra_hdr');

  /// 异步提取 EXIF 信息（结合纯 Dart 提取器与 Android 原生 ExifInterface 双重保障）
  static Future<ExifInfo> extractExifAsync(
    Uint8List bytes, {
    String? path,
    String? uri,
  }) async {
    // 1. 先用纯 Dart 提取器高速同步解析 (支持 JPEG, HEIC, WebP, PNG, TIFF/DNG)
    final parsed = extractExif(bytes);
    if (parsed.hasExif) {
      return parsed;
    }

    // 2. 若 Dart 解析未发现完整 EXIF 且在 Android 平台，调用原生 ExifInterface
    if (Platform.isAndroid) {
      try {
        final Map<dynamic, dynamic>? nativeMap = await _nativeChannel.invokeMethod('getExif', {
          'bytes': bytes.length < 1024 * 1024 * 24 ? bytes : null,
          'path': path,
          'uri': uri,
        });

        if (nativeMap != null) {
          final make = (nativeMap['make'] ?? '').toString().trim();
          final model = (nativeMap['model'] ?? '').toString().trim();
          var fNumber = (nativeMap['fNumber'] ?? '').toString().trim();
          if (fNumber.isNotEmpty && !fNumber.startsWith('f/')) {
            final d = double.tryParse(fNumber);
            if (d != null && d > 0) {
              fNumber = 'f/${d.toStringAsFixed(1)}';
            }
          }

          var focalLength = (nativeMap['focalLength'] ?? '').toString().trim();
          if (focalLength.isNotEmpty && !focalLength.endsWith('mm')) {
            if (focalLength.contains('/')) {
              final parts = focalLength.split('/');
              final num = double.tryParse(parts[0]);
              final den = double.tryParse(parts[1]);
              if (num != null && den != null && den > 0) {
                final val = num / den;
                focalLength = '${val == val.roundToDouble() ? val.toInt() : val.toStringAsFixed(1)}mm';
              }
            } else {
              final d = double.tryParse(focalLength);
              if (d != null && d > 0) {
                focalLength = '${d == d.roundToDouble() ? d.toInt() : d.toStringAsFixed(1)}mm';
              }
            }
          }

          final exposureTime = formatExposureTime(nativeMap['exposureTime'], nativeMap['shutterSpeedValue']);

          var iso = (nativeMap['iso'] ?? '').toString().replaceAll(RegExp(r'[^\d]'), '').trim();
          if (iso.isNotEmpty) {
            iso = 'ISO $iso';
          }

          var dateTime = (nativeMap['dateTime'] ?? '').toString().trim();
          if (dateTime.isNotEmpty) {
            final parts = dateTime.split(' ');
            if (parts.length >= 2) {
              final datePart = parts[0].replaceAll(':', '.');
              final timeParts = parts[1].split(':');
              final timePart = timeParts.length >= 2 ? '${timeParts[0]}:${timeParts[1]}' : parts[1];
              dateTime = '$datePart $timePart';
            }
          }

          final hasExif = make.isNotEmpty ||
              model.isNotEmpty ||
              focalLength.isNotEmpty ||
              fNumber.isNotEmpty ||
              exposureTime.isNotEmpty ||
              iso.isNotEmpty ||
              dateTime.isNotEmpty;

          if (hasExif) {
            return ExifInfo(
              make: make,
              model: model,
              lens: '$focalLength $fNumber'.trim(),
              focalLength: focalLength,
              fNumber: fNumber,
              exposureTime: exposureTime,
              iso: iso,
              dateTime: dateTime,
              hasExif: true,
            );
          }
        }
      } catch (e) {
        debugPrint('[ExifService] Native getExif error: $e');
      }
    }

    return parsed;
  }

  /// 从图片字节流中解析 EXIF 拍摄参数（支持 JPEG、WebP、PNG、HEIC/HEIF、TIFF/DNG）
  static ExifInfo extractExif(Uint8List bytes) {
    try {
      if (bytes.length < 12) {
        return const ExifInfo(hasExif: false);
      }

      img.ExifData? exif;

      // 1. 尝试从常见格式中高速提取 TIFF EXIF 数据块 (JPEG APP1, WebP, PNG, HEIC)
      final tiffBytes = extractTiffBytes(bytes);
      if (tiffBytes != null && tiffBytes.isNotEmpty) {
        try {
          final directExif = img.ExifData();
          directExif.read(img.InputBuffer(tiffBytes));
          if (!directExif.isEmpty) {
            exif = directExif;
          }
        } catch (_) {}
      }

      // 2. 若直接提取未成功，尝试直接作为 TIFF 结构读取 (DNG / TIFF)
      if (exif == null || exif.isEmpty) {
        try {
          final fallbackExif = img.ExifData();
          fallbackExif.read(img.InputBuffer(bytes));
          if (!fallbackExif.isEmpty) {
            exif = fallbackExif;
          }
        } catch (_) {}
      }

      // 3. 若仍未读取到，通过图像解码器元数据提取
      if (exif == null || exif.isEmpty) {
        try {
          final decoder = img.findDecoderForData(bytes);
          if (decoder != null) {
            final decoded = decoder.decode(bytes);
            if (decoded != null && !decoded.exif.isEmpty) {
              exif = decoded.exif;
            }
          }
        } catch (_) {}
      }

      if (exif == null || exif.isEmpty) {
        return const ExifInfo(hasExif: false);
      }

      // 1. 提取相机品牌与机型 (Make 0x010f, Model 0x0110)
      String make = '';
      String model = '';
      final makeVal = _getTag(exif, ['Make', 0x010f]);
      final modelVal = _getTag(exif, ['Model', 0x0110]);

      if (makeVal != null) {
        make = _cleanString(makeVal.toString());
      }
      if (modelVal != null) {
        model = _cleanString(modelVal.toString());
      }

      // 2. 焦距 (FocalLength 0x920a)
      String focalLength = '';
      final focalVal = _getTag(exif, ['FocalLength', 0x920a, 'FocalLengthIn35mmFilm', 0xa405]);
      if (focalVal != null) {
        final d = _parseToDouble(focalVal);
        if (d != null && d > 0) {
          final isInt = d == d.roundToDouble();
          focalLength = '${isInt ? d.toInt() : d.toStringAsFixed(1)}mm';
        }
      }

      // 3. 光圈 f 值 (FNumber 0x829d / ApertureValue 0x9202)
      String fNumber = '';
      final fVal = _getTag(exif, ['FNumber', 0x829d, 'ApertureValue', 0x9202, 'MaxApertureValue', 0x9205]);
      if (fVal != null) {
        final d = _parseToDouble(fVal);
        if (d != null && d > 0) {
          fNumber = 'f/${d.toStringAsFixed(1)}';
        }
      }

      // 4. 快门速度 (优先 ExposureTime 0x829a, 其次 ShutterSpeedValue 0x9201)
      final expVal = _getTag(exif, ['ExposureTime', 0x829a]);
      final shutterVal = _getTag(exif, ['ShutterSpeedValue', 0x9201]);
      final exposureTime = formatExposureTime(expVal, shutterVal);

      // 5. ISO (ISOSpeedRatings 0x8827 / PhotographicSensitivity 0x8827)
      String iso = '';
      final isoVal = _getTag(exif, ['ISOSpeedRatings', 'PhotographicSensitivity', 'ISO', 0x8827, 0x8833]);
      if (isoVal != null) {
        final rawIso = isoVal.toString().replaceAll(RegExp(r'[^\d]'), '');
        if (rawIso.isNotEmpty) {
          iso = 'ISO $rawIso';
        }
      }

      // 6. 拍摄时间 (DateTimeOriginal 0x9003 / DateTimeDigitized 0x9004 / DateTime 0x0132)
      String dateTime = '';
      final dtVal = _getTag(exif, ['DateTimeOriginal', 0x9003, 'DateTimeDigitized', 0x9004, 'DateTime', 0x0132]);
      if (dtVal != null) {
        final rawDt = _cleanString(dtVal.toString());
        final parts = rawDt.split(' ');
        if (parts.length >= 2) {
          final datePart = parts[0].replaceAll(':', '.');
          final timeParts = parts[1].split(':');
          final timePart = timeParts.length >= 2 ? '${timeParts[0]}:${timeParts[1]}' : parts[1];
          dateTime = '$datePart $timePart';
        } else if (rawDt.isNotEmpty) {
          dateTime = rawDt;
        }
      }

      final hasExif = make.isNotEmpty ||
          model.isNotEmpty ||
          focalLength.isNotEmpty ||
          fNumber.isNotEmpty ||
          exposureTime.isNotEmpty ||
          iso.isNotEmpty ||
          dateTime.isNotEmpty;

      return ExifInfo(
        make: make,
        model: model,
        lens: '$focalLength $fNumber'.trim(),
        focalLength: focalLength,
        fNumber: fNumber,
        exposureTime: exposureTime,
        iso: iso,
        dateTime: dateTime,
        hasExif: hasExif,
      );
    } catch (_) {
      return const ExifInfo(hasExif: false);
    }
  }

  static dynamic _getTag(img.ExifData exif, List<dynamic> tagKeys) {
    for (final dir in [exif.exifIfd, exif.imageIfd, ...exif.directories.values]) {
      for (final key in tagKeys) {
        final val = dir[key];
        if (val != null) return val;
      }
    }
    return null;
  }

  /// 从各类图像容器（JPEG APP1、WebP EXIF、PNG eXIf、HEIC/ISOBMFF、TIFF/DNG）中精准剥离 TIFF 数据块
  static Uint8List? extractTiffBytes(Uint8List bytes) {
    if (bytes.length < 12) return null;

    // 1. 原生 TIFF / DNG 格式 (II* 或 MM*)
    if ((bytes[0] == 0x49 && bytes[1] == 0x49 && bytes[2] == 0x2A && bytes[3] == 0x00) ||
        (bytes[0] == 0x4D && bytes[1] == 0x4D && bytes[2] == 0x00 && bytes[3] == 0x2A)) {
      return bytes;
    }

    // 2. JPEG 格式 (0xFF 0xD8) -> 扫描 APP1 标记 (0xFF 0xE1)
    if (bytes[0] == 0xFF && bytes[1] == 0xD8) {
      int offset = 2;
      while (offset + 4 < bytes.length) {
        if (bytes[offset] != 0xFF) {
          offset++;
          continue;
        }

        final marker = bytes[offset + 1];
        if (marker == 0xDA || marker == 0xD9) {
          // SOS (Start of Scan) 或 EOI
          break;
        }

        final length = (bytes[offset + 2] << 8) | bytes[offset + 3];
        if (length < 2 || offset + 2 + length > bytes.length) break;

        // APP1 (0xFF 0xE1) 包含 Exif\0\0
        if (marker == 0xE1 && length >= 8) {
          final header = bytes.sublist(offset + 4, offset + 10);
          if (header[0] == 0x45 &&
              header[1] == 0x78 &&
              header[2] == 0x69 &&
              header[3] == 0x66 &&
              header[4] == 0x00 &&
              header[5] == 0x00) {
            final tiffStart = offset + 10;
            final tiffEnd = offset + 2 + length;
            if (tiffEnd <= bytes.length && tiffStart < tiffEnd) {
              return bytes.sublist(tiffStart, tiffEnd);
            }
          }
        }

        offset += 2 + length;
      }
    }

    // 3. WebP 格式 (RIFF....WEBP) -> 扫描 EXIF chunk
    if (bytes.length >= 12 &&
        bytes[0] == 0x52 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x46 &&
        bytes[8] == 0x57 && bytes[9] == 0x45 && bytes[10] == 0x42 && bytes[11] == 0x50) {
      int offset = 12;
      while (offset + 8 < bytes.length) {
        final chunkType = String.fromCharCodes(bytes.sublist(offset, offset + 4));
        final chunkSize = bytes[offset + 4] |
            (bytes[offset + 5] << 8) |
            (bytes[offset + 6] << 16) |
            (bytes[offset + 7] << 24);
        final chunkDataStart = offset + 8;
        final chunkDataEnd = chunkDataStart + chunkSize;

        if (chunkType == 'EXIF') {
          if (chunkDataEnd <= bytes.length) {
            var tiffBytes = bytes.sublist(chunkDataStart, chunkDataEnd);
            if (tiffBytes.length > 6 &&
                tiffBytes[0] == 0x45 &&
                tiffBytes[1] == 0x78 &&
                tiffBytes[2] == 0x69 &&
                tiffBytes[3] == 0x66 &&
                tiffBytes[4] == 0x00 &&
                tiffBytes[5] == 0x00) {
              tiffBytes = tiffBytes.sublist(6);
            }
            return tiffBytes;
          }
        }

        offset += 8 + chunkSize + (chunkSize % 2);
      }
    }

    // 4. PNG 格式 (eXIf chunk)
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47) {
      int offset = 8;
      while (offset + 12 < bytes.length) {
        final length = (bytes[offset] << 24) |
            (bytes[offset + 1] << 16) |
            (bytes[offset + 2] << 8) |
            bytes[offset + 3];
        final type = String.fromCharCodes(bytes.sublist(offset + 4, offset + 8));
        final dataStart = offset + 8;
        final dataEnd = dataStart + length;

        if (type == 'eXIf' && dataEnd <= bytes.length) {
          return bytes.sublist(dataStart, dataEnd);
        }

        offset += 12 + length;
      }
    }

    // 5. HEIC / HEIF / AVIF / ISOBMFF 格式
    final heicTiff = _extractHeicTiffBytes(bytes);
    if (heicTiff != null && heicTiff.isNotEmpty) {
      return heicTiff;
    }

    return null;
  }

  /// 从 HEIC / HEIF / AVIF / ISOBMFF 容器中提取 TIFF 格式 EXIF 字节块
  static Uint8List? _extractHeicTiffBytes(Uint8List bytes) {
    if (bytes.length < 16) return null;

    // 检查 ftyp 签名
    final isIsobmff = bytes[4] == 0x66 && bytes[5] == 0x74 && bytes[6] == 0x79 && bytes[7] == 0x70;
    if (!isIsobmff) return null;

    // 1. 深度特征特征扫描 (扫描 Exif 签名与 II*/MM* TIFF 标头)
    return _scanTiffHeader(bytes);
  }

  /// 获取原始图片 EXIF 中的 Orientation 方向值 (1~8, 默认 1)
  static int getExifOrientation(Uint8List bytes) {
    if (bytes.length < 14) return 1;

    int tiffStart = 0;
    // 如果是 JPEG, 扫描寻找 APP1 EXIF 段
    if (bytes[0] == 0xFF && bytes[1] == 0xD8) {
      int offset = 2;
      while (offset + 4 < bytes.length) {
        if (bytes[offset] != 0xFF) break;
        final marker = bytes[offset + 1];
        if (marker == 0xDA || marker == 0xD9) break;
        final len = (bytes[offset + 2] << 8) | bytes[offset + 3];
        if (marker == 0xE1 && offset + 10 <= bytes.length) {
          final header = bytes.sublist(offset + 4, offset + 10);
          if (header[0] == 0x45 && header[1] == 0x78 && header[2] == 0x69 && header[3] == 0x66) {
            tiffStart = offset + 10;
            break;
          }
        }
        offset += 2 + len;
      }
    } else if (bytes.length >= 10 && bytes[0] == 0xFF && bytes[1] == 0xE1) {
      if (bytes[4] == 0x45 && bytes[5] == 0x78 && bytes[6] == 0x69 && bytes[7] == 0x66) {
        tiffStart = 10;
      }
    }

    if (tiffStart + 8 > bytes.length) return 1;

    final isLe = bytes[tiffStart] == 0x49 && bytes[tiffStart + 1] == 0x49;
    final isBe = bytes[tiffStart] == 0x4D && bytes[tiffStart + 1] == 0x4D;
    if (!isLe && !isBe) return 1;

    int r16(int p) => isLe
        ? (bytes[p] | (bytes[p + 1] << 8))
        : ((bytes[p] << 8) | bytes[p + 1]);
    int r32(int p) => isLe
        ? (bytes[p] | (bytes[p + 1] << 8) | (bytes[p + 2] << 16) | (bytes[p + 3] << 24))
        : ((bytes[p] << 24) | (bytes[p + 1] << 16) | (bytes[p + 2] << 8) | bytes[p + 3]);

    try {
      final ifd0Offset = r32(tiffStart + 4);
      if (ifd0Offset < 8 || tiffStart + ifd0Offset + 2 > bytes.length) return 1;

      final numEntries = r16(tiffStart + ifd0Offset);
      int tagPos = tiffStart + ifd0Offset + 2;

      for (int i = 0; i < numEntries; i++) {
        if (tagPos + 12 > bytes.length) break;
        final tagId = r16(tagPos);
        if (tagId == 0x0112) { // Orientation Tag
          final orientation = r16(tagPos + 8);
          if (orientation >= 1 && orientation <= 8) {
            return orientation;
          }
          break;
        }
        tagPos += 12;
      }
    } catch (_) {}

    return 1;
  }

  /// 将 APP1 EXIF 段或 TIFF 结构中的 Orientation 旋转标签重置为 1 (正常朝向)，
  /// 防止导出的图片因为像素已被 Canvas 旋转为正向后被相册再次二次旋转。
  static Uint8List normalizeExifOrientation(Uint8List app1OrTiffBytes) {
    if (app1OrTiffBytes.length < 14) return app1OrTiffBytes;

    final bytes = Uint8List.fromList(app1OrTiffBytes);

    int tiffStart = 0;
    // 检查是否为包含 APP1 标记的段
    if (bytes[0] == 0xFF && bytes[1] == 0xE1 && bytes.length >= 10) {
      if (bytes[4] == 0x45 && bytes[5] == 0x78 && bytes[6] == 0x69 && bytes[7] == 0x66) {
        tiffStart = 10;
      }
    }

    if (tiffStart + 8 > bytes.length) return bytes;

    final isLe = bytes[tiffStart] == 0x49 && bytes[tiffStart + 1] == 0x49;
    final isBe = bytes[tiffStart] == 0x4D && bytes[tiffStart + 1] == 0x4D;
    if (!isLe && !isBe) return bytes;

    int r16(int p) => isLe
        ? (bytes[p] | (bytes[p + 1] << 8))
        : ((bytes[p] << 8) | bytes[p + 1]);
    int r32(int p) => isLe
        ? (bytes[p] | (bytes[p + 1] << 8) | (bytes[p + 2] << 16) | (bytes[p + 3] << 24))
        : ((bytes[p] << 24) | (bytes[p + 1] << 16) | (bytes[p + 2] << 8) | bytes[p + 3]);

    void w16(int p, int val) {
      if (isLe) {
        bytes[p] = val & 0xFF;
        bytes[p + 1] = (val >> 8) & 0xFF;
      } else {
        bytes[p] = (val >> 8) & 0xFF;
        bytes[p + 1] = val & 0xFF;
      }
    }

    try {
      final ifd0Offset = r32(tiffStart + 4);
      if (ifd0Offset < 8 || tiffStart + ifd0Offset + 2 > bytes.length) return bytes;

      final numEntries = r16(tiffStart + ifd0Offset);
      int tagPos = tiffStart + ifd0Offset + 2;

      for (int i = 0; i < numEntries; i++) {
        if (tagPos + 12 > bytes.length) break;
        final tagId = r16(tagPos);
        if (tagId == 0x0112) { // Orientation Tag
          // 重置 Orientation 为 1 (Normal / Top-Left)
          w16(tagPos + 8, 1);
          bytes[tagPos + 10] = 0;
          bytes[tagPos + 11] = 0;
          break;
        }
        tagPos += 12;
      }
    } catch (_) {}

    return bytes;
  }

  /// 扫描二进制数据流中的 TIFF 标头 (II* 或 MM*)
  static Uint8List? _scanTiffHeader(Uint8List bytes) {
    if (bytes.length < 16) return null;
    final maxScan = math.min(bytes.length - 12, 1024 * 1024); // 扫描前 1MB

    for (int i = 0; i < maxScan; i++) {
      // 检查 'Exif\0\0'
      if (i + 6 < bytes.length &&
          bytes[i] == 0x45 &&
          bytes[i + 1] == 0x78 &&
          bytes[i + 2] == 0x69 &&
          bytes[i + 3] == 0x66 &&
          bytes[i + 4] == 0x00 &&
          bytes[i + 5] == 0x00) {
        final candidate = bytes.sublist(i + 6);
        if (_isValidTiffHeader(candidate)) {
          return normalizeExifOrientation(candidate);
        }
      }

      // 检查 II*\0 (0x49 0x49 0x2A 0x00) 或 MM\0* (0x4D 0x4D 0x00 0x2A)
      if ((bytes[i] == 0x49 && bytes[i + 1] == 0x49 && bytes[i + 2] == 0x2A && bytes[i + 3] == 0x00) ||
          (bytes[i] == 0x4D && bytes[i + 1] == 0x4D && bytes[i + 2] == 0x00 && bytes[i + 3] == 0x2A)) {
        final candidate = bytes.sublist(i);
        if (_isValidTiffHeader(candidate)) {
          return normalizeExifOrientation(candidate);
        }
      }
    }
    return null;
  }

  /// 快速验证是否为有效的 TIFF 结构标头
  static bool _isValidTiffHeader(Uint8List bytes) {
    if (bytes.length < 12) return false;
    final isLittleEndian = bytes[0] == 0x49 && bytes[1] == 0x49 && bytes[2] == 0x2A && bytes[3] == 0x00;
    final isBigEndian = bytes[0] == 0x4D && bytes[1] == 0x4D && bytes[2] == 0x00 && bytes[3] == 0x2A;
    if (!isLittleEndian && !isBigEndian) return false;

    // 读取 IFD0 偏移量
    final ifd0Offset = isLittleEndian
        ? (bytes[4] | (bytes[5] << 8) | (bytes[6] << 16) | (bytes[7] << 24))
        : ((bytes[4] << 24) | (bytes[5] << 16) | (bytes[6] << 8) | bytes[7]);

    if (ifd0Offset < 8 || ifd0Offset + 2 > bytes.length) return false;

    // 读取 IFD0 条目数量
    final entryCount = isLittleEndian
        ? (bytes[ifd0Offset] | (bytes[ifd0Offset + 1] << 8))
        : ((bytes[ifd0Offset] << 8) | bytes[ifd0Offset + 1]);

    return entryCount > 0 && entryCount < 1000;
  }

  /// 从 JPEG 字节流中直接提取完整的 APP1 EXIF 数据段 (包含 0xFF 0xE1、长度与 'Exif\0\0')
  /// 并自动将 Orientation 归一化为 1
  static Uint8List? extractApp1ExifSegment(Uint8List bytes) {
    if (bytes.length < 14 || bytes[0] != 0xFF || bytes[1] != 0xD8) return null;
    int offset = 2;
    while (offset + 4 < bytes.length) {
      if (bytes[offset] != 0xFF) break;
      final marker = bytes[offset + 1];
      if (marker == 0xDA || marker == 0xD9) break; // SOS or EOI
      final len = (bytes[offset + 2] << 8) | bytes[offset + 3];
      if (marker == 0xE1 && offset + 10 <= bytes.length) {
        final header = bytes.sublist(offset + 4, offset + 10);
        if (header[0] == 0x45 &&
            header[1] == 0x78 &&
            header[2] == 0x69 &&
            header[3] == 0x66 &&
            header[4] == 0x00 &&
            header[5] == 0x00) {
          final segEnd = offset + 2 + len;
          if (segEnd <= bytes.length) {
            final seg = bytes.sublist(offset, segEnd);
            return normalizeExifOrientation(seg);
          }
        }
      }
      offset += 2 + len;
    }
    return null;
  }

  /// 将纯 TIFF EXIF 字节封装为标准的 JPEG APP1 EXIF 数据段
  static Uint8List createJpegApp1ExifSegment(Uint8List tiffBytes) {
    final segLen = tiffBytes.length + 2 + 6; // 2 bytes for length field + 6 for 'Exif\0\0'
    final builder = BytesBuilder();
    builder.add([
      0xFF, 0xE1,
      (segLen >> 8) & 0xFF, segLen & 0xFF,
      0x45, 0x78, 0x69, 0x66, 0x00, 0x00,
    ]);
    builder.add(tiffBytes);
    return builder.takeBytes();
  }

  /// 将 APP1 EXIF 数据段安全注入到导出的 JPEG 图片流中 (紧随 SOI 0xFF 0xD8 之后)
  static Uint8List injectExifToJpeg(Uint8List jpegBytes, Uint8List app1Segment) {
    if (jpegBytes.length < 4 || jpegBytes[0] != 0xFF || jpegBytes[1] != 0xD8) {
      return jpegBytes;
    }

    // 检查目标 JPEG 是否已有原生的空/旧 APP1 EXIF 段，若有则精准替换
    int offset = 2;
    int? existingStart;
    int? existingEnd;
    while (offset + 4 < jpegBytes.length) {
      if (jpegBytes[offset] != 0xFF) break;
      final marker = jpegBytes[offset + 1];
      if (marker == 0xDA || marker == 0xD9) break;
      final len = (jpegBytes[offset + 2] << 8) | jpegBytes[offset + 3];
      if (marker == 0xE1 && offset + 10 <= jpegBytes.length) {
        final header = jpegBytes.sublist(offset + 4, offset + 10);
        if (header[0] == 0x45 && header[1] == 0x78 && header[2] == 0x69 && header[3] == 0x66) {
          existingStart = offset;
          existingEnd = offset + 2 + len;
          break;
        }
      }
      offset += 2 + len;
    }

    final builder = BytesBuilder();
    builder.add([0xFF, 0xD8]); // SOI
    builder.add(app1Segment);  // Injected EXIF

    if (existingStart != null && existingEnd != null) {
      if (existingStart > 2) {
        builder.add(jpegBytes.sublist(2, existingStart));
      }
      if (existingEnd < jpegBytes.length) {
        builder.add(jpegBytes.sublist(existingEnd));
      }
    } else {
      builder.add(jpegBytes.sublist(2));
    }

    return builder.takeBytes();
  }

  /// 将 EXIF TIFF 字节封装为 PNG eXIf chunk 注入到导出的 PNG 图片流中 (放置于 IEND 之前)
  static Uint8List injectExifToPng(Uint8List pngBytes, Uint8List tiffBytes) {
    if (pngBytes.length < 8 ||
        pngBytes[0] != 0x89 || pngBytes[1] != 0x50 ||
        pngBytes[2] != 0x4E || pngBytes[3] != 0x47) {
      return pngBytes;
    }

    // 寻找 IEND 块
    int iendIndex = -1;
    for (int i = 8; i <= pngBytes.length - 12; i++) {
      if (pngBytes[i + 4] == 0x49 &&
          pngBytes[i + 5] == 0x45 &&
          pngBytes[i + 6] == 0x4E &&
          pngBytes[i + 7] == 0x44) {
        iendIndex = i;
        break;
      }
    }

    if (iendIndex == -1) {
      iendIndex = pngBytes.length;
    }

    // 构建 eXIf chunk: 4 bytes length, 4 bytes 'eXIf', data, 4 bytes CRC
    final chunkType = [0x65, 0x58, 0x49, 0x66]; // 'eXIf'
    final chunkLen = tiffBytes.length;
    final crcData = <int>[...chunkType, ...tiffBytes];
    final crc = calculateCrc32(crcData);

    final chunkBuilder = BytesBuilder();
    chunkBuilder.add([
      (chunkLen >> 24) & 0xFF,
      (chunkLen >> 16) & 0xFF,
      (chunkLen >> 8) & 0xFF,
      chunkLen & 0xFF,
      ...chunkType,
    ]);
    chunkBuilder.add(tiffBytes);
    chunkBuilder.add([
      (crc >> 24) & 0xFF,
      (crc >> 16) & 0xFF,
      (crc >> 8) & 0xFF,
      crc & 0xFF,
    ]);

    final finalBuilder = BytesBuilder();
    finalBuilder.add(pngBytes.sublist(0, iendIndex));
    finalBuilder.add(chunkBuilder.takeBytes());
    if (iendIndex < pngBytes.length) {
      finalBuilder.add(pngBytes.sublist(iendIndex));
    }

    return finalBuilder.takeBytes();
  }

  /// 统一定制：从原图字节中提取 EXIF 并完整写回合成导出的图片中 (支持 JPG 与 PNG)
  static Uint8List preserveExif({
    required Uint8List outputBytes,
    required Uint8List originalBytes,
    required String format,
  }) {
    try {
      final isJpg = format.toLowerCase().contains('jpg') || format.toLowerCase().contains('jpeg');
      final isPng = format.toLowerCase().contains('png');

      if (isJpg) {
        // 优先提取原图完整的 APP1 EXIF 段
        final app1Segment = extractApp1ExifSegment(originalBytes);
        if (app1Segment != null && app1Segment.isNotEmpty) {
          return injectExifToJpeg(outputBytes, app1Segment);
        }

        // 若原图为非 JPEG (如 PNG/WebP/HEIC)，但包含 TIFF EXIF，转换为 APP1 注入
        final tiffBytes = extractTiffBytes(originalBytes);
        if (tiffBytes != null && tiffBytes.isNotEmpty) {
          final synthesizedApp1 = createJpegApp1ExifSegment(tiffBytes);
          return injectExifToJpeg(outputBytes, synthesizedApp1);
        }
      } else if (isPng) {
        final tiffBytes = extractTiffBytes(originalBytes);
        if (tiffBytes != null && tiffBytes.isNotEmpty) {
          return injectExifToPng(outputBytes, tiffBytes);
        }
      }
    } catch (_) {
      // 容错降级返回原始输出
    }
    return outputBytes;
  }

  /// 标准 CRC-32 计算 (IEEE 802.3 多项式 0xEDB88320)
  static int calculateCrc32(List<int> bytes) {
    int crc = 0xFFFFFFFF;
    for (final byte in bytes) {
      crc ^= (byte & 0xFF);
      for (int i = 0; i < 8; i++) {
        if ((crc & 1) != 0) {
          crc = (crc >>> 1) ^ 0xEDB88320;
        } else {
          crc = crc >>> 1;
        }
      }
    }
    return (~crc) & 0xFFFFFFFF;
  }

  static double? _parseToDouble(dynamic val) {
    if (val == null) return null;
    if (val is num) return val.toDouble();

    final str = val.toString().replaceAll('[', '').replaceAll(']', '').trim();
    if (str.contains('/')) {
      final parts = str.split('/');
      if (parts.length >= 2) {
        final num1 = double.tryParse(parts[0].replaceAll(RegExp(r'[^\d.]'), '').trim());
        final num2 = double.tryParse(parts[1].replaceAll(RegExp(r'[^\d.]'), '').trim());
        if (num1 != null && num2 != null && num2 != 0) {
          return num1 / num2;
        }
      }
    }
    return double.tryParse(str.replaceAll(RegExp(r'[^\d.]'), ''));
  }

  static String _cleanString(String raw) {
    return raw.replaceAll('\u0000', '').replaceAll('"', '').trim();
  }

  /// 标准化摄影快门速度 (支持各种分数/比率、十进制秒、APEX Tv 转换与智能约分)
  static String formatExposureTime(dynamic expVal, [dynamic shutterSpeedVal]) {
    if (expVal == null && shutterSpeedVal == null) return '';

    double? seconds;

    if (expVal != null) {
      if (expVal is num) {
        if (expVal > 0) seconds = expVal.toDouble();
      } else {
        final rawStr = expVal.toString().replaceAll('sec', '').replaceAll('s', '').replaceAll('[', '').replaceAll(']', '').trim();
        if (rawStr.contains('/')) {
          final parts = rawStr.split('/');
          if (parts.length >= 2) {
            final num1 = double.tryParse(parts[0].replaceAll(RegExp(r'[^\d.]'), '').trim());
            final num2 = double.tryParse(parts[1].replaceAll(RegExp(r'[^\d.]'), '').trim());
            if (num1 != null && num2 != null && num2 > 0 && num1 > 0) {
              if (num1 == 1.0 && num2 >= 1.0) {
                final denom = num2 == num2.roundToDouble() ? num2.toInt() : num2.round();
                return '1/${denom}s';
              }
              seconds = num1 / num2;
            }
          }
        } else {
          final d = double.tryParse(rawStr.replaceAll(RegExp(r'[^\d.]'), ''));
          if (d != null && d > 0) {
            seconds = d;
          }
        }
      }
    }

    // 若 ExposureTime 缺失或无效，尝试通过 APEX ShutterSpeedValue (Tv) 计算: T = 2^(-Tv)
    if ((seconds == null || seconds <= 0) && shutterSpeedVal != null) {
      final tv = _parseToDouble(shutterSpeedVal);
      if (tv != null) {
        seconds = math.pow(2.0, -tv).toDouble();
      }
    }

    if (seconds == null || seconds <= 0 || seconds.isNaN || seconds.isInfinite) {
      return '';
    }

    // 格式化输出为符合相机标准的快门表示法
    if (seconds < 0.6) {
      // 快速快门 (如 1/8000s, 1/2000s, 1/60s, 1/30s, 1/2s)
      final denom = (1.0 / seconds).round();
      if (denom > 1) {
        return '1/${denom}s';
      }
      return '1s';
    } else if (seconds < 1.0) {
      // 0.6s ~ 0.9s
      return '${seconds.toStringAsFixed(1)}s';
    } else {
      // 慢门与长曝光 (如 1s, 2s, 2.5s, 30s)
      if ((seconds - seconds.roundToDouble()).abs() < 0.05) {
        return '${seconds.round()}s';
      } else {
        return '${seconds.toStringAsFixed(1)}s';
      }
    }
  }
}
