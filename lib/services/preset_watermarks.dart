import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class PresetWatermark {
  final String id;
  final String title;
  final String description;
  final Future<Uint8List> Function() generateBytes;

  const PresetWatermark({
    required this.id,
    required this.title,
    required this.description,
    required this.generateBytes,
  });
}

class PresetWatermarkService {
  static final List<PresetWatermark> presets = [
    PresetWatermark(
      id: 'samsung_galaxy',
      title: 'Samsung Galaxy',
      description: 'Samsung Galaxy 官方水印',
      generateBytes: () => _loadSamsungGalaxyAsset(),
    ),
    PresetWatermark(
      id: 'galaxy_s24',
      title: 'Galaxy 影像水印',
      description: 'Galaxy S24 Ultra · AI 摄影',
      generateBytes: () => _generateGalaxyS24Badge(),
    ),
    PresetWatermark(
      id: 'camera_aperture',
      title: '极简镜头印记',
      description: 'SHOT ON GALAXY · 50mm f/1.4',
      generateBytes: () => _generateApertureBadge(),
    ),
    PresetWatermark(
      id: 'confidential_seal',
      title: '绝密防盗印章',
      description: 'CONFIDENTIAL · 严禁翻印',
      generateBytes: () => _generateConfidentialSeal(),
    ),
    PresetWatermark(
      id: 'copyright_minimal',
      title: '极简版权徽标',
      description: '© 2026 ALL RIGHTS RESERVED',
      generateBytes: () => _generateCopyrightBadge(),
    ),
    PresetWatermark(
      id: 'sample_stamp',
      title: '样本防伪印',
      description: 'SAMPLE · 仅供审阅',
      generateBytes: () => _generateSampleStamp(),
    ),
  ];

  /// 从资源目录加载 Samsung Galaxy 官方水印 (res/SamsungGalaxy.png)
  static Future<Uint8List> _loadSamsungGalaxyAsset() async {
    for (final path in [
      'res/SamsungGalaxy.png',
      'res/Samsung_Galaxy.png',
      'res/Samsung Galaxy.png',
      'res/Samsung_galaxy.png',
      'res/Samsung_galaxy.jpg',
    ]) {
      try {
        final byteData = await rootBundle.load(path);
        return byteData.buffer.asUint8List();
      } catch (_) {}
    }
    return _generateGalaxyS24Badge();
  }

  /// 生成 Galaxy S24 Ultra 风格水印 PNG (带透明背景)
  static Future<Uint8List> _generateGalaxyS24Badge() async {
    const double width = 640;
    const double height = 140;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, width, height));

    // 背景半透明微黑药丸底衬 (可选，让浅色和深色图都清晰可见)
    final bgPaint = Paint()
      ..color = const Color(0x77000000)
      ..style = PaintingStyle.fill;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(10, 10, width - 20, height - 20),
        const Radius.circular(32),
      ),
      bgPaint,
    );

    // 边框描边
    final borderPaint = Paint()
      ..color = const Color(0x33FFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(10, 10, width - 20, height - 20),
        const Radius.circular(32),
      ),
      borderPaint,
    );

    // 左侧 Samsung Galaxy 星钻/相机图标
    final iconPaint = Paint()
      ..color = const Color(0xFF0381FE)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(const Offset(65, 70), 28, iconPaint);

    final innerLensPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0;
    canvas.drawCircle(const Offset(65, 70), 16, innerLensPaint);
    canvas.drawCircle(const Offset(65, 70), 7, Paint()..color = Colors.white);

    // 文字: 主标题
    final titleParagraph = _buildTextParagraph(
      'Galaxy S24 Ultra',
      fontSize: 32,
      fontWeight: FontWeight.w800,
      color: Colors.white,
    );
    canvas.drawParagraph(titleParagraph, const Offset(115, 36));

    // 文字: 副标题
    final subParagraph = _buildTextParagraph(
      '200MP PRO CAMERA | AI PHOTOGRAPHY',
      fontSize: 18,
      fontWeight: FontWeight.w600,
      color: const Color(0xCCFFFFFF),
      letterSpacing: 2.0,
    );
    canvas.drawParagraph(subParagraph, const Offset(115, 78));

    final picture = recorder.endRecording();
    final image = await picture.toImage(width.toInt(), height.toInt());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  /// 极简镜头光圈水印
  static Future<Uint8List> _generateApertureBadge() async {
    const double width = 500;
    const double height = 120;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, width, height));

    // 绘制光圈图标
    final ringPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5;
    canvas.drawCircle(const Offset(60, 60), 30, ringPaint);

    final dotPaint = Paint()
      ..color = const Color(0xFF0381FE)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(const Offset(60, 60), 10, dotPaint);

    // 分隔线
    final linePaint = Paint()
      ..color = const Color(0x66FFFFFF)
      ..strokeWidth = 2;
    canvas.drawLine(const Offset(110, 30), const Offset(110, 90), linePaint);

    // 文字
    final t1 = _buildTextParagraph(
      'SHOT ON GALAXY',
      fontSize: 26,
      fontWeight: FontWeight.bold,
      color: Colors.white,
      letterSpacing: 3.0,
    );
    canvas.drawParagraph(t1, const Offset(130, 32));

    final t2 = _buildTextParagraph(
      '50mm f/1.4  ISO 100  1/1000s',
      fontSize: 18,
      fontWeight: FontWeight.w400,
      color: const Color(0xBBFFFFFF),
      letterSpacing: 1.5,
    );
    canvas.drawParagraph(t2, const Offset(130, 68));

    final picture = recorder.endRecording();
    final image = await picture.toImage(width.toInt(), height.toInt());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  /// 绝密防盗印章
  static Future<Uint8List> _generateConfidentialSeal() async {
    const double width = 460;
    const double height = 160;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, width, height));

    final redPaint = Paint()
      ..color = const Color(0xFFE53935)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5.0;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(15, 15, width - 30, height - 30),
        const Radius.circular(20),
      ),
      redPaint,
    );

    final t1 = _buildTextParagraph(
      'CONFIDENTIAL',
      fontSize: 40,
      fontWeight: FontWeight.w900,
      color: const Color(0xFFE53935),
      letterSpacing: 6.0,
    );
    canvas.drawParagraph(t1, const Offset(45, 35));

    final t2 = _buildTextParagraph(
      '—— 内部资料 · 严禁翻印传播 ——',
      fontSize: 20,
      fontWeight: FontWeight.bold,
      color: const Color(0xFFE53935),
      letterSpacing: 2.0,
    );
    canvas.drawParagraph(t2, const Offset(65, 95));

    final picture = recorder.endRecording();
    final image = await picture.toImage(width.toInt(), height.toInt());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  /// 极简版权徽标
  static Future<Uint8List> _generateCopyrightBadge() async {
    const double width = 520;
    const double height = 100;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, width, height));

    // © 徽章圆圈
    final cCircle = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;
    canvas.drawCircle(const Offset(50, 50), 25, cCircle);

    final cText = _buildTextParagraph(
      'C',
      fontSize: 28,
      fontWeight: FontWeight.bold,
      color: Colors.white,
    );
    canvas.drawParagraph(cText, const Offset(39, 32));

    final t1 = _buildTextParagraph(
      'COPYRIGHT © 2026',
      fontSize: 26,
      fontWeight: FontWeight.bold,
      color: Colors.white,
      letterSpacing: 2.0,
    );
    canvas.drawParagraph(t1, const Offset(95, 24));

    final t2 = _buildTextParagraph(
      'ALL RIGHTS RESERVED',
      fontSize: 16,
      fontWeight: FontWeight.w500,
      color: const Color(0xAAFFFFFF),
      letterSpacing: 4.0,
    );
    canvas.drawParagraph(t2, const Offset(96, 56));

    final picture = recorder.endRecording();
    final image = await picture.toImage(width.toInt(), height.toInt());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  /// SAMPLE 样本防伪印
  static Future<Uint8List> _generateSampleStamp() async {
    const double width = 420;
    const double height = 140;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, width, height));

    final border = Paint()
      ..color = const Color(0xFF0381FE)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(10, 10, width - 20, height - 20),
        const Radius.circular(16),
      ),
      border,
    );

    final t1 = _buildTextParagraph(
      'SAMPLE',
      fontSize: 48,
      fontWeight: FontWeight.w900,
      color: const Color(0xFF0381FE),
      letterSpacing: 10.0,
    );
    canvas.drawParagraph(t1, const Offset(65, 25));

    final t2 = _buildTextParagraph(
      '仅 供 样 本 预 览 审 阅',
      fontSize: 20,
      fontWeight: FontWeight.bold,
      color: const Color(0xFF0381FE),
      letterSpacing: 3.0,
    );
    canvas.drawParagraph(t2, const Offset(95, 88));

    final picture = recorder.endRecording();
    final image = await picture.toImage(width.toInt(), height.toInt());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  static ui.Paragraph _buildTextParagraph(
    String text, {
    required double fontSize,
    required FontWeight fontWeight,
    required Color color,
    double letterSpacing = 0.0,
  }) {
    final builder = ui.ParagraphBuilder(
      ui.ParagraphStyle(
        textAlign: TextAlign.left,
        fontSize: fontSize,
        fontWeight: fontWeight,
      ),
    )
      ..pushStyle(
        ui.TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: fontWeight,
          letterSpacing: letterSpacing,
        ),
      )
      ..addText(text);

    final paragraph = builder.build();
    paragraph.layout(const ui.ParagraphConstraints(width: double.infinity));
    return paragraph;
  }
}
