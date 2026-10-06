package com.example.watermark_samsung

import android.app.ActivityManager
import android.content.Context
import android.content.SharedPreferences
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.atomic.AtomicBoolean

/**
 * 运行时守护：设备内存画像查询、前台存活探针、OOM/崩溃探针与热状态推送。
 *
 * 所有能力均经由唯一 MethodChannel `com.example.watermark_samsung/ultra_hdr` 暴露：
 * - Dart → Kotlin: `getRuntimeMemoryInfo` / `getRuntimeState`
 * - Kotlin → Dart: `onThermalStatusChanged` / `onMemoryTrim`
 *
 * Dart 侧对应 `lib/services/runtime_guard.dart`，负责把内存档位换算成
 * 图片缓存与缩略图管线的容量，并在降级信号到来时收缩缓存。
 */
class RuntimeGuard(private val context: Context) {

    private val prefs: SharedPreferences =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    private val mainHandler = Handler(Looper.getMainLooper())
    private val installed = AtomicBoolean(false)
    private var channel: MethodChannel? = null
    private var thermalListener: PowerManager.OnThermalStatusChangedListener? = null

    /** 进程启动后尽早调用：接管未捕获异常，识别 OOM 并持久化降级标记。 */
    fun install() {
        if (!installed.compareAndSet(false, true)) return
        val previous = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { thread, throwable ->
            try {
                if (findOOM(throwable, maxCauseDepth = 8)) {
                    prefs.edit()
                        .putBoolean(KEY_OOM_RECOVERY_ACTIVE, true)
                        .putLong(KEY_LAST_OOM_AT_MS, System.currentTimeMillis())
                        .apply()
                }
                android.util.Log.i(
                    TAG,
                    "uncaught on ${thread.name}: ${throwable.javaClass.simpleName}"
                )
            } catch (_: Throwable) {
            }
            previous?.uncaughtException(thread, throwable)
                ?: run {
                    ProcessKiller.kill()
                }
        }
    }

    /**
     * 前台探针：正常退出必然经过 onStop 写回 false；
     * 若下次启动时仍为 true，说明上次会话在前台被异常终止 (崩溃/ANR/强杀)。
     */
    fun setForeground(active: Boolean) {
        prefs.edit().putBoolean(KEY_FOREGROUND_ACTIVE, active).apply()
    }

    /** 保存通道引用并注册热状态监听 (API 29+)；可安全重复调用。 */
    fun attachChannel(target: MethodChannel) {
        channel = target
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val existing = thermalListener
            if (existing == null) {
                val listener = PowerManager.OnThermalStatusChangedListener { status ->
                    pushToDart(EVENT_THERMAL, status)
                }
                thermalListener = listener
                try {
                    powerManager()?.addThermalStatusListener(
                        java.util.concurrent.Executor { mainHandler.post(it) },
                        listener
                    )
                } catch (_: Throwable) {
                    thermalListener = null
                }
            }
        }
    }

    fun detachChannel() {
        val listener = thermalListener
        if (listener != null) {
            try {
                powerManager()?.removeThermalStatusListener(listener)
            } catch (_: Throwable) {
            }
            thermalListener = null
        }
        channel = null
    }

    /** Dart 侧 `getRuntimeMemoryInfo`：设备内存画像，用于缓存分档。 */
    fun memoryInfo(): Map<String, Any> {
        val activityManager =
            context.getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager
        val memoryInfo = ActivityManager.MemoryInfo().also {
            activityManager?.getMemoryInfo(it)
        }
        return mapOf(
            "totalRamBytes" to (memoryInfo?.totalMem ?: 0L),
            "isLowRamDevice" to (activityManager?.isLowRamDevice == true),
            "memoryClass" to (activityManager?.memoryClass ?: 0)
        )
    }

    /** Dart 侧 `getRuntimeState`：上次会话健康度与当前降级状态。 */
    fun runtimeState(): Map<String, Any> {
        val lastOomAt = prefs.getLong(KEY_LAST_OOM_AT_MS, 0L)
        val active = prefs.getBoolean(KEY_OOM_RECOVERY_ACTIVE, false) &&
            System.currentTimeMillis() - lastOomAt < OOM_RECOVERY_WINDOW_MS
        if (active != prefs.getBoolean(KEY_OOM_RECOVERY_ACTIVE, false)) {
            prefs.edit().putBoolean(KEY_OOM_RECOVERY_ACTIVE, active).apply()
        }
        var thermalStatus = 0
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            thermalStatus = powerManager()?.currentThermalStatus ?: 0
        }
        return mapOf(
            "previousSessionCrashed" to prefs.getBoolean(KEY_FOREGROUND_ACTIVE, false),
            "oomRecoveryActive" to active,
            "lastOomAtMs" to lastOomAt,
            "thermalStatus" to thermalStatus
        )
    }

    /** Activity.onTrimMemory 转发：等级作为 int 推给 Dart 收缩缓存。 */
    fun onTrimMemory(level: Int) {
        pushToDart(EVENT_TRIM, level)
    }

    private fun powerManager(): PowerManager? =
        context.getSystemService(Context.POWER_SERVICE) as? PowerManager

    private fun pushToDart(method: String, argument: Any?) {
        val target = channel ?: return
        // 引擎销毁后 invoke 会抛异常；推丢失的信号会有下一次 trim/thermal 补偿。
        mainHandler.post {
            try {
                target.invokeMethod(method, argument)
            } catch (_: Throwable) {
            }
        }
    }

    private fun findOOM(throwable: Throwable, maxCauseDepth: Int): Boolean {
        var cause: Throwable? = throwable
        var depth = 0
        while (cause != null && depth < maxCauseDepth) {
            if (cause is OutOfMemoryError) return true
            cause = cause.cause
            depth++
        }
        return false
    }

    private object ProcessKiller {
        fun kill() {
            android.os.Process.killProcess(android.os.Process.myPid())
            kotlin.system.exitProcess(10)
        }
    }

    companion object {
        private const val TAG = "RuntimeGuard"
        private const val PREFS_NAME = "runtime_guard"
        private const val KEY_FOREGROUND_ACTIVE = "foreground_active"
        private const val KEY_OOM_RECOVERY_ACTIVE = "oom_recovery_active"
        private const val KEY_LAST_OOM_AT_MS = "last_oom_at_ms"
        private const val EVENT_THERMAL = "onThermalStatusChanged"
        private const val EVENT_TRIM = "onMemoryTrim"

        /** OOM 后保守降级窗口：窗口过后自动恢复正常档位。 */
        private const val OOM_RECOVERY_WINDOW_MS = 48 * 60 * 60 * 1000L
    }
}
