import 'dart:typed_data';
import 'tiff_container_extractor.dart';

/// EXIF 注入与回写：JPEG APP1 段提取/构建/替换、PNG eXIf chunk 注入，
/// 以及面向导出图片的统一 preserveExif 编排
class ExifInjector {
  ExifInjector._();

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
            return TiffContainerExtractor.normalizeExifOrientation(seg);
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

    // 沿 chunk 结构定位 IEND：length(4) + type(4) + data + crc(4)。
    // 直接裸扫 "IEND" 四字节可能命中 IDAT 压缩数据内部，导致 eXIf 被插进图像数据里
    int iendIndex = -1;
    int pos = 8;
    while (pos + 8 <= pngBytes.length) {
      final chunkDataLen = (pngBytes[pos] << 24) |
          (pngBytes[pos + 1] << 16) |
          (pngBytes[pos + 2] << 8) |
          pngBytes[pos + 3];
      if (chunkDataLen < 0 || pos + 12 + chunkDataLen > pngBytes.length) {
        break; // 结构异常，放弃遍历
      }
      final isIend = pngBytes[pos + 4] == 0x49 &&
          pngBytes[pos + 5] == 0x45 &&
          pngBytes[pos + 6] == 0x4E &&
          pngBytes[pos + 7] == 0x44;
      if (isIend) {
        iendIndex = pos;
        break;
      }
      pos += 12 + chunkDataLen;
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
        final tiffBytes = TiffContainerExtractor.extractTiffBytes(originalBytes);
        if (tiffBytes != null && tiffBytes.isNotEmpty) {
          final synthesizedApp1 = createJpegApp1ExifSegment(tiffBytes);
          return injectExifToJpeg(outputBytes, synthesizedApp1);
        }
      } else if (isPng) {
        final tiffBytes = TiffContainerExtractor.extractTiffBytes(originalBytes);
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
}
