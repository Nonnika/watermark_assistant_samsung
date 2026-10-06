import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'motion_photo_service.dart';
import 'photos/thumbnail_loader.dart';
import 'ultra_hdr_service.dart';

export 'photos/thumbnail_loader.dart' show ThumbnailRequest;

class DevicePhotoModel {
  final String id;
  final String name;
  final String path;
  final String? uri;
  final int size;
  final int dateAdded;
  final int dateModified;
  final int width;
  final int height;
  final String mimeType;
  final Uint8List? cachedThumbnail;
  final Uint8List? directBytes;

  const DevicePhotoModel({
    required this.id,
    required this.name,
    required this.path,
    this.uri,
    this.size = 0,
    this.dateAdded = 0,
    this.dateModified = 0,
    this.width = 0,
    this.height = 0,
    this.mimeType = 'image/jpeg',
    this.cachedThumbnail,
    this.directBytes,
  });

  String get formattedDate {
    if (dateAdded <= 0) return '';
    try {
      final dt = DateTime.fromMillisecondsSinceEpoch(dateAdded * 1000);
      return '${dt.year}/${dt.month.toString().padLeft(2, '0')}/${dt.day.toString().padLeft(2, '0')}';
    } catch (_) {
      return '';
    }
  }

  String get formattedSize {
    if (size <= 0) return '';
    if (size < 1024 * 1024) {
      return '${(size / 1024).toStringAsFixed(1)} KB';
    }
    return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

class DevicePhotoService {
  static const MethodChannel _channel = MethodChannel('com.example.watermark_samsung/ultra_hdr');
  static final _thumbnails = ThumbnailLoader();
  // Stable identity without retaining the full source bytes in cache keys.
  static final _byteSourceKeys = Expando<Object>();

  static Object? _byteSourceKey(Uint8List? bytes) =>
      bytes == null ? null : (_byteSourceKeys[bytes] ??= Object());

  // Include the source and its revision so a refreshed MediaStore item cannot
  // reuse a thumbnail from an edited photo or a different URI with the same ID.
  static Object _thumbnailKey(DevicePhotoModel photo, int size) => (
    photo.id, photo.path, photo.uri, photo.size, photo.dateAdded,
    photo.dateModified, _byteSourceKey(photo.directBytes), size,
  );

  static void clearThumbnailCache() => _thumbnails.clearCache();

  /// 运行时调整缩略图管线容量（内存分档 / 降级信号），立即驱逐超额缓存。
  static void applyThumbnailPolicy({
    required int maxCacheBytes,
    required int maxCacheEntries,
    required int maxConcurrent,
  }) {
    _thumbnails.configure(
      maxCacheBytes: maxCacheBytes,
      maxCacheEntries: maxCacheEntries,
      maxConcurrent: maxConcurrent,
    );
  }

  /// Decode at a bounded size, keeping full file bytes out of the Dart heap.
  /// PNG encoding runs in the engine instead of a synchronous Dart JPEG loop.
  static Future<Uint8List?> _downscaleToThumbnail(
    DevicePhotoModel photo,
    int size,
  ) async {
    ui.ImmutableBuffer? buffer;
    ui.ImageDescriptor? descriptor;
    ui.Codec? codec;
    ui.Image? image;
    try {
      buffer = photo.directBytes != null
          ? await ui.ImmutableBuffer.fromUint8List(photo.directBytes!)
          : await ui.ImmutableBuffer.fromFilePath(photo.path);
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      final longest = descriptor.width > descriptor.height
          ? descriptor.width : descriptor.height;
      final scale = longest > size ? size / longest : 1.0;
      codec = await descriptor.instantiateCodec(
        targetWidth: (descriptor.width * scale).round().clamp(1, size),
        targetHeight: (descriptor.height * scale).round().clamp(1, size),
      );
      image = (await codec.getNextFrame()).image;
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data?.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    } catch (_) {
      return null;
    } finally {
      image?.dispose();
      codec?.dispose();
      descriptor?.dispose();
      buffer?.dispose();
    }
  }

  @visibleForTesting
  static bool? debugOverrideIsAndroid;

  static bool get _isAndroid => debugOverrideIsAndroid ?? Platform.isAndroid;

  /// 检查是否已授予相册读取权限
  static Future<bool> checkPermission() async {
    if (!_isAndroid) return true;
    try {
      final granted = await _channel.invokeMethod<bool>('checkStoragePermission');
      return granted ?? true;
    } catch (_) {
      return true;
    }
  }

  /// 申请相册读取权限
  static Future<bool> requestPermission() async {
    if (!_isAndroid) return true;
    try {
      final granted = await _channel.invokeMethod<bool>('requestStoragePermission');
      return granted ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 打开系统应用设置页
  static Future<bool> openAppSettings() async {
    if (!_isAndroid) return false;
    try {
      final res = await _channel.invokeMethod<bool>('openAppSettings');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 获取设备最近的照片列表 (原生 MediaStore + 本地目录扫描 + 回退)
  /// limit: 0 或负数表示无限制（拉取相册全量照片）
  static Future<List<DevicePhotoModel>> getRecentPhotos({int limit = 0}) async {
    final List<DevicePhotoModel> photos = [];

    // 1. Android 原生 MediaStore 查询 (超高速、系统级别)
    if (_isAndroid) {
      try {
        final List<dynamic>? rawList = await _channel.invokeMethod<List<dynamic>>('getRecentPhotos', {
          'limit': limit,
        });

        if (rawList != null) {
          for (final item in rawList) {
            if (item is Map) {
              photos.add(
                DevicePhotoModel(
                  id: item['id']?.toString() ?? UniqueKey().toString(),
                  name: item['name']?.toString() ?? 'Photo',
                  path: item['path']?.toString() ?? '',
                  uri: item['uri']?.toString(),
                  size: (item['size'] as num?)?.toInt() ?? 0,
                  dateAdded: (item['dateAdded'] as num?)?.toInt() ?? 0,
                  dateModified: (item['dateModified'] as num?)?.toInt() ?? 0,
                  width: (item['width'] as num?)?.toInt() ?? 0,
                  height: (item['height'] as num?)?.toInt() ?? 0,
                  mimeType: item['mimeType']?.toString() ?? 'image/jpeg',
                ),
              );
            }
          }
          return photos;
        }
      } catch (e) {
        debugPrint('[DevicePhotoService] Native MediaStore query failed: $e');
      }
    }

    // 2. 本地常见相册目录扫描 (DCIM / Pictures / Downloads / Documents / macOS)
    try {
      final scanned = await _scanLocalDirectories(limit: limit > 0 ? limit : 2000);
      if (scanned.isNotEmpty) {
        return scanned;
      }
    } catch (e) {
      debugPrint('[DevicePhotoService] Local directory scan failed: $e');
    }

    return photos;
  }

  /// 扫描常见本地文件夹
  static Future<List<DevicePhotoModel>> _scanLocalDirectories({int limit = 2000}) async {
    final List<DevicePhotoModel> results = [];
    final Set<String> targetDirs = {};

    try {
      if (Platform.isAndroid) {
        targetDirs.add('/storage/emulated/0/DCIM/Camera');
        targetDirs.add('/storage/emulated/0/DCIM');
        targetDirs.add('/storage/emulated/0/Pictures');
        targetDirs.add('/storage/emulated/0/Download');
      } else {
        final docDir = await getApplicationDocumentsDirectory();
        targetDirs.add(docDir.path);
        final picDir = await getDownloadsDirectory();
        if (picDir != null) targetDirs.add(picDir.path);
      }
    } catch (_) {}

    final supportedExts = {'.jpg', '.jpeg', '.png', '.webp', '.heic', '.heif', '.avif', '.dng'};

    for (final dirPath in targetDirs) {
      final dir = Directory(dirPath);
      if (!await dir.exists()) continue;

      try {
        final entities = dir.listSync(recursive: false);
        for (final entity in entities) {
          if (entity is File) {
            final ext = p.extension(entity.path).toLowerCase();
            if (supportedExts.contains(ext)) {
              final stat = await entity.stat();
              results.add(
                DevicePhotoModel(
                  id: entity.path,
                  name: p.basename(entity.path),
                  path: entity.path,
                  size: stat.size,
                  dateAdded: (stat.modified.millisecondsSinceEpoch / 1000).round(),
                  dateModified: stat.modified.millisecondsSinceEpoch,
                ),
              );
              if (limit > 0 && results.length >= limit) break;
            }
          }
        }
      } catch (_) {}
      if (limit > 0 && results.length >= limit) break;
    }

    // 按照时间倒序
    results.sort((a, b) => b.dateAdded.compareTo(a.dateAdded));
    return results;
  }

  /// 同步获取缩略图内存缓存 (首帧零延迟渲染, 彻底消除黑块闪烁)
  static Uint8List? getCachedThumbnail(DevicePhotoModel photo, {int size = 256}) {
    if (photo.cachedThumbnail != null) return photo.cachedThumbnail;
    return _thumbnails.getCached(_thumbnailKey(photo, size));
  }

  /// 同步获取动态照片识别缓存
  static bool? getCachedMotionPhoto(DevicePhotoModel photo) {
    if (_motionPhotoCache.containsKey(photo.id)) {
      return _motionPhotoCache[photo.id];
    }
    final lowerName = photo.name.toLowerCase();
    if (lowerName.contains('motion') || lowerName.contains('mvimg') || lowerName.contains('_mp.jpg')) {
      _motionPhotoCache[photo.id] = true;
      return true;
    }
    return null;
  }

  /// 同步获取 Ultra HDR 识别缓存
  static bool? getCachedUltraHdr(DevicePhotoModel photo) {
    return _ultraHdrCache[photo.id];
  }

  /// Visible cards keep a request handle so offscreen queued work can be dropped.
  static ThumbnailRequest requestThumbnail(
    DevicePhotoModel photo, {
    int size = 256,
    bool prefetch = false,
  }) {
    if (size <= 0) throw ArgumentError.value(size, 'size', 'Must be positive');
    if (photo.cachedThumbnail != null) {
      return ThumbnailRequest.completed(photo.cachedThumbnail);
    }
    return _thumbnails.request(
      _thumbnailKey(photo, size),
      () => _loadThumbnail(photo, size),
      prefetch: prefetch,
    );
  }

  /// Calls for the same source and size share one queued or active decode.
  static Future<Uint8List?> getThumbnail(DevicePhotoModel photo, {int size = 256}) =>
      requestThumbnail(photo, size: size).bytes;

  static Future<Uint8List?> _loadThumbnail(DevicePhotoModel photo, int size) async {
    if (photo.directBytes == null && _isAndroid) {
      try {
        final bytes = await _channel.invokeMethod<Uint8List>('getPhotoThumbnail', {
          'id': photo.id,
          'path': photo.path,
          'uri': photo.uri,
          'width': size,
          'height': size,
        });
        if (bytes != null && bytes.isNotEmpty) return bytes;
      } catch (_) {}
    }
    if (photo.directBytes != null || photo.path.isNotEmpty) {
      return _downscaleToThumbnail(photo, size);
    }
    return null;
  }

  /// Prefetch yields queue priority to visible cells and stops between batches
  /// when the selector that initiated it has gone away.
  static Future<void> preloadThumbnails(
    List<DevicePhotoModel> photos, {
    int size = 256,
    int batchSize = 4,
    bool Function()? shouldContinue,
  }) async {
    if (batchSize <= 0) {
      throw ArgumentError.value(batchSize, 'batchSize', 'Must be positive');
    }
    for (int i = 0; i < photos.length; i += batchSize) {
      if (shouldContinue != null && !shouldContinue()) return;
      await Future.wait(photos.skip(i).take(batchSize).map((photo) =>
          requestThumbnail(photo, size: size, prefetch: true).bytes));
    }
  }

  /// 获取照片完整字节流 (用于水印工作区编辑)
  static Future<Uint8List?> getFullPhotoBytes(DevicePhotoModel photo) async {
    if (photo.directBytes != null) return photo.directBytes;

    if (_isAndroid && (photo.uri != null || photo.path.isNotEmpty)) {
      try {
        final Uint8List? bytes = await _channel.invokeMethod<Uint8List>('getPhotoBytes', {
          'path': photo.path,
          'uri': photo.uri,
        });
        if (bytes != null && bytes.isNotEmpty) {
          return bytes;
        }
      } catch (e) {
        debugPrint('[DevicePhotoService] Native getPhotoBytes failed: $e');
      }
    }

    if (photo.path.isNotEmpty) {
      try {
        final file = File(photo.path);
        if (await file.exists()) {
          return await file.readAsBytes();
        }
      } catch (e) {
        debugPrint('[DevicePhotoService] File read failed: $e');
      }
    }

    return null;
  }

  static final Map<String, bool> _motionPhotoCache = {};
  static final Map<String, bool> _ultraHdrCache = {};

  /// 检查照片是否为动态照片 (Motion Photo, 深度支持 JPG 与 HEIC，杜绝普通静态 HEIC/JPG 误判)
  static Future<bool> isMotionPhoto(DevicePhotoModel photo) async {
    if (_motionPhotoCache.containsKey(photo.id)) {
      return _motionPhotoCache[photo.id]!;
    }

    final lowerName = photo.name.toLowerCase();
    if (lowerName.contains('motion') || lowerName.contains('mvimg') || lowerName.contains('_mp.jpg')) {
      _motionPhotoCache[photo.id] = true;
      return true;
    }

    if (photo.directBytes != null) {
      final isMotion = MotionPhotoService.isMotionPhoto(photo.directBytes!);
      _motionPhotoCache[photo.id] = isMotion;
      return isMotion;
    }

    if (photo.path.isNotEmpty) {
      try {
        final file = File(photo.path);
        if (await file.exists()) {
          final length = await file.length();
          if (length > 2048) {
            final raf = await file.open(mode: FileMode.read);

            // 1. 读取头部 256KB (探测 XMP 与图像容器特征)
            final headReadSize = length > 262144 ? 262144 : length;
            final headerBytes = await raf.read(headReadSize.toInt());

            // 2. 读取尾部 8KB (探测三星 SEFT 结构)
            final tailReadSize = length > 8192 ? 8192 : length;
            await raf.setPosition(length - tailReadSize);
            final tailBytes = await raf.read(tailReadSize.toInt());
            await raf.close();

            // A. 三星 SEFT 结构探测 (文件末尾为 'SEFT')
            if (tailBytes.length >= 4 &&
                tailBytes[tailBytes.length - 4] == 0x53 &&
                tailBytes[tailBytes.length - 3] == 0x45 &&
                tailBytes[tailBytes.length - 2] == 0x46 &&
                tailBytes[tailBytes.length - 1] == 0x54) {
              final tailStr = String.fromCharCodes(tailBytes);
              if (tailStr.contains('MotionPhoto_Data')) {
                _motionPhotoCache[photo.id] = true;
                return true;
              }
            }

            // B. XMP 动态照片元数据探测 (Google Pixel / 小米 / OPPO / vivo / Samsung)
            final headStr = utf8.decode(headerBytes, allowMalformed: true);
            final hasXmpMotionTag = headStr.contains('GCamera:MotionPhoto="1"') ||
                headStr.contains("GCamera:MotionPhoto='1'") ||
                headStr.contains('Camera:MotionPhoto="1"') ||
                headStr.contains("Camera:MotionPhoto='1'") ||
                headStr.contains('GCamera:MicroVideo="1"') ||
                headStr.contains("GCamera:MicroVideo='1'") ||
                headStr.contains('Camera:MicroVideo="1"') ||
                headStr.contains("Camera:MicroVideo='1'") ||
                headStr.contains('samsung:MotionPhoto="1"') ||
                headStr.contains('samsung:MotionPhoto_Data="1"') ||
                headStr.contains('Item:Semantic="MotionPhoto"') ||
                headStr.contains("Item:Semantic='MotionPhoto'") ||
                headStr.contains('MicroVideoOffset=') ||
                headStr.contains('<GCamera:MicroVideoOffset>');

            if (hasXmpMotionTag) {
              _motionPhotoCache[photo.id] = true;
              return true;
            }
          }
        }
      } catch (_) {}
    }

    _motionPhotoCache[photo.id] = false;
    return false;
  }

  /// 检查照片是否为 Ultra HDR (包含 Gainmap 增益图 / Apple HDR / ISO 21496-1)
  static Future<bool> isUltraHdr(DevicePhotoModel photo) async {
    final cached = _ultraHdrCache[photo.id];
    if (cached != null) return cached;

    if (photo.directBytes == null && _isAndroid) {
      final native = await UltraHdrService.checkPhotoGainmap(path: photo.path, uri: photo.uri);
      if (native != null) {
        _ultraHdrCache[photo.id] = native;
        return native;
      }
    }
    // 用完整原图统一判定；分开的头尾片段无法验证 MPF / 增益图结构。
    final bytes = await getFullPhotoBytes(photo);
    if (bytes == null || bytes.isEmpty) return false; // 读取失败不缓存，允许重试。
    final isHdr = await UltraHdrService.checkIsUltraHdr(bytes);
    _ultraHdrCache[photo.id] = isHdr;
    return isHdr;
  }

  /// 批量并发检测动态照片 (Android 原生 Snapdragon 多核并行加速 + 渐进式流式返回)
  static Future<List<DevicePhotoModel>> filterMotionPhotos(
    List<DevicePhotoModel> photos, {
    int concurrency = 16,
    void Function(List<DevicePhotoModel> partialResults)? onProgress,
  }) async {
    if (photos.isEmpty) return [];

    // 1. Android 原生 Snapdragon 多核超高速并行探测 (< 150ms)
    if (_isAndroid) {
      try {
        final List<Map<String, String>> photoArgs = photos.map((p) => {
          'id': p.id,
          'path': p.path,
        }).toList();

        final List<dynamic>? motionIdList = await _channel.invokeMethod<List<dynamic>>('scanMotionPhotos', {
          'photos': photoArgs,
        });

        if (motionIdList != null) {
          final idSet = motionIdList.map((e) => e.toString()).toSet();
          final results = <DevicePhotoModel>[];
          for (final p in photos) {
            if (idSet.contains(p.id)) {
              _motionPhotoCache[p.id] = true;
              results.add(p);
            } else {
              _motionPhotoCache[p.id] = false;
            }
          }
          onProgress?.call(results);
          return results;
        }
      } catch (e) {
        debugPrint('[DevicePhotoService] Native scanMotionPhotos error: $e');
      }
    }

    // 2. 纯 Dart 并发检测 (带渐进式回调)
    final List<DevicePhotoModel> result = [];
    for (int i = 0; i < photos.length; i += concurrency) {
      final batch = photos.skip(i).take(concurrency).toList();
      final futures = batch.map((p) async {
        final isMotion = await isMotionPhoto(p);
        return isMotion ? p : null;
      });
      final resolved = await Future.wait(futures);
      for (final item in resolved) {
        if (item != null) result.add(item);
      }
      onProgress?.call(List.from(result));
    }
    return result;
  }
}
