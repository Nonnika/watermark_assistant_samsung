import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:watermark_samsung/services/photos/thumbnail_loader.dart';

void main() {
  test(
    'coalesces active and queued requests within the concurrency limit',
    () async {
      final loader = ThumbnailLoader(maxConcurrent: 2);
      final gates = List.generate(3, (_) => Completer<Uint8List?>());
      final calls = <int>[];
      ThumbnailRequest request(int id) => loader.request(id, () {
        calls.add(id);
        return gates[id].future;
      });

      final requests = [
        request(0),
        request(0),
        request(1),
        request(2),
        request(2),
      ];
      expect(calls, [0, 1]);
      gates[0].complete(Uint8List.fromList([1]));
      expect(await requests[0].bytes, same(await requests[1].bytes));
      expect(calls, [0, 1, 2]);
      gates[1].complete(Uint8List.fromList([2]));
      gates[2].complete(Uint8List.fromList([3]));
      await Future.wait(requests.map((request) => request.bytes));
      expect(calls, [0, 1, 2]);
      expect(await request(0).bytes, [1]);
      expect(calls, [0, 1, 2]);
    },
  );

  test(
    'prioritizes visible requests and promotes shared prefetch work',
    () async {
      final loader = ThumbnailLoader(maxConcurrent: 1);
      final gate = Completer<Uint8List?>();
      final active = loader.request('active', () => gate.future);
      final calls = <String>[];
      ThumbnailRequest request(String key, {bool prefetch = false}) =>
          loader.request(key, () async {
            calls.add(key);
            return Uint8List(1);
          }, prefetch: prefetch);
      final background = request('background', prefetch: true);
      final promoted = request('promoted', prefetch: true);
      final visible = request('visible');
      final shared = request('promoted');
      gate.complete(null);
      await Future.wait(
        [active, background, promoted, visible, shared].map((r) => r.bytes),
      );
      expect(calls, ['visible', 'promoted', 'background']);
    },
  );

  test('cancels queued work only after the last consumer leaves', () async {
    final loader = ThumbnailLoader(maxConcurrent: 1);
    final gate = Completer<Uint8List?>();
    final active = loader.request('active', () => gate.future);
    var calls = 0;
    Future<Uint8List?> decode() async {
      calls++;
      return Uint8List(1);
    }

    final removed = loader.request('removed', decode);
    removed.cancel();
    removed.cancel();
    final shared1 = loader.request('shared', decode);
    final shared2 = loader.request('shared', decode);
    shared1.cancel();
    expect(await removed.bytes, isNull);
    gate.complete(null);
    await active.bytes;
    expect(await shared2.bytes, isNotNull);
    expect(calls, 1);
    expect(await loader.request('removed', decode).bytes, isNotNull);
    expect(calls, 2);
  });

  test(
    'canceling an active request preserves shared completion and caching',
    () async {
      final loader = ThumbnailLoader(maxConcurrent: 1);
      final gate = Completer<Uint8List?>();
      final first = loader.request('photo', () => gate.future);
      first.cancel();
      final second = loader.request(
        'photo',
        () => throw StateError('duplicate'),
      );
      gate.complete(Uint8List.fromList([7]));
      expect(await second.bytes, [7]);
      expect(loader.getCached('photo'), [7]);
    },
  );

  test('failures release capacity and remain retryable', () async {
    final loader = ThumbnailLoader(maxConcurrent: 1);
    final failed = loader.request('bad', () => throw StateError('bad image'));
    final next = loader.request('next', () async => Uint8List(1));
    expect(await failed.bytes, isNull);
    expect(await next.bytes, isNotNull);
    expect(await loader.request('bad', () async => Uint8List(0)).bytes, isNull);
    expect(
      await loader.request('bad', () async => Uint8List(2)).bytes,
      hasLength(2),
    );
  });

  test('evicts by byte budget using LRU order', () async {
    final loader = ThumbnailLoader(maxCacheBytes: 6);
    Future<void> put(String key) async {
      await loader.request(key, () async => Uint8List(3)).bytes;
    }

    await put('a');
    await put('b');
    expect(loader.getCached('a'), isNotNull);
    await put('c');
    expect(loader.getCached('b'), isNull);
    expect(loader.getCached('a'), isNotNull);
    expect(loader.getCached('c'), isNotNull);
    expect(loader.cachedBytes, 6);
    expect(loader.cachedCount, 2);
    loader.clearCache();
    expect(loader.cachedBytes, 0);
    expect(loader.cachedCount, 0);
  });

  test(
    'also caps entry count and does not cache oversized backing buffers',
    () async {
      final loader = ThumbnailLoader(maxCacheEntries: 2, maxCacheBytes: 10);
      for (var i = 0; i < 3; i++) {
        await loader.request(i, () async => Uint8List(1)).bytes;
      }
      expect(loader.getCached(0), isNull);
      final smallView = Uint8List.view(Uint8List(20).buffer, 0, 1);
      expect(
        await loader.request('large', () async => smallView).bytes,
        same(smallView),
      );
      expect(loader.getCached('large'), isNull);
      expect(loader.cachedBytes, 2);
    },
  );
}
