import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import '../../models/exif_info.dart';
import 'tiff_container_extractor.dart';

/// EXIF 读取与解析：纯 Dart 高速解析（JPEG/HEIC/WebP/PNG/TIFF），
/// 未命中时回落到 Android 原生 ExifInterface
class ExifReader {
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
      final tiffBytes = TiffContainerExtractor.extractTiffBytes(bytes);
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
      // FNumber 直接是 f 数；ApertureValue/MaxApertureValue 是 APEX 值，需按 N = 2^(Av/2) 换算
      String fNumber = '';
      final fVal = _getTag(exif, ['FNumber', 0x829d]);
      final dF = _parseToDouble(fVal);
      if (dF != null && dF > 0) {
        fNumber = 'f/${dF.toStringAsFixed(1)}';
      } else {
        final apexVal = _getTag(exif, ['ApertureValue', 0x9202, 'MaxApertureValue', 0x9205]);
        final dAv = _parseToDouble(apexVal);
        if (dAv != null && dAv > 0) {
          final f = math.pow(2.0, dAv / 2.0).toDouble();
          if (f > 0 && f.isFinite) {
            fNumber = 'f/${f.toStringAsFixed(1)}';
          }
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
