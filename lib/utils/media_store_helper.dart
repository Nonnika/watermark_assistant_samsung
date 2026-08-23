import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class MediaStoreHelper {
  static const MethodChannel _nativeChannel = MethodChannel('com.example.watermark_samsung/ultra_hdr');

  /// 获取保存水印图片的输出目录 (作为非 Android 或备用回退)
  static Future<Directory> getOutputDirectory() async {
    Directory? dir;

    if (Platform.isAndroid) {
      final externalDir = await getExternalStorageDirectory();
      if (externalDir != null) {
        final picturesPath = p.join('/storage/emulated/0', 'Pictures', 'OneWatermark');
        final customPicturesDir = Directory(picturesPath);
        try {
          if (await customPicturesDir.exists() || (await customPicturesDir.create(recursive: true)).existsSync()) {
            return customPicturesDir;
          }
        } catch (_) {}
        
        final fallbackPath = p.join(externalDir.path, 'Watermarked');
        dir = Directory(fallbackPath);
      }
    }

    dir ??= await getApplicationDocumentsDirectory();
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// 保存合成后的图片到系统公共相册 (Android MediaStore / Pictures/OneWatermark)
  static Future<String> saveImageFile({
    required Uint8List bytes,
    required String originalName,
    required String format,
    String? customPrefix,
  }) async {
    final ext = format.toLowerCase().replaceAll('.', '');
    final nameWithoutExt = p.basenameWithoutExtension(originalName);
    final prefix = customPrefix ?? 'WM_';
    final timestamp = DateTime.now().millisecondsSinceEpoch.toString().substring(8);
    final fileName = '$prefix${nameWithoutExt}_$timestamp.$ext';
    final mimeType = ext == 'png' ? 'image/png' : 'image/jpeg';

    if (Platform.isAndroid) {
      try {
        debugPrint('[MediaStoreHelper] Saving via Android MediaStore: $fileName, bytes=${bytes.length}');
        final uri = await _nativeChannel.invokeMethod<String>('saveImageToGallery', {
          'bytes': bytes,
          'filename': fileName,
          'mimeType': mimeType,
          'relativePath': 'Pictures/OneWatermark',
        });
        if (uri != null && uri.isNotEmpty) {
          debugPrint('[MediaStoreHelper] Successfully saved to MediaStore: $uri');
          return uri;
        }
      } catch (e) {
        debugPrint('[MediaStoreHelper] MediaStore save failed: $e, falling back to file write');
      }
    }

    // 回退写入方式
    final outputDir = await getOutputDirectory();
    final filePath = p.join(outputDir.path, fileName);
    final file = File(filePath);
    await file.writeAsBytes(bytes);
    debugPrint('[MediaStoreHelper] Saved to file fallback: $filePath');
    return filePath;
  }
}
