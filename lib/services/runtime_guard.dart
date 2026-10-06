import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';

import 'device_photo_service.dart';

/// 设备内存档位，决定图片缓存与缩略图管线的容量。
enum MemoryTier { low, mid, high }

/// 单个档位的全部容量参数（字节 / 条目 / 并发）。
class MemoryCaps {
  final int imageCacheBytes;
  final int imageCacheEntries;
  final int thumbnailCacheBytes;
  final int thumbnailCacheEntries;
  final int thumbnailConcurrency;

  const MemoryCaps({
    required this.imageCacheBytes,
    required this.imageCacheEntries,
    required this.thumbnailCacheBytes,
    required this.thumbnailCacheEntries,
    required this.thumbnailConcurrency,
  });

  /// 降级档：字节与并发减半、条目打六折，下限保护避免归零。
  MemoryCaps degraded() {
    int halve(int v, int min) => v >> 1 < min ? min : v >> 1;
    return MemoryCaps(
      imageCacheBytes: halve(imageCacheBytes, 16 * 1024 * 1024),
      imageCacheEntries: halve(imageCacheEntries, 128),
      thumbnailCacheBytes: halve(thumbnailCacheBytes, 4 * 1024 * 1024),
      thumbnailCacheEntries: (thumbnailCacheEntries * 0.6).round(),
      thumbnailConcurrency: thumbnailConcurrency > 2 ? 2 : 1,
    );
  }
}

const _kCapsByTier = {
  MemoryTier.low: MemoryCaps(
    imageCacheBytes: 32 * 1024 * 1024,
    imageCacheEntries: 300,
    thumbnailCacheBytes: 8 * 1024 * 1024,
    thumbnailCacheEntries: 320,
    thumbnailConcurrency: 2,
  ),
  MemoryTier.mid: MemoryCaps(
    imageCacheBytes: 56 * 1024 * 1024,
    imageCacheEntries: 600,
    thumbnailCacheBytes: 16 * 1024 * 1024,
    thumbnailCacheEntries: 600,
    thumbnailConcurrency: 4,
  ),
  MemoryTier.high: MemoryCaps(
    imageCacheBytes: 96 * 1024 * 1024,
    imageCacheEntries: 1000,
    thumbnailCacheBytes: 24 * 1024 * 1024,
    thumbnailCacheEntries: 900,
    thumbnailConcurrency: 5,
  ),
};

/// 热状态阈值（PowerManager.THERMAL_STATUS_*）：
/// MODERATE 及以上开始降级，回落到 LIGHT 以下恢复。
const int _kThermalDegradeThreshold = 2;
const int _kThermalRestoreThreshold = 1;

/// trim 等级阈值（ComponentCallbacks2.*）：RUNNING_LOW 起清缓存，
/// COMPLETE 追加清 live image，避免被后台 UI 存活引用顶住内存。
const int _kTrimRunningLow = 10;
const int _kTrimComplete = 80;

/// 运行时守护（Dart 侧）。
///
/// 启动时通过原生通道读取设备内存画像并选定 [MemoryTier]，据此设定
/// Flutter [ImageCache] 与缩略图管线容量；随后持续接收两类原生推送：
/// - `onThermalStatusChanged`：热状态升高即降档收缩，回落自动恢复；
/// - `onMemoryTrim`：系统内存压力下清空两级缓存。
///
/// 另读取上次会话的崩溃/OOM 探针：前台异常终止或 OOM 恢复期内
/// 直接以降级档启动并清空陈旧缓存。
///
/// 本类是共享通道 Dart 端入站回调的唯一持有者（Kotlin→Dart），
/// 其余服务门面仅做 Dart→Kotlin 调用，勿再对该通道 setMethodCallHandler。
class RuntimeGuard {
  RuntimeGuard._();

  static final RuntimeGuard instance = RuntimeGuard._();

  static const MethodChannel _channel =
      MethodChannel('com.example.watermark_samsung/ultra_hdr');

  /// 原生查询的硬上限：通道无响应时按 mid 档启动，绝不阻塞首帧。
  static const _queryTimeout = Duration(milliseconds: 500);

  MemoryTier tier = MemoryTier.mid;
  bool previousSessionCrashed = false;
  bool oomRecoveryActive = false;

  final thermalStatus = ValueNotifier<int>(0);
  final degradedMode = ValueNotifier<bool>(false);

  bool _inboundBound = false;
  bool _thermalDegradeActive = false;

  /// 当前生效容量；纯函数便于测试与外部展示。
  static MemoryCaps effectiveCaps({
    required MemoryTier tier,
    required bool degraded,
  }) {
    final base = _kCapsByTier[tier]!;
    return degraded ? base.degraded() : base;
  }

  /// 由设备内存画像计算档位；纯函数便于测试。
  static MemoryTier tierFor({
    required int totalRamBytes,
    required bool isLowRamDevice,
    required int memoryClass,
  }) {
    const gb = 1024 * 1024 * 1024;
    // 画像双缺失时按中档处理，避免误判成高端机放大缓存。
    if (totalRamBytes <= 0 && memoryClass <= 0) return MemoryTier.mid;
    if (isLowRamDevice || (memoryClass > 0 && memoryClass <= 96)) {
      return MemoryTier.low;
    }
    if (totalRamBytes > 0 && totalRamBytes <= 3 * gb) return MemoryTier.low;
    if (totalRamBytes > 0 && totalRamBytes <= 7 * gb) return MemoryTier.mid;
    if (memoryClass > 0 && memoryClass <= 192) return MemoryTier.mid;
    return MemoryTier.high;
  }

  /// 在 runApp 前调用：拉取画像与上次会话状态，落定初始容量。
  Future<void> init() async {
    if (!_isAndroid) return;
    try {
      final info = await _channel
          .invokeMethod<Map<dynamic, dynamic>>('getRuntimeMemoryInfo')
          .timeout(_queryTimeout);
      if (info != null) {
        tier = tierFor(
          totalRamBytes: (info['totalRamBytes'] as num?)?.toInt() ?? 0,
          isLowRamDevice: info['isLowRamDevice'] == true,
          memoryClass: (info['memoryClass'] as num?)?.toInt() ?? 0,
        );
      }
    } catch (_) {
      // 查询失败维持 mid 档默认值。
    }

    try {
      final state = await _channel
          .invokeMethod<Map<dynamic, dynamic>>('getRuntimeState')
          .timeout(_queryTimeout);
      if (state != null) {
        previousSessionCrashed = state['previousSessionCrashed'] == true;
        oomRecoveryActive = state['oomRecoveryActive'] == true;
        final thermal = (state['thermalStatus'] as num?)?.toInt() ?? 0;
        thermalStatus.value = thermal;
        _thermalDegradeActive = thermal >= _kThermalDegradeThreshold;
      }
    } catch (_) {
      // 状态探针失败不阻塞启动。
    }

    degradedMode.value = oomRecoveryActive || _thermalDegradeActive;
    _applyCaps();
    if (previousSessionCrashed || oomRecoveryActive) {
      // 上次会话非正常终止：陈旧缓存不可信，清空后按降级档重建。
      _releaseMemory(liveImages: oomRecoveryActive);
    }
    _bindInbound();
  }

  void _bindInbound() {
    if (_inboundBound) return;
    _inboundBound = true;
    _channel.setMethodCallHandler(_handleInbound);
  }

  Future<dynamic> _handleInbound(MethodCall call) async {
    switch (call.method) {
      case 'onThermalStatusChanged':
        _onThermalStatusChanged((call.arguments as num?)?.toInt() ?? 0);
      case 'onMemoryTrim':
        _onMemoryTrim((call.arguments as num?)?.toInt() ?? 0);
    }
    return null;
  }

  void _onThermalStatusChanged(int status) {
    thermalStatus.value = status;
    // 迟滞区间 (LIGHT~MODERATE 之间) 维持原状态，避免边界抖动反复扩缩容。
    final shouldDegrade = _thermalDegradeActive
        ? status > _kThermalRestoreThreshold
        : status >= _kThermalDegradeThreshold;
    if (shouldDegrade != _thermalDegradeActive) {
      _thermalDegradeActive = shouldDegrade;
      final wasDegraded = degradedMode.value;
      degradedMode.value = oomRecoveryActive || _thermalDegradeActive;
      if (degradedMode.value != wasDegraded) {
        _applyCaps();
        if (degradedMode.value) {
          // 进入降级：立即释放解码缓存与已退休的 live image。
          _releaseMemory(liveImages: true);
        }
        // 恢复时只扩容不清缓存，现存条目自然按新上限保留。
      }
    }
  }

  void _onMemoryTrim(int level) {
    if (level >= _kTrimComplete) {
      _releaseMemory(liveImages: true);
      return;
    }
    if (level >= _kTrimRunningLow) {
      _releaseMemory();
    }
  }

  void _applyCaps() {
    final caps = effectiveCaps(tier: tier, degraded: degradedMode.value);
    final ImageCache imageCache = PaintingBinding.instance.imageCache;
    imageCache.maximumSizeBytes = caps.imageCacheBytes;
    imageCache.maximumSize = caps.imageCacheEntries;
    DevicePhotoService.applyThumbnailPolicy(
      maxCacheBytes: caps.thumbnailCacheBytes,
      maxCacheEntries: caps.thumbnailCacheEntries,
      maxConcurrent: caps.thumbnailConcurrency,
    );
  }

  void _releaseMemory({bool liveImages = false}) {
    DevicePhotoService.clearThumbnailCache();
    final ImageCache imageCache = PaintingBinding.instance.imageCache;
    imageCache.clear();
    if (liveImages) imageCache.clearLiveImages();
  }

  static bool get _isAndroid => Platform.isAndroid;
}
