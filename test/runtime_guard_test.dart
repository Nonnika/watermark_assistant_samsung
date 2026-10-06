import 'package:flutter_test/flutter_test.dart';
import 'package:watermark_samsung/services/runtime_guard.dart';

void main() {
  const gb = 1024 * 1024 * 1024;
  const mb = 1024 * 1024;

  test('tierFor maps device memory profiles to tiers', () {
    // 低端：低内存标记 / 3GB 及以下 / 小 memoryClass
    expect(
      RuntimeGuard.tierFor(
          totalRamBytes: 2 * gb, isLowRamDevice: false, memoryClass: 128),
      MemoryTier.low,
    );
    expect(
      RuntimeGuard.tierFor(
          totalRamBytes: 8 * gb, isLowRamDevice: true, memoryClass: 256),
      MemoryTier.low,
    );
    expect(
      RuntimeGuard.tierFor(
          totalRamBytes: 0, isLowRamDevice: false, memoryClass: 96),
      MemoryTier.low,
    );
    // 中端：4-7GB / memoryClass 128-192
    expect(
      RuntimeGuard.tierFor(
          totalRamBytes: 6 * gb, isLowRamDevice: false, memoryClass: 160),
      MemoryTier.mid,
    );
    expect(
      RuntimeGuard.tierFor(
          totalRamBytes: 0, isLowRamDevice: false, memoryClass: 192),
      MemoryTier.mid,
    );
    // 高端：8GB+ 且 memoryClass > 192
    expect(
      RuntimeGuard.tierFor(
          totalRamBytes: 12 * gb, isLowRamDevice: false, memoryClass: 512),
      MemoryTier.high,
    );
    // 画像双缺失按中档，避免误判高端机放大缓存
    expect(
      RuntimeGuard.tierFor(
          totalRamBytes: 0, isLowRamDevice: false, memoryClass: 0),
      MemoryTier.mid,
    );
  });

  test('degraded caps keep safe minimums for every tier', () {
    for (final tier in MemoryTier.values) {
      final caps = RuntimeGuard.effectiveCaps(tier: tier, degraded: true);
      expect(caps.imageCacheBytes, greaterThanOrEqualTo(16 * mb));
      expect(caps.imageCacheEntries, greaterThanOrEqualTo(128));
      expect(caps.thumbnailCacheBytes, greaterThanOrEqualTo(4 * mb));
      expect(caps.thumbnailCacheEntries, greaterThan(0));
      expect(caps.thumbnailConcurrency, greaterThanOrEqualTo(1));
    }
  });

  test('degraded caps never exceed base caps', () {
    for (final tier in MemoryTier.values) {
      final base = RuntimeGuard.effectiveCaps(tier: tier, degraded: false);
      final degraded = RuntimeGuard.effectiveCaps(tier: tier, degraded: true);
      expect(degraded.imageCacheBytes, lessThanOrEqualTo(base.imageCacheBytes));
      expect(
          degraded.imageCacheEntries, lessThanOrEqualTo(base.imageCacheEntries));
      expect(degraded.thumbnailCacheBytes,
          lessThanOrEqualTo(base.thumbnailCacheBytes));
      expect(degraded.thumbnailCacheEntries,
          lessThanOrEqualTo(base.thumbnailCacheEntries));
      expect(degraded.thumbnailConcurrency,
          lessThanOrEqualTo(base.thumbnailConcurrency));
    }
  });

  test('caps grow monotonically with tier', () {
    final low = RuntimeGuard.effectiveCaps(tier: MemoryTier.low, degraded: false);
    final mid = RuntimeGuard.effectiveCaps(tier: MemoryTier.mid, degraded: false);
    final high =
        RuntimeGuard.effectiveCaps(tier: MemoryTier.high, degraded: false);
    expect(mid.thumbnailCacheBytes, greaterThan(low.thumbnailCacheBytes));
    expect(high.thumbnailCacheBytes, greaterThan(mid.thumbnailCacheBytes));
    expect(mid.imageCacheBytes, greaterThan(low.imageCacheBytes));
    expect(high.imageCacheBytes, greaterThan(mid.imageCacheBytes));
  });
}
