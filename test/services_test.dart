import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:watermark_samsung/services/app_strings.dart';
import 'package:watermark_samsung/services/brand_logos.dart';
import 'package:watermark_samsung/services/device_photo_service.dart';
import 'package:watermark_samsung/services/photo_color_extractor.dart';
import 'package:watermark_samsung/services/watermark_processor.dart';
import 'package:watermark_samsung/utils/date_auto_formatter.dart';
import 'package:watermark_samsung/widgets/pebble_icon.dart';

void main() {
  test('BrandLogoService generates valid logos', () async {
    for (final brand in BrandLogoService.brands) {
      final bytes = await BrandLogoService.getLogoBytes(brand.id);
      expect(bytes.isNotEmpty, isTrue);

      final image = await WatermarkProcessor.decodeImageFromBytes(bytes);
      expect(image.width > 0, isTrue);
      expect(image.height > 0, isTrue);
    }
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
}
