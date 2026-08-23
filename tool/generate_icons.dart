// ignore_for_file: avoid_print
import 'dart:io';
import 'package:image/image.dart' as img;

void main() {
  print('Generating high-resolution Android launcher icons...');
  
  final sourceFile = File('/Users/nonnika/.gemini/antigravity/brain/04216294-c6cd-432a-b507-ed4f988db894/watermark_app_icon_v2_1787247146091.jpg');
  
  img.Image baseIcon;
  if (sourceFile.existsSync()) {
    final bytes = sourceFile.readAsBytesSync();
    final decoded = img.decodeImage(bytes);
    if (decoded != null) {
      // The icon is centered in the 1024x1024 image from roughly x: 180 to 844 (width ~ 664)
      // Let's crop the icon squircle directly
      final cropX = (decoded.width * 0.176).round();
      final cropY = (decoded.height * 0.176).round();
      final cropW = (decoded.width * 0.648).round();
      final cropH = (decoded.height * 0.648).round();
      baseIcon = img.copyCrop(decoded, x: cropX, y: cropY, width: cropW, height: cropH);
    } else {
      baseIcon = _renderVectorIcon(512);
    }
  } else {
    baseIcon = _renderVectorIcon(512);
  }

  final sizes = {
    'mipmap-mdpi': 48,
    'mipmap-hdpi': 72,
    'mipmap-xhdpi': 96,
    'mipmap-xxhdpi': 144,
    'mipmap-xxxhdpi': 192,
  };

  final resDir = Directory('android/app/src/main/res');

  for (final entry in sizes.entries) {
    final folder = Directory('${resDir.path}/${entry.key}');
    if (!folder.existsSync()) {
      folder.createSync(recursive: true);
    }

    final targetSize = entry.value;
    final resized = img.copyResize(
      baseIcon,
      width: targetSize,
      height: targetSize,
      interpolation: img.Interpolation.cubic,
    );

    final pngBytes = img.encodePng(resized);
    File('${folder.path}/ic_launcher.png').writeAsBytesSync(pngBytes);
    print('Generated ${entry.key}/ic_launcher.png ($targetSize x $targetSize)');
  }

  // Also save a 512x512 master icon
  final master512 = img.copyResize(baseIcon, width: 512, height: 512, interpolation: img.Interpolation.cubic);
  final assetsDir = Directory('assets');
  if (!assetsDir.existsSync()) {
    assetsDir.createSync(recursive: true);
  }
  File('assets/app_icon.png').writeAsBytesSync(img.encodePng(master512));
  print('Saved assets/app_icon.png (512x512)');
  print('All launcher icons generated successfully!');
}

img.Image _renderVectorIcon(int size) {
  final image = img.Image(width: size, height: size);
  for (int y = 0; y < size; y++) {
    for (int x = 0; x < size; x++) {
      final t = (x + y) / (size * 2);
      final r = (0x38 * (1 - t) + 0x0D * t).round();
      final g = (0xB6 * (1 - t) + 0x47 * t).round();
      final b = (0xFF * (1 - t) + 0xA1 * t).round();
      image.setPixelRgba(x, y, r, g, b, 255);
    }
  }
  return image;
}
