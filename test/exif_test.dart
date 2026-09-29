import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:watermark_samsung/models/exif_info.dart';
import 'package:watermark_samsung/services/exif_service.dart';

void main() {
  test('ExifService accurately detects missing EXIF without dummy data', () {
    final emptyBytes = Uint8List(0);
    final exif = ExifService.extractExif(emptyBytes);
    expect(exif.hasExif, isFalse);
    expect(exif.isEmpty, isTrue);
    expect(exif.model, '');
    expect(exif.fNumber, '');
    expect(exif.parametersString, '');
  });

  test('ExifService accurately extracts EXIF metadata from JPEG image', () {
    final image = img.Image(width: 100, height: 100);
    image.exif.imageIfd['Make'] = img.IfdValueAscii('SAMSUNG');
    image.exif.imageIfd['Model'] = img.IfdValueAscii('Galaxy S24 Ultra');
    image.exif.exifIfd['FNumber'] = img.IfdValueRational(17, 10);
    image.exif.exifIfd['FocalLength'] = img.IfdValueRational(23, 1);
    image.exif.exifIfd['ExposureTime'] = img.IfdValueRational(1, 2000);
    image.exif.exifIfd[0x8827] = img.IfdValueShort(50);
    image.exif.exifIfd['DateTimeOriginal'] = img.IfdValueAscii('2024:08:20 16:30:00');

    final jpegBytes = Uint8List.fromList(img.encodeJpg(image));
    final parsed = ExifService.extractExif(jpegBytes);

    expect(parsed.hasExif, isTrue);
    expect(parsed.make, 'SAMSUNG');
    expect(parsed.model, 'Galaxy S24 Ultra');
    expect(parsed.fNumber, 'f/1.7');
    expect(parsed.focalLength, '23mm');
    expect(parsed.exposureTime, '1/2000s');
    expect(parsed.iso, 'ISO 50');
    expect(parsed.dateTime, '2024.08.20 16:30');
    expect(parsed.parametersString, '23mm  f/1.7  1/2000s  ISO 50');
  });

  test('ExifService accurately extracts EXIF from HEIC / ISOBMFF bytes', () {
    final image = img.Image(width: 50, height: 50);
    image.exif.imageIfd['Make'] = img.IfdValueAscii('Apple');
    image.exif.imageIfd['Model'] = img.IfdValueAscii('iPhone 15 Pro');
    image.exif.exifIfd['FNumber'] = img.IfdValueRational(18, 10);
    image.exif.exifIfd['FocalLength'] = img.IfdValueRational(24, 1);
    image.exif.exifIfd['ExposureTime'] = img.IfdValueRational(1, 1000);
    image.exif.exifIfd[0x8827] = img.IfdValueShort(100);

    final jpegBytes = Uint8List.fromList(img.encodeJpg(image));
    final tiffBlock = ExifService.extractTiffBytes(jpegBytes)!;

    // Construct mock HEIC container with ftyp and embedded TIFF EXIF block
    final heicBytes = BytesBuilder();
    heicBytes.add([0x00, 0x00, 0x00, 0x18]);
    heicBytes.add(utf8.encode('ftyp'));
    heicBytes.add(utf8.encode('heic'));
    heicBytes.add([0x00, 0x00, 0x00, 0x00]);
    heicBytes.add(utf8.encode('mif1heic'));
    heicBytes.add(utf8.encode('Exif\x00\x00'));
    heicBytes.add(tiffBlock);

    final parsed = ExifService.extractExif(heicBytes.toBytes());
    expect(parsed.hasExif, isTrue);
    expect(parsed.make, 'Apple');
    expect(parsed.model, 'iPhone 15 Pro');
    expect(parsed.fNumber, 'f/1.8');
    expect(parsed.focalLength, '24mm');
  });

  test('ExifInfo editing and formatted parameters string generation', () {
    const original = ExifInfo(
      model: 'Galaxy S24 Ultra',
      make: 'Samsung',
      focalLength: '24mm',
      fNumber: 'f/1.7',
      exposureTime: '1/2000s',
      iso: 'ISO 50',
      dateTime: '2024.08.21 14:30',
      hasExif: true,
    );

    expect(original.displayModelName, 'Samsung Galaxy S24 Ultra');
    expect(original.parametersString, '24mm  f/1.7  1/2000s  ISO 50');

    // Test editing EXIF
    final edited = original.copyWith(
      model: 'A7M4',
      make: 'Sony',
      focalLength: '50mm',
      fNumber: 'f/1.2',
      exposureTime: '1/8000s',
      iso: 'ISO 100',
      dateTime: '2026.08.21 11:30',
    );

    expect(edited.displayModelName, 'Sony A7M4');
    expect(edited.parametersString, '50mm  f/1.2  1/8000s  ISO 100');
    expect(edited.dateTime, '2026.08.21 11:30');
  });

  test('ExifService.preserveExif injects and preserves EXIF in JPEG and PNG files', () {
    // 1. Create a dummy JPEG with valid EXIF (Make=Samsung, Model=SM-S9280)
    final origImg = img.Image(width: 80, height: 80);
    final exifData = img.ExifData();
    exifData.imageIfd['Make'] = 'Samsung';
    exifData.imageIfd['Model'] = 'SM-S9280';
    origImg.exif = exifData;
    final origJpgWithExif = Uint8List.fromList(img.encodeJpg(origImg));

    // 2. Create clean destination images without EXIF
    final destImg = img.Image(width: 120, height: 120);
    final cleanDestJpg = Uint8List.fromList(img.encodeJpg(destImg));
    final cleanDestPng = Uint8List.fromList(img.encodePng(destImg));

    // 3. Preserve EXIF to JPEG
    final outputJpg = ExifService.preserveExif(
      outputBytes: cleanDestJpg,
      originalBytes: origJpgWithExif,
      format: 'jpg',
    );
    final parsedJpgExif = ExifService.extractExif(outputJpg);
    expect(parsedJpgExif.hasExif, isTrue);
    expect(parsedJpgExif.make, 'Samsung');
    expect(parsedJpgExif.model, 'SM-S9280');

    // 4. Preserve EXIF to PNG (eXIf chunk)
    final outputPng = ExifService.preserveExif(
      outputBytes: cleanDestPng,
      originalBytes: origJpgWithExif,
      format: 'png',
    );
    final parsedPngExif = ExifService.extractExif(outputPng);
    expect(parsedPngExif.hasExif, isTrue);
    expect(parsedPngExif.make, 'Samsung');
    expect(parsedPngExif.model, 'SM-S9280');

    // 5. Test Orientation normalization: Orientation=6 (90 CW) must be normalized to 1 (Normal)
    final origImgWithOrientation = img.Image(width: 80, height: 80);
    final exifWithOrientation = img.ExifData();
    exifWithOrientation.imageIfd['Make'] = 'Samsung';
    exifWithOrientation.imageIfd[0x0112] = img.IfdValueShort(6);
    origImgWithOrientation.exif = exifWithOrientation;
    final origJpgWithOrientation = Uint8List.fromList(img.encodeJpg(origImgWithOrientation));

    final outputJpgNormalized = ExifService.preserveExif(
      outputBytes: cleanDestJpg,
      originalBytes: origJpgWithOrientation,
      format: 'jpg',
    );
    final app1 = ExifService.extractApp1ExifSegment(outputJpgNormalized);
    expect(app1, isNotNull);
    int? readOrientation;
    if (app1 != null) {
      final isLe = app1[10] == 0x49;
      int r16(int p) => isLe ? (app1[p] | (app1[p + 1] << 8)) : ((app1[p] << 8) | app1[p + 1]);
      int r32(int p) => isLe
          ? (app1[p] | (app1[p + 1] << 8) | (app1[p + 2] << 16) | (app1[p + 3] << 24))
          : ((app1[p] << 24) | (app1[p + 1] << 16) | (app1[p + 2] << 8) | app1[p + 3]);
      final ifd0 = r32(14);
      final count = r16(10 + ifd0);
      for (int i = 0; i < count; i++) {
        final pos = 10 + ifd0 + 2 + i * 12;
        if (r16(pos) == 0x0112) {
          readOrientation = r16(pos + 8);
          break;
        }
      }
    }
    expect(readOrientation, 1);
  });

  test('ExifService.formatExposureTime accurately formats fractions, unreduced ratios, decimals, APEX, and long exposures', () {
    // 1. Standard fractions
    expect(ExifService.formatExposureTime('1/2000'), '1/2000s');
    expect(ExifService.formatExposureTime('1/2000s'), '1/2000s');
    expect(ExifService.formatExposureTime('1/60'), '1/60s');
    expect(ExifService.formatExposureTime('1/30'), '1/30s');
    expect(ExifService.formatExposureTime('1/2'), '1/2s');

    // 2. Unreduced ratios from camera drivers (Samsung / Sony / Xiaomi / Canon)
    expect(ExifService.formatExposureTime('10/20000'), '1/2000s');
    expect(ExifService.formatExposureTime('16666/1000000'), '1/60s');
    expect(ExifService.formatExposureTime('33333/1000000'), '1/30s');
    expect(ExifService.formatExposureTime('10/500'), '1/50s');
    expect(ExifService.formatExposureTime('10/300'), '1/30s');
    expect(ExifService.formatExposureTime('10/10'), '1s');
    expect(ExifService.formatExposureTime('20/10'), '2s');
    expect(ExifService.formatExposureTime('25/10'), '2.5s');

    // 3. Decimal seconds
    expect(ExifService.formatExposureTime('0.0005'), '1/2000s');
    expect(ExifService.formatExposureTime('0.000125'), '1/8000s');
    expect(ExifService.formatExposureTime('0.016666'), '1/60s');
    expect(ExifService.formatExposureTime('0.033333'), '1/30s');
    expect(ExifService.formatExposureTime('0.5'), '1/2s');
    expect(ExifService.formatExposureTime(0.005), '1/200s');
    expect(ExifService.formatExposureTime(1.0), '1s');
    expect(ExifService.formatExposureTime(2.0), '2s');
    expect(ExifService.formatExposureTime(2.5), '2.5s');
    expect(ExifService.formatExposureTime(30.0), '30s');

    // 4. APEX ShutterSpeedValue fallback
    expect(ExifService.formatExposureTime(null, 10.965784), '1/2000s');
    expect(ExifService.formatExposureTime(null, '5.906891'), '1/60s');
  });
}
