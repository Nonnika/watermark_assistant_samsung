import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';

/// 动态照片合成 (纯 Dart 同步装配)：GCamera/GContainer/Samsung 双格式 XMP
/// 注入与 Samsung SEF trailer 构建，输出 [JPEG with XMP] + [SEF Trailer] 结构
class MotionPhotoComposer {
  MotionPhotoComposer._();

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
