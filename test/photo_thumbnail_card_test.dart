import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:watermark_samsung/services/device_photo_service.dart';
import 'package:watermark_samsung/widgets/selector/photo_thumbnail_card.dart';
import 'package:watermark_samsung/widgets/selector/selector_grid_page.dart';

void main() {
  const channel = MethodChannel('com.example.watermark_samsung/ultra_hdr');
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  DevicePhotoModel photo(String id) =>
      DevicePhotoModel(id: id, name: '$id.jpg', path: '');
  final red = Uint8List.fromList(img.encodePng(img.Image(width: 4, height: 8)));
  final blue = Uint8List.fromList(
    img.encodePng(img.Image(width: 8, height: 4)),
  );

  Widget card(DevicePhotoModel photo) => MaterialApp(
    home: Center(
      child: SizedBox(
        width: 100,
        height: 100,
        child: PhotoThumbnailCard(
          photo: photo,
          isSelected: false,
          isMultiSelect: true,
          onTap: () {},
          onLongPress: () {},
        ),
      ),
    ),
  );

  setUp(() {
    DevicePhotoService.debugOverrideIsAndroid = true;
    DevicePhotoService.clearThumbnailCache();
  });
  tearDown(() {
    DevicePhotoService.debugOverrideIsAndroid = null;
    DevicePhotoService.clearThumbnailCache();
    messenger.setMockMethodCallHandler(channel, null);
  });

  testWidgets(
    'reused cells ignore stale completions and preserve aspect ratio',
    (tester) async {
      final first = Completer<Uint8List?>();
      final second = Completer<Uint8List?>();
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method != 'getPhotoThumbnail') return null;
        return call.arguments['id'] == 'first' ? first.future : second.future;
      });
      await tester.pumpWidget(card(photo('first')));
      await tester.pumpWidget(card(photo('second')));
      second.complete(blue);
      await tester.pumpAndSettle();
      ResizeImage provider() =>
          tester.widget<Image>(find.byType(Image)).image as ResizeImage;
      final currentBytes = (provider().imageProvider as MemoryImage).bytes;
      expect(currentBytes, orderedEquals(blue));
      expect(provider().policy, ResizeImagePolicy.fit);
      first.complete(red);
      await tester.pumpAndSettle();
      expect(
        (provider().imageProvider as MemoryImage).bytes,
        same(currentBytes),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('disposing a queued card prevents its native decode', (
    tester,
  ) async {
    final gate = Completer<Uint8List?>();
    final calls = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.arguments['id'] as String);
      return gate.future;
    });
    final active = List.generate(
      4,
      (i) => DevicePhotoService.getThumbnail(photo('active-$i')),
    );
    await tester.pumpWidget(card(photo('canceled')));
    expect(calls, hasLength(4));
    await tester.pumpWidget(const SizedBox.shrink());
    gate.complete(null);
    await tester.pumpAndSettle();
    await Future.wait(active);
    expect(calls, isNot(contains('canceled')));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'scrolling releases offscreen cards instead of retaining the album',
    (tester) async {
      messenger.setMockMethodCallHandler(channel, (_) async => null);
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SelectorGridPage(
              items: List.generate(300, (i) => photo('scroll-$i')),
              scrollController: controller,
              isExpanded: true,
              isLoading: false,
              hasPermission: true,
              emptyTitle: '',
              emptyIcon: Icons.photo,
              selectedIds: const {},
              onTogglePhoto: (_) {},
              onRequestPermission: () {},
              onRefresh: () {},
              onCollapseRequest: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final initial = find
          .byType(PhotoThumbnailCard, skipOffstage: false)
          .evaluate()
          .length;
      for (var i = 1; i <= 10; i++) {
        controller.jumpTo(i * 600);
        await tester.pumpAndSettle();
      }
      expect(
        find.byType(PhotoThumbnailCard, skipOffstage: false).evaluate().length,
        lessThanOrEqualTo(initial + 6),
      );
      expect(
        find.byKey(const ValueKey('photo_scroll-0'), skipOffstage: false),
        findsNothing,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
