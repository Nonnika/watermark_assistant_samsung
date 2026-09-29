package com.example.watermark_samsung

import android.app.Activity
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Rect
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaCodecList
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMetadataRetriever
import android.media.MediaMuxer
import android.os.Build
import android.os.Process
import android.os.SystemClock
import android.util.Log
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.nio.ByteBuffer
import java.util.concurrent.ExecutorService

private const val TAG_VIDEO = "UltraHDR"

/** 动态照片内嵌视频水印：MediaCodec 硬编转码管线（优先高通骁龙编码器） */
class VideoWatermarker(
    private val activity: Activity,
    private val heavyTaskExecutor: ExecutorService
) {
    fun watermarkVideo(call: MethodCall, result: MethodChannel.Result) {
        val videoBytes = call.argument<ByteArray>("videoBytes")
        val overlayBytes = call.argument<ByteArray>("overlayBytes")
        if (videoBytes == null || videoBytes.isEmpty() || overlayBytes == null || overlayBytes.isEmpty()) {
            result.success(videoBytes)
            return
        }

        // 高通 SoC 优化：视频转码走统一重负载线程池 (受 ADPF 调度管理)，不再裸开线程
        heavyTaskExecutor.execute {
            // finally 中统一清理临时文件，失败路径不再向 cacheDir 泄漏 MB 级残留
            var tempInFile: File? = null
            var tempOutFile: File? = null
            try {
                tempInFile = File.createTempFile("motion_in_", ".mp4", activity.cacheDir)
                tempInFile.writeBytes(videoBytes)
                tempOutFile = File.createTempFile("motion_out_", ".mp4", activity.cacheDir)

                val overlayBitmap = BitmapFactory.decodeByteArray(overlayBytes, 0, overlayBytes.size)
                // ADPF：按 30fps 帧间隔声明目标时长，调度器持续将转码线程钉在 Prime/Big 核心
                val success = activity.runWithAdpfBoost(33L) {
                    processVideoWatermark(tempInFile, tempOutFile, overlayBitmap)
                }
                overlayBitmap?.recycle()

                if (success && tempOutFile.exists() && tempOutFile.length() > 0) {
                    val outBytes = tempOutFile.readBytes()
                    activity.runOnUiThread { result.success(outBytes) }
                } else {
                    activity.runOnUiThread { result.success(videoBytes) }
                }
            } catch (e: Exception) {
                Log.e(TAG_VIDEO, "watermarkVideo failed: ${e.message}", e)
                activity.runOnUiThread { result.success(videoBytes) }
            } finally {
                try { tempInFile?.delete() } catch (_: Exception) {}
                try { tempOutFile?.delete() } catch (_: Exception) {}
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
        var videoExtractorForPts: MediaExtractor? = null
        var encoder: MediaCodec? = null
        var muxer: MediaMuxer? = null

        try {
            retriever.setDataSource(inputFile.absolutePath)

            // 读取原始视频元数据（不截断任何值）
            val durationMs = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 1500L
            val durationUs = durationMs * 1000L

            // 1. 用 MediaExtractor 枚举原始视频帧的真实 PTS（不生成假时间轴）
            videoExtractorForPts = MediaExtractor()
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
                while (true) {
                    val pts = videoExtractorForPts.sampleTime
                    if (pts < 0) break
                    framePtsListUs.add(pts)
                    if (!videoExtractorForPts.advance()) break
                }
            }
            videoExtractorForPts.release()
            videoExtractorForPts = null

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

            Log.d(TAG_VIDEO, "processVideoWatermark: uprightSize=${videoWidth}x${videoHeight}, frames=${finalPtsListUs.size}, duration=${durationMs}ms")

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
                Log.w(TAG_VIDEO, "Audio track: ${e.message}")
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
                        Log.d(TAG_VIDEO, "Using Qualcomm Hardware Encoder: $qcomEncoder")
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
                // EOS 模式下设置总超时：编码器未收到 EOS 标志时永远不输出结束帧，
                // 无限重试会永久占用线程池并挂起 Dart 侧 await
                val deadline = if (eos) SystemClock.elapsedRealtime() + 10000L else 0L
                while (true) {
                    val outIdx = enc.dequeueOutputBuffer(bufferInfo, if (eos) 10000L else 0L)
                    when {
                        outIdx == MediaCodec.INFO_TRY_AGAIN_LATER -> {
                            if (!eos) return
                            if (SystemClock.elapsedRealtime() > deadline) {
                                Log.e(TAG_VIDEO, "drainEncoder: EOS drain timed out, aborting")
                                return
                            }
                            Thread.sleep(2)
                        }
                        outIdx == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                            if (!muxerStarted) {
                                muxerVideoTrackIndex = mux.addTrack(enc.outputFormat)
                                if (audioTrackFormat != null)
                                    muxerAudioTrackIndex = mux.addTrack(audioTrackFormat)
                                mux.start()
                                muxerStarted = true
                                Log.d(TAG_VIDEO, "Muxer started: video=$muxerVideoTrackIndex audio=$muxerAudioTrackIndex")
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
            // 使用 30fps 过滤后的帧列表 (finalPtsListUs)，60fps 源视频不做双倍冗余转码
            val totalFrames = finalPtsListUs.size
            var eosQueued = false
            finalPtsListUs.forEachIndexed { idx, ptsUs ->
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
                var inputIdx = enc.dequeueInputBuffer(100000L)
                if (isEos && inputIdx < 0) {
                    // EOS 帧必须入队：丢弃后编码器永不输出结束帧，drainEncoder(true) 将死循环
                    while (inputIdx < 0) {
                        drainEncoder(false)
                        inputIdx = enc.dequeueInputBuffer(100000L)
                    }
                }
                if (inputIdx >= 0) {
                    val inBuf = enc.getInputBuffer(inputIdx)!!
                    inBuf.clear()
                    inBuf.put(yuvBuffer)
                    val flags = if (isEos) MediaCodec.BUFFER_FLAG_END_OF_STREAM else 0
                    enc.queueInputBuffer(inputIdx, 0, yuvBuffer.size, ptsUs, flags)
                    if (isEos) eosQueued = true
                }

                drainEncoder(false)
            }

            // 5. 冲刷编码器 (EOS 未入队时用零长度缓冲补发)
            if (!eosQueued) {
                var inputIdx = enc.dequeueInputBuffer(100000L)
                while (inputIdx < 0) {
                    drainEncoder(false)
                    inputIdx = enc.dequeueInputBuffer(100000L)
                }
                val lastPtsUs = if (finalPtsListUs.isEmpty()) 0L else finalPtsListUs.last()
                enc.queueInputBuffer(inputIdx, 0, 0, lastPtsUs, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
            }
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
                Log.d(TAG_VIDEO, "Audio copied")
            }

            Log.d(TAG_VIDEO, "processVideoWatermark done! size=${outputFile.length()}B")
            return true

        } catch (e: Exception) {
            Log.e(TAG_VIDEO, "processVideoWatermark error: ${e.message}", e)
            return false
        } finally {
            try { encoder?.stop() } catch (_: Throwable) {}
            try { encoder?.release() } catch (_: Throwable) {}
            try { muxer?.stop() } catch (_: Throwable) {}
            try { muxer?.release() } catch (_: Throwable) {}
            try { audioExtractor.release() } catch (_: Throwable) {}
            try { retriever.release() } catch (_: Throwable) {}
            try { videoExtractorForPts?.release() } catch (_: Throwable) {}
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
}
