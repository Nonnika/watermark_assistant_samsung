import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:watermark_samsung/services/ultra_hdr_service.dart';

void main() {
  test('UltraHdrService accurately detects Ultra HDR signatures and parses metadata', () {
    const mockXmpHeader = 'http://ns.adobe.com/hdr-gain-map/1.0/ hdrgm:GainMapMin="0.0" hdrgm:GainMapMax="2.5" hdrgm:Gamma="1.0"';
    final mockBytes = Uint8List.fromList([
      0xFF, 0xD8, 0xFF, 0xE1, 0x00, 0x50,
      ...mockXmpHeader.codeUnits,
      0xFF, 0xD9,
    ]);

    expect(UltraHdrService.isUltraHdr(mockBytes), isTrue);

    final meta = UltraHdrService.parseMetadata(mockBytes);
    expect(meta.gainMapMin, 0.0);
    expect(meta.gainMapMax, 2.5);
    expect(meta.gamma, 1.0);

    final xmp = UltraHdrService.generateUltraHdrXmp(meta, gainmapLength: 1024);
    expect(xmp.contains('hdrgm:GainMapMax="2.500000"'), isTrue);
    expect(xmp.contains('Item:Semantic="GainMap"'), isTrue);
  });

  test('UltraHdrService synthesizes and injects Gainmap into composite JPEG', () async {
    final origImg = img.Image(width: 100, height: 100);
    img.fill(origImg, color: img.ColorRgb8(255, 200, 100));
    final origJpg = Uint8List.fromList(img.encodeJpg(origImg));

    final sdrImg = img.Image(width: 120, height: 140);
    img.fill(sdrImg, color: img.ColorRgb8(255, 255, 255));
    final sdrJpg = Uint8List.fromList(img.encodeJpg(sdrImg));

    final ultraHdrOutput = await UltraHdrService.compositeAndPreserveUltraHdr(
      originalBytes: origJpg,
      sdrCompositeBytes: sdrJpg,
      photoLeft: 10,
      photoTop: 10,
      photoWidth: 100,
      photoHeight: 100,
      totalWidth: 120,
      totalHeight: 140,
      quality: 90,
    );

    expect(ultraHdrOutput.isNotEmpty, isTrue);
    expect(UltraHdrService.isUltraHdr(ultraHdrOutput), isTrue);
  });
}
