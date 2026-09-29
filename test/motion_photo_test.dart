import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:watermark_samsung/models/frame_watermark_config.dart';
import 'package:watermark_samsung/models/watermark_config.dart';
import 'package:watermark_samsung/services/motion_photo_service.dart';
import 'package:watermark_samsung/services/watermark_processor.dart';

void main() {
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
}
