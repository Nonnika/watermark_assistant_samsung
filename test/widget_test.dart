import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:watermark_samsung/main.dart';
import 'package:watermark_samsung/models/exif_info.dart';
import 'package:watermark_samsung/models/frame_watermark_config.dart';
import 'package:watermark_samsung/models/saved_preset.dart';
import 'package:watermark_samsung/models/watermark_config.dart';
import 'package:watermark_samsung/services/app_strings.dart';
import 'package:watermark_samsung/services/brand_logos.dart';
import 'package:watermark_samsung/services/device_photo_service.dart';
import 'package:watermark_samsung/services/exif_service.dart';
import 'package:watermark_samsung/services/motion_photo_service.dart';
import 'package:watermark_samsung/services/photo_color_extractor.dart';
import 'package:watermark_samsung/services/ultra_hdr_service.dart';
import 'package:watermark_samsung/services/watermark_processor.dart';
import 'package:watermark_samsung/utils/date_auto_formatter.dart';
import 'package:watermark_samsung/widgets/custom_photo_selector.dart';
import 'package:watermark_samsung/widgets/frame_controls.dart';
import 'package:watermark_samsung/widgets/hero_poster_banner.dart';
import 'package:watermark_samsung/widgets/pebble_icon.dart';
import 'package:watermark_samsung/widgets/selector/selector_bottom_action.dart';
import 'package:watermark_samsung/widgets/splash_screen.dart';

void main() {
  testWidgets('Watermark Assistant App launches with animated splash screen and transitions to Home', (WidgetTester tester) async {
    // Set system locale to zh for test
    tester.platformDispatcher.localeTestValue = const Locale('zh', 'CN');
    addTearDown(tester.platformDispatcher.clearLocaleTestValue);

    await tester.pumpWidget(const WatermarkAssistantApp(showSplashOnInit: true));
    await tester.pump(const Duration(milliseconds: 600));

    // In Splash Screen
    expect(find.text('水印助手'), findsOneWidget);
    expect(find.text('感受更强大的水印体验'), findsOneWidget);

    // Tap to finish splash and transition to Home
    await tester.tap(find.byType(SplashScreen));
    await tester.pump(const Duration(milliseconds: 500));

    // Now in HomeScreen
    expect(find.byType(HeroPosterBanner), findsOneWidget);
    expect(find.byType(CustomPhotoSelector), findsOneWidget);
  });

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

  test('BrandLogoService generates valid logos', () async {
    for (final brand in BrandLogoService.brands) {
      final bytes = await BrandLogoService.getLogoBytes(brand.id);
      expect(bytes.isNotEmpty, isTrue);

      final image = await WatermarkProcessor.decodeImageFromBytes(bytes);
      expect(image.width > 0, isTrue);
      expect(image.height > 0, isTrue);
    }
  });

  test('SavedPreset JSON serialization and deserialization', () {
    final preset = SavedPreset(
      id: 'test_1',
      name: '极简白标预设',
      createdAt: DateTime.now(),
      scale: 0.3,
      opacity: 0.8,
      rotation: 15.0,
      customX: 0.75,
      customY: 0.82,
      isInverted: true,
      mode: 'single',
    );

    final json = preset.toJson();
    final restored = SavedPreset.fromJson(json);

    expect(restored.id, 'test_1');
    expect(restored.name, '极简白标预设');
    expect(restored.scale, 0.3);
    expect(restored.opacity, 0.8);
    expect(restored.rotation, 15.0);
    expect(restored.customX, 0.75);
    expect(restored.customY, 0.82);
    expect(restored.isInverted, isTrue);
    expect(restored.mode, 'single');
  });

  test('WatermarkConfig supports isInverted toggle', () {
    const config = WatermarkConfig();
    expect(config.isInverted, isFalse);

    final inverted = config.copyWith(isInverted: true);
    expect(inverted.isInverted, isTrue);
  });

  test('PhotoColorExtractor accurately extracts photo palette', () {
    final img.Image image = img.Image(width: 100, height: 100);
    // Draw some distinct colors
    img.fillRect(image, x1: 0, y1: 0, x2: 50, y2: 50, color: img.ColorRgba8(255, 0, 0, 255));
    img.fillRect(image, x1: 50, y1: 0, x2: 100, y2: 50, color: img.ColorRgba8(0, 255, 0, 255));
    img.fillRect(image, x1: 0, y1: 50, x2: 50, y2: 100, color: img.ColorRgba8(0, 0, 255, 255));
    img.fillRect(image, x1: 50, y1: 50, x2: 100, y2: 100, color: img.ColorRgba8(255, 255, 0, 255));

    final palette = PhotoColorExtractor.extractPalette(image);
    expect(palette.isNotEmpty, isTrue);
    expect(palette.length >= 3, isTrue);
  });

  test('FrameWatermarkConfig supports isLogoInverted, logoScale, logoOffsetX, logoOffsetY, textOffsetX, textOffsetY, isPaperTextureBg, cornerRadius, and shadowOpacity', () {
    const frameConfig = FrameWatermarkConfig();
    expect(frameConfig.isLogoInverted, isFalse);
    expect(frameConfig.logoScale, 1.0);
    expect(frameConfig.logoOffsetX, 0.0);
    expect(frameConfig.logoOffsetY, 0.0);
    expect(frameConfig.textOffsetX, 0.0);
    expect(frameConfig.textOffsetY, 0.0);
    expect(frameConfig.isBlurredBg, isFalse);
    expect(frameConfig.isPaperTextureBg, isFalse);
    expect(frameConfig.cornerRadius, 0.0);
    expect(frameConfig.shadowOpacity, 0.0);

    final updated = frameConfig.copyWith(
      isLogoInverted: true,
      logoScale: 1.5,
      logoOffsetX: 0.15,
      logoOffsetY: 0.25,
      textOffsetX: -0.20,
      textOffsetY: -0.30,
      isBlurredBg: true,
      isPaperTextureBg: true,
      cornerRadius: 0.04,
      shadowOpacity: 0.6,
    );
    expect(updated.isLogoInverted, isTrue);
    expect(updated.logoScale, 1.5);
    expect(updated.logoOffsetX, 0.15);
    expect(updated.logoOffsetY, 0.25);
    expect(updated.textOffsetX, -0.20);
    expect(updated.textOffsetY, -0.30);
    expect(updated.isBlurredBg, isTrue);
    expect(updated.isPaperTextureBg, isTrue);
    expect(updated.cornerRadius, 0.04);
    expect(updated.shadowOpacity, 0.6);
    expect(updated.effectiveCornerRadius, 0.04);
    expect(updated.effectiveShadowOpacity, 0.6);
  });

  test('FrameWatermarkConfig properly switches between custom and built-in logos and resets invert', () {
    final customConfig = const FrameWatermarkConfig().copyWith(
      selectedLogoId: 'custom_123',
      customLogoBytes: Uint8List.fromList([1, 2, 3]),
      isLogoInverted: true,
    );
    expect(customConfig.selectedLogoId, 'custom_123');
    expect(customConfig.customLogoBytes, isNotNull);
    expect(customConfig.isLogoInverted, isTrue);

    // Switch back to built-in brand
    final backToBuiltin = customConfig.copyWith(
      selectedLogoId: 'samsung_blue',
      clearCustomLogo: true,
    );
    expect(backToBuiltin.selectedLogoId, 'samsung_blue');
    expect(backToBuiltin.customLogoBytes, isNull);
    expect(backToBuiltin.isLogoInverted, isFalse);
  });

  test('AppStrings supports dynamic Chinese and English switching', () {
    AppStrings.currentLanguage.value = AppLanguage.zh;
    expect(AppStrings.appName, '水印助手');
    expect(AppStrings.headerSubtitle, '感受更强大的水印体验');

    AppStrings.toggleLanguage();
    expect(AppStrings.appName, 'Watermark Assistant');
    expect(AppStrings.headerSubtitle, 'Experience a More Powerful Watermark Tool');

    // Reset back to default zh
    AppStrings.currentLanguage.value = AppLanguage.zh;
  });

  test('SamsungSquircleClipper creates valid superellipse pebble path', () {
    const size = Size(100, 100);
    final path = SamsungSquircleClipper.createSamsungSquirclePath(size, n: 2.85);
    expect(path, isNotNull);
    final bounds = path.getBounds();
    expect(bounds.width, closeTo(100, 1.0));
    expect(bounds.height, closeTo(100, 1.0));
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

  test('DateTimeAutoSegmentFormatter correctly auto-segments continuous digits and normalizes date-time', () {
    final formatter = DateTimeAutoSegmentFormatter();

    // 1. Test auto-formatting progressive numeric input
    final res1 = formatter.formatEditUpdate(
      const TextEditingValue(text: ''),
      const TextEditingValue(text: '20240821'),
    );
    expect(res1.text, '2024.08.21');

    final res2 = formatter.formatEditUpdate(
      const TextEditingValue(text: '2024.08.21'),
      const TextEditingValue(text: '202408211430'),
    );
    expect(res2.text, '2024.08.21 14:30');

    // 2. Test normalization of various date-time formats
    expect(DateTimeAutoSegmentFormatter.normalizeDateTime('202408211430'), '2024.08.21 14:30');
    expect(DateTimeAutoSegmentFormatter.normalizeDateTime('20240821143045'), '2024.08.21 14:30:45');
    expect(DateTimeAutoSegmentFormatter.normalizeDateTime('20240821'), '2024.08.21');
    expect(DateTimeAutoSegmentFormatter.nowFormatted().length, 16); // e.g. 2026.08.21 11:30
  });

  testWidgets('FrameControls color strip renders blurred ball and switches background correctly', (WidgetTester tester) async {
    FrameWatermarkConfig currentConfig = const FrameWatermarkConfig();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              return FrameControls(
                activeToolIndex: 1, // Color tool
                config: currentConfig,
                photoColors: const [Color(0xFF123456), Color(0xFF654321)],
                photoBytes: img.encodePng(img.Image(width: 8, height: 8)),
                isAdjusting: false,
                adjustingParamName: '',
                adjustingParamValue: '',
                adjustingProgress: 0.0,
                onChanged: (newCfg) {
                  setState(() {
                    currentConfig = newCfg;
                  });
                },
              );
            },
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Verify slim frame color strip is present
    expect(find.byKey(const ValueKey('slim_frame_color')), findsOneWidget);
    expect(currentConfig.isBlurredBg, isFalse);

    // Tap on the blurred background ball (second child in row)
    final blurBallFinder = find.byIcon(Icons.blur_on_rounded);
    expect(blurBallFinder, findsOneWidget);
    await tester.tap(blurBallFinder);
    await tester.pumpAndSettle();

    expect(currentConfig.isBlurredBg, isTrue);
    expect(currentConfig.isPaperTextureBg, isFalse);

    // Tap on the paper texture ball (third child in row)
    final paperBallFinder = find.byIcon(Icons.texture_rounded);
    expect(paperBallFinder, findsOneWidget);
    await tester.tap(paperBallFinder);
    await tester.pumpAndSettle();

    expect(currentConfig.isPaperTextureBg, isTrue);
    expect(currentConfig.isBlurredBg, isFalse);
  });

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

  test('MotionPhotoService detects, extracts MP4, and composites Motion Photos with XMP and SEF metadata', () async {
    // 1. Create a base JPEG
    final testImg = img.Image(width: 100, height: 100);
    img.fill(testImg, color: img.ColorRgb8(200, 100, 50));
    final baseJpg = Uint8List.fromList(img.encodeJpg(testImg));

    // 2. Create mock MP4 stream (ftyp box + mdat)
    final mockMp4 = Uint8List.fromList([
      0x00, 0x00, 0x00, 0x18, // box size = 24
      0x66, 0x74, 0x79, 0x70, // 'ftyp'
      0x6D, 0x70, 0x34, 0x32, // 'mp42'
      0x00, 0x00, 0x00, 0x00,
      0x69, 0x73, 0x6F, 0x6D, // 'isom'
      0x6D, 0x70, 0x34, 0x32, // 'mp42'
      // dummy video payload
      0x00, 0x00, 0x00, 0x20, // mdat size = 32
      0x6D, 0x64, 0x61, 0x74, // 'mdat'
      ...List.filled(24, 0xAA),
    ]);

    // 3. Composite into Motion Photo
    final motionPhotoBytes = MotionPhotoService.compositeAndPreserveMotionPhoto(
      watermarkedJpgBytes: baseJpg,
      motionVideoBytes: mockMp4,
      presentationTimestampUs: 1500000,
    );

    // 4. Verify detection
    expect(MotionPhotoService.isMotionPhoto(motionPhotoBytes), isTrue);

    // 5. Verify extraction
    final extractedVideo = MotionPhotoService.extractMotionVideo(motionPhotoBytes);
    expect(extractedVideo, isNotNull);
    expect(extractedVideo!.length, mockMp4.length);
    expect(extractedVideo.presentationTimestampUs, 1500000);

    // Verify MP4 header in extracted stream
    expect(extractedVideo.videoBytes[4], 0x66); // 'f'
    expect(extractedVideo.videoBytes[5], 0x74); // 't'
    expect(extractedVideo.videoBytes[6], 0x79); // 'y'
    expect(extractedVideo.videoBytes[7], 0x70); // 'p'

    // 6. Verify primary image extraction
    final primaryJpg = MotionPhotoService.extractPrimaryJpg(motionPhotoBytes);
    expect(primaryJpg.length < motionPhotoBytes.length, isTrue);

    // 7. Verify createImageItem detects Motion Photo
    final item = await WatermarkProcessor.createImageItem(
      id: 'test_motion_1',
      name: 'motion_test.jpg',
      path: '/path/motion_test.jpg',
      bytes: motionPhotoBytes,
    );
    expect(item.isMotionPhoto, isTrue);
    expect(item.motionVideoBytes, isNotNull);
  });

  test('MotionPhotoService accurately distinguishes static HEIC/JPG from true Motion Photos (both JPG & HEIC)', () async {
    final mockMp4 = Uint8List.fromList([
      0x00, 0x00, 0x00, 0x18,
      0x66, 0x74, 0x79, 0x70, // 'ftyp'
      0x6D, 0x70, 0x34, 0x32, // 'mp42'
      0x00, 0x00, 0x00, 0x00,
      0x69, 0x73, 0x6F, 0x6D,
      0x6D, 0x70, 0x34, 0x32,
      0x00, 0x00, 0x00, 0x10,
      0x6D, 0x64, 0x61, 0x74,
      ...List.filled(8, 0x55),
    ]);

    // 1. Static HEIC (has ftypheic at offset 0, but no video stream) -> MUST NOT be detected as motion photo
    final staticHeic = Uint8List.fromList([
      0x00, 0x00, 0x00, 0x18,
      0x66, 0x74, 0x79, 0x70, // 'ftyp'
      0x68, 0x65, 0x69, 0x63, // 'heic'
      0x00, 0x00, 0x00, 0x00,
      0x6D, 0x69, 0x66, 0x31,
      0x68, 0x65, 0x69, 0x63,
      ...List.filled(3000, 0x00),
    ]);
    expect(MotionPhotoService.isMotionPhoto(staticHeic), isFalse, reason: 'Static HEIC must not be classified as motion photo');

    // 2. Static JPEG (standard JPEG bytes) -> MUST NOT be detected as motion photo
    final testImg = img.Image(width: 50, height: 50);
    img.fill(testImg, color: img.ColorRgb8(10, 20, 30));
    final staticJpg = Uint8List.fromList(img.encodeJpg(testImg));
    expect(MotionPhotoService.isMotionPhoto(staticJpg), isFalse, reason: 'Static JPG must not be classified as motion photo');

    // 3. Google Pixel / Xiaomi / OPPO / vivo XMP JPG Motion Photo (MicroVideoOffset + appended MP4)
    final gcamXmp = '<x:xmpmeta xmlns:x="adobe:ns:meta/">\n'
        '<rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">\n'
        '  <rdf:Description xmlns:GCamera="http://ns.google.com/photos/1.0/camera/" '
        'GCamera:MotionPhoto="1" GCamera:MicroVideo="1" GCamera:MicroVideoOffset="${mockMp4.length}" />\n'
        '</rdf:RDF>\n</x:xmpmeta>';
    final gcamJpgBuilder = BytesBuilder();
    gcamJpgBuilder.add(staticJpg);
    // Inject XMP string
    gcamJpgBuilder.add(utf8.encode(gcamXmp));
    gcamJpgBuilder.add(mockMp4);
    final gcamMotionJpg = gcamJpgBuilder.toBytes();

    expect(MotionPhotoService.isMotionPhoto(gcamMotionJpg), isTrue, reason: 'Google Pixel / Standard XMP JPG Motion Photo must be recognized');
    final extractedGcamVideo = MotionPhotoService.extractMotionVideo(gcamMotionJpg);
    expect(extractedGcamVideo, isNotNull);
    expect(extractedGcamVideo!.length, mockMp4.length);

    // 4. Samsung SEF HEIC Motion Photo (HEIC + SEF trailer with MP4)
    final samsungHeicMotion = MotionPhotoService.compositeAndPreserveMotionPhoto(
      watermarkedJpgBytes: staticHeic,
      motionVideoBytes: mockMp4,
    );
    expect(MotionPhotoService.isMotionPhoto(samsungHeicMotion), isTrue, reason: 'Samsung HEIC Motion Photo must be recognized');
  });

  test('DevicePhotoService detects Ultra HDR and Motion Photo correctly', () async {
    const hdrPhoto = DevicePhotoModel(
      id: 'hdr_photo_1',
      name: 'sunset_gainmap.jpg',
      path: '/mock/sunset_gainmap.jpg',
    );
    expect(DevicePhotoService.getCachedUltraHdr(hdrPhoto), isTrue);

    const motionPhoto = DevicePhotoModel(
      id: 'motion_photo_1',
      name: 'IMG_2026_motion.jpg',
      path: '/mock/IMG_2026_motion.jpg',
    );
    expect(DevicePhotoService.getCachedMotionPhoto(motionPhoto), isTrue);
  });

  test('WatermarkProcessor generates video overlay PNG and MotionPhotoService watermarks video', () async {
    final overlayBytes = await WatermarkProcessor.generateWatermarkOverlayBytes(
      type: WatermarkType.frame,
      watermarkImage: null,
      pngConfig: const WatermarkConfig(),
      logoImage: null,
      frameConfig: const FrameWatermarkConfig(),
      width: 400,
      height: 600,
    );
    expect(overlayBytes, isNotEmpty);
    expect(overlayBytes.length > 50, isTrue);

    // Mock video bytes
    final mockVideoBytes = Uint8List.fromList([0x00, 0x00, 0x00, 0x20, 0x66, 0x74, 0x79, 0x70, 0x69, 0x73, 0x6F, 0x6D]);
    final resultVideo = await MotionPhotoService.watermarkMotionVideo(
      videoBytes: mockVideoBytes,
      overlayPngBytes: overlayBytes,
    );
    expect(resultVideo, isNotEmpty);
  });

  testWidgets('SelectorBottomAction renders action buttons when visible and triggers callbacks', (WidgetTester tester) async {
    WatermarkType? selectedType;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SelectorBottomAction(
            isVisible: true,
            onSelectType: (type) {
              selectedType = type;
            },
          ),
        ),
      ),
    );

    expect(find.text('边框水印'), findsOneWidget);
    expect(find.text('叠加水印'), findsOneWidget);

    await tester.tap(find.text('边框水印'));
    await tester.pump();
    expect(selectedType, WatermarkType.frame);

    await tester.tap(find.text('叠加水印'));
    await tester.pump();
    expect(selectedType, WatermarkType.floatingPng);
  });

  testWidgets('CustomPhotoSelector renders with GPU matrix translation and displays empty state with refresh/permission button', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    DevicePhotoService.debugOverrideIsAndroid = true;
    addTearDown(() => DevicePhotoService.debugOverrideIsAndroid = null);

    // 1. Mock channel returning permission = true
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('com.example.watermark_samsung/ultra_hdr'),
      (MethodCall methodCall) async {
        if (methodCall.method == 'checkStoragePermission') return true;
        if (methodCall.method == 'requestStoragePermission') return true;
        if (methodCall.method == 'getRecentPhotos') return [];
        return null;
      },
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CustomPhotoSelector(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('照片'), findsOneWidget);
    expect(find.text('动态照片'), findsOneWidget);
    expect(find.text('暂未发现相册照片'), findsOneWidget);
    expect(find.text('刷新'), findsOneWidget);

    // 2. Mock channel returning permission = false
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('com.example.watermark_samsung/ultra_hdr'),
      (MethodCall methodCall) async {
        if (methodCall.method == 'checkStoragePermission') return false;
        if (methodCall.method == 'requestStoragePermission') return true;
        if (methodCall.method == 'getRecentPhotos') return [];
        return null;
      },
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CustomPhotoSelector(key: ValueKey('no_perm')),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('未获得相册访问权限'), findsOneWidget);
    expect(find.text('申请权限'), findsOneWidget);

    // Tap 申请权限
    await tester.tap(find.text('申请权限'), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 300));

    // Reset handler
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('com.example.watermark_samsung/ultra_hdr'),
      null,
    );
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

  testWidgets('Top-right About button renders on Home and opens Samsung OneUI AboutPage', (WidgetTester tester) async {
    tester.platformDispatcher.localeTestValue = const Locale('zh', 'CN');
    addTearDown(tester.platformDispatcher.clearLocaleTestValue);

    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const WatermarkAssistantApp(showSplashOnInit: false),
    );
    await tester.pump(const Duration(milliseconds: 400));

    // Verify top-right About button is visible
    final aboutBtn = find.text('关于');
    expect(aboutBtn, findsOneWidget);

    // Tap About button
    await tester.tap(aboutBtn);
    for (int i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    // Verify Samsung One UI AboutPage content
    expect(find.text('水印助手'), findsWidgets);
    expect(find.text('版本 1.0.00.01'), findsOneWidget);
    expect(find.text('已安装最新版本。'), findsOneWidget);
    expect(find.text('条款与条件'), findsOneWidget);
    expect(find.text('开源许可证'), findsOneWidget);

    // Test Terms and Conditions OneUI bottom-floating dialog
    await tester.tap(find.text('条款与条件'));
    for (int i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(find.text('本应用所有水印合成与图像/视频渲染均在您的设备本地完成，不会将您的任何照片、EXIF 隐私或地理位置上传至任何远程服务器。请安心使用。'), findsOneWidget);
    expect(find.text('确定'), findsOneWidget);

    // Dismiss dialog via '确定'
    await tester.tap(find.text('确定'));
    for (int i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('确定'), findsNothing);

    // Test App Details info dialog
    final infoBtn = find.byTooltip('应用详情');
    expect(infoBtn, findsOneWidget);
    await tester.tap(infoBtn);
    for (int i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('本次更新'), findsOneWidget);
    expect(find.textContaining('1. 适配高通 Adreno GPU'), findsOneWidget);
    await tester.tap(find.text('确定'));
    for (int i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('本次更新'), findsNothing);

    // Pop AboutPage with back button
    final backBtn = find.byTooltip('返回');
    expect(backBtn, findsOneWidget);
    await tester.tap(backBtn);
    for (int i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(find.text('已安装最新版本。'), findsNothing);
  });
}
