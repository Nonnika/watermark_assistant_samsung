package com.example.watermark_samsung

import android.app.Activity
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.PorterDuff
import android.graphics.PorterDuffXfermode
import android.os.Process
import android.util.Log
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.ExecutorService
import java.util.concurrent.atomic.AtomicInteger

private const val TAG_TILED = "TiledJpeg"

/**
 * 分块 RGBA → JPEG 编码会话。
 *
 * Dart 侧按 ≤4096 宽的小块在 GPU 上渲染并回读，逐块推送到这里拼进一张原生 Bitmap，
 * 最后一次性编码 JPEG。相比整幅 RGBA 一次性跨通道传输：GPU 不再需要整幅离屏渲染目标与
 * 回读缓冲（Adreno 与系统共享内存，且 Vulkan 单边上限 16384），Java 堆上也只存在单块
 * byte[]（Bitmap 像素位于 native 堆），避免数百 MB 的大数组分配与 GC 抖动。
 */
class TiledJpegEncoder(
    private val activity: Activity,
    private val heavyTaskExecutor: ExecutorService
) {
    private class Session(val bitmap: Bitmap) {
        val canvas = Canvas(bitmap)
        var closed = false
    }

    private val sessions = ConcurrentHashMap<Int, Session>()
    private val nextId = AtomicInteger(1)
    private val srcPaint = Paint().apply { xfermode = PorterDuffXfermode(PorterDuff.Mode.SRC) }

    fun begin(call: MethodCall, result: MethodChannel.Result) {
        val width = call.argument<Int>("width") ?: 0
        val height = call.argument<Int>("height") ?: 0
        if (width <= 0 || height <= 0) {
            result.error("INVALID_ARGS", "Invalid size ${width}x$height", null)
            return
        }
        heavyTaskExecutor.execute {
            try {
                // 导出是串行的：开始新会话前回收 Dart 侧异常退出后遗留的会话，防止整幅 Bitmap 泄漏
                for (id in sessions.keys.toList()) {
                    Log.w(TAG_TILED, "Evicting stale session $id")
                    release(id)
                }
                val session = Session(Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888))
                val id = nextId.getAndIncrement()
                sessions[id] = session
                activity.runOnUiThread { result.success(id) }
            } catch (e: Throwable) {
                Log.e(TAG_TILED, "begin failed: ${e.message}", e)
                activity.runOnUiThread { result.error("BEGIN_FAILED", e.localizedMessage, null) }
            }
        }
    }

    fun write(call: MethodCall, result: MethodChannel.Result) {
        val id = call.argument<Int>("session") ?: -1
        val x = call.argument<Int>("x") ?: 0
        val y = call.argument<Int>("y") ?: 0
        val width = call.argument<Int>("width") ?: 0
        val height = call.argument<Int>("height") ?: 0
        val rgba = call.argument<ByteArray>("rgba")
        val session = sessions[id]
        if (session == null || rgba == null || width <= 0 || height <= 0 ||
            rgba.size < width * height * 4
        ) {
            result.error("INVALID_ARGS", "Invalid tile for session $id", null)
            return
        }
        heavyTaskExecutor.execute {
            try {
                // Dart 回读的 rawRgba 为预乘 RGBA，与 ARGB_8888 的内存布局一致
                val tile = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
                try {
                    tile.copyPixelsFromBuffer(ByteBuffer.wrap(rgba, 0, width * height * 4))
                    synchronized(session) {
                        check(!session.closed) { "Session $id closed" }
                        session.canvas.drawBitmap(tile, x.toFloat(), y.toFloat(), srcPaint)
                    }
                } finally {
                    tile.recycle()
                }
                activity.runOnUiThread { result.success(null) }
            } catch (e: Throwable) {
                Log.e(TAG_TILED, "write failed: ${e.message}", e)
                activity.runOnUiThread { result.error("WRITE_FAILED", e.localizedMessage, null) }
            }
        }
    }

    fun finish(call: MethodCall, result: MethodChannel.Result) {
        val id = call.argument<Int>("session") ?: -1
        val quality = call.argument<Int>("quality") ?: 95
        val session = sessions.remove(id)
        if (session == null) {
            result.error("INVALID_ARGS", "Unknown session $id", null)
            return
        }
        heavyTaskExecutor.execute {
            Process.setThreadPriority(Process.THREAD_PRIORITY_LESS_FAVORABLE)
            try {
                val jpeg = activity.runWithAdpfBoost(150L) {
                    synchronized(session) {
                        check(!session.closed) { "Session $id closed" }
                        val bitmap = session.bitmap
                        val baos = ByteArrayOutputStream(bitmap.byteCount / 5)
                        bitmap.compress(Bitmap.CompressFormat.JPEG, quality, baos)
                        baos.toByteArray()
                    }
                }
                activity.runOnUiThread { result.success(jpeg) }
            } catch (e: Throwable) {
                Log.e(TAG_TILED, "finish failed: ${e.message}", e)
                activity.runOnUiThread { result.error("ENCODE_FAILED", e.localizedMessage, null) }
            } finally {
                close(session)
            }
        }
    }

    fun abort(call: MethodCall, result: MethodChannel.Result) {
        val id = call.argument<Int>("session") ?: -1
        heavyTaskExecutor.execute {
            release(id)
            activity.runOnUiThread { result.success(null) }
        }
    }

    private fun release(id: Int) {
        sessions.remove(id)?.let { close(it) }
    }

    private fun close(session: Session) {
        synchronized(session) {
            if (!session.closed) {
                session.closed = true
                session.bitmap.recycle()
            }
        }
    }
}
