import 'dart:async';
import 'dart:typed_data';

/// A consumer of a shared load. Canceling the last consumer drops queued work;
/// decodes already running may finish and populate the cache.
class ThumbnailRequest {
  final Future<Uint8List?> bytes;
  final void Function() _onCancel;
  bool _canceled = false;

  ThumbnailRequest._(this.bytes, this._onCancel);

  factory ThumbnailRequest.completed(Uint8List? bytes) =>
      ThumbnailRequest._(Future.value(bytes), () {});

  void cancel() {
    if (_canceled) return;
    _canceled = true;
    _onCancel();
  }
}

/// Deduplicates both queued and active loads, prioritizes visible cells, and
/// bounds retained encoded thumbnails by bytes as well as entry count.
class ThumbnailLoader {
  final int maxConcurrent;
  final int maxCacheBytes;
  final int maxCacheEntries;
  final _cache = <Object, Uint8List>{};
  final _loads = <Object, _ThumbnailLoad>{};
  final _visible = <Object, _ThumbnailLoad>{};
  final _prefetch = <Object, _ThumbnailLoad>{};
  int _active = 0;
  int _cacheBytes = 0;

  ThumbnailLoader({
    this.maxConcurrent = 4,
    this.maxCacheBytes = 16 * 1024 * 1024,
    this.maxCacheEntries = 600,
  }) : assert(maxConcurrent > 0),
       assert(maxCacheBytes >= 0),
       assert(maxCacheEntries >= 0);

  int get cachedBytes => _cacheBytes;
  int get cachedCount => _cache.length;

  Uint8List? getCached(Object key) {
    final bytes = _cache.remove(key);
    if (bytes != null) _cache[key] = bytes;
    return bytes;
  }

  void clearCache() {
    _cache.clear();
    _cacheBytes = 0;
  }

  ThumbnailRequest request(
    Object key,
    Future<Uint8List?> Function() decode, {
    bool prefetch = false,
  }) {
    final cached = getCached(key);
    if (cached != null) return ThumbnailRequest.completed(cached);

    final load = _loads.putIfAbsent(key, () {
      final load = _ThumbnailLoad(key, decode);
      (prefetch ? _prefetch : _visible)[key] = load;
      return load;
    });
    load.consumers++;
    if (!prefetch && _prefetch.remove(key) != null) _visible[key] = load;
    _drain();

    return ThumbnailRequest._(load.completer.future, () {
      load.consumers--;
      if (load.consumers == 0 && !load.started) {
        _visible.remove(key);
        _prefetch.remove(key);
        _loads.remove(key);
        load.completer.complete(null);
      }
    });
  }

  void _drain() {
    while (_active < maxConcurrent &&
        (_visible.isNotEmpty || _prefetch.isNotEmpty)) {
      final queue = _visible.isNotEmpty ? _visible : _prefetch;
      final load = queue.remove(queue.keys.first)!;
      load.started = true;
      _active++;
      unawaited(_run(load));
    }
  }

  Future<void> _run(_ThumbnailLoad load) async {
    Uint8List? bytes;
    try {
      bytes = await Future.sync(load.decode);
      if (bytes != null && bytes.isNotEmpty) {
        _store(load.key, bytes);
      } else {
        bytes = null;
      }
    } catch (_) {
      // Failures are retryable, and must never stall the queue.
    } finally {
      _loads.remove(load.key);
      _active--;
      load.completer.complete(bytes);
      _drain();
    }
  }

  void _store(Object key, Uint8List bytes) {
    // Count backing buffers too: a tiny view can retain a whole source photo.
    final length = bytes.buffer.lengthInBytes;
    if (length > maxCacheBytes || maxCacheEntries == 0) return;
    final previous = _cache.remove(key);
    if (previous != null) _cacheBytes -= previous.buffer.lengthInBytes;
    while (_cache.isNotEmpty &&
        (_cacheBytes + length > maxCacheBytes ||
            _cache.length >= maxCacheEntries)) {
      _cacheBytes -= _cache.remove(_cache.keys.first)!.buffer.lengthInBytes;
    }
    _cache[key] = bytes;
    _cacheBytes += length;
  }
}

class _ThumbnailLoad {
  final Object key;
  final Future<Uint8List?> Function() decode;
  final completer = Completer<Uint8List?>();
  int consumers = 0;
  bool started = false;

  _ThumbnailLoad(this.key, this.decode);
}
