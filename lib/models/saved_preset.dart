import 'dart:convert';
import 'dart:typed_data';

class SavedPreset {
  final String id;
  final String name;
  final DateTime createdAt;
  final String? watermarkBase64; // 自定义 PNG 水印的 base64
  final String? presetId;        // 如果是内置预设的 ID
  final double scale;
  final double opacity;
  final double rotation;
  final double customX;
  final double customY;
  final bool isInverted;
  final String mode;            // 'single' or 'tiled'
  final double tileSpacingX;
  final double tileSpacingY;
  final bool tileStaggered;

  const SavedPreset({
    required this.id,
    required this.name,
    required this.createdAt,
    this.watermarkBase64,
    this.presetId,
    required this.scale,
    required this.opacity,
    required this.rotation,
    required this.customX,
    required this.customY,
    required this.isInverted,
    this.mode = 'single',
    this.tileSpacingX = 0.35,
    this.tileSpacingY = 0.35,
    this.tileStaggered = true,
  });

  Uint8List? get watermarkBytes =>
      watermarkBase64 != null ? base64Decode(watermarkBase64!) : null;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'createdAt': createdAt.toIso8601String(),
      'watermarkBase64': watermarkBase64,
      'presetId': presetId,
      'scale': scale,
      'opacity': opacity,
      'rotation': rotation,
      'customX': customX,
      'customY': customY,
      'isInverted': isInverted,
      'mode': mode,
      'tileSpacingX': tileSpacingX,
      'tileSpacingY': tileSpacingY,
      'tileStaggered': tileStaggered,
    };
  }

  factory SavedPreset.fromJson(Map<String, dynamic> json) {
    return SavedPreset(
      id: json['id'] as String,
      name: json['name'] as String,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
      watermarkBase64: json['watermarkBase64'] as String?,
      presetId: json['presetId'] as String?,
      scale: (json['scale'] as num?)?.toDouble() ?? 0.25,
      opacity: (json['opacity'] as num?)?.toDouble() ?? 0.90,
      rotation: (json['rotation'] as num?)?.toDouble() ?? 0.0,
      customX: (json['customX'] as num?)?.toDouble() ?? 0.8,
      customY: (json['customY'] as num?)?.toDouble() ?? 0.8,
      isInverted: json['isInverted'] as bool? ?? false,
      mode: json['mode'] as String? ?? 'single',
      tileSpacingX: (json['tileSpacingX'] as num?)?.toDouble() ?? 0.35,
      tileSpacingY: (json['tileSpacingY'] as num?)?.toDouble() ?? 0.35,
      tileStaggered: json['tileStaggered'] as bool? ?? true,
    );
  }
}
