import 'dart:math' as math;
import 'dart:typed_data';

/// 各类图像容器（JPEG APP1、WebP EXIF、PNG eXIf、HEIC/ISOBMFF、TIFF/DNG）
/// 中 TIFF EXIF 数据块的提取，以及 Orientation 方向标签的读取与归一化
class TiffContainerExtractor {
  TiffContainerExtractor._();

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
}
