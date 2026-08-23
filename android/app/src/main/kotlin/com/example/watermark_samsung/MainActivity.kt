package com.example.watermark_samsung

import android.Manifest
import android.content.ContentUris
import android.content.ContentValues
import android.content.Intent
import android.content.pm.ActivityInfo
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Gainmap
import android.graphics.ImageDecoder
import android.graphics.Paint
import android.graphics.Rect
import android.graphics.RectF
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaCodecList
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMetadataRetriever
import android.media.MediaMuxer
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.PerformanceHintManager
import android.os.Process
import android.os.SystemClock
import android.provider.MediaStore
import android.provider.Settings
import android.util.Log
import android.util.Size
import androidx.annotation.NonNull
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.InputStream
import java.nio.ByteBuffer
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.watermark_samsung/ultra_hdr"
    private val TAG = "UltraHDR"
    private val REQUEST_STORAGE_PERMISSION_CODE = 1001
    private var pendingPermissionResult: MethodChannel.Result? = null

    // 高通 Snapdragon 优化的后台缩略图解码线程池 (固定 4 线程，杜绝并发开辟裸线程抢占 UI / Raster 核心)
    private val thumbnailExecutor: ExecutorService = Executors.newFixedThreadPool(4) { runnable ->
        Thread(runnable).apply {
            priority = Thread.MIN_PRIORITY
            isDaemon = true
        }
    }

    // 高通 Snapdragon 优化：重负载任务 (全分辨率 Ultra HDR 合成 / JPEG 硬件编码) 专用线程池，
    // 按大核数量配置并发度，默认调度优先级以充分利用 Snapdragon Prime/Big 核心算力
    private val heavyTaskExecutor: ExecutorService = Executors.newFixedThreadPool(
        Runtime.getRuntime().availableProcessors().coerceIn(2, 6)
    ) { runnable ->
        Thread(runnable).apply {
            isDaemon = true
        }
    }

    override fun onDestroy() {
        thumbnailExecutor.shutdown()
        heavyTaskExecutor.shutdown()
        super.onDestroy()
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableHdrMode(true)
    }

    private fun enableHdrMode(enable: Boolean) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            window.colorMode = if (enable) ActivityInfo.COLOR_MODE_HDR else ActivityInfo.COLOR_MODE_DEFAULT
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            window.colorMode = if (enable) ActivityInfo.COLOR_MODE_WIDE_COLOR_GAMUT else ActivityInfo.COLOR_MODE_DEFAULT
        }
    }

    /**
     * 高通 Snapdragon ADPF (Android Dynamic Performance Framework) CPU 提速封装。
     *
     * 通过 PerformanceHintManager 创建 Hint Session，向调度器声明当前线程的预期工作时长，
     * 使 Snapdragon 的调度策略优先将本任务放置在 Prime/Big (Gold/Prime) 核心并提升频点，
     * 显著缩短全分辨率图像解码、Gainmap 合成与 JPEG 硬件编码的墙钟时间。
     * 在不支持 ADPF 的设备上静默退化为直接执行。
     */
    private inline fun <T> runWithAdpfBoost(targetDurationMs: Long, block: () -> T): T {
        var session: PerformanceHintManager.Session? = null
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            try {
                val manager = getSystemService(PERFORMANCE_HINT_SERVICE) as PerformanceHintManager
                session = manager.createHintSession(
                    intArrayOf(Process.myTid()),
                    targetDurationMs * 1_000_000L
                )
                session?.updateTargetWorkDuration(targetDurationMs * 1_000_000L)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                    session?.setPreferPowerEfficiency(false) // 明确偏好峰值性能而非省电
                }
            } catch (_: Throwable) {}
        }
        val startNs = SystemClock.elapsedRealtimeNanos()
        try {
            return block()
        } finally {
            try { session?.reportActualWorkDuration(SystemClock.elapsedRealtimeNanos() - startNs) } catch (_: Throwable) {}
            try { session?.close() } catch (_: Throwable) {}
        }
    }

    private fun checkStoragePermission(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            ContextCompat.checkSelfPermission(this, Manifest.permission.READ_MEDIA_IMAGES) == PackageManager.PERMISSION_GRANTED ||
            ContextCompat.checkSelfPermission(this, Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED) == PackageManager.PERMISSION_GRANTED
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            ContextCompat.checkSelfPermission(this, Manifest.permission.READ_MEDIA_IMAGES) == PackageManager.PERMISSION_GRANTED
        } else {
            ContextCompat.checkSelfPermission(this, Manifest.permission.READ_EXTERNAL_STORAGE) == PackageManager.PERMISSION_GRANTED
        }
    }

    private fun requestStoragePermission(result: MethodChannel.Result) {
        if (checkStoragePermission()) {
            result.success(true)
            return
        }
        val permissions = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            arrayOf(
                Manifest.permission.READ_MEDIA_IMAGES,
                Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED
            )
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            arrayOf(Manifest.permission.READ_MEDIA_IMAGES)
        } else {
            arrayOf(Manifest.permission.READ_EXTERNAL_STORAGE)
        }
        pendingPermissionResult = result
        ActivityCompat.requestPermissions(this, permissions, REQUEST_STORAGE_PERMISSION_CODE)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQUEST_STORAGE_PERMISSION_CODE) {
            val granted = grantResults.isNotEmpty() && grantResults.all { it == PackageManager.PERMISSION_GRANTED }
            pendingPermissionResult?.success(granted)
            pendingPermissionResult = null
        }
    }

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "checkStoragePermission" -> {
                    result.success(checkStoragePermission())
                }
                "requestStoragePermission" -> {
                    requestStoragePermission(result)
                }
                "openAppSettings" -> {
                    try {
                        val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                            data = Uri.fromParts("package", packageName, null)
                            flags = Intent.FLAG_ACTIVITY_NEW_TASK
                        }
                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                "isUltraHdrSupported" -> {
                    result.success(Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE)
                }
                "isHdrDisplaySupported" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        result.success(display?.isHdr == true)
                    } else {
                        result.success(false)
                    }
                }
                "getHdrSdrRatio" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                        val ratio = display?.hdrSdrRatio ?: 1.0f
                        result.success(ratio.toDouble())
                    } else {
                        result.success(1.0)
                    }
                }
                "setHdrDisplayMode" -> {
                    val enable = call.argument<Boolean>("enable") ?: true
                    enableHdrMode(enable)
                    result.success(true)
                }
                "hasGainmap" -> {
                    val bytes = call.argument<ByteArray>("bytes")
                    if (bytes != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                        // 高通 SoC 优化：Gainmap 探测需要完整解码原图，移出主线程并启用 ADPF 提速
                        heavyTaskExecutor.execute {
                            Process.setThreadPriority(Process.THREAD_PRIORITY_LESS_FAVORABLE)
                            val has = runWithAdpfBoost(50L) {
                                try {
                                    val source = ImageDecoder.createSource(ByteBuffer.wrap(bytes))
                                    val bitmap = ImageDecoder.decodeBitmap(source) { _, _, _ -> }
                                    val has = bitmap.hasGainmap()
                                    Log.d(TAG, "hasGainmap: $has, bitmap=${bitmap.width}x${bitmap.height}, config=${bitmap.config}")
                                    bitmap.recycle()
                                    has
                                } catch (e: Exception) {
                                    Log.e(TAG, "hasGainmap ImageDecoder failed: ${e.message}, trying BitmapFactory")
                                    try {
                                        val bitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
                                        val has = bitmap?.hasGainmap() == true
                                        Log.d(TAG, "hasGainmap (BitmapFactory fallback): $has")
                                        bitmap?.recycle()
                                        has
                                    } catch (e2: Exception) {
                                        Log.e(TAG, "hasGainmap BitmapFactory also failed: ${e2.message}")
                                        false
                                    }
                                }
                            }
                            runOnUiThread { result.success(has) }
                        }
                    } else {
                        result.success(false)
                    }
                }
                "getUltraHdrGainmap" -> {
                    val bytes = call.argument<ByteArray>("bytes")
                    if (bytes != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                        heavyTaskExecutor.execute {
                            Process.setThreadPriority(Process.THREAD_PRIORITY_LESS_FAVORABLE)
                            try {
                                val source = ImageDecoder.createSource(ByteBuffer.wrap(bytes))
                                val bitmap = ImageDecoder.decodeBitmap(source) { _, _, _ -> }
                                if (bitmap.hasGainmap()) {
                                    val gainmap = bitmap.gainmap!!
                                    val gmContentRaw = gainmap.gainmapContents
                                    val gmContent = if (gmContentRaw.config == Bitmap.Config.HARDWARE) {
                                        gmContentRaw.copy(Bitmap.Config.ARGB_8888, false)
                                    } else {
                                        gmContentRaw
                                    }
                                    val stream = ByteArrayOutputStream()
                                    gmContent.compress(Bitmap.CompressFormat.JPEG, 92, stream)
                                    val gmJpeg = stream.toByteArray()
                                    if (gmContent !== gmContentRaw) {
                                        gmContent.recycle()
                                    }
                                    bitmap.recycle()

                                    val rMin = gainmap.ratioMin
                                    val rMax = gainmap.ratioMax
                                    val gam = gainmap.gamma
                                    val eSdr = gainmap.epsilonSdr
                                    val eHdr = gainmap.epsilonHdr

                                    val resultMap = mapOf(
                                        "gainmapJpeg" to gmJpeg,
                                        "gainMapMin" to (rMin.getOrNull(0)?.toDouble() ?: 0.0),
                                        "gainMapMax" to (rMax.getOrNull(0)?.toDouble() ?: 2.0),
                                        "gamma" to (gam.getOrNull(0)?.toDouble() ?: 1.0),
                                        "offsetSdr" to (eSdr.getOrNull(0)?.toDouble() ?: 0.015625),
                                        "offsetHdr" to (eHdr.getOrNull(0)?.toDouble() ?: 0.015625),
                                        "displayRatioForFullHdr" to gainmap.displayRatioForFullHdr.toDouble(),
                                        "minDisplayRatioForHdrTransition" to gainmap.minDisplayRatioForHdrTransition.toDouble()
                                    )
                                    runOnUiThread { result.success(resultMap) }
                                    return@execute
                                }
                                bitmap.recycle()
                                runOnUiThread { result.success(null) }
                            } catch (e: Exception) {
                                Log.w(TAG, "getUltraHdrGainmap error: ${e.message}")
                                runOnUiThread { result.success(null) }
                            }
                        }
                    } else {
                        result.success(null)
                    }
                }
                "processUltraHdrImage" -> {
                    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                        result.error("UNSUPPORTED", "Ultra HDR requires Android 14+", null)
                        return@setMethodCallHandler
                    }

                    val originalBytes = call.argument<ByteArray>("originalBytes") ?: run {
                        result.error("INVALID_ARGS", "Missing originalBytes", null)
                        return@setMethodCallHandler
                    }
                    val sdrCompositeBytes = call.argument<ByteArray>("sdrCompositeBytes") ?: run {
                        result.error("INVALID_ARGS", "Missing sdrCompositeBytes", null)
                        return@setMethodCallHandler
                    }
                    val photoLeft = (call.argument<Double>("photoLeft") ?: 0.0).toFloat()
                    val photoTop = (call.argument<Double>("photoTop") ?: 0.0).toFloat()
                    val photoWidth = (call.argument<Double>("photoWidth") ?: 0.0).toFloat()
                    val photoHeight = (call.argument<Double>("photoHeight") ?: 0.0).toFloat()
                    val totalWidth = (call.argument<Double>("totalWidth") ?: 0.0).toFloat()
                    val totalHeight = (call.argument<Double>("totalHeight") ?: 0.0).toFloat()
                    val quality = call.argument<Int>("quality") ?: 95

                    Log.d(TAG, "processUltraHdrImage: origBytes=${originalBytes.size}, sdrBytes=${sdrCompositeBytes.size}")
                    Log.d(TAG, "  photo: left=$photoLeft top=$photoTop w=$photoWidth h=$photoHeight")
                    Log.d(TAG, "  total: w=$totalWidth h=$totalHeight quality=$quality")

                    // 高通 SoC 优化：全分辨率解码 + Gainmap 合成 + JPEG 编码全部移出主线程，
                    // 并通过 ADPF Hint Session 调度至 Snapdragon Prime/Big 核心满频运行
                    heavyTaskExecutor.execute {
                        Process.setThreadPriority(Process.THREAD_PRIORITY_LESS_FAVORABLE)
                        try {
                            val outputBytes = runWithAdpfBoost(300L) processUltraHdr@{
                                // 1. 用 ImageDecoder 解码原图
                                val origSource = ImageDecoder.createSource(ByteBuffer.wrap(originalBytes))
                                val origBitmap = ImageDecoder.decodeBitmap(origSource) { _, _, _ -> }
                                Log.d(TAG, "  origBitmap: ${origBitmap.width}x${origBitmap.height}, config=${origBitmap.config}, hasGainmap=${origBitmap.hasGainmap()}")

                                if (!origBitmap.hasGainmap()) {
                                    Log.w(TAG, "  Original image has NO gainmap! Cannot produce Ultra HDR.")
                                    origBitmap.recycle()
                                    return@processUltraHdr sdrCompositeBytes
                                }

                                val originalGainmap = origBitmap.gainmap!!
                                val origGmContentsRaw = originalGainmap.gainmapContents
                                val origGmContents = if (origGmContentsRaw.config == Bitmap.Config.HARDWARE) {
                                    origGmContentsRaw.copy(Bitmap.Config.ARGB_8888, false)
                                } else {
                                    origGmContentsRaw
                                }
                                Log.d(TAG, "  originalGainmap: contents=${origGmContents.width}x${origGmContents.height}, config=${origGmContents.config}")
                                Log.d(TAG, "  displayRatioForFullHdr=${originalGainmap.displayRatioForFullHdr}")
                                Log.d(TAG, "  ratioMin=${originalGainmap.ratioMin.toList()}")
                                Log.d(TAG, "  ratioMax=${originalGainmap.ratioMax.toList()}")
                                Log.d(TAG, "  gamma=${originalGainmap.gamma.toList()}")

                                // 2. 解码 SDR 合成图并确保可变
                                val sdrBitmapRaw = BitmapFactory.decodeByteArray(sdrCompositeBytes, 0, sdrCompositeBytes.size)
                                val sdrBitmap = sdrBitmapRaw.copy(Bitmap.Config.ARGB_8888, true)
                                sdrBitmapRaw.recycle()
                                Log.d(TAG, "  sdrBitmap: ${sdrBitmap.width}x${sdrBitmap.height}, isMutable=${sdrBitmap.isMutable}")

                                // 3. 构建与合成画幅对齐的新 Gainmap
                                val targetGmWidth = origGmContents.width.coerceIn(256, 4096)
                                val ratio = totalHeight / totalWidth
                                val targetGmHeight = (targetGmWidth * ratio).toInt().coerceIn(256, 4096)
                                Log.d(TAG, "  targetGainmap: ${targetGmWidth}x${targetGmHeight}")

                                val newGmBitmap = Bitmap.createBitmap(targetGmWidth, targetGmHeight, Bitmap.Config.ARGB_8888)
                                val gmCanvas = Canvas(newGmBitmap)
                                gmCanvas.drawColor(Color.BLACK)

                                val scaleX = targetGmWidth.toFloat() / totalWidth
                                val scaleY = targetGmHeight.toFloat() / totalHeight
                                val dstRect = RectF(
                                    photoLeft * scaleX,
                                    photoTop * scaleY,
                                    (photoLeft + photoWidth) * scaleX,
                                    (photoTop + photoHeight) * scaleY
                                )
                                val srcRect = Rect(0, 0, origGmContents.width, origGmContents.height)
                                gmCanvas.drawBitmap(origGmContents, srcRect, dstRect, Paint(Paint.FILTER_BITMAP_FLAG))
                                Log.d(TAG, "  drew gainmap from src=$srcRect to dst=$dstRect")

                                if (origGmContents !== origGmContentsRaw) {
                                    origGmContents.recycle()
                                }

                                // 4. 创建新 Gainmap 并复制所有元数据
                                val newGainmap = Gainmap(newGmBitmap)
                                newGainmap.displayRatioForFullHdr = originalGainmap.displayRatioForFullHdr
                                newGainmap.minDisplayRatioForHdrTransition = originalGainmap.minDisplayRatioForHdrTransition
                                val rMin = originalGainmap.ratioMin
                                newGainmap.setRatioMin(rMin[0], rMin[1], rMin[2])
                                val rMax = originalGainmap.ratioMax
                                newGainmap.setRatioMax(rMax[0], rMax[1], rMax[2])
                                val gam = originalGainmap.gamma
                                newGainmap.setGamma(gam[0], gam[1], gam[2])
                                val eSdr = originalGainmap.epsilonSdr
                                newGainmap.setEpsilonSdr(eSdr[0], eSdr[1], eSdr[2])
                                val eHdr = originalGainmap.epsilonHdr
                                newGainmap.setEpsilonHdr(eHdr[0], eHdr[1], eHdr[2])

                                // 5. 挂载 Gainmap
                                sdrBitmap.gainmap = newGainmap
                                Log.d(TAG, "  sdrBitmap after attach: hasGainmap=${sdrBitmap.hasGainmap()}")

                                // 6. 压缩为 JPEG
                                val stream = ByteArrayOutputStream()
                                val compressSuccess = sdrBitmap.compress(Bitmap.CompressFormat.JPEG, quality, stream)
                                var outputBytes = stream.toByteArray()
                                Log.d(TAG, "  compressed output (success=$compressSuccess): ${outputBytes.size} bytes")

                                // 7. 注入/保留原图 EXIF 元数据
                                try {
                                    val tempFile = File.createTempFile("uhdr_export_", ".jpg", cacheDir)
                                    tempFile.writeBytes(outputBytes)

                                    val origExif = android.media.ExifInterface(ByteArrayInputStream(originalBytes))
                                    val destExif = android.media.ExifInterface(tempFile.absolutePath)

                                    val standardTags = arrayOf(
                                        android.media.ExifInterface.TAG_MAKE,
                                        android.media.ExifInterface.TAG_MODEL,
                                        android.media.ExifInterface.TAG_F_NUMBER,
                                        android.media.ExifInterface.TAG_DATETIME,
                                        android.media.ExifInterface.TAG_EXPOSURE_TIME,
                                        android.media.ExifInterface.TAG_FLASH,
                                        android.media.ExifInterface.TAG_FOCAL_LENGTH,
                                        android.media.ExifInterface.TAG_GPS_ALTITUDE,
                                        android.media.ExifInterface.TAG_GPS_ALTITUDE_REF,
                                        android.media.ExifInterface.TAG_GPS_DATESTAMP,
                                        android.media.ExifInterface.TAG_GPS_LATITUDE,
                                        android.media.ExifInterface.TAG_GPS_LATITUDE_REF,
                                        android.media.ExifInterface.TAG_GPS_LONGITUDE,
                                        android.media.ExifInterface.TAG_GPS_LONGITUDE_REF,
                                        android.media.ExifInterface.TAG_GPS_PROCESSING_METHOD,
                                        android.media.ExifInterface.TAG_GPS_TIMESTAMP,
                                        android.media.ExifInterface.TAG_ISO_SPEED_RATINGS,
                                        android.media.ExifInterface.TAG_WHITE_BALANCE
                                    )
                                    for (tag in standardTags) {
                                        val v = origExif.getAttribute(tag)
                                        if (v != null) destExif.setAttribute(tag, v)
                                    }
                                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                                        val extendedTags = arrayOf(
                                            android.media.ExifInterface.TAG_DATETIME_ORIGINAL,
                                            android.media.ExifInterface.TAG_DATETIME_DIGITIZED,
                                            android.media.ExifInterface.TAG_FOCAL_LENGTH_IN_35MM_FILM,
                                            "OffsetTime",
                                            "OffsetTimeOriginal",
                                            "OffsetTimeDigitized",
                                            android.media.ExifInterface.TAG_SUBSEC_TIME,
                                            android.media.ExifInterface.TAG_SUBSEC_TIME_ORIGINAL,
                                            android.media.ExifInterface.TAG_SUBSEC_TIME_DIGITIZED,
                                            "ExposureProgram",
                                            "MeteringMode",
                                            "LensMake",
                                            "LensModel",
                                            "LensSpecification",
                                            "ShutterSpeedValue",
                                            "ApertureValue",
                                            "BrightnessValue",
                                            "ExposureBiasValue"
                                        )
                                        for (tag in extendedTags) {
                                            val v = origExif.getAttribute(tag)
                                            if (v != null) destExif.setAttribute(tag, v)
                                        }
                                    }
                                    // 像素已在 Canvas 中归一化为正向，重置 Orientation 为 1 (正常朝向)
                                    destExif.setAttribute(android.media.ExifInterface.TAG_ORIENTATION, "1")
                                    destExif.saveAttributes()
                                    outputBytes = tempFile.readBytes()
                                    tempFile.delete()
                                } catch (exifErr: Exception) {
                                    Log.w(TAG, "Exif preservation in JPEG failed: ${exifErr.message}")
                                }

                                // 8. 严格验证输出是否包含 Gainmap
                                val verifySource = ImageDecoder.createSource(ByteBuffer.wrap(outputBytes))
                                val verifyBitmap = ImageDecoder.decodeBitmap(verifySource) { _, _, _ -> }
                                val outputHasGainmap = verifyBitmap.hasGainmap()
                                verifyBitmap.recycle()
                                Log.d(TAG, "  OUTPUT VERIFICATION: hasGainmap=$outputHasGainmap")

                                origBitmap.recycle()
                                sdrBitmap.recycle()

                                if (!outputHasGainmap) {
                                    Log.w(TAG, "  Native output has no gainmap; returning null to allow Dart Ultra HDR synthesis")
                                    return@processUltraHdr null
                                }

                                outputBytes
                            }
                            result.success(outputBytes)
                        } catch (e: Exception) {
                            Log.e(TAG, "processUltraHdrImage FAILED: ${e.message}", e)
                            result.error("PROCESSING_FAILED", e.localizedMessage, e.stackTraceToString())
                        }
                    }
                }
                "saveImageToGallery" -> {
                    val bytes = call.argument<ByteArray>("bytes") ?: run {
                        result.error("INVALID_ARGS", "Missing bytes", null)
                        return@setMethodCallHandler
                    }
                    val filename = call.argument<String>("filename") ?: "WM_${System.currentTimeMillis()}.jpg"
                    val mimeType = call.argument<String>("mimeType") ?: "image/jpeg"
                    val relativePath = call.argument<String>("relativePath") ?: "Pictures/OneWatermark"

                    try {
                        val values = ContentValues().apply {
                            put(MediaStore.Images.Media.DISPLAY_NAME, filename)
                            put(MediaStore.Images.Media.MIME_TYPE, mimeType)
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                                put(MediaStore.Images.Media.RELATIVE_PATH, relativePath)
                                put(MediaStore.Images.Media.IS_PENDING, 1)
                            }
                        }

                        val resolver = applicationContext.contentResolver
                        val uri = resolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values)

                        if (uri != null) {
                            resolver.openOutputStream(uri)?.use { stream ->
                                stream.write(bytes)
                                stream.flush()
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
                                Log.w(TAG, "Could not resolve DATA path: ${e.message}")
                            }

                            val scanPath = realFilePath ?: "/storage/emulated/0/$relativePath/$filename"
                            MediaScannerConnection.scanFile(
                                applicationContext,
                                arrayOf(scanPath),
                                arrayOf(mimeType)
                            ) { path, scannedUri ->
                                Log.d(TAG, "MediaScanner finished: $path -> $scannedUri")
                            }

                            Log.d(TAG, "Saved image to MediaStore: $uri ($filename) at $scanPath")
                            result.success(uri.toString())
                        } else {
                            result.error("SAVE_FAILED", "Failed to create MediaStore entry", null)
                        }
                    } catch (e: Exception) {
                        Log.e(TAG, "saveImageToGallery FAILED: ${e.message}", e)
                        result.error("SAVE_FAILED", e.localizedMessage, null)
                    }
                }
                "getRecentPhotos" -> {
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

                            val cursor = contentResolver.query(
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
                                        "width" to width,
                                        "height" to height,
                                        "mimeType" to mimeType
                                    ))
                                    count++
                                }
                            }
                            runOnUiThread { result.success(photoList) }
                        } catch (e: Exception) {
                            Log.e(TAG, "getRecentPhotos error: ${e.message}", e)
                            runOnUiThread { result.error("QUERY_FAILED", e.localizedMessage, null) }
                        }
                    }
                }
                "scanMotionPhotos" -> {
                    val photos = call.argument<List<Map<String, Any>>>("photos") ?: emptyList()
                    heavyTaskExecutor.execute {
                        Process.setThreadPriority(Process.THREAD_PRIORITY_BACKGROUND)
                        val motionIds = java.util.concurrent.ConcurrentHashMap.newKeySet<String>()
                        photos.parallelStream().forEach { item ->
                            val id = item["id"]?.toString() ?: ""
                            val path = item["path"]?.toString() ?: ""
                            if (id.isNotEmpty() && path.isNotEmpty()) {
                                if (checkIsMotionPhotoFile(path)) {
                                    motionIds.add(id)
                                }
                            }
                        }
                        val resultList = motionIds.toList()
                        runOnUiThread { result.success(resultList) }
                    }
                }
                "getPhotoThumbnail" -> {
                    val idStr = call.argument<String>("id")
                    val path = call.argument<String>("path")
                    val targetWidth = call.argument<Int>("width") ?: 256
                    val targetHeight = call.argument<Int>("height") ?: 256

                    // 在后台专用线程池执行位图解码, 降低线程优先级, 杜绝抢占 UI/Raster 渲染核心
                    thumbnailExecutor.execute {
                        Process.setThreadPriority(Process.THREAD_PRIORITY_BACKGROUND)
                        try {
                            var thumbBitmap: Bitmap? = null
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q && idStr != null) {
                                val id = idStr.toLongOrNull()
                                if (id != null) {
                                    val collection = MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL)
                                    val uri = ContentUris.withAppendedId(collection, id)
                                    try {
                                        thumbBitmap = contentResolver.loadThumbnail(uri, Size(targetWidth, targetHeight), null)
                                    } catch (e: Exception) {
                                        Log.w(TAG, "loadThumbnail failed: ${e.message}")
                                    }
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
                                        while ((halfHeight / inSampleSize) >= targetHeight && (halfWidth / inSampleSize) >= targetWidth) {
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
                                val stream = ByteArrayOutputStream()
                                thumbBitmap.compress(Bitmap.CompressFormat.JPEG, 75, stream)
                                thumbBitmap.recycle()
                                val bytes = stream.toByteArray()
                                runOnUiThread { result.success(bytes) }
                            } else {
                                runOnUiThread { result.success(null) }
                            }
                        } catch (e: Exception) {
                            Log.e(TAG, "getPhotoThumbnail error: ${e.message}", e)
                            runOnUiThread { result.success(null) }
                        }
                    }
                }
                "getPhotoBytes" -> {
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
                                    val uri = android.net.Uri.parse(uriStr)
                                    contentResolver.openInputStream(uri)?.use { stream ->
                                        bytes = stream.readBytes()
                                    }
                                } catch (_: Exception) {}
                            }
                            val finalResultBytes = bytes
                            if (finalResultBytes != null && finalResultBytes.isNotEmpty()) {
                                runOnUiThread { result.success(finalResultBytes) }
                            } else {
                                runOnUiThread { result.error("FILE_NOT_FOUND", "Could not read file from path ($path) or uri ($uriStr)", null) }
                            }
                        } catch (e: Exception) {
                            Log.e(TAG, "getPhotoBytes error: ${e.message}", e)
                            runOnUiThread { result.error("READ_FAILED", e.localizedMessage, null) }
                        }
                    }
                }
                "getExif" -> {
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
                                    Log.w(TAG, "ExifInterface from bytes failed: ${e.message}")
                                }
                            }
                        }

                        if (exifInterface == null && path != null && path.isNotEmpty() && File(path).exists()) {
                            try {
                                exifInterface = android.media.ExifInterface(path)
                            } catch (e: Exception) {
                                Log.w(TAG, "ExifInterface from path failed: ${e.message}")
                            }
                        }

                        if (exifInterface == null && uriStr != null && uriStr.isNotEmpty()) {
                            try {
                                val uri = Uri.parse(uriStr)
                                val pfd = contentResolver.openFileDescriptor(uri, "r")
                                if (pfd != null) {
                                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                                        exifInterface = android.media.ExifInterface(pfd.fileDescriptor)
                                    }
                                    pfd.close()
                                }
                            } catch (e: Exception) {
                                Log.w(TAG, "ExifInterface from uri failed: ${e.message}")
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
                            result.success(map)
                        } else {
                            result.success(null)
                        }
                    } catch (e: Exception) {
                        Log.e(TAG, "getExif error: ${e.message}", e)
                        result.success(null)
                    }
                }
                "compressRgbaToJpeg" -> {
                    val rgbaBytes = call.argument<ByteArray>("rgba")
                    val width = call.argument<Int>("width") ?: 0
                    val height = call.argument<Int>("height") ?: 0
                    val quality = call.argument<Int>("quality") ?: 95

                    if (rgbaBytes == null || width <= 0 || height <= 0) {
                        result.error("INVALID_ARGS", "Missing RGBA data", null)
                        return@setMethodCallHandler
                    }

                    // 高通 SoC 优化：全尺寸位图编码移出主线程，ADPF 提速 + Snapdragon 硬件编解码管线
                    heavyTaskExecutor.execute {
                        Process.setThreadPriority(Process.THREAD_PRIORITY_LESS_FAVORABLE)
                        try {
                            val jpeg = runWithAdpfBoost(150L) {
                                val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
                                val buffer = ByteBuffer.wrap(rgbaBytes)
                                bitmap.copyPixelsFromBuffer(buffer)

                                val baos = ByteArrayOutputStream(rgbaBytes.size / 5)
                                bitmap.compress(Bitmap.CompressFormat.JPEG, quality, baos)
                                bitmap.recycle()
                                baos.toByteArray()
                            }
                            result.success(jpeg)
                        } catch (e: Exception) {
                            Log.e(TAG, "compressRgbaToJpeg error: ${e.message}", e)
                            result.error("ENCODE_FAILED", e.localizedMessage, null)
                        }
                    }
                }
                "watermarkVideo" -> {
                    val videoBytes = call.argument<ByteArray>("videoBytes")
                    val overlayBytes = call.argument<ByteArray>("overlayBytes")
                    if (videoBytes == null || videoBytes.isEmpty() || overlayBytes == null || overlayBytes.isEmpty()) {
                        result.success(videoBytes)
                        return@setMethodCallHandler
                    }

                    // 高通 SoC 优化：视频转码走统一重负载线程池 (受 ADPF 调度管理)，不再裸开线程
                    heavyTaskExecutor.execute {
                        try {
                            val tempInFile = File.createTempFile("motion_in_", ".mp4", cacheDir)
                            tempInFile.writeBytes(videoBytes)
                            val tempOutFile = File.createTempFile("motion_out_", ".mp4", cacheDir)

                            val overlayBitmap = BitmapFactory.decodeByteArray(overlayBytes, 0, overlayBytes.size)
                            // ADPF：按 30fps 帧间隔声明目标时长，调度器持续将转码线程钉在 Prime/Big 核心
                            val success = runWithAdpfBoost(33L) {
                                processVideoWatermark(tempInFile, tempOutFile, overlayBitmap)
                            }
                            overlayBitmap?.recycle()
                            tempInFile.delete()

                            if (success && tempOutFile.exists() && tempOutFile.length() > 0) {
                                val outBytes = tempOutFile.readBytes()
                                tempOutFile.delete()
                                runOnUiThread { result.success(outBytes) }
                            } else {
                                tempOutFile.delete()
                                runOnUiThread { result.success(videoBytes) }
                            }
                        } catch (e: Exception) {
                            Log.e(TAG, "watermarkVideo failed: ${e.message}", e)
                            runOnUiThread { result.success(videoBytes) }
                        }
                    }
                }
                "extractMotionPhotoNative" -> {
                    val bytesArg = call.argument<ByteArray>("bytes")
                    val path = call.argument<String>("path")
                    val uriStr = call.argument<String>("uri")

                    heavyTaskExecutor.execute {
                        Process.setThreadPriority(Process.THREAD_PRIORITY_BACKGROUND)
                        try {
                            // ★ 关键修复: 对于大文件 (HEIC 动态照片 15MB+), Dart 通过 MethodChannel 传递
                            //   bytes 时可能因为 platform channel buffer 限制而被截断。
                            //   截断的 bytes 不包含 SEF 尾部, 导致 MP4 定位失败。
                            //   因此: 若有 path 则优先直接从文件系统读取完整文件, bytes 仅作最终回退。
                            var targetBytes: ByteArray? = null

                            // 1. 优先: 直接读取物理文件路径 (最可靠，完整字节)
                            if (path != null && path.isNotEmpty()) {
                                try {
                                    val f = File(path)
                                    if (f.exists() && f.canRead()) {
                                        targetBytes = f.readBytes()
                                        Log.d(TAG, "extractMotionPhotoNative: read ${targetBytes.size}B from path")
                                    }
                                } catch (e: Exception) {
                                    Log.w(TAG, "extractMotionPhotoNative: path read failed: ${e.message}")
                                }
                            }

                            // 2. 备选: ContentResolver URI (处理 Android Q+ scoped storage)
                            if (targetBytes == null && uriStr != null && uriStr.isNotEmpty()) {
                                try {
                                    val uri = Uri.parse(uriStr)
                                    contentResolver.openInputStream(uri)?.use { stream ->
                                        targetBytes = stream.readBytes()
                                        Log.d(TAG, "extractMotionPhotoNative: read ${targetBytes?.size}B from URI")
                                    }
                                } catch (e: Exception) {
                                    Log.w(TAG, "extractMotionPhotoNative: URI read failed: ${e.message}")
                                }
                            }

                            // 3. 最终回退: 使用 Dart 传入的 bytes (可能是部分字节)
                            if (targetBytes == null && bytesArg != null && bytesArg.isNotEmpty()) {
                                targetBytes = bytesArg
                                Log.d(TAG, "extractMotionPhotoNative: using Dart bytes (${bytesArg.size}B), may be truncated for large HEIC")
                            }

                            val finalBytes = targetBytes
                            if (finalBytes == null || finalBytes.isEmpty() || finalBytes.size < 64) {
                                runOnUiThread { result.success(mapOf("isMotionPhoto" to false)) }
                                return@execute
                            }

                            val info = nativeExtractMotionVideo(finalBytes)
                            if (info != null) {
                                Log.d(TAG, "extractMotionPhotoNative: extracted ${info.first.size}B video, ts=${info.second}us, offset=${info.third}")
                                runOnUiThread {
                                    result.success(mapOf(
                                        "isMotionPhoto" to true,
                                        "videoBytes" to info.first,
                                        "presentationTimestampUs" to info.second,
                                        "offset" to info.third,
                                        "length" to info.first.size
                                    ))
                                }
                            } else {
                                Log.d(TAG, "extractMotionPhotoNative: not a motion photo (${finalBytes.size}B)")
                                runOnUiThread { result.success(mapOf("isMotionPhoto" to false)) }
                            }
                        } catch (e: Exception) {
                            Log.e(TAG, "extractMotionPhotoNative error: ${e.message}", e)
                            runOnUiThread { result.success(mapOf("isMotionPhoto" to false)) }
                        }
                    }
                }
                "compositeMotionPhotoNative" -> {
                    val jpgBytes = call.argument<ByteArray>("watermarkedJpgBytes")
                    val videoBytes = call.argument<ByteArray>("motionVideoBytes")
                    val ts = (call.argument<Number>("presentationTimestampUs"))?.toLong() ?: 0L

                    if (jpgBytes == null || jpgBytes.isEmpty() || videoBytes == null || videoBytes.isEmpty()) {
                        result.error("INVALID_ARGS", "Missing jpg or video bytes", null)
                        return@setMethodCallHandler
                    }

                    heavyTaskExecutor.execute {
                        Process.setThreadPriority(Process.THREAD_PRIORITY_LESS_FAVORABLE)
                        try {
                            val composited = nativeCompositeMotionPhoto(jpgBytes, videoBytes, ts)
                            runOnUiThread { result.success(composited) }
                        } catch (e: Exception) {
                            Log.e(TAG, "compositeMotionPhotoNative error: ${e.message}", e)
                            runOnUiThread { result.error("COMPOSITE_FAILED", e.localizedMessage, null) }
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun processVideoWatermark(
        inputFile: File,
        outputFile: File,
        overlayBitmap: Bitmap?
    ): Boolean {
        if (overlayBitmap == null) return false

        val retriever = MediaMetadataRetriever()
        val audioExtractor = MediaExtractor()
        var encoder: MediaCodec? = null
        var muxer: MediaMuxer? = null

        try {
            retriever.setDataSource(inputFile.absolutePath)

            // 读取原始视频元数据（不截断任何值）
            val durationMs = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 1500L
            val durationUs = durationMs * 1000L

            // 1. 用 MediaExtractor 枚举原始视频帧的真实 PTS（不生成假时间轴）
            val videoExtractorForPts = MediaExtractor()
            videoExtractorForPts.setDataSource(inputFile.absolutePath)
            var videoTrackIdx = -1
            for (i in 0 until videoExtractorForPts.trackCount) {
                val fmt = videoExtractorForPts.getTrackFormat(i)
                if ((fmt.getString(MediaFormat.KEY_MIME) ?: "").startsWith("video/")) {
                    videoTrackIdx = i
                    break
                }
            }

            val framePtsListUs = mutableListOf<Long>()
            if (videoTrackIdx >= 0) {
                videoExtractorForPts.selectTrack(videoTrackIdx)
                val emptyBuf = ByteBuffer.allocate(0)
                while (true) {
                    val pts = videoExtractorForPts.sampleTime
                    if (pts < 0) break
                    framePtsListUs.add(pts)
                    if (!videoExtractorForPts.advance()) break
                }
            }
            videoExtractorForPts.release()

            // 若 PTS 枚举失败则均匀分布（兜底）
            if (framePtsListUs.isEmpty()) {
                val fps = 30
                val n = ((durationMs / 1000.0) * fps).toInt().coerceAtLeast(1)
                val step = durationUs / n
                for (i in 0 until n) framePtsListUs.add(i * step)
            }
            framePtsListUs.sort() // 保证时间顺序

            // 限制最大转码帧率为 30fps (动态照片标准帧率)，超采样视频进行平滑降采样，避免 60fps 冗余计算
            val finalPtsListUs = if (framePtsListUs.size > 50) {
                val minIntervalUs = 1000000L / 30L // 33.3ms
                val filtered = mutableListOf<Long>()
                var lastPts = -minIntervalUs
                for (pts in framePtsListUs) {
                    if (pts - lastPts >= minIntervalUs * 0.85) {
                        filtered.add(pts)
                        lastPts = pts
                    }
                }
                if (filtered.isEmpty()) framePtsListUs else filtered
            } else {
                framePtsListUs
            }

            // 采样第一帧获取解码后的实际宽高 (MediaMetadataRetriever 会自动按视频旋转角度将图像摆正，输出正是最终显示宽高)
            val samplePts = if (finalPtsListUs.isNotEmpty()) finalPtsListUs[0] else 0L
            val probeFrame = retriever.getFrameAtTime(samplePts, MediaMetadataRetriever.OPTION_CLOSEST)
            var videoWidth = probeFrame?.width ?: (retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)?.toIntOrNull() ?: 1920)
            var videoHeight = probeFrame?.height ?: (retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)?.toIntOrNull() ?: 1080)
            probeFrame?.recycle()

            if (videoWidth % 2 != 0) videoWidth--
            if (videoHeight % 2 != 0) videoHeight--

            Log.d(TAG, "processVideoWatermark: uprightSize=${videoWidth}x${videoHeight}, frames=${finalPtsListUs.size}, duration=${durationMs}ms")

            // 2. 检查音频轨道
            var audioTrackIndex = -1
            var audioTrackFormat: MediaFormat? = null
            var muxerAudioTrackIndex = -1
            try {
                audioExtractor.setDataSource(inputFile.absolutePath)
                for (i in 0 until audioExtractor.trackCount) {
                    val fmt = audioExtractor.getTrackFormat(i)
                    val mime = fmt.getString(MediaFormat.KEY_MIME) ?: ""
                    if (mime.startsWith("audio/")) {
                        audioTrackIndex = i
                        audioTrackFormat = fmt
                        audioExtractor.selectTrack(i)
                        break
                    }
                }
            } catch (e: Exception) {
                Log.w(TAG, "Audio track: ${e.message}")
            }

            // 3. 配置 ByteBuffer 输入模式编码器（优先选择高通骁龙专用硬件编码器 c2.qti.avc.encoder）
            val mimeType = MediaFormat.MIMETYPE_VIDEO_AVC
            val bitrate = (videoWidth * videoHeight * 4).coerceIn(2000000, 20000000)
            val encFormat = MediaFormat.createVideoFormat(mimeType, videoWidth, videoHeight).apply {
                setInteger(MediaFormat.KEY_COLOR_FORMAT, MediaCodecInfo.CodecCapabilities.COLOR_FormatYUV420Flexible)
                setInteger(MediaFormat.KEY_BIT_RATE, bitrate)
                setInteger(MediaFormat.KEY_FRAME_RATE, 30)
                setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 1)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    setInteger(MediaFormat.KEY_PRIORITY, 0)
                    setInteger(MediaFormat.KEY_COMPLEXITY, 1)
                }
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                    setInteger(MediaFormat.KEY_BITRATE_MODE, MediaCodecInfo.EncoderCapabilities.BITRATE_MODE_VBR)
                }
                try {
                    setInteger("vendor.qti-ext-enc-low-latency.enable", 1)
                } catch (_: Throwable) {}
            }

            val qcomEncoder = findQualcommEncoder(mimeType)
            val enc = if (qcomEncoder != null) {
                try {
                    MediaCodec.createByCodecName(qcomEncoder).also {
                        Log.d(TAG, "Using Qualcomm Hardware Encoder: $qcomEncoder")
                    }
                } catch (_: Throwable) {
                    MediaCodec.createEncoderByType(mimeType)
                }
            } else {
                MediaCodec.createEncoderByType(mimeType)
            }
            encoder = enc
            enc.configure(encFormat, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
            enc.start()

            val mux = MediaMuxer(outputFile.absolutePath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
            muxer = mux
            mux.setOrientationHint(0)

            var muxerVideoTrackIndex = -1
            var muxerStarted = false
            val bufferInfo = MediaCodec.BufferInfo()

            // 预缩放水印图层至视频目标尺寸（避免每帧重复重采样，性能提升 500%）
            val scaledOverlay = if (overlayBitmap.width != videoWidth || overlayBitmap.height != videoHeight) {
                Bitmap.createScaledBitmap(overlayBitmap, videoWidth, videoHeight, true)
            } else {
                overlayBitmap
            }

            // 复用内存缓冲区，彻底杜绝帧循环 GC 抖动
            val compositeBitmap = Bitmap.createBitmap(videoWidth, videoHeight, Bitmap.Config.ARGB_8888)
            val compositeCanvas = Canvas(compositeBitmap)
            val paint = Paint().apply { isFilterBitmap = true; isAntiAlias = true }
            val dstRect = Rect(0, 0, videoWidth, videoHeight)
            val argbBuffer = IntArray(videoWidth * videoHeight)
            val yuvBuffer = ByteArray(videoWidth * videoHeight * 3 / 2)

            fun drainEncoder(eos: Boolean) {
                while (true) {
                    val outIdx = enc.dequeueOutputBuffer(bufferInfo, if (eos) 10000L else 0L)
                    when {
                        outIdx == MediaCodec.INFO_TRY_AGAIN_LATER -> {
                            if (!eos) return
                            Thread.sleep(2)
                        }
                        outIdx == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                            if (!muxerStarted) {
                                muxerVideoTrackIndex = mux.addTrack(enc.outputFormat)
                                if (audioTrackFormat != null)
                                    muxerAudioTrackIndex = mux.addTrack(audioTrackFormat)
                                mux.start()
                                muxerStarted = true
                                Log.d(TAG, "Muxer started: video=$muxerVideoTrackIndex audio=$muxerAudioTrackIndex")
                            }
                        }
                        outIdx >= 0 -> {
                            val buf = enc.getOutputBuffer(outIdx)
                            if (buf != null) {
                                if (bufferInfo.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG != 0)
                                    bufferInfo.size = 0
                                if (bufferInfo.size > 0 && muxerStarted) {
                                    buf.position(bufferInfo.offset)
                                    buf.limit(bufferInfo.offset + bufferInfo.size)
                                    mux.writeSampleData(muxerVideoTrackIndex, buf, bufferInfo)
                                }
                            }
                            enc.releaseOutputBuffer(outIdx, false)
                            if (bufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) return
                        }
                    }
                }
            }

            // 4. 逐帧硬件缩放解码 + 水印合成 + 快速编码
            val totalFrames = framePtsListUs.size
            framePtsListUs.forEachIndexed { idx, ptsUs ->
                val frameBitmap = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
                    retriever.getScaledFrameAtTime(ptsUs, MediaMetadataRetriever.OPTION_CLOSEST, videoWidth, videoHeight)
                } else {
                    retriever.getFrameAtTime(ptsUs, MediaMetadataRetriever.OPTION_CLOSEST)
                }

                if (frameBitmap != null) {
                    compositeCanvas.drawBitmap(frameBitmap, null, dstRect, paint)
                    frameBitmap.recycle()
                } else {
                    compositeCanvas.drawColor(Color.BLACK)
                }
                compositeCanvas.drawBitmap(scaledOverlay, null, dstRect, paint)

                // 快速 YUV420 转换
                fastBitmapToYuv420(compositeBitmap, argbBuffer, yuvBuffer, videoWidth, videoHeight)

                // 送入硬件编码器
                val isEos = idx == totalFrames - 1
                val inputIdx = enc.dequeueInputBuffer(100000L)
                if (inputIdx >= 0) {
                    val inBuf = enc.getInputBuffer(inputIdx)!!
                    inBuf.clear()
                    inBuf.put(yuvBuffer)
                    val flags = if (isEos) MediaCodec.BUFFER_FLAG_END_OF_STREAM else 0
                    enc.queueInputBuffer(inputIdx, 0, yuvBuffer.size, ptsUs, flags)
                }

                drainEncoder(false)
            }

            // 5. 冲刷编码器
            drainEncoder(true)
            compositeBitmap.recycle()
            if (scaledOverlay != overlayBitmap) {
                scaledOverlay.recycle()
            }

            // 6. 复制音频轨（原始 PTS，不重新压缩）
            if (audioTrackIndex >= 0 && muxerAudioTrackIndex >= 0 && muxerStarted) {
                val audioBuf = ByteBuffer.allocate(128 * 1024)
                val audioInfo = MediaCodec.BufferInfo()
                while (true) {
                    val size = audioExtractor.readSampleData(audioBuf, 0)
                    if (size < 0) break
                    audioInfo.offset = 0
                    audioInfo.size = size
                    audioInfo.presentationTimeUs = audioExtractor.sampleTime
                    audioInfo.flags = audioExtractor.sampleFlags
                    mux.writeSampleData(muxerAudioTrackIndex, audioBuf, audioInfo)
                    audioExtractor.advance()
                }
                Log.d(TAG, "Audio copied")
            }

            Log.d(TAG, "processVideoWatermark done! size=${outputFile.length()}B")
            return true

        } catch (e: Exception) {
            Log.e(TAG, "processVideoWatermark error: ${e.message}", e)
            return false
        } finally {
            try { encoder?.stop() } catch (_: Throwable) {}
            try { encoder?.release() } catch (_: Throwable) {}
            try { muxer?.stop() } catch (_: Throwable) {}
            try { muxer?.release() } catch (_: Throwable) {}
            try { audioExtractor.release() } catch (_: Throwable) {}
            try { retriever.release() } catch (_: Throwable) {}
        }
    }

    /** 查找高通骁龙专有硬件视频编码器 (如 c2.qti.avc.encoder / OMX.qcom.video.encoder.avc) */
    private fun findQualcommEncoder(mimeType: String): String? {
        try {
            val codecInfos = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                MediaCodecList(MediaCodecList.REGULAR_CODECS).codecInfos
            } else {
                emptyArray()
            }
            for (codecInfo in codecInfos) {
                if (!codecInfo.isEncoder) continue
                val name = codecInfo.name.lowercase()
                if (name.contains("qti") || name.contains("qcom")) {
                    for (type in codecInfo.supportedTypes) {
                        if (type.equals(mimeType, ignoreCase = true)) {
                            return codecInfo.name
                        }
                    }
                }
            }
        } catch (_: Exception) {}
        return null
    }

    /** 快速零分配 ARGB Bitmap → YUV420 Semi-planar (NV12 风格) */
    private fun fastBitmapToYuv420(
        bitmap: Bitmap,
        argb: IntArray,
        yuv: ByteArray,
        width: Int,
        height: Int
    ) {
        bitmap.getPixels(argb, 0, width, 0, 0, width, height)

        val frameSize = width * height
        var yIdx = 0
        var uvIdx = frameSize

        for (j in 0 until height) {
            val rowOffset = j * width
            val isEvenRow = (j and 1) == 0

            for (i in 0 until width) {
                val pixel = argb[rowOffset + i]
                val r = (pixel ushr 16) and 0xff
                val g = (pixel ushr 8) and 0xff
                val b = pixel and 0xff

                val y = ((66 * r + 129 * g + 25 * b + 128) shr 8) + 16
                yuv[yIdx++] = if (y < 16) 16.toByte() else if (y > 235) 235.toByte() else y.toByte()

                if (isEvenRow && (i and 1) == 0) {
                    val u = ((-38 * r - 74 * g + 112 * b + 128) shr 8) + 128
                    val v = ((112 * r - 94 * g - 18 * b + 128) shr 8) + 128
                    yuv[uvIdx++] = if (u < 16) 16.toByte() else if (u > 240) 240.toByte() else u.toByte()
                    yuv[uvIdx++] = if (v < 16) 16.toByte() else if (v > 240) 240.toByte() else v.toByte()
                }
            }
        }
    }

    /** 原生高精度提取动态照片中的 MP4 视频流 (支持 HEIC 与 JPEG) */
    private fun nativeExtractMotionVideo(bytes: ByteArray): Triple<ByteArray, Long, Int>? {
        if (bytes.size < 64) return null
        val len = bytes.size

        var mp4Offset = -1
        var videoEnd = len
        var timestampUs = 0L

        // 1. 优先尝试解析三星 SEF 尾部结构 (Samsung HEIC / JPEG)
        val sefPair = parseSamsungSefNative(bytes)
        if (sefPair != null && isValidMp4HeaderNative(bytes, sefPair.first)) {
            mp4Offset = sefPair.first
            videoEnd = sefPair.second
        }

        // 2. 尝试从 XMP 中解析 MicroVideoOffset / GContainer Directory (Google Pixel / 小米 / OPPO / vivo / Samsung)
        if (mp4Offset < 0) {
            val headLen = Math.min(len, 2097152)
            val headStr = String(bytes, 0, headLen, Charsets.ISO_8859_1)

            val offsetRegex = Regex("""(?:GCamera:|Camera:)?MicroVideoOffset\s*=\s*["']?(\d+)["']?""")
            val match = offsetRegex.find(headStr)
            if (match != null) {
                val offsetFromEnd = match.groupValues[1].toIntOrNull() ?: 0
                if (offsetFromEnd in 1 until len) {
                    val calcOffset = len - offsetFromEnd
                    if (isValidMp4HeaderNative(bytes, calcOffset)) {
                        mp4Offset = calcOffset
                        videoEnd = len
                    }
                }
            }

            if (mp4Offset < 0) {
                val gcontainerRegex = Regex("""<Item:Semantic>MotionPhoto</Item:Semantic>\s*<Item:Length>(\d+)</Item:Length>|Item:Semantic=["']MotionPhoto["'][^>]*Item:Length=["'](\d+)["']|Item:Length=["'](\d+)["'][^>]*Item:Semantic=["']MotionPhoto["']""")
                val gmatch = gcontainerRegex.find(headStr)
                if (gmatch != null) {
                    val lenStr = gmatch.groupValues[1].ifEmpty { gmatch.groupValues[2].ifEmpty { gmatch.groupValues[3] } }
                    val vLen = lenStr.toIntOrNull() ?: 0
                    if (vLen in 1 until len) {
                        val calcOffset = len - vLen
                        if (isValidMp4HeaderNative(bytes, calcOffset)) {
                            mp4Offset = calcOffset
                            videoEnd = len
                        }
                    }
                }
            }
        }

        // 3. 逆向快速搜索 MP4 ftyp 头部 (直接拼接 MP4 流兜底)
        if (mp4Offset < 0) {
            val isJpeg = bytes[0] == 0xFF.toByte() && bytes[1] == 0xD8.toByte()
            val minOffset = if (isJpeg) 2 else 16
            for (i in (len - 16) downTo minOffset) {
                if (bytes[i + 4] == 0x66.toByte() && bytes[i + 5] == 0x74.toByte() &&
                    bytes[i + 6] == 0x79.toByte() && bytes[i + 7] == 0x70.toByte()
                ) {
                    if (isValidMp4HeaderNative(bytes, i)) {
                        mp4Offset = i
                        videoEnd = len
                        break
                    }
                }
            }
        }

        if (mp4Offset <= 0 || mp4Offset >= videoEnd) return null

        val videoSize = videoEnd - mp4Offset
        if (videoSize < 16) return null

        val videoBytes = ByteArray(videoSize)
        System.arraycopy(bytes, mp4Offset, videoBytes, 0, videoSize)

        // 解析原始 XMP PresentationTimestamp (扩大搜索范围到 2MB 或视频起始偏移，支持大尺寸 HEIC / JPEG)
        try {
            val searchLen = Math.min(len, if (mp4Offset > 0) mp4Offset else 2097152)
            val headStr = String(bytes, 0, searchLen, Charsets.ISO_8859_1)
            val tsRegex = Regex("""(?:GCamera:|Camera:|samsung:)?(?:MotionPhotoPresentationTimestampUs|MicroVideoPresentationTimestampUs|PresentationTimestampUs|SpecialTypeTimestamp)\s*=\s*["']?(\d+)["']?""")
            val tsMatch = tsRegex.find(headStr)
            if (tsMatch != null) {
                timestampUs = tsMatch.groupValues[1].toLongOrNull() ?: 0L
            }
        } catch (_: Exception) {}

        // 若 XMP 未记录时间戳，通过 MediaMetadataRetriever 探测 MP4 真实总时长并精准定位快门点
        if (timestampUs <= 0L) {
            try {
                val tempFile = File.createTempFile("mphoto_probe_", ".mp4", cacheDir)
                tempFile.writeBytes(videoBytes)
                val retriever = MediaMetadataRetriever()
                retriever.setDataSource(tempFile.absolutePath)
                val durationStr = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
                if (durationStr != null) {
                    val dMs = durationStr.toLongOrNull() ?: 0L
                    if (dMs > 0) {
                        val durationUs = dMs * 1000L
                        // 三星相册动态照片默认在快门点前捕获 1.5s~2.5s，后捕获 0.5s~1.0s
                        timestampUs = if (durationUs > 1500000L) durationUs - 500000L else durationUs / 2L
                    }
                }
                retriever.release()
                tempFile.delete()
            } catch (_: Exception) {}
        }

        if (timestampUs <= 0L) {
            timestampUs = 1500000L
        }

        return Triple(videoBytes, timestampUs, mp4Offset)
    }

    private fun isValidMp4HeaderNative(bytes: ByteArray, offset: Int): Boolean {
        if (offset < 0 || offset + 16 > bytes.size) return false
        if (bytes[offset + 4] != 0x66.toByte() ||
            bytes[offset + 5] != 0x74.toByte() ||
            bytes[offset + 6] != 0x79.toByte() ||
            bytes[offset + 7] != 0x70.toByte()
        ) {
            return false
        }

        val b0 = bytes[offset + 8]
        val b1 = bytes[offset + 9]
        val b2 = bytes[offset + 10]
        val b3 = bytes[offset + 11]
        val brand = String(byteArrayOf(b0, b1, b2, b3), Charsets.US_ASCII).lowercase()

        val staticImageBrands = setOf("heic", "heix", "heim", "heis", "mif1", "msf1", "avif", "avis", "avic", "miaf")
        if (staticImageBrands.contains(brand)) {
            return false
        }

        val validVideoBrands = setOf(
            "mp41", "mp42", "isom", "iso2", "iso4", "iso5", "iso6",
            "avc1", "hvc1", "hev1", "qt  ", "m4v ", "m4a ", "msnv",
            "dash", "mp71", "3gp4", "3gp5", "3gp6", "3g2a", "caep",
            "qvfs", "f4v ", "sec ", "s264", "kddi", "mmp4"
        )
        if (validVideoBrands.contains(brand) || brand.startsWith("mp4") || brand.startsWith("iso") || brand.startsWith("3gp")) {
            return true
        }

        val boxSize = ((bytes[offset].toInt() and 0xFF) shl 24) or
                ((bytes[offset + 1].toInt() and 0xFF) shl 16) or
                ((bytes[offset + 2].toInt() and 0xFF) shl 8) or
                (bytes[offset + 3].toInt() and 0xFF)
        if (boxSize in 16..65536) {
            val compatEnd = Math.min(offset + boxSize, bytes.size)
            var c = offset + 16
            while (c + 4 <= compatEnd) {
                val cBrand = String(byteArrayOf(bytes[c], bytes[c + 1], bytes[c + 2], bytes[c + 3]), Charsets.US_ASCII).lowercase()
                if (validVideoBrands.contains(cBrand) || cBrand.startsWith("mp4") || cBrand.startsWith("iso") || cBrand.startsWith("3gp")) {
                    return true
                }
                c += 4
            }
        }
        return false
    }

    private fun parseSamsungSefNative(bytes: ByteArray): Pair<Int, Int>? {
        val len = bytes.size
        if (len < 40) return null
        if (bytes[len - 4] != 0x53.toByte() || bytes[len - 3] != 0x45.toByte() ||
            bytes[len - 2] != 0x46.toByte() || bytes[len - 1] != 0x54.toByte()
        ) {
            return null
        }

        try {
            val sefDataSize = (bytes[len - 8].toInt() and 0xFF) or
                    ((bytes[len - 7].toInt() and 0xFF) shl 8) or
                    ((bytes[len - 6].toInt() and 0xFF) shl 16) or
                    ((bytes[len - 5].toInt() and 0xFF) shl 24)
            if (sefDataSize <= 0 || sefDataSize > 65536) return null
            val sefhAbs = len - 8 - sefDataSize
            if (sefhAbs < 0 || sefhAbs + 12 > len) return null

            if (bytes[sefhAbs] != 0x53.toByte() || bytes[sefhAbs + 1] != 0x45.toByte() ||
                bytes[sefhAbs + 2] != 0x46.toByte() || bytes[sefhAbs + 3] != 0x48.toByte()
            ) {
                return null
            }

            val count = (bytes[sefhAbs + 8].toInt() and 0xFF) or
                    ((bytes[sefhAbs + 9].toInt() and 0xFF) shl 8) or
                    ((bytes[sefhAbs + 10].toInt() and 0xFF) shl 16) or
                    ((bytes[sefhAbs + 11].toInt() and 0xFF) shl 24)
            val entryCount = count.coerceIn(1, 32)

            val entries = mutableListOf<Pair<Int, Int>>() // (negOffset, entryOffset)
            for (i in 0 until entryCount) {
                val entryOffset = sefhAbs + 12 + (i * 12)
                if (entryOffset + 12 > len) break

                val negativeOffset = (bytes[entryOffset + 4].toInt() and 0xFF) or
                        ((bytes[entryOffset + 5].toInt() and 0xFF) shl 8) or
                        ((bytes[entryOffset + 6].toInt() and 0xFF) shl 16) or
                        ((bytes[entryOffset + 7].toInt() and 0xFF) shl 24)

                if (negativeOffset in 1..sefhAbs) {
                    entries.add(Pair(negativeOffset, entryOffset))
                }
            }

            for (entry in entries) {
                val negativeOffset = entry.first
                val fieldStart = sefhAbs - negativeOffset
                val mp4Start = fieldStart + 24

                if (mp4Start >= 0 && mp4Start + 8 <= len) {
                    if (bytes[mp4Start + 4] == 0x66.toByte() && bytes[mp4Start + 5] == 0x74.toByte() &&
                        bytes[mp4Start + 6] == 0x79.toByte() && bytes[mp4Start + 7] == 0x70.toByte()
                    ) {
                        // 找到下一个较小 negativeOffset 的 entry (即物理上紧随其后的字段)，计算精确结尾
                        val nextSmallerNeg = entries.map { it.first }.filter { it < negativeOffset }.maxOrNull() ?: 0
                        val videoEnd = if (nextSmallerNeg > 0) sefhAbs - nextSmallerNeg else sefhAbs
                        return Pair(mp4Start, videoEnd)
                    }
                }
            }
        } catch (_: Exception) {}
        return null
    }

    private fun nativeCompositeMotionPhoto(
        watermarkedJpgBytes: ByteArray,
        motionVideoBytes: ByteArray,
        timestampUs: Long
    ): ByteArray {
        val videoLength = motionVideoBytes.size
        val sefBlockSize = 32
        val microVideoOffset = videoLength + sefBlockSize

        val effectiveTimestampUs = if (timestampUs > 0L) timestampUs else 1500000L

        // 1. 构建 Samsung SEF 尾部结构
        val sefTrailer = ByteArrayOutputStream(24 + videoLength + 32)
        // Part 1: Field Header (24 bytes)
        sefTrailer.write(byteArrayOf(0x00, 0x00, 0x30, 0x0A))
        sefTrailer.write(byteArrayOf(0x10, 0x00, 0x00, 0x00)) // 16 LE
        sefTrailer.write("MotionPhoto_Data".toByteArray(Charsets.US_ASCII))

        // Part 2: Video Bytes
        sefTrailer.write(motionVideoBytes)

        // Part 3: SEFH Index Block (32 bytes)
        val negativeOffset = 24 + videoLength
        val dataLength = 24 + videoLength
        sefTrailer.write("SEFH".toByteArray(Charsets.US_ASCII))
        sefTrailer.write(byteArrayOf(0x6A, 0x00, 0x00, 0x00)) // version 106 LE
        sefTrailer.write(byteArrayOf(0x01, 0x00, 0x00, 0x00)) // count 1 LE
        sefTrailer.write(byteArrayOf(0x00, 0x00, 0x30, 0x0A)) // entry marker
        sefTrailer.write(byteArrayOf(
            (negativeOffset and 0xFF).toByte(),
            ((negativeOffset shr 8) and 0xFF).toByte(),
            ((negativeOffset shr 16) and 0xFF).toByte(),
            ((negativeOffset shr 24) and 0xFF).toByte()
        ))
        sefTrailer.write(byteArrayOf(
            (dataLength and 0xFF).toByte(),
            ((dataLength shr 8) and 0xFF).toByte(),
            ((dataLength shr 16) and 0xFF).toByte(),
            ((dataLength shr 24) and 0xFF).toByte()
        ))
        sefTrailer.write(byteArrayOf(0x18, 0x00, 0x00, 0x00)) // sefDataSize = 24 LE
        sefTrailer.write("SEFT".toByteArray(Charsets.US_ASCII))

        val sefTrailerBytes = sefTrailer.toByteArray()

        // 2. 构建 XMP (Google GCamera + GContainer + Samsung 双格式)
        val xmpString = """<x:xmpmeta xmlns:x="adobe:ns:meta/" x:xmptk="Adobe XMP Core 5.1.0-jc003">
  <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
    <rdf:Description rdf:about=""
        xmlns:GCamera="http://ns.google.com/photos/1.0/camera/"
        xmlns:Container="http://ns.google.com/photos/1.0/container/"
        xmlns:Item="http://ns.google.com/photos/1.0/container/item/"
        xmlns:Camera="http://ns.google.com/photos/1.0/camera/"
        xmlns:samsung="http://ns.samsung.com/photo/1.0/"
        GCamera:MotionPhoto="1"
        GCamera:MotionPhotoVersion="1"
        GCamera:MotionPhotoPresentationTimestampUs="$effectiveTimestampUs"
        GCamera:MicroVideo="1"
        GCamera:MicroVideoVersion="1"
        GCamera:MicroVideoOffset="$microVideoOffset"
        GCamera:MicroVideoPresentationTimestampUs="$effectiveTimestampUs"
        Camera:MotionPhoto="1"
        Camera:MicroVideo="1"
        Camera:MicroVideoOffset="$microVideoOffset"
        samsung:MotionPhoto="1"
        samsung:MotionPhotoVersion="1"
        samsung:MotionPhoto_Data="1"
        samsung:SEFType="2048"
        samsung:SpecialType="2048">
      <Container:Directory>
        <rdf:Seq>
          <rdf:li rdf:parseType="Resource">
            <Item:Mime>image/jpeg</Item:Mime>
            <Item:Semantic>Primary</Item:Semantic>
            <Item:Length>0</Item:Length>
            <Item:Padding>24</Item:Padding>
          </rdf:li>
          <rdf:li rdf:parseType="Resource">
            <Item:Mime>video/mp4</Item:Mime>
            <Item:Semantic>MotionPhoto</Item:Semantic>
            <Item:Length>$videoLength</Item:Length>
            <Item:Padding>$sefBlockSize</Item:Padding>
          </rdf:li>
        </rdf:Seq>
      </Container:Directory>
    </rdf:Description>
  </rdf:RDF>
</x:xmpmeta>
"""
        val xmpBytes = xmpString.toByteArray(Charsets.UTF_8)

        // 3. 将 XMP APP1 注入 JPEG
        val jpgWithXmp = injectXmpApp1Native(watermarkedJpgBytes, xmpBytes)

        // 4. 拼接 JPEG 与 SEF Trailer
        val result = ByteArray(jpgWithXmp.size + sefTrailerBytes.size)
        System.arraycopy(jpgWithXmp, 0, result, 0, jpgWithXmp.size)
        System.arraycopy(sefTrailerBytes, 0, result, jpgWithXmp.size, sefTrailerBytes.size)

        return result
    }

    private fun injectXmpApp1Native(jpgBytes: ByteArray, xmpBytes: ByteArray): ByteArray {
        if (jpgBytes.size < 4 || jpgBytes[0] != 0xFF.toByte() || jpgBytes[1] != 0xD8.toByte()) {
            return jpgBytes
        }

        val nsBytes = "http://ns.adobe.com/xap/1.0/\u0000".toByteArray(Charsets.UTF_8)
        val markerLen = nsBytes.size + xmpBytes.size + 2
        val app1Seg = ByteArrayOutputStream(4 + nsBytes.size + xmpBytes.size)
        app1Seg.write(0xFF)
        app1Seg.write(0xE1)
        app1Seg.write((markerLen shr 8) and 0xFF)
        app1Seg.write(markerLen and 0xFF)
        app1Seg.write(nsBytes)
        app1Seg.write(xmpBytes)
        val newApp1 = app1Seg.toByteArray()

        val out = ByteArrayOutputStream(jpgBytes.size + newApp1.size)
        out.write(0xFF)
        out.write(0xD8)

        var offset = 2
        var insertPos = 2

        while (offset + 4 < jpgBytes.size) {
            if (jpgBytes[offset] != 0xFF.toByte()) break
            val marker = jpgBytes[offset + 1].toInt() and 0xFF
            if (marker == 0xDA || marker == 0xD9) break
            val len = ((jpgBytes[offset + 2].toInt() and 0xFF) shl 8) or (jpgBytes[offset + 3].toInt() and 0xFF)
            val segEnd = offset + 2 + len
            if (marker == 0xE0 || (marker == 0xE1 && !isXmpSegmentNative(jpgBytes, offset, nsBytes))) {
                insertPos = segEnd
            }
            offset = segEnd
        }

        offset = 2
        var xmpWritten = false
        while (offset + 4 < jpgBytes.size) {
            if (jpgBytes[offset] != 0xFF.toByte()) {
                out.write(jpgBytes, offset, jpgBytes.size - offset)
                break
            }
            val marker = jpgBytes[offset + 1].toInt() and 0xFF
            if (marker == 0xDA || marker == 0xD9) {
                if (!xmpWritten) {
                    out.write(newApp1)
                    xmpWritten = true
                }
                out.write(jpgBytes, offset, jpgBytes.size - offset)
                break
            }
            val len = ((jpgBytes[offset + 2].toInt() and 0xFF) shl 8) or (jpgBytes[offset + 3].toInt() and 0xFF)
            val segEnd = offset + 2 + len

            if (marker == 0xE1 && isXmpSegmentNative(jpgBytes, offset, nsBytes)) {
                // 跳过旧 XMP 段
                offset = segEnd
                continue
            }

            out.write(jpgBytes, offset, segEnd - offset)
            if (!xmpWritten && segEnd >= insertPos) {
                out.write(newApp1)
                xmpWritten = true
            }
            offset = segEnd
        }

        if (!xmpWritten) {
            out.write(newApp1)
        }

        return out.toByteArray()
    }

    private fun isXmpSegmentNative(bytes: ByteArray, offset: Int, nsBytes: ByteArray): Boolean {
        if (offset + 4 + nsBytes.size > bytes.size) return false
        for (i in nsBytes.indices) {
            if (bytes[offset + 4 + i] != nsBytes[i]) return false
        }
        return true
    }

    /** 快速检测文件是否为动态照片 (Motion Photo / MicroVideo / SEF) */
    private fun checkIsMotionPhotoFile(path: String): Boolean {
        try {
            val file = File(path)
            if (!file.exists()) return false
            val length = file.length()
            if (length < 2048) return false

            java.io.RandomAccessFile(file, "r").use { raf ->
                // 1. 检查文件尾部 8KB 是否包含三星 SEFT 结构且含有 MotionPhoto_Data 标记
                val tailSize = if (length > 8192) 8192 else length.toInt()
                raf.seek(length - tailSize)
                val tailBytes = ByteArray(tailSize)
                raf.readFully(tailBytes)

                if (tailSize >= 4 &&
                    tailBytes[tailSize - 4] == 0x53.toByte() && // S
                    tailBytes[tailSize - 3] == 0x45.toByte() && // E
                    tailBytes[tailSize - 2] == 0x46.toByte() && // F
                    tailBytes[tailSize - 1] == 0x54.toByte()    // T
                ) {
                    val tailStr = String(tailBytes, Charsets.ISO_8859_1)
                    if (tailStr.contains("MotionPhoto_Data")) {
                        return true
                    }
                }

                // 2. 检查头部 512KB 是否包含 Google / 小米 / OPPO / vivo / 三星 XMP 动态照片标签
                val headSize = if (length > 524288) 524288 else length.toInt()
                raf.seek(0)
                val headBytes = ByteArray(headSize)
                raf.readFully(headBytes)

                val headStr = String(headBytes, Charsets.ISO_8859_1)
                if (headStr.contains("MotionPhoto=\"1\"") ||
                    headStr.contains("MotionPhoto='1'") ||
                    headStr.contains("MicroVideo=\"1\"") ||
                    headStr.contains("MicroVideo='1'") ||
                    headStr.contains("MicroVideoOffset") ||
                    headStr.contains("Item:Semantic=\"MotionPhoto\"") ||
                    headStr.contains("samsung:MotionPhoto=\"1\"")
                ) {
                    return true
                }
            }
        } catch (_: Exception) {}
        return false
    }
}
