import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

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

/// 动态照片 (Motion Photo / Live Photo / MicroVideo) 全流程处理引擎
/// 深度支持 Samsung (SEF/SEFT)、Google Pixel (GCamera/MicroVideo)、小米/OPPO/vivo 等主流 Android 动态照片
class MotionPhotoService {
  static const MethodChannel _nativeChannel = MethodChannel('com.example.watermark_samsung/ultra_hdr');

  /// 为动态照片的内嵌 MP4 视频叠加水印图层
  static Future<Uint8List> watermarkMotionVideo({
    required Uint8List videoBytes,
    required Uint8List overlayPngBytes,
  }) async {
    if (!Platform.isAndroid || videoBytes.isEmpty || overlayPngBytes.isEmpty) {
      return videoBytes;
    }

    try {
      final Uint8List? processed = await _nativeChannel.invokeMethod<Uint8List>('watermarkVideo', {
        'videoBytes': videoBytes,
        'overlayBytes': overlayPngBytes,
      });
      return (processed != null && processed.isNotEmpty) ? processed : videoBytes;
    } catch (e) {
      debugPrint('[MotionPhotoService] watermarkVideo error: $e');
      return videoBytes;
    }
  }

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

  /// 获取文件末尾三星 SEF 尾部(含内嵌视频)的总字节数


  /// 从动态照片中精确提取纯净 MP4 视频流 (支持 Android 原生高效提取与 Dart 兜底)
  static Future<MotionVideoInfo?> extractMotionVideoAsync(
    Uint8List bytes, {
    String? path,
    String? uri,
  }) async {
    if (Platform.isAndroid) {
      try {
        final dynamic res = await _nativeChannel.invokeMethod('extractMotionPhotoNative', {
          'bytes': bytes,
          'path': path,
          'uri': uri,
        });
        if (res is Map && res['isMotionPhoto'] == true) {
          final Uint8List? vBytes = res['videoBytes'] as Uint8List?;
          if (vBytes != null && vBytes.isNotEmpty) {
            return MotionVideoInfo(
              videoBytes: vBytes,
              offset: (res['offset'] as num?)?.toInt() ?? 0,
              length: (res['length'] as num?)?.toInt() ?? vBytes.length,
              presentationTimestampUs: (res['presentationTimestampUs'] as num?)?.toInt() ?? 0,
            );
          }
        }
      } catch (e) {
        debugPrint('[MotionPhotoService] Native extractMotionPhotoNative error: $e, falling back to Dart');
      }
    }

    return extractMotionVideo(bytes);
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
      try {
        final sefDataSize = (bytes[len - 8] & 0xFF) |
            ((bytes[len - 7] & 0xFF) << 8) |
            ((bytes[len - 6] & 0xFF) << 16) |
            ((bytes[len - 5] & 0xFF) << 24);
        final sefhAbs = len - 8 - sefDataSize;
        videoEnd = sefhAbs > offset ? sefhAbs : len;
      } catch (_) {
        videoEnd = len;
      }
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

  /// 将处理完水印的高清静态 JPEG 与动态视频流 (MP4) 重新组装为原生动态照片 (优先 Android 原生组装)
  static Future<Uint8List> compositeAndPreserveMotionPhotoAsync({
    required Uint8List watermarkedJpgBytes,
    required Uint8List motionVideoBytes,
    int? presentationTimestampUs,
  }) async {
    if (Platform.isAndroid) {
      try {
        final Uint8List? composited = await _nativeChannel.invokeMethod<Uint8List>('compositeMotionPhotoNative', {
          'watermarkedJpgBytes': watermarkedJpgBytes,
          'motionVideoBytes': motionVideoBytes,
          'presentationTimestampUs': presentationTimestampUs ?? 0,
        });
        if (composited != null && composited.isNotEmpty) {
          return composited;
        }
      } catch (e) {
        debugPrint('[MotionPhotoService] Native compositeMotionPhotoNative error: $e, falling back to Dart');
      }
    }

    return compositeAndPreserveMotionPhoto(
      watermarkedJpgBytes: watermarkedJpgBytes,
      motionVideoBytes: motionVideoBytes,
      presentationTimestampUs: presentationTimestampUs,
    );
  }

  /// 将处理完水印的高清静态 JPEG 与动态视频流 (MP4) 重新组装为原生动态照片 (Motion Photo, 纯 Dart 同步装配)
  ///
  /// 正确文件结构 (根据 doodspav/motionphoto 参考实现):
  ///   [JPEG with XMP] + [SEF Trailer]
  /// 其中 SEF Trailer 完整内容为:
  ///   [marker(4)][nameLen(4)][name(16)][MP4 video bytes][SEFH(4)][version(4)][count(4)][entry(12)][sefDataSize(4)][SEFT(4)]
  ///   = 24 + videoLength + 32 bytes
  ///
  /// MicroVideoOffset (距文件末尾到 MP4 起始点的距离):
  ///   = total_sef_trailer_size - 24 = videoLength + 32
  static Uint8List compositeAndPreserveMotionPhoto({
    required Uint8List watermarkedJpgBytes,
    required Uint8List motionVideoBytes,
    int? presentationTimestampUs,
  }) {
    final videoLength = motionVideoBytes.length;
    final ts = (presentationTimestampUs != null && presentationTimestampUs > 0)
        ? presentationTimestampUs
        : 1500000;

    // 1. 构造包含内嵌视频的 Samsung SEF 完整尾部
    //    视频字节直接嵌入 SEF trailer 中 (不是单独放在 trailer 之前)
    final sefTrailer = _buildSamsungSefTrailerWithVideo(motionVideoBytes);

    // 2. MicroVideoOffset: 从 EOF 到 MP4 视频起始点的字节距离
    //    SEF trailer 结构: [field_header(24)] + [video] + [SEFH block(32)]
    //    MicroVideoOffset = sefTrailer.length - 24 = videoLength + 32
    const sefBlockSize = 32; // SEFH(4)+ver(4)+count(4)+entry(12)+sefDataSize(4)+SEFT(4)
    final microVideoOffset = videoLength + sefBlockSize;

    // 3. 构造 XMP (Google GCamera + GContainer + Samsung 双格式)
    //    - Primary Item:Padding = 24 (JPEG 尾部到 MP4 开头之间的 Samsung field header 长度: 4 marker + 4 len + 16 name)
    //    - MotionPhoto Item:Padding = 32 (MP4 视频尾部到文件 EOF 之间的 SEFH 目录块长度)
    //    - GCamera:MicroVideoOffset = videoLength + 32 (EOF 到 MP4 视频开头的绝对距离)
    final xmpString = '<x:xmpmeta xmlns:x="adobe:ns:meta/" x:xmptk="Adobe XMP Core 5.1.0-jc003">\n'
        '  <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">\n'
        '    <rdf:Description rdf:about=""\n'
        '        xmlns:GCamera="http://ns.google.com/photos/1.0/camera/"\n'
        '        xmlns:Container="http://ns.google.com/photos/1.0/container/"\n'
        '        xmlns:Item="http://ns.google.com/photos/1.0/container/item/"\n'
        '        xmlns:Camera="http://ns.google.com/photos/1.0/camera/"\n'
        '        xmlns:samsung="http://ns.samsung.com/photo/1.0/"\n'
        '        GCamera:MotionPhoto="1"\n'
        '        GCamera:MotionPhotoVersion="1"\n'
        '        GCamera:MotionPhotoPresentationTimestampUs="$ts"\n'
        '        GCamera:MicroVideo="1"\n'
        '        GCamera:MicroVideoVersion="1"\n'
        '        GCamera:MicroVideoOffset="$microVideoOffset"\n'
        '        GCamera:MicroVideoPresentationTimestampUs="$ts"\n'
        '        Camera:MotionPhoto="1"\n'
        '        Camera:MicroVideo="1"\n'
        '        Camera:MicroVideoOffset="$microVideoOffset"\n'
        '        samsung:MotionPhoto="1"\n'
        '        samsung:MotionPhotoVersion="1"\n'
        '        samsung:MotionPhoto_Data="1"\n'
        '        samsung:SEFType="2048"\n'
        '        samsung:SpecialType="2048">\n'
        '      <Container:Directory>\n'
        '        <rdf:Seq>\n'
        '          <rdf:li rdf:parseType="Resource">\n'
        '            <Item:Mime>image/jpeg</Item:Mime>\n'
        '            <Item:Semantic>Primary</Item:Semantic>\n'
        '            <Item:Length>0</Item:Length>\n'
        '            <Item:Padding>24</Item:Padding>\n'
        '          </rdf:li>\n'
        '          <rdf:li rdf:parseType="Resource">\n'
        '            <Item:Mime>video/mp4</Item:Mime>\n'
        '            <Item:Semantic>MotionPhoto</Item:Semantic>\n'
        '            <Item:Length>$videoLength</Item:Length>\n'
        '            <Item:Padding>$sefBlockSize</Item:Padding>\n'
        '          </rdf:li>\n'
        '        </rdf:Seq>\n'
        '      </Container:Directory>\n'
        '    </rdf:Description>\n'
        '  </rdf:RDF>\n'
        '</x:xmpmeta>\n';

    final xmpBytes = utf8.encode(xmpString);

    // 4. 注入 XMP 到 JPEG (置于 Exif APP1 之后)
    final jpgWithXmp = _injectOrReplaceXmpApp1(watermarkedJpgBytes, xmpBytes);

    // 5. 拼接: [JPEG with XMP] + [SEF trailer (含内嵌 MP4)]
    final result = Uint8List(jpgWithXmp.length + sefTrailer.length);
    result.setRange(0, jpgWithXmp.length, jpgWithXmp);
    result.setRange(jpgWithXmp.length, result.length, sefTrailer);

    debugPrint('[MotionPhotoService] Composited: jpeg=${jpgWithXmp.length}B, sefTrailer=${sefTrailer.length}B (video=${videoLength}B embedded), total=${result.length}B, microVideoOffset=$microVideoOffset');
    return result;
  }

  /// 向 JPEG 中规范注入或替换 XMP APP1 (0xFFE1) 段
  /// 严格遵循 JPEG 规范：保持 SOI -> APP0/Exif APP1 -> XMP APP1 -> 其他 Markers，清除旧 XMP 段
  static Uint8List _injectOrReplaceXmpApp1(Uint8List jpgBytes, List<int> xmpBytes) {
    if (jpgBytes.length < 4 || jpgBytes[0] != 0xFF || jpgBytes[1] != 0xD8) {
      return jpgBytes;
    }

    const xmpNamespace = 'http://ns.adobe.com/xap/1.0/\x00';
    final nsBytes = utf8.encode(xmpNamespace);

    final app1PayloadLength = nsBytes.length + xmpBytes.length;
    final markerLength = app1PayloadLength + 2;

    final app1Bytes = BytesBuilder();
    app1Bytes.addByte(0xFF);
    app1Bytes.addByte(0xE1);
    app1Bytes.addByte((markerLength >> 8) & 0xFF);
    app1Bytes.addByte(markerLength & 0xFF);
    app1Bytes.add(nsBytes);
    app1Bytes.add(xmpBytes);

    final newApp1Segment = app1Bytes.toBytes();

    // 扫描 JPEG 所有标记段，滤除所有已有的 XMP 段，并在 Exif APP1 / JFIF 之后插入新 XMP 段
    final builder = BytesBuilder();
    int offset = 2;
    int insertPosition = 2;

    while (offset + 4 < jpgBytes.length) {
      if (jpgBytes[offset] != 0xFF) break;
      final marker = jpgBytes[offset + 1];
      if (marker == 0xDA || marker == 0xD9) break;

      final len = (jpgBytes[offset + 2] << 8) | jpgBytes[offset + 3];
      final segEnd = offset + 2 + len;

      if (marker == 0xE0 || (marker == 0xE1 && !_isXmpSegment(jpgBytes, offset, nsBytes))) {
        insertPosition = segEnd;
      }
      offset = segEnd;
    }

    offset = 2;
    builder.add(jpgBytes.sublist(0, 2)); // SOI

    bool xmpInserted = false;
    while (offset + 4 < jpgBytes.length) {
      if (jpgBytes[offset] != 0xFF) {
        builder.add(jpgBytes.sublist(offset));
        break;
      }
      final marker = jpgBytes[offset + 1];
      if (marker == 0xDA || marker == 0xD9) {
        if (!xmpInserted) {
          builder.add(newApp1Segment);
          xmpInserted = true;
        }
        builder.add(jpgBytes.sublist(offset));
        break;
      }

      final len = (jpgBytes[offset + 2] << 8) | jpgBytes[offset + 3];
      final segEnd = offset + 2 + len;

      if (marker == 0xE1 && _isXmpSegment(jpgBytes, offset, nsBytes)) {
        // 跳过旧 XMP 段
        offset = segEnd;
        continue;
      }

      builder.add(jpgBytes.sublist(offset, segEnd));
      if (!xmpInserted && segEnd >= insertPosition) {
        builder.add(newApp1Segment);
        xmpInserted = true;
      }
      offset = segEnd;
    }

    if (!xmpInserted) {
      builder.add(newApp1Segment);
    }

    return builder.toBytes();
  }

  static bool _isXmpSegment(Uint8List bytes, int offset, List<int> nsBytes) {
    if (offset + 4 + nsBytes.length > bytes.length) return false;
    for (int i = 0; i < nsBytes.length; i++) {
      if (bytes[offset + 4 + i] != nsBytes[i]) return false;
    }
    return true;
  }

  /// 构造三星 Samsung SEF (Samsung Extra Field) 完整尾部结构 (含内嵌 MP4 视频)
  ///
  /// 根据 doodspav/motionphoto 与 Samsung SEF 标准精准构造：
  /// 文件最终结构: [JPEG with XMP] + [此 SEF trailer]
  ///
  /// SEF trailer 内部结构:
  ///   [0x30 0x0A 0x00 0x00]  EmbeddedVideo tag (0x0A30, type 0x0000 in LE)
  ///   [16 LE]                nameLen (4 bytes LE)
  ///   "MotionPhoto_Data"     name (16 bytes, no null)
  ///   [MP4 video bytes]      actual video data
  ///   "SEFH"                 head marker (4 bytes)
  ///   [106 LE]               version (4 bytes)
  ///   [1 LE]                 field count (4 bytes)
  ///   [0x30 0x0A 0x00 0x00]  entry tag/type (4 bytes LE)
  ///   [negOff LE]            negativeOffset from SEFH to field start (4 bytes)
  ///   [dataLen LE]           data length = field header + video (4 bytes)
  ///   [sefDataSize LE]       bytes from SEFH (excl.) to sefDataSize field (4 bytes) = 24
  ///   "SEFT"                 tail marker (4 bytes)
  ///
  /// Total size = 24 + videoLength + 32 bytes
  static Uint8List _buildSamsungSefTrailerWithVideo(Uint8List videoBytes) {
    final videoLength = videoBytes.length;
    final trailer = BytesBuilder();

    // ── Part 1: EmbeddedVideoType field header (24 bytes) ───────────────────
    // Marker (4 bytes): 0x00, 0x00, 0x30, 0x0A (Embedded Video = 0x0000300A)
    trailer.addByte(0x00);
    trailer.addByte(0x00);
    trailer.addByte(0x30);
    trailer.addByte(0x0A);
    // nameLen = 16 (4 bytes LE): 0x10, 0x00, 0x00, 0x00
    trailer.addByte(16);
    trailer.addByte(0x00);
    trailer.addByte(0x00);
    trailer.addByte(0x00);
    // name "MotionPhoto_Data" (exactly 16 bytes, no null terminator)
    trailer.add(utf8.encode('MotionPhoto_Data'));

    // ── Part 2: Video data (embedded directly here) ─────────────────────────
    trailer.add(videoBytes);

    // ── Part 3: SEFH index block (32 bytes) ─────────────────────────────────
    final negativeOffset = 24 + videoLength;
    final dataLength = 24 + videoLength;

    // "SEFH" (4 bytes ASCII)
    trailer.addByte(0x53); // S
    trailer.addByte(0x45); // E
    trailer.addByte(0x46); // F
    trailer.addByte(0x48); // H

    // version = 106 (4 bytes LE)
    trailer.addByte(106);
    trailer.addByte(0x00);
    trailer.addByte(0x00);
    trailer.addByte(0x00);

    // field count = 1 (4 bytes LE)
    trailer.addByte(0x01);
    trailer.addByte(0x00);
    trailer.addByte(0x00);
    trailer.addByte(0x00);

    // entry: marker (4 bytes) = 0x00, 0x00, 0x30, 0x0A
    trailer.addByte(0x00);
    trailer.addByte(0x00);
    trailer.addByte(0x30);
    trailer.addByte(0x0A);
    // entry: negativeOffset (4 bytes LE)
    trailer.addByte(negativeOffset & 0xFF);
    trailer.addByte((negativeOffset >> 8) & 0xFF);
    trailer.addByte((negativeOffset >> 16) & 0xFF);
    trailer.addByte((negativeOffset >> 24) & 0xFF);
    // entry: dataLength (4 bytes LE)
    trailer.addByte(dataLength & 0xFF);
    trailer.addByte((dataLength >> 8) & 0xFF);
    trailer.addByte((dataLength >> 16) & 0xFF);
    trailer.addByte((dataLength >> 24) & 0xFF);

    // ── Part 4: SEF tail ────────────────────────────────────────────────────
    // sefDataSize = size of directory from SEFH to sefDataSize field = 24 bytes (0x18)
    const sefDataSize = 24;
    trailer.addByte(sefDataSize);
    trailer.addByte(0x00);
    trailer.addByte(0x00);
    trailer.addByte(0x00);

    // "SEFT" (4 bytes ASCII)
    trailer.addByte(0x53); // S
    trailer.addByte(0x45); // E
    trailer.addByte(0x46); // F
    trailer.addByte(0x54); // T

    return trailer.toBytes();
  }
}
