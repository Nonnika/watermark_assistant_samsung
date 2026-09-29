import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:watermark_samsung/models/frame_watermark_config.dart';
import 'package:watermark_samsung/models/saved_preset.dart';
import 'package:watermark_samsung/models/watermark_config.dart';

void main() {
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
}
