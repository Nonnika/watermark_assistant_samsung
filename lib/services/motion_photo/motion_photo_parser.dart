import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

/// 动态照片内嵌视频信息
class MotionVideoInfo {
  final Uint8List videoBytes;
  final int offset;
  final int length;
  final int presentationTimestampUs;

  const MotionVideoInfo({
    required this.videoBytes,
    required this.offset,
    required this.length,
    this.presentationTimestampUs = 0,
  });
}

/// 动态照片解析：Motion Photo 判定、MP4 视频流定位与提取、静态封面剥离
/// 支持 Samsung (SEF/SEFT)、Google Pixel (GCamera/MicroVideo)、小米/OPPO/vivo 等主流 Android 动态照片
class MotionPhotoParser {
  MotionPhotoParser._();

  /// 检查图像字节流是否为真实的动态照片 (Motion Photo)
  /// 必须实际存在可提取的有效 MP4 视频流，杜绝仅包含元数据或特征误判的情况 (支持 JPEG 与 HEIC)
  static bool isMotionPhoto(Uint8List bytes) {
    if (bytes.length < 32) return false;
    final mp4Offset = findMp4Offset(bytes);
    if (mp4Offset <= 0 || mp4Offset >= bytes.length - 8) return false;

    // 验证 MP4 头部签名与有效性
    return _isValidMp4Header(bytes, mp4Offset);
  }

  /// 验证指定偏移处是否为合法的 MP4 头部 (ftyp box)
  static bool _isValidMp4Header(Uint8List bytes, int offset) {
    if (offset < 0 || offset + 12 > bytes.length) return false;

    // 检查 'ftyp' (0x66, 0x74, 0x79, 0x70)
    if (bytes[offset + 4] != 0x66 ||
        bytes[offset + 5] != 0x74 ||
        bytes[offset + 6] != 0x79 ||
        bytes[offset + 7] != 0x70) {
      return false;
    }

    // 读取 box 大小 (4 字节大端序)
    final boxSize = (bytes[offset] << 24) |
        (bytes[offset + 1] << 16) |
        (bytes[offset + 2] << 8) |
        bytes[offset + 3];
    if (boxSize < 16 || boxSize > 65536) return false;

    final b0 = bytes[offset + 8];
    final b1 = bytes[offset + 9];
    final b2 = bytes[offset + 10];
    final b3 = bytes[offset + 11];
    final brand = String.fromCharCodes([b0, b1, b2, b3]).toLowerCase();

    // 静态图像容器 Brand 坚决不能作为视频流 (杜绝将静态 HEIC/AVIF 误判为视频)
    const staticImageBrands = {
      'heic', 'heix', 'heim', 'heis', 'mif1', 'msf1', 'avif', 'avis', 'avic', 'miaf'
    };
    if (staticImageBrands.contains(brand)) {
      return false;
    }

    // 常见标准视频 Brand (包含 MP4/MOV/3GP/Samsung/Xiaomi 等)
    const validVideoBrands = {
      'mp41', 'mp42', 'isom', 'iso2', 'iso4', 'iso5', 'iso6',
      'avc1', 'hvc1', 'hev1', 'qt  ', 'm4v ', 'm4a ', 'msnv',
      'dash', 'mp71', '3gp4', '3gp5', '3gp6', '3g2a', 'caep',
      'qvfs', 'f4v ', 'sec ', 's264', 'kddi', 'mmp4'
    };

    if (validVideoBrands.contains(brand) ||
        brand.startsWith('mp4') ||
        brand.startsWith('iso') ||
        brand.startsWith('3gp')) {
      return true;
    }

    // 检查 compatible brands 列表 (紧随 major_brand 和 minor_version 之后)
    if (offset + 16 < bytes.length) {
      final compatEnd = math.min(offset + boxSize, bytes.length);
      for (int c = offset + 16; c + 4 <= compatEnd; c += 4) {
        final cBrand = String.fromCharCodes([bytes[c], bytes[c + 1], bytes[c + 2], bytes[c + 3]]).toLowerCase();
        if (validVideoBrands.contains(cBrand) ||
            cBrand.startsWith('mp4') ||
            cBrand.startsWith('iso') ||
            cBrand.startsWith('3gp')) {
          return true;
        }
      }
    }

    return false;
  }

  /// 搜索 MP4 视频流在整个图像字节流中的起始偏移位置 (支持 JPEG 与 HEIC)
  static int findMp4Offset(Uint8List bytes) {
    if (bytes.length < 32) return -1;

    // 1. 优先尝试从 XMP 中解析 MicroVideoOffset / Item:Length (Google Pixel / 小米 / OPPO / vivo / Samsung 等)
    final headLen = math.min(bytes.length, 524288);
    final headStr = utf8.decode(bytes.sublist(0, headLen), allowMalformed: true);

    // 1.1 MicroVideoOffset
    final offsetMatch = RegExp(r'''(?:GCamera:|Camera:)?MicroVideoOffset\s*=\s*["']?(\d+)["']?''').firstMatch(headStr) ??
        RegExp(r'''<(?:\w+:)?MicroVideoOffset>(\d+)</(?:\w+:)?MicroVideoOffset>''').firstMatch(headStr);
    if (offsetMatch != null) {
      final offsetFromEnd = int.tryParse(offsetMatch.group(1) ?? '');
      if (offsetFromEnd != null && offsetFromEnd > 0 && offsetFromEnd < bytes.length) {
        final calcOffset = bytes.length - offsetFromEnd;
        if (_isValidMp4Header(bytes, calcOffset)) {
          return calcOffset;
        }
      }
    }

    // 1.2 GContainer Directory Item:Length (MotionPhoto)
    final gcontainerMatch = RegExp(r'''<Item:Semantic>MotionPhoto</Item:Semantic>\s*<Item:Length>(\d+)</Item:Length>''').firstMatch(headStr) ??
        RegExp(r'''Item:Semantic=["']MotionPhoto["'][^>]*Item:Length=["'](\d+)["']''').firstMatch(headStr) ??
        RegExp(r'''Item:Length=["'](\d+)["'][^>]*Item:Semantic=["']MotionPhoto["']''').firstMatch(headStr);
    if (gcontainerMatch != null) {
      final videoLength = int.tryParse(gcontainerMatch.group(1) ?? '');
      if (videoLength != null && videoLength > 0 && videoLength < bytes.length) {
        final calcOffset = bytes.length - videoLength;
        if (_isValidMp4Header(bytes, calcOffset)) {
          return calcOffset;
        }
        final sefOff = _parseSamsungSefMp4Offset(bytes);
        if (sefOff > 0) {
          return sefOff;
        }
      }
    }

    // 2. 尝试从三星 SEF 尾部元数据中提取 MP4 偏移量 (Samsung JPEG / HEIC)
    final sefOffset = _parseSamsungSefMp4Offset(bytes);
    if (sefOffset > 0 && _isValidMp4Header(bytes, sefOffset)) {
      return sefOffset;
    }

    // 3. 逆向快速搜索 MP4 ftyp box (从文件尾部向前扫描，毫秒级快速匹配直接拼接的 MP4)
    final isJpeg = bytes[0] == 0xFF && bytes[1] == 0xD8;
    final minOffset = isJpeg ? 2 : 16;

    for (int i = bytes.length - 16; i >= minOffset; i--) {
      if (bytes[i + 4] == 0x66 && bytes[i + 5] == 0x74 && bytes[i + 6] == 0x79 && bytes[i + 7] == 0x70) {
        if (_isValidMp4Header(bytes, i)) {
          return i;
        }
      }
    }

    return -1;
  }

  /// 解析三星 SEFH/SEFT 结构中的 MP4 偏移量 (支持单条目与多条目 SEF 结构)
  ///
  /// 文件结构: [JPEG][field_header(24)][MP4 video][SEFH(4)][version(4)][count(4)][entries(12*N)][sefDataSize(4)][SEFT(4)]
  static int _parseSamsungSefMp4Offset(Uint8List bytes) {
    if (bytes.length < 40) return -1;
    final len = bytes.length;

    // 必须以 "SEFT" 结尾
    if (bytes[len - 4] != 0x53 || bytes[len - 3] != 0x45 ||
        bytes[len - 2] != 0x46 || bytes[len - 1] != 0x54) {
      return -1;
    }

    try {
      // sefDataSize 在 SEFT 前 4 bytes (LE)
      final sefDataSize = (bytes[len - 8] & 0xFF) |
          ((bytes[len - 7] & 0xFF) << 8) |
          ((bytes[len - 6] & 0xFF) << 16) |
          ((bytes[len - 5] & 0xFF) << 24);

      if (sefDataSize <= 0 || sefDataSize > 65536) return -1;

      // SEFH 绝对位置 = len - 8 - sefDataSize
      final sefhAbs = len - 8 - sefDataSize;
      if (sefhAbs < 0 || sefhAbs + 12 > len) return -1;

      // 验证 SEFH 标记
      if (bytes[sefhAbs] != 0x53 || bytes[sefhAbs + 1] != 0x45 ||
          bytes[sefhAbs + 2] != 0x46 || bytes[sefhAbs + 3] != 0x48) {
        return -1;
      }

      // 读取 entry 数量
      final count = (bytes[sefhAbs + 8] & 0xFF) |
          ((bytes[sefhAbs + 9] & 0xFF) << 8) |
          ((bytes[sefhAbs + 10] & 0xFF) << 16) |
          ((bytes[sefhAbs + 11] & 0xFF) << 24);

      final entryCount = count.clamp(1, 32);

      // 遍历所有 SEF entries 查找 MotionPhoto_Data (tag = 0x0A30 = 2608)
      for (int i = 0; i < entryCount; i++) {
        final entryOffset = sefhAbs + 12 + (i * 12);
        if (entryOffset + 12 > len) break;

        final negativeOffset = (bytes[entryOffset + 4] & 0xFF) |
            ((bytes[entryOffset + 5] & 0xFF) << 8) |
            ((bytes[entryOffset + 6] & 0xFF) << 16) |
            ((bytes[entryOffset + 7] & 0xFF) << 24);

        if (negativeOffset <= 0 || negativeOffset > sefhAbs) continue;

        // 字段起始 = SEFH - negativeOffset，MP4 起始 = 字段起始 + 24
        final fieldStart = sefhAbs - negativeOffset;
        final mp4Start = fieldStart + 24;

        if (mp4Start >= 0 && mp4Start + 8 <= len) {
          if (bytes[mp4Start + 4] == 0x66 && bytes[mp4Start + 5] == 0x74 &&
              bytes[mp4Start + 6] == 0x79 && bytes[mp4Start + 7] == 0x70) {
            return mp4Start;
          }
        }
      }
    } catch (_) {}

    return -1;
  }

  /// 从动态照片中精确提取纯净 MP4 视频流 (纯 Dart 同步解析)
  static MotionVideoInfo? extractMotionVideo(Uint8List bytes) {
    final offset = findMp4Offset(bytes);
    if (offset <= 0 || offset >= bytes.length) return null;

    // 确定视频结束位置: SEFH 的绝对位置 (视频之后紧接 SEFH)
    final len = bytes.length;
    int videoEnd;

    if (bytes[len - 4] == 0x53 && bytes[len - 3] == 0x45 &&
        bytes[len - 2] == 0x46 && bytes[len - 1] == 0x54) {
      // 有 SEFH/SEFT 结构: 找到 SEFH 位置即视频末尾
      // sefDataSize 需与 _parseSamsungSefMp4Offset 相同的边界校验，
      // 否则损坏文件会把 SEFH/SEFT 目录拼进 MP4 尾部
      final sefDataSize = (bytes[len - 8] & 0xFF) |
          ((bytes[len - 7] & 0xFF) << 8) |
          ((bytes[len - 6] & 0xFF) << 16) |
          ((bytes[len - 5] & 0xFF) << 24);
      final sefhAbs = len - 8 - sefDataSize;
      if (sefDataSize <= 0 || sefDataSize > 65536 || sefhAbs <= offset) {
        return null; // SEFT 尾部损坏，无法可靠界定视频边界
      }
      videoEnd = sefhAbs;
    } else {
      videoEnd = len;
    }

    if (videoEnd <= offset) return null;
    final videoBytes = bytes.sublist(offset, videoEnd);

    int timestampUs = 0;
    try {
      final headLen = math.min(bytes.length, 524288);
      final headStr = utf8.decode(bytes.sublist(0, headLen), allowMalformed: true);
      final tsMatch = RegExp(r'''(?:GCamera:|Camera:|samsung:)?(?:MotionPhotoPresentationTimestampUs|MicroVideoPresentationTimestampUs|PresentationTimestampUs)\s*=\s*["']?(\d+)["']?''').firstMatch(headStr);
      if (tsMatch != null) {
        timestampUs = int.tryParse(tsMatch.group(1) ?? '0') ?? 0;
      }
    } catch (_) {}

    if (timestampUs <= 0) {
      timestampUs = 1500000;
    }

    return MotionVideoInfo(
      videoBytes: videoBytes,
      offset: offset,
      length: videoBytes.length,
      presentationTimestampUs: timestampUs,
    );
  }

  /// 提取纯净的静态封面主图 JPEG (剔除尾部内嵌 MP4 与 SEF)
  static Uint8List extractPrimaryJpg(Uint8List bytes) {
    final offset = findMp4Offset(bytes);
    if (offset <= 0) return bytes;
    return bytes.sublist(0, offset);
  }
}
