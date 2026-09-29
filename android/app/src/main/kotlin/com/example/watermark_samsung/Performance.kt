package com.example.watermark_samsung

import android.content.Context
import android.os.Build
import android.os.PerformanceHintManager
import android.os.Process
import android.os.SystemClock

/**
 * 高通 Snapdragon ADPF (Android Dynamic Performance Framework) CPU 提速封装。
 *
 * 通过 PerformanceHintManager 创建 Hint Session，向调度器声明当前线程的预期工作时长，
 * 使 Snapdragon 的调度策略优先将本任务放置在 Prime/Big (Gold/Prime) 核心并提升频点，
 * 显著缩短全分辨率图像解码、Gainmap 合成与 JPEG 硬件编码的墙钟时间。
 * 在不支持 ADPF 的设备上静默退化为直接执行。
 */
inline fun <T> Context.runWithAdpfBoost(targetDurationMs: Long, block: () -> T): T {
    var session: PerformanceHintManager.Session? = null
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
        try {
            val manager = getSystemService(Context.PERFORMANCE_HINT_SERVICE) as PerformanceHintManager
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
