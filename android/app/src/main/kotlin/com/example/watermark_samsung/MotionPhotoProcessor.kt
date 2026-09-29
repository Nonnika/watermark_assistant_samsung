package com.example.watermark_samsung

import android.app.Activity
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Process
import android.util.Log
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.ExecutorService

private const val TAG_MOTION = "UltraHDR"

/** 动态照片原生管线：完整文件读取、MP4 视频流提取与 SEF/XMP 合成的通道入口 */
class MotionPhotoProcessor(
    private val activity: Activity,
    private val heavyTaskExecutor: ExecutorService
) {
    fun extractMotionPhotoNative(call: MethodCall, result: MethodChannel.Result) {
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
                            Log.d(TAG_MOTION, "extractMotionPhotoNative: read ${targetBytes.size}B from path")
                        }
                    } catch (e: Exception) {
                        Log.w(TAG_MOTION, "extractMotionPhotoNative: path read failed: ${e.message}")
                    }
                }

                // 2. 备选: ContentResolver URI (处理 Android Q+ scoped storage)
                if (targetBytes == null && uriStr != null && uriStr.isNotEmpty()) {
                    try {
                        val uri = Uri.parse(uriStr)
                        activity.contentResolver.openInputStream(uri)?.use { stream ->
                            targetBytes = stream.readBytes()
                            Log.d(TAG_MOTION, "extractMotionPhotoNative: read ${targetBytes?.size}B from URI")
                        }
                    } catch (e: Exception) {
                        Log.w(TAG_MOTION, "extractMotionPhotoNative: URI read failed: ${e.message}")
                    }
                }

                // 3. 最终回退: 使用 Dart 传入的 bytes (可能是部分字节)
                if (targetBytes == null && bytesArg != null && bytesArg.isNotEmpty()) {
                    targetBytes = bytesArg
                    Log.d(TAG_MOTION, "extractMotionPhotoNative: using Dart bytes (${bytesArg.size}B), may be truncated for large HEIC")
                }

                val finalBytes = targetBytes
                if (finalBytes == null || finalBytes.isEmpty() || finalBytes.size < 64) {
                    activity.runOnUiThread { result.success(mapOf("isMotionPhoto" to false)) }
                    return@execute
                }

                val info = nativeExtractMotionVideo(finalBytes)
                if (info != null) {
                    Log.d(TAG_MOTION, "extractMotionPhotoNative: extracted ${info.first.size}B video, ts=${info.second}us, offset=${info.third}")
                    activity.runOnUiThread {
                        result.success(mapOf(
                            "isMotionPhoto" to true,
                            "videoBytes" to info.first,
                            "presentationTimestampUs" to info.second,
                            "offset" to info.third,
                            "length" to info.first.size
                        ))
                    }
                } else {
                    Log.d(TAG_MOTION, "extractMotionPhotoNative: not a motion photo (${finalBytes.size}B)")
                    activity.runOnUiThread { result.success(mapOf("isMotionPhoto" to false)) }
                }
            } catch (e: Exception) {
                Log.e(TAG_MOTION, "extractMotionPhotoNative error: ${e.message}", e)
                activity.runOnUiThread { result.success(mapOf("isMotionPhoto" to false)) }
            }
        }
    }

    fun compositeMotionPhotoNative(call: MethodCall, result: MethodChannel.Result) {
        val jpgBytes = call.argument<ByteArray>("watermarkedJpgBytes")
        val videoBytes = call.argument<ByteArray>("motionVideoBytes")
        val ts = (call.argument<Number>("presentationTimestampUs"))?.toLong() ?: 0L

        if (jpgBytes == null || jpgBytes.isEmpty() || videoBytes == null || videoBytes.isEmpty()) {
            result.error("INVALID_ARGS", "Missing jpg or video bytes", null)
            return
        }

        heavyTaskExecutor.execute {
            Process.setThreadPriority(Process.THREAD_PRIORITY_LESS_FAVORABLE)
            try {
                val composited = SefTrailerCodec.nativeCompositeMotionPhoto(jpgBytes, videoBytes, ts)
                activity.runOnUiThread { result.success(composited) }
            } catch (e: Exception) {
                Log.e(TAG_MOTION, "compositeMotionPhotoNative error: ${e.message}", e)
                activity.runOnUiThread { result.error("COMPOSITE_FAILED", e.localizedMessage, null) }
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
        val sefPair = SefTrailerCodec.parseSamsungSefNative(bytes)
        if (sefPair != null && SefTrailerCodec.isValidMp4HeaderNative(bytes, sefPair.first)) {
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
                    if (SefTrailerCodec.isValidMp4HeaderNative(bytes, calcOffset)) {
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
                        if (SefTrailerCodec.isValidMp4HeaderNative(bytes, calcOffset)) {
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
                    if (SefTrailerCodec.isValidMp4HeaderNative(bytes, i)) {
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
                val tempFile = File.createTempFile("mphoto_probe_", ".mp4", activity.cacheDir)
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
}
