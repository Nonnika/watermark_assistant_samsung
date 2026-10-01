import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:watermark_samsung/services/ultra_hdr_service.dart';
import 'package:watermark_samsung/services/ultra_hdr/ultra_hdr_detector.dart';
import 'package:watermark_samsung/services/device_photo_service.dart';
import 'package:watermark_samsung/services/motion_photo_service.dart';
import 'package:watermark_samsung/services/watermark_processor.dart';
import 'package:watermark_samsung/models/frame_watermark_config.dart';
import 'package:watermark_samsung/models/watermark_config.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.example.watermark_samsung/ultra_hdr');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() {
    UltraHdrDetector.debugOverrideIsAndroid = null;
    DevicePhotoService.debugOverrideIsAndroid = null;
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('UltraHdrService parses metadata without treating XMP alone as HDR', () {
    const mockXmpHeader =
        'http://ns.adobe.com/hdr-gain-map/1.0/ hdrgm:GainMapMin="0.0" hdrgm:GainMapMax="2.5" hdrgm:Gamma="1.0"';
    final mockBytes = _segment(
      _jpeg(),
      0xe1,
      utf8.encode('http://ns.adobe.com/xap/1.0/\x00$mockXmpHeader'),
    );
    expect(UltraHdrService.isUltraHdr(mockBytes), isFalse);

    final meta = UltraHdrService.parseMetadata(mockBytes);
    expect(meta.gainMapMin, 0.0);
    expect(meta.gainMapMax, 2.5);
    expect(meta.gamma, 1.0);

    final xmp = UltraHdrService.generateUltraHdrXmp(meta, gainmapLength: 1024);
    expect(xmp.contains('hdrgm:GainMapMax="2.500000"'), isTrue);
    expect(xmp.contains('Item:Semantic="GainMap"'), isTrue);
  });

  test(
    'UltraHdrService synthesizes and injects Gainmap into composite JPEG',
    () async {
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
    },
  );
  test('SDR motion photos and generic multi-picture JPEGs are not HDR', () {
    final jpeg = _jpeg();
    final motion = MotionPhotoService.compositeAndPreserveMotionPhoto(
      watermarkedJpgBytes: jpeg,
      motionVideoBytes: _video(),
    );
    expect(MotionPhotoService.isMotionPhoto(motion), isTrue);
    for (final bytes in [
      jpeg,
      motion,
      _pair(jpeg, jpeg),
      _sef(jpeg, jpeg, 'MotionPhoto_Data'),
    ]) {
      expect(UltraHdrService.isUltraHdr(bytes), isFalse);
      expect(UltraHdrService.extractGainmapJpeg(bytes), isNull);
    }
  });

  test('Adobe, Apple and ISO gain maps are detected and extracted without trailing video', () {
    final gainmap = _jpeg();
    final variants = [
      _segment(
        gainmap,
        0xe1,
        utf8.encode(
          UltraHdrService.generateSecondaryGainmapXmp(const UltraHdrMetadata()),
        ),
      ),
      _segment(
        gainmap,
        0xe1,
        utf8.encode(
          'http://ns.adobe.com/xap/1.0/\x00<rdf:Description xmlns:apgain="http://ns.apple.com/HDRGainMap/1.0/"/>',
        ),
      ),
      _segment(gainmap, 0xe2, [
        ...ascii.encode('urn:iso:std:iso:ts:21496:-1\x00'),
        0,
        0,
        0,
        1,
      ]),
    ];
    for (final secondary in variants) {
      final hdr = _pair(_jpeg(), secondary);
      expect(UltraHdrService.isUltraHdr(hdr), isTrue);
      expect(UltraHdrService.extractGainmapJpeg(hdr), secondary);
      final motion = MotionPhotoService.compositeAndPreserveMotionPhoto(
        watermarkedJpgBytes: hdr,
        motionVideoBytes: _video(),
      );
      expect(UltraHdrService.isUltraHdr(motion), isTrue);
      expect(UltraHdrService.extractGainmapJpeg(motion), secondary);
    }
  });

  test('Samsung SEF requires an actual named gainmap JPEG', () {
    final primary = _jpeg();
    final gainmap = _jpeg();
    for (final name in ['DualShot_GainMap', 'HdrGainMap']) {
      final hdr = _sef(primary, gainmap, name);
      expect(UltraHdrService.isUltraHdr(hdr), isTrue);
      expect(UltraHdrService.extractGainmapJpeg(hdr), gainmap);
      expect(
        UltraHdrService.isUltraHdr(_sef(primary, Uint8List(100), name)),
        isFalse,
      );
    }
    expect(
      UltraHdrService.isUltraHdr(_sef(primary, gainmap, 'GainMap_Info')),
      isFalse,
    );
  });

  test('HDR keywords and EXIF thumbnails cannot masquerade as a gain map', () {
    final jpeg = _jpeg();
    final xmp = utf8.encode(
      UltraHdrService.generateUltraHdrXmp(const UltraHdrMetadata()),
    );
    final withThumbnail = _segment(_segment(jpeg, 0xe1, xmp), 0xe1, [
      ...ascii.encode('Exif\x00\x00'),
      ...jpeg,
    ]);
    expect(UltraHdrService.isUltraHdr(withThumbnail), isFalse);
    expect(UltraHdrService.extractGainmapJpeg(withThumbnail), isNull);
    final comment = _segment(jpeg, 0xfe, xmp);
    expect(UltraHdrService.isUltraHdr(_pair(comment, jpeg)), isFalse);
  });

  test('Truncated JPEG and malformed SEF fail safely', () {
    final hdr = _pair(
      _jpeg(),
      _segment(
        _jpeg(),
        0xe1,
        utf8.encode(
          UltraHdrService.generateSecondaryGainmapXmp(const UltraHdrMetadata()),
        ),
      ),
    );
    expect(
      UltraHdrService.isUltraHdr(Uint8List.sublistView(hdr, 0, hdr.length - 2)),
      isFalse,
    );
    for (final bytes in [
      Uint8List.fromList([0xff, 0xd8, 0xff, 0xe1, 0, 1, 0xff, 0xd9]),
      Uint8List.fromList([0xff, 0xd8, 0xff, 0xe1, 0xff, 0xff]),
      Uint8List.fromList([
        ..._jpeg(),
        0xff,
        0xff,
        0xff,
        0xff,
        ...ascii.encode('SEFT'),
      ]),
    ]) {
      expect(UltraHdrService.isUltraHdr(bytes), isFalse);
    }
  });

  test('Native SDR is authoritative; unsupported or failed decoding uses strict fallback', () async {
    UltraHdrDetector.debugOverrideIsAndroid = true;
    final hdr = _pair(
      _jpeg(),
      _segment(
        _jpeg(),
        0xe1,
        utf8.encode(
          UltraHdrService.generateSecondaryGainmapXmp(const UltraHdrMetadata()),
        ),
      ),
    );
    messenger.setMockMethodCallHandler(channel, (call) async => false);
    expect(await UltraHdrService.checkIsUltraHdr(hdr), isFalse);
    messenger.setMockMethodCallHandler(channel, (call) async => true);
    expect(await UltraHdrService.checkIsUltraHdr(_jpeg()), isTrue);
    for (final fail in [false, true]) {
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (fail) throw PlatformException(code: 'DECODE_FAILED');
        return null;
      });
      expect(await UltraHdrService.checkIsUltraHdr(hdr), isTrue);
      expect(
        await UltraHdrService.checkIsUltraHdr(_pair(_jpeg(), _jpeg())),
        isFalse,
      );
    }
  });

  test(
    'Gallery ignores HDR filenames and applies native results to direct bytes',
    () async {
      UltraHdrDetector.debugOverrideIsAndroid = true;
      messenger.setMockMethodCallHandler(channel, (call) async => false);
      for (final name in ['IMG_HDR.jpg', 'sunset_gainmap.jpg']) {
        final photo = DevicePhotoModel(
          id: 'filename-$name',
          name: name,
          path: '',
          directBytes: _jpeg(),
        );
        expect(DevicePhotoService.getCachedUltraHdr(photo), isNull);
        expect(await DevicePhotoService.isUltraHdr(photo), isFalse);
        expect(DevicePhotoService.getCachedUltraHdr(photo), isFalse);
      }
      messenger.setMockMethodCallHandler(channel, (call) async => true);
      final photo = DevicePhotoModel(
        id: 'native-heic',
        name: 'IMG.heic',
        path: '',
        directBytes: Uint8List(20),
      );
      expect(await DevicePhotoService.isUltraHdr(photo), isTrue);
    },
  );

  test(
    'Gallery detects URI-only photos and does not cache a failed read',
    () async {
      UltraHdrDetector.debugOverrideIsAndroid = true;
      DevicePhotoService.debugOverrideIsAndroid = true;
      const photo = DevicePhotoModel(
        id: 'uri-only',
        name: 'IMG.jpg',
        path: '',
        uri: 'content://media/42',
      );
      var readable = false;
      final hdr = _pair(
        _jpeg(),
        _segment(
          _jpeg(),
          0xe1,
          utf8.encode(
            UltraHdrService.generateSecondaryGainmapXmp(
              const UltraHdrMetadata(),
            ),
          ),
        ),
      );
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect((call.arguments as Map)['uri'], photo.uri);
        if (call.method == 'getPhotoBytes') return readable ? hdr : null;
        if ((call.arguments as Map).containsKey('bytes')) return null;
        return null;
      });
      expect(await DevicePhotoService.isUltraHdr(photo), isFalse);
      expect(DevicePhotoService.getCachedUltraHdr(photo), isNull);
      readable = true;
      // The byte-based fallback has no URI argument.
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'getPhotoBytes') {
          expect((call.arguments as Map)['uri'], photo.uri);
          return hdr;
        }
        return null;
      });
      expect(await DevicePhotoService.isUltraHdr(photo), isTrue);
      expect(DevicePhotoService.getCachedUltraHdr(photo), isTrue);
    },
  );

  test(
    'Gallery uses native URI detection without reading full bytes',
    () async {
      UltraHdrDetector.debugOverrideIsAndroid = true;
      DevicePhotoService.debugOverrideIsAndroid = true;
      for (final hasGainmap in [true, false]) {
        final photo = DevicePhotoModel(
          id: 'native-uri-$hasGainmap',
          name: 'IMG.heic',
          path: '',
          uri: 'content://media/$hasGainmap',
        );
        messenger.setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'hasGainmap');
          expect((call.arguments as Map)['uri'], photo.uri);
          expect((call.arguments as Map).containsKey('bytes'), isFalse);
          return hasGainmap;
        });
        expect(await DevicePhotoService.isUltraHdr(photo), hasGainmap);
        expect(DevicePhotoService.getCachedUltraHdr(photo), hasGainmap);
      }
    },
  );

  test(
    'Export preserves native SDR decision instead of synthesizing a gainmap',
    () async {
      UltraHdrDetector.debugOverrideIsAndroid = true;
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'hasGainmap');
        return false;
      });
      final primary = _jpeg();
      final original = _pair(
        primary,
        _segment(
          _jpeg(),
          0xe1,
          utf8.encode(
            UltraHdrService.generateSecondaryGainmapXmp(
              const UltraHdrMetadata(),
            ),
          ),
        ),
      );
      expect(UltraHdrService.isUltraHdr(original), isTrue);
      final baseImage = await WatermarkProcessor.decodeImageFromBytes(primary);
      addTearDown(baseImage.dispose);
      final output = await WatermarkProcessor.compositeFullResolutionUnified(
        baseImage: baseImage,
        type: WatermarkType.floatingPng,
        watermarkImage: null,
        pngConfig: const WatermarkConfig(),
        logoImage: null,
        frameConfig: const FrameWatermarkConfig(),
        outputFormat: 'jpg',
        originalBytes: original,
        preserveMotionPhoto: false,
      );
      expect(img.decodeJpg(output), isNotNull);
      expect(UltraHdrService.isUltraHdr(output), isFalse);
    },
  );

  test('Gallery uses full files including small JPEGs and gainmaps outside head/tail slices', () async {
    final directory = await Directory.systemTemp.createTemp('hdr-test');
    addTearDown(() => directory.delete(recursive: true));
    final hdr = _pair(
      _jpeg(),
      _segment(
        _jpeg(),
        0xe1,
        utf8.encode(
          UltraHdrService.generateSecondaryGainmapXmp(const UltraHdrMetadata()),
        ),
      ),
    );
    for (final size in [0, 150000]) {
      final file = File('${directory.path}/$size.jpg');
      var content = hdr;
      if (size > 0) {
        for (var i = 0; i < 5; i++) {
          content = _segment(content, 0xfe, List.filled(60000, 0));
        }
      }
      await file.writeAsBytes([...content, ...List.filled(size, 0)]);
      final photo = DevicePhotoModel(
        id: 'file-$size',
        name: '$size.jpg',
        path: file.path,
      );
      expect(await DevicePhotoService.isUltraHdr(photo), isTrue);
    }
  });
}

Uint8List _jpeg() =>
    Uint8List.fromList(img.encodeJpg(img.Image(width: 16, height: 16)));

Uint8List _segment(Uint8List jpeg, int marker, List<int> payload) {
  final length = payload.length + 2;
  return Uint8List.fromList([
    0xff,
    0xd8,
    0xff,
    marker,
    length >> 8,
    length & 255,
    ...payload,
    ...jpeg.skip(2),
  ]);
}

Uint8List _pair(Uint8List primary, Uint8List secondary) {
  final dummy = UltraHdrService.buildMpfSegment(
    primaryImageSize: 0,
    gainmapImageSize: 0,
    gainmapOffsetFromTiffHeader: 0,
  );
  final mpf = UltraHdrService.buildMpfSegment(
    primaryImageSize: primary.length + dummy.length,
    gainmapImageSize: secondary.length,
    gainmapOffsetFromTiffHeader: primary.length + dummy.length - 10,
  );
  return Uint8List.fromList([
    0xff,
    0xd8,
    ...mpf,
    ...primary.skip(2),
    ...secondary,
  ]);
}

Uint8List _sef(Uint8List primary, Uint8List payload, String name) {
  List<int> le(int value) => [
    value & 255,
    (value >> 8) & 255,
    (value >> 16) & 255,
    (value >> 24) & 255,
  ];
  final field = [
    0,
    0,
    0,
    0,
    ...le(name.length),
    ...ascii.encode(name),
    ...payload,
  ];
  return Uint8List.fromList([
    ...primary,
    ...field,
    ...ascii.encode('SEFH'),
    ...le(106),
    ...le(1),
    0,
    0,
    0,
    0,
    ...le(field.length),
    ...le(field.length),
    ...le(24),
    ...ascii.encode('SEFT'),
  ]);
}

Uint8List _video() => Uint8List.fromList([
  0,
  0,
  0,
  24,
  ...ascii.encode('ftypmp42'),
  0,
  0,
  0,
  0,
  ...ascii.encode('isommp42'),
  0,
  0,
  0,
  32,
  ...ascii.encode('mdat'),
  ...List.filled(24, 0xaa),
]);
