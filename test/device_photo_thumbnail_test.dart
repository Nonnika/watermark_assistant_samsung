import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:watermark_samsung/services/device_photo_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.example.watermark_samsung/ultra_hdr');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUp(DevicePhotoService.clearThumbnailCache);
  tearDown(() {
    DevicePhotoService.debugOverrideIsAndroid = null;
    DevicePhotoService.clearThumbnailCache();
    messenger.setMockMethodCallHandler(channel, null);
  });

  test(
    'native prefetch and visible cards share one call including source URI',
    () async {
      DevicePhotoService.debugOverrideIsAndroid = true;
      const photo = DevicePhotoModel(
        id: 'native',
        name: 'photo.jpg',
        path: '',
        uri: 'content://media/external/images/media/1',
      );
      final gate = Completer<Uint8List>();
      var calls = 0;
      messenger.setMockMethodCallHandler(channel, (call) {
        expect(call.method, 'getPhotoThumbnail');
        expect(call.arguments['uri'], photo.uri);
        expect(call.arguments['width'], 256);
        calls++;
        return gate.future;
      });
      final warm = DevicePhotoService.preloadThumbnails([photo]);
      final visible = DevicePhotoService.getThumbnail(photo);
      await Future<void>.delayed(Duration.zero);
      expect(calls, 1);
      gate.complete(Uint8List.fromList([1, 2, 3]));
      await warm;
      final bytes = await visible;
      expect(DevicePhotoService.getCachedThumbnail(photo), same(bytes));
      expect(await DevicePhotoService.getThumbnail(photo), same(bytes));
      expect(calls, 1);
    },
  );

  test('cache separates revisions, sizes and sources sharing an ID', () async {
    DevicePhotoService.debugOverrideIsAndroid = true;
    var calls = 0;
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => Uint8List.fromList([++calls]),
    );
    const original = DevicePhotoModel(
      id: 'revision',
      name: '',
      path: '/a',
      dateModified: 1,
    );
    const edited = DevicePhotoModel(
      id: 'revision',
      name: '',
      path: '/a',
      dateModified: 2,
    );
    const otherSource = DevicePhotoModel(
      id: 'revision',
      name: '',
      path: '/b',
      dateModified: 2,
    );
    expect(await DevicePhotoService.getThumbnail(original), [1]);
    expect(await DevicePhotoService.getThumbnail(edited), [2]);
    expect(await DevicePhotoService.getThumbnail(otherSource), [3]);
    expect(await DevicePhotoService.getThumbnail(original, size: 128), [4]);
    expect(await DevicePhotoService.getThumbnail(original), [1]);
    expect(calls, 4);
  });

  for (final (width, height, expectedWidth, expectedHeight) in [
    (400, 1200, 85, 256),
    (1200, 400, 256, 85),
    (20, 40, 20, 40),
    (1, 1200, 1, 256),
  ]) {
    test(
      'fallback bounds ${width}x$height without stretching or upscaling',
      () async {
        final source = Uint8List.fromList(
          img.encodePng(img.Image(width: width, height: height)),
        );
        final photo = DevicePhotoModel(
          id: 'memory-$width-$height',
          name: '',
          path: '',
          directBytes: source,
        );
        expect(DevicePhotoService.getCachedThumbnail(photo), isNull);
        final bytes = await DevicePhotoService.getThumbnail(photo);
        expect(bytes, isNotNull);
        expect(identical(source, bytes), isFalse);
        final codec = await ui.instantiateImageCodec(bytes!);
        final image = (await codec.getNextFrame()).image;
        expect(image.width, expectedWidth);
        expect(image.height, expectedHeight);
        image.dispose();
        codec.dispose();
        expect(await DevicePhotoService.getFullPhotoBytes(photo), same(source));
      },
    );
  }

  test(
    'file fallback loads after native failure and retries a corrupt file',
    () async {
      DevicePhotoService.debugOverrideIsAndroid = true;
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => throw PlatformException(code: 'failed'),
      );
      final dir = await Directory.systemTemp.createTemp('thumbnail-test');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/photo.png');
      await file.writeAsBytes([1, 2, 3]);
      final photo = DevicePhotoModel(id: 'file', name: '', path: file.path);
      expect(await DevicePhotoService.getThumbnail(photo), isNull);
      await file.writeAsBytes(
        img.encodePng(img.Image(width: 600, height: 300)),
      );
      final bytes = await DevicePhotoService.getThumbnail(photo);
      final codec = await ui.instantiateImageCodec(bytes!);
      final image = (await codec.getNextFrame()).image;
      expect([image.width, image.height], [256, 128]);
      image.dispose();
      codec.dispose();
    },
  );

  test(
    'prefetch stops after the current batch when the selector closes',
    () async {
      DevicePhotoService.debugOverrideIsAndroid = true;
      var calls = 0;
      var keepLoading = true;
      messenger.setMockMethodCallHandler(channel, (_) async {
        calls++;
        keepLoading = false;
        return Uint8List(1);
      });
      final photos = List.generate(
        12,
        (i) => DevicePhotoModel(id: 'warm-$i', name: '', path: ''),
      );
      await DevicePhotoService.preloadThumbnails(
        photos,
        shouldContinue: () => keepLoading,
      );
      expect(calls, 4);
      expect(
        () => DevicePhotoService.getThumbnail(photos.first, size: 0),
        throwsArgumentError,
      );
      await expectLater(
        DevicePhotoService.preloadThumbnails(photos, batchSize: 0),
        throwsArgumentError,
      );
    },
  );
}
