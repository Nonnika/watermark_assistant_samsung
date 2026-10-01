package com.example.watermark_samsung

import android.app.Activity
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Gainmap
import android.graphics.ImageDecoder
import android.graphics.Paint
import android.graphics.Rect
import android.graphics.RectF
import android.net.Uri
import android.os.Build
import android.os.Process
import android.util.Log
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.File
import java.nio.ByteBuffer
import java.util.concurrent.ExecutorService

private const val TAG_UHDR = "UltraHDR"

/** Ultra HDR / Gainmap 原生编码：Gainmap 探测、提取与全分辨率合成 */
class UltraHdrEncoder(
    private val activity: Activity,
    private val heavyTaskExecutor: ExecutorService
) {
    fun hasGainmap(call: MethodCall, result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            result.success(null) // 不支持检测，Dart 可解析完整 JPEG 回退。
            return
        }
        val bytes = call.argument<ByteArray>("bytes")
        val path = call.argument<String>("path")
        val uri = call.argument<String>("uri")
        heavyTaskExecutor.execute {
            Process.setThreadPriority(Process.THREAD_PRIORITY_LESS_FAVORABLE)
            val has: Boolean? = activity.runWithAdpfBoost(50L) {
                try {
                    val source = when {
                        bytes != null -> ImageDecoder.createSource(ByteBuffer.wrap(bytes))
                        !uri.isNullOrEmpty() -> ImageDecoder.createSource(activity.contentResolver, Uri.parse(uri))
                        !path.isNullOrEmpty() -> ImageDecoder.createSource(File(path))
                        else -> return@runWithAdpfBoost null
                    }
                    val bitmap = ImageDecoder.decodeBitmap(source) { decoder, info, _ ->
                        // 采样仍保留增益图，避免相册并发探测时解码多张全分辨率照片。
                        decoder.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
                        val sample = ((maxOf(info.size.width, info.size.height) + 255) / 256).coerceAtLeast(1)
                        decoder.setTargetSampleSize(sample)
                    }
                    try {
                        bitmap.hasGainmap()
                    } finally {
                        bitmap.recycle()
                    }
                } catch (e: Exception) {
                    Log.w(TAG_UHDR, "hasGainmap decode failed: ${e.message}")
                    null // 解码失败不等于 SDR，也不能写入相册的否定缓存。
                }
            }
            activity.runOnUiThread { result.success(has) }
        }
    }

    fun getUltraHdrGainmap(call: MethodCall, result: MethodChannel.Result) {
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
                        activity.runOnUiThread { result.success(resultMap) }
                        return@execute
                    }
                    bitmap.recycle()
                    activity.runOnUiThread { result.success(null) }
                } catch (e: Exception) {
                    Log.w(TAG_UHDR, "getUltraHdrGainmap error: ${e.message}")
                    activity.runOnUiThread { result.success(null) }
                }
            }
        } else {
            result.success(null)
        }
    }

    fun processUltraHdrImage(call: MethodCall, result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            result.error("UNSUPPORTED", "Ultra HDR requires Android 14+", null)
            return
        }

        val originalBytes = call.argument<ByteArray>("originalBytes") ?: run {
            result.error("INVALID_ARGS", "Missing originalBytes", null)
            return
        }
        val sdrCompositeBytes = call.argument<ByteArray>("sdrCompositeBytes") ?: run {
            result.error("INVALID_ARGS", "Missing sdrCompositeBytes", null)
            return
        }
        val photoLeft = (call.argument<Double>("photoLeft") ?: 0.0).toFloat()
        val photoTop = (call.argument<Double>("photoTop") ?: 0.0).toFloat()
        val photoWidth = (call.argument<Double>("photoWidth") ?: 0.0).toFloat()
        val photoHeight = (call.argument<Double>("photoHeight") ?: 0.0).toFloat()
        val totalWidth = (call.argument<Double>("totalWidth") ?: 0.0).toFloat()
        val totalHeight = (call.argument<Double>("totalHeight") ?: 0.0).toFloat()
        val quality = call.argument<Int>("quality") ?: 95

        Log.d(TAG_UHDR, "processUltraHdrImage: origBytes=${originalBytes.size}, sdrBytes=${sdrCompositeBytes.size}")
        Log.d(TAG_UHDR, "  photo: left=$photoLeft top=$photoTop w=$photoWidth h=$photoHeight")
        Log.d(TAG_UHDR, "  total: w=$totalWidth h=$totalHeight quality=$quality")

        // 高通 SoC 优化：全分辨率解码 + Gainmap 合成 + JPEG 编码全部移出主线程，
        // 并通过 ADPF Hint Session 调度至 Snapdragon Prime/Big 核心满频运行
        heavyTaskExecutor.execute {
            Process.setThreadPriority(Process.THREAD_PRIORITY_LESS_FAVORABLE)
            // 全部位图在 finally 统一回收：50MP ARGB_8888 单张 ~200MB，
            // 异常路径泄漏一两张即可 OOM。recycle() 幂等，重复调用安全
            var origBitmap: Bitmap? = null
            var origGmCopy: Bitmap? = null
            var sdrBitmap: Bitmap? = null
            var newGmBitmap: Bitmap? = null
            var verifyBitmap: Bitmap? = null
            var exifTempFile: File? = null
            try {
                val outputBytes = activity.runWithAdpfBoost(300L) processUltraHdr@{
                    // 1. 用 ImageDecoder 解码原图
                    val origSource = ImageDecoder.createSource(ByteBuffer.wrap(originalBytes))
                    origBitmap = ImageDecoder.decodeBitmap(origSource) { _, _, _ -> }
                    Log.d(TAG_UHDR, "  origBitmap: ${origBitmap!!.width}x${origBitmap!!.height}, config=${origBitmap!!.config}, hasGainmap=${origBitmap!!.hasGainmap()}")

                    if (!origBitmap!!.hasGainmap()) {
                        Log.w(TAG_UHDR, "  Original image has NO gainmap! Cannot produce Ultra HDR.")
                        return@processUltraHdr sdrCompositeBytes
                    }

                    val originalGainmap = origBitmap!!.gainmap!!
                    val origGmContentsRaw = originalGainmap.gainmapContents
                    val origGmContents = if (origGmContentsRaw.config == Bitmap.Config.HARDWARE) {
                        origGmContentsRaw.copy(Bitmap.Config.ARGB_8888, false).also { origGmCopy = it }
                    } else {
                        origGmContentsRaw
                    }
                    Log.d(TAG_UHDR, "  originalGainmap: contents=${origGmContents.width}x${origGmContents.height}, config=${origGmContents.config}")
                    Log.d(TAG_UHDR, "  displayRatioForFullHdr=${originalGainmap.displayRatioForFullHdr}")
                    Log.d(TAG_UHDR, "  ratioMin=${originalGainmap.ratioMin.toList()}")
                    Log.d(TAG_UHDR, "  ratioMax=${originalGainmap.ratioMax.toList()}")
                    Log.d(TAG_UHDR, "  gamma=${originalGainmap.gamma.toList()}")

                    // 2. 解码 SDR 合成图并确保可变
                    val sdrBitmapRaw = BitmapFactory.decodeByteArray(sdrCompositeBytes, 0, sdrCompositeBytes.size)
                    if (sdrBitmapRaw == null) {
                        Log.e(TAG_UHDR, "  SDR composite decode failed (null bitmap)")
                        return@processUltraHdr sdrCompositeBytes
                    }
                    sdrBitmap = sdrBitmapRaw.copy(Bitmap.Config.ARGB_8888, true)
                    sdrBitmapRaw.recycle()
                    Log.d(TAG_UHDR, "  sdrBitmap: ${sdrBitmap!!.width}x${sdrBitmap!!.height}, isMutable=${sdrBitmap!!.isMutable}")

                    // 3. 构建与合成画幅对齐的新 Gainmap
                    val targetGmWidth = origGmContents.width.coerceIn(256, 4096)
                    val ratio = totalHeight / totalWidth
                    val targetGmHeight = (targetGmWidth * ratio).toInt().coerceIn(256, 4096)
                    Log.d(TAG_UHDR, "  targetGainmap: ${targetGmWidth}x${targetGmHeight}")

                    newGmBitmap = Bitmap.createBitmap(targetGmWidth, targetGmHeight, Bitmap.Config.ARGB_8888)
                    val gmCanvas = Canvas(newGmBitmap!!)
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
                    Log.d(TAG_UHDR, "  drew gainmap from src=$srcRect to dst=$dstRect")

                    if (origGmContents !== origGmContentsRaw) {
                        origGmContents.recycle()
                    }

                    // 4. 创建新 Gainmap 并复制所有元数据
                    val newGainmap = Gainmap(newGmBitmap!!)
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
                    sdrBitmap!!.gainmap = newGainmap
                    Log.d(TAG_UHDR, "  sdrBitmap after attach: hasGainmap=${sdrBitmap!!.hasGainmap()}")

                    // 6. 压缩为 JPEG
                    val stream = ByteArrayOutputStream()
                    val compressSuccess = sdrBitmap!!.compress(Bitmap.CompressFormat.JPEG, quality, stream)
                    var outputBytes = stream.toByteArray()
                    Log.d(TAG_UHDR, "  compressed output (success=$compressSuccess): ${outputBytes.size} bytes")

                    // 7. 注入/保留原图 EXIF 元数据
                    try {
                        val tempFile = File.createTempFile("uhdr_export_", ".jpg", activity.cacheDir)
                        exifTempFile = tempFile
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
                    } catch (exifErr: Exception) {
                        Log.w(TAG_UHDR, "Exif preservation in JPEG failed: ${exifErr.message}")
                    } finally {
                        try { exifTempFile?.delete() } catch (_: Exception) {}
                    }

                    // 8. 严格验证输出是否包含 Gainmap
                    val verifySource = ImageDecoder.createSource(ByteBuffer.wrap(outputBytes))
                    verifyBitmap = ImageDecoder.decodeBitmap(verifySource) { _, _, _ -> }
                    val outputHasGainmap = verifyBitmap!!.hasGainmap()
                    Log.d(TAG_UHDR, "  OUTPUT VERIFICATION: hasGainmap=$outputHasGainmap")

                    if (!outputHasGainmap) {
                        Log.w(TAG_UHDR, "  Native output has no gainmap; returning null to allow Dart Ultra HDR synthesis")
                        return@processUltraHdr null
                    }

                    outputBytes
                }
                activity.runOnUiThread { result.success(outputBytes) }
            } catch (e: Exception) {
                Log.e(TAG_UHDR, "processUltraHdrImage FAILED: ${e.message}", e)
                activity.runOnUiThread { result.error("PROCESSING_FAILED", e.localizedMessage, e.stackTraceToString()) }
            } finally {
                try { origBitmap?.recycle() } catch (_: Throwable) {}
                try { origGmCopy?.recycle() } catch (_: Throwable) {}
                try { sdrBitmap?.recycle() } catch (_: Throwable) {}
                try { newGmBitmap?.recycle() } catch (_: Throwable) {}
                try { verifyBitmap?.recycle() } catch (_: Throwable) {}
                try { exifTempFile?.delete() } catch (_: Exception) {}
            }
        }
    }
}
