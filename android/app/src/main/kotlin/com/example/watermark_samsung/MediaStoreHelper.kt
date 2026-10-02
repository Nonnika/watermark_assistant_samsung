package com.example.watermark_samsung

import android.app.Activity
import android.content.ContentUris
import android.content.ContentValues
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.ImageDecoder
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Process
import android.provider.MediaStore
import android.util.Log
import android.util.Size
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.File
import java.nio.ByteBuffer
import java.util.concurrent.ExecutorService

private const val TAG_MEDIA = "UltraHDR"

/** MediaStore 相册读写：图片保存、相册查询、缩略图、原图字节、EXIF 读取与 RGBA 编码 */
class MediaStoreHelper(
    private val activity: Activity,
    private val heavyTaskExecutor: ExecutorService,
    private val thumbnailExecutor: ExecutorService
) {
    fun saveImageToGallery(call: MethodCall, result: MethodChannel.Result) {
        val bytes = call.argument<ByteArray>("bytes") ?: run {
            result.error("INVALID_ARGS", "Missing bytes", null)
            return
        }
        val filename = call.argument<String>("filename") ?: "WM_${System.currentTimeMillis()}.jpg"
        val mimeType = call.argument<String>("mimeType") ?: "image/jpeg"
        val relativePath = call.argument<String>("relativePath") ?: "Pictures/OneWatermark"

        // 保存涉及多 MB 级磁盘写入与 MediaStore 查询，移出主线程避免卡顿/ANR
        heavyTaskExecutor.execute {
            try {
                val values = ContentValues().apply {
                    put(MediaStore.Images.Media.DISPLAY_NAME, filename)
                    put(MediaStore.Images.Media.MIME_TYPE, mimeType)
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                        put(MediaStore.Images.Media.RELATIVE_PATH, relativePath)
                        put(MediaStore.Images.Media.IS_PENDING, 1)
                    }
                }

                val resolver = activity.applicationContext.contentResolver
                val uri = resolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values)

                if (uri == null) {
                    activity.runOnUiThread { result.error("SAVE_FAILED", "Failed to create MediaStore entry", null) }
                    return@execute
                }

                // 流打开失败或写入异常时删除残留条目，避免发布 0 字节图片或遗留 IS_PENDING 孤儿记录
                var writeOk = false
                try {
                    resolver.openOutputStream(uri)?.use { stream ->
                        stream.write(bytes)
                        stream.flush()
                        writeOk = true
                    } ?: run {
                        Log.e(TAG_MEDIA, "saveImageToGallery: openOutputStream returned null for $uri")
                    }
                } catch (e: Exception) {
                    Log.e(TAG_MEDIA, "saveImageToGallery write failed: ${e.message}", e)
                }

                if (!writeOk) {
                    try { resolver.delete(uri, null, null) } catch (e: Exception) {
                        Log.w(TAG_MEDIA, "Failed to delete pending entry: ${e.message}")
                    }
                    activity.runOnUiThread { result.error("SAVE_FAILED", "Failed to write image data", null) }
                    return@execute
                }

                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    values.clear()
                    values.put(MediaStore.Images.Media.IS_PENDING, 0)
                    resolver.update(uri, values, null, null)
                }

                var realFilePath: String? = null
                try {
                    val proj = arrayOf(MediaStore.Images.Media.DATA)
                    resolver.query(uri, proj, null, null, null)?.use { cursor ->
                        if (cursor.moveToFirst()) {
                            val idx = cursor.getColumnIndexOrThrow(MediaStore.Images.Media.DATA)
                            realFilePath = cursor.getString(idx)
                        }
                    }
                } catch (e: Exception) {
                    Log.w(TAG_MEDIA, "Could not resolve DATA path: ${e.message}")
                }

                val scanPath = realFilePath ?: "/storage/emulated/0/$relativePath/$filename"
                MediaScannerConnection.scanFile(
                    activity.applicationContext,
                    arrayOf(scanPath),
                    arrayOf(mimeType)
                ) { path, scannedUri ->
                    Log.d(TAG_MEDIA, "MediaScanner finished: $path -> $scannedUri")
                }

                Log.d(TAG_MEDIA, "Saved image to MediaStore: $uri ($filename) at $scanPath")
                activity.runOnUiThread { result.success(uri.toString()) }
            } catch (e: Exception) {
                Log.e(TAG_MEDIA, "saveImageToGallery FAILED: ${e.message}", e)
                activity.runOnUiThread { result.error("SAVE_FAILED", e.localizedMessage, null) }
            }
        }
    }

    fun getRecentPhotos(call: MethodCall, result: MethodChannel.Result) {
        val limit = call.argument<Int>("limit") ?: 0
        heavyTaskExecutor.execute {
            Process.setThreadPriority(Process.THREAD_PRIORITY_BACKGROUND)
            val projection = arrayOf(
                MediaStore.Images.Media._ID,
                MediaStore.Images.Media.DISPLAY_NAME,
                MediaStore.Images.Media.DATA,
                MediaStore.Images.Media.SIZE,
                MediaStore.Images.Media.DATE_ADDED,
                MediaStore.Images.Media.DATE_MODIFIED,
                MediaStore.Images.Media.WIDTH,
                MediaStore.Images.Media.HEIGHT,
                MediaStore.Images.Media.MIME_TYPE
            )
            val selection = "${MediaStore.Images.Media.SIZE} > 0"
            val sortOrder = "${MediaStore.Images.Media.DATE_ADDED} DESC, ${MediaStore.Images.Media._ID} DESC"
            val photoList = mutableListOf<Map<String, Any?>>()

            try {
                val collection = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL)
                } else {
                    MediaStore.Images.Media.EXTERNAL_CONTENT_URI
                }

                val cursor = activity.contentResolver.query(
                    collection,
                    projection,
                    selection,
                    null,
                    sortOrder
                )
                cursor?.use {
                    val idCol = it.getColumnIndexOrThrow(MediaStore.Images.Media._ID)
                    val nameCol = it.getColumnIndex(MediaStore.Images.Media.DISPLAY_NAME)
                    val dataCol = it.getColumnIndex(MediaStore.Images.Media.DATA)
                    val sizeCol = it.getColumnIndexOrThrow(MediaStore.Images.Media.SIZE)
                    val dateAddedCol = it.getColumnIndex(MediaStore.Images.Media.DATE_ADDED)
                    val dateModCol = it.getColumnIndex(MediaStore.Images.Media.DATE_MODIFIED)
                    val widthCol = it.getColumnIndex(MediaStore.Images.Media.WIDTH)
                    val heightCol = it.getColumnIndex(MediaStore.Images.Media.HEIGHT)
                    val mimeCol = it.getColumnIndex(MediaStore.Images.Media.MIME_TYPE)

                    var count = 0
                    while (it.moveToNext()) {
                        if (limit > 0 && count >= limit) break
                        val id = it.getLong(idCol)
                        val name = if (nameCol >= 0) it.getString(nameCol) ?: "IMG_$id" else "IMG_$id"
                        val path = if (dataCol >= 0) it.getString(dataCol) ?: "" else ""
                        val size = it.getLong(sizeCol)
                        val dateAdded = if (dateAddedCol >= 0) it.getLong(dateAddedCol) else 0L
                        val dateMod = if (dateModCol >= 0) it.getLong(dateModCol) else 0L
                        val effectiveDate = if (dateAdded > 0) dateAdded else dateMod
                        val width = if (widthCol >= 0) it.getInt(widthCol) else 0
                        val height = if (heightCol >= 0) it.getInt(heightCol) else 0
                        val mimeType = if (mimeCol >= 0) it.getString(mimeCol) ?: "image/jpeg" else "image/jpeg"
                        val contentUri = ContentUris.withAppendedId(collection, id).toString()

                        photoList.add(mapOf(
                            "id" to id.toString(),
                            "name" to name,
                            "path" to path,
                            "uri" to contentUri,
                            "size" to size,
                            "dateAdded" to effectiveDate,
                            "dateModified" to dateMod,
                            "width" to width,
                            "height" to height,
                            "mimeType" to mimeType
                        ))
                        count++
                    }
                }
                activity.runOnUiThread { result.success(photoList) }
            } catch (e: Exception) {
                Log.e(TAG_MEDIA, "getRecentPhotos error: ${e.message}", e)
                activity.runOnUiThread { result.error("QUERY_FAILED", e.localizedMessage, null) }
            }
        }
    }

    fun scanMotionPhotos(call: MethodCall, result: MethodChannel.Result) {
        val photos = call.argument<List<Map<String, Any>>>("photos") ?: emptyList()
        heavyTaskExecutor.execute {
            Process.setThreadPriority(Process.THREAD_PRIORITY_BACKGROUND)
            val motionIds = java.util.concurrent.ConcurrentHashMap.newKeySet<String>()
            photos.parallelStream().forEach { item ->
                val id = item["id"]?.toString() ?: ""
                val path = item["path"]?.toString() ?: ""
                if (id.isNotEmpty() && path.isNotEmpty()) {
                    if (SefTrailerCodec.checkIsMotionPhotoFile(path)) {
                        motionIds.add(id)
                    }
                }
            }
            val resultList = motionIds.toList()
            activity.runOnUiThread { result.success(resultList) }
        }
    }

    fun getPhotoThumbnail(call: MethodCall, result: MethodChannel.Result) {
        val idStr = call.argument<String>("id")
        val path = call.argument<String>("path")
        val uriStr = call.argument<String>("uri")
        val targetWidth = (call.argument<Int>("width") ?: 256).coerceIn(1, 2048)
        val targetHeight = (call.argument<Int>("height") ?: 256).coerceIn(1, 2048)

        // 在后台专用线程池执行位图解码, 降低线程优先级, 杜绝抢占 UI/Raster 渲染核心
        thumbnailExecutor.execute {
            Process.setThreadPriority(Process.THREAD_PRIORITY_BACKGROUND)
            var thumbBitmap: Bitmap? = null
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    val uri = if (!uriStr.isNullOrEmpty()) {
                        Uri.parse(uriStr)
                    } else idStr?.toLongOrNull()?.let { id ->
                        val collection = MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL)
                        ContentUris.withAppendedId(collection, id)
                    }
                    if (uri != null) {
                        try {
                            thumbBitmap = activity.contentResolver.loadThumbnail(uri, Size(targetWidth, targetHeight), null)
                        } catch (e: Exception) {
                            Log.w(TAG_MEDIA, "loadThumbnail failed: ${e.message}")
                        }
                    }
                }

                // ImageDecoder applies EXIF orientation and downsamples before
                // allocating pixels, including HEIC and very tall panoramas.
                if (thumbBitmap == null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                    try {
                        val source = when {
                            !uriStr.isNullOrEmpty() -> ImageDecoder.createSource(activity.contentResolver, Uri.parse(uriStr))
                            !path.isNullOrEmpty() -> ImageDecoder.createSource(File(path))
                            else -> null
                        }
                        if (source != null) {
                            thumbBitmap = ImageDecoder.decodeBitmap(source) { decoder, info, _ ->
                                val scale = minOf(1.0, targetWidth.toDouble() / info.size.width,
                                    targetHeight.toDouble() / info.size.height)
                                decoder.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
                                decoder.setTargetSize(
                                    (info.size.width * scale).toInt().coerceAtLeast(1),
                                    (info.size.height * scale).toInt().coerceAtLeast(1)
                                )
                            }
                        }
                    } catch (e: Exception) {
                        Log.w(TAG_MEDIA, "ImageDecoder thumbnail failed: ${e.message}")
                    }
                }

                if (thumbBitmap == null && path != null && path.isNotEmpty()) {
                    val file = File(path)
                    if (file.exists()) {
                        val options = BitmapFactory.Options().apply {
                            inJustDecodeBounds = true
                        }
                        BitmapFactory.decodeFile(path, options)
                        var inSampleSize = 1
                        if (options.outHeight > targetHeight || options.outWidth > targetWidth) {
                            val halfHeight = options.outHeight / 2
                            val halfWidth = options.outWidth / 2
                            while ((halfHeight / inSampleSize) >= targetHeight || (halfWidth / inSampleSize) >= targetWidth) {
                                inSampleSize *= 2
                            }
                        }
                        val decodeOptions = BitmapFactory.Options().apply {
                            this.inSampleSize = inSampleSize
                            // 使用 RGB_565 节省内存 (缩略图不需要 alpha)
                            inPreferredConfig = Bitmap.Config.RGB_565
                        }
                        thumbBitmap = BitmapFactory.decodeFile(path, decodeOptions)
                    }
                }

                if (thumbBitmap != null) {
                    val bitmap = thumbBitmap!!
                    val scale = minOf(1.0, targetWidth.toDouble() / bitmap.width,
                        targetHeight.toDouble() / bitmap.height)
                    if (scale < 1.0) {
                        thumbBitmap = Bitmap.createScaledBitmap(bitmap,
                            (bitmap.width * scale).toInt().coerceAtLeast(1),
                            (bitmap.height * scale).toInt().coerceAtLeast(1), true)
                        if (thumbBitmap !== bitmap) bitmap.recycle()
                    }
                    val stream = ByteArrayOutputStream()
                    thumbBitmap!!.compress(Bitmap.CompressFormat.JPEG, 75, stream)
                    val bytes = stream.toByteArray()
                    activity.runOnUiThread { result.success(bytes) }
                } else {
                    activity.runOnUiThread { result.success(null) }
                }
            } catch (e: Exception) {
                Log.e(TAG_MEDIA, "getPhotoThumbnail error: ${e.message}", e)
                activity.runOnUiThread { result.success(null) }
            } finally {
                thumbBitmap?.recycle()
            }
        }
    }

    fun getPhotoBytes(call: MethodCall, result: MethodChannel.Result) {
        val path = call.argument<String>("path")
        val uriStr = call.argument<String>("uri")
        // 高通 SoC 优化：大文件读取移出主线程，避免阻塞 UI / Raster
        heavyTaskExecutor.execute {
            Process.setThreadPriority(Process.THREAD_PRIORITY_LESS_FAVORABLE)
            try {
                var bytes: ByteArray? = null
                if (path != null && path.isNotEmpty()) {
                    try {
                        val file = File(path)
                        if (file.exists() && file.canRead()) {
                            bytes = file.readBytes()
                        }
                    } catch (_: Exception) {}
                }
                if (bytes == null && uriStr != null && uriStr.isNotEmpty()) {
                    try {
                        val uri = Uri.parse(uriStr)
                        activity.contentResolver.openInputStream(uri)?.use { stream ->
                            bytes = stream.readBytes()
                        }
                    } catch (_: Exception) {}
                }
                val finalResultBytes = bytes
                if (finalResultBytes != null && finalResultBytes.isNotEmpty()) {
                    activity.runOnUiThread { result.success(finalResultBytes) }
                } else {
                    activity.runOnUiThread { result.error("FILE_NOT_FOUND", "Could not read file from path ($path) or uri ($uriStr)", null) }
                }
            } catch (e: Exception) {
                Log.e(TAG_MEDIA, "getPhotoBytes error: ${e.message}", e)
                activity.runOnUiThread { result.error("READ_FAILED", e.localizedMessage, null) }
            }
        }
    }

    fun getExif(call: MethodCall, result: MethodChannel.Result) {
        // EXIF 解析伴随文件 IO 与全量元数据读取，移出主线程
        heavyTaskExecutor.execute {
            try {
                val bytes = call.argument<ByteArray>("bytes")
                val path = call.argument<String>("path")
                val uriStr = call.argument<String>("uri")

                var exifInterface: android.media.ExifInterface? = null

                if (bytes != null && bytes.isNotEmpty()) {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                        try {
                            exifInterface = android.media.ExifInterface(ByteArrayInputStream(bytes))
                        } catch (e: Exception) {
                            Log.w(TAG_MEDIA, "ExifInterface from bytes failed: ${e.message}")
                        }
                    }
                }

                if (exifInterface == null && path != null && path.isNotEmpty() && File(path).exists()) {
                    try {
                        exifInterface = android.media.ExifInterface(path)
                    } catch (e: Exception) {
                        Log.w(TAG_MEDIA, "ExifInterface from path failed: ${e.message}")
                    }
                }

                if (exifInterface == null && uriStr != null && uriStr.isNotEmpty()) {
                    try {
                        val uri = Uri.parse(uriStr)
                        val pfd = activity.contentResolver.openFileDescriptor(uri, "r")
                        if (pfd != null) {
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                                exifInterface = android.media.ExifInterface(pfd.fileDescriptor)
                            }
                            pfd.close()
                        }
                    } catch (e: Exception) {
                        Log.w(TAG_MEDIA, "ExifInterface from uri failed: ${e.message}")
                    }
                }

                if (exifInterface != null) {
                    val make = exifInterface.getAttribute(android.media.ExifInterface.TAG_MAKE) ?: ""
                    val model = exifInterface.getAttribute(android.media.ExifInterface.TAG_MODEL) ?: ""
                    val fNumber = exifInterface.getAttribute(android.media.ExifInterface.TAG_F_NUMBER) ?: ""
                    val focalLength = exifInterface.getAttribute(android.media.ExifInterface.TAG_FOCAL_LENGTH) ?: ""
                    val focal35 = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                        exifInterface.getAttribute(android.media.ExifInterface.TAG_FOCAL_LENGTH_IN_35MM_FILM) ?: ""
                    } else ""
                    val exposureTime = exifInterface.getAttribute(android.media.ExifInterface.TAG_EXPOSURE_TIME) ?: ""
                    val shutterSpeed = (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) exifInterface.getAttribute(android.media.ExifInterface.TAG_SHUTTER_SPEED_VALUE) else null)
                        ?: exifInterface.getAttribute("ShutterSpeedValue")
                        ?: ""
                    val iso = exifInterface.getAttribute(android.media.ExifInterface.TAG_ISO_SPEED_RATINGS)
                        ?: exifInterface.getAttribute("PhotographicSensitivity")
                        ?: exifInterface.getAttribute("ISO")
                        ?: ""
                    val dateTime = (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) exifInterface.getAttribute(android.media.ExifInterface.TAG_DATETIME_ORIGINAL) else null)
                        ?: (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) exifInterface.getAttribute(android.media.ExifInterface.TAG_DATETIME_DIGITIZED) else null)
                        ?: exifInterface.getAttribute(android.media.ExifInterface.TAG_DATETIME)
                        ?: ""

                    val map = mapOf(
                        "make" to make,
                        "model" to model,
                        "fNumber" to fNumber,
                        "focalLength" to focalLength,
                        "focalLengthIn35mm" to focal35,
                        "exposureTime" to exposureTime,
                        "shutterSpeedValue" to shutterSpeed,
                        "iso" to iso,
                        "dateTime" to dateTime,
                    )
                    result.let { r -> activity.runOnUiThread { r.success(map) } }
                } else {
                    result.let { r -> activity.runOnUiThread { r.success(null) } }
                }
            } catch (e: Exception) {
                Log.e(TAG_MEDIA, "getExif error: ${e.message}", e)
                result.let { r -> activity.runOnUiThread { r.success(null) } }
            }
        }
    }

    fun compressRgbaToJpeg(call: MethodCall, result: MethodChannel.Result) {
        val rgbaBytes = call.argument<ByteArray>("rgba")
        val width = call.argument<Int>("width") ?: 0
        val height = call.argument<Int>("height") ?: 0
        val quality = call.argument<Int>("quality") ?: 95

        if (rgbaBytes == null || width <= 0 || height <= 0) {
            result.error("INVALID_ARGS", "Missing RGBA data", null)
            return
        }

        // 高通 SoC 优化：全尺寸位图编码移出主线程，ADPF 提速 + Snapdragon 硬件编解码管线
        heavyTaskExecutor.execute {
            Process.setThreadPriority(Process.THREAD_PRIORITY_LESS_FAVORABLE)
            try {
                val jpeg = activity.runWithAdpfBoost(150L) {
                    val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
                    val buffer = ByteBuffer.wrap(rgbaBytes)
                    bitmap.copyPixelsFromBuffer(buffer)

                    val baos = ByteArrayOutputStream(rgbaBytes.size / 5)
                    bitmap.compress(Bitmap.CompressFormat.JPEG, quality, baos)
                    bitmap.recycle()
                    baos.toByteArray()
                }
                activity.runOnUiThread { result.success(jpeg) }
            } catch (e: Exception) {
                Log.e(TAG_MEDIA, "compressRgbaToJpeg error: ${e.message}", e)
                activity.runOnUiThread { result.error("ENCODE_FAILED", e.localizedMessage, null) }
            }
        }
    }
}
