package com.example.watermark_samsung

import android.Manifest
import android.content.Intent
import android.content.pm.ActivityInfo
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import androidx.annotation.NonNull
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * 单一 MethodChannel `com.example.watermark_samsung/ultra_hdr` 的装配层：
 * 仅负责通道注册、权限与 HDR 窗口模式等 Activity 绑定逻辑，其余能力按功能域
 * 委托给 [UltraHdrEncoder]、[MediaStoreHelper]、[VideoWatermarker]、[MotionPhotoProcessor]、
 * 字节级 [SefTrailerCodec] 与运行时守护 [RuntimeGuard]。
 */
class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.watermark_samsung/ultra_hdr"
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

    private val ultraHdrEncoder by lazy { UltraHdrEncoder(this, heavyTaskExecutor) }
    private val mediaStoreHelper by lazy { MediaStoreHelper(this, heavyTaskExecutor, thumbnailExecutor) }
    private val videoWatermarker by lazy { VideoWatermarker(this, heavyTaskExecutor) }
    private val motionPhotoProcessor by lazy { MotionPhotoProcessor(this, heavyTaskExecutor) }
    private val runtimeGuard by lazy { RuntimeGuard(this) }

    override fun onDestroy() {
        runtimeGuard.detachChannel()
        thumbnailExecutor.shutdown()
        heavyTaskExecutor.shutdown()
        super.onDestroy()
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        // 在引擎初始化前接管未捕获异常，OOM 标记才能覆盖启动阶段
        runtimeGuard.install()
        super.onCreate(savedInstanceState)
        enableHdrMode(true)
    }

    override fun onStart() {
        super.onStart()
        runtimeGuard.setForeground(true)
    }

    override fun onStop() {
        runtimeGuard.setForeground(false)
        super.onStop()
    }

    override fun onTrimMemory(level: Int) {
        super.onTrimMemory(level)
        runtimeGuard.onTrimMemory(level)
    }

    private fun enableHdrMode(enable: Boolean) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            window.colorMode = if (enable) ActivityInfo.COLOR_MODE_HDR else ActivityInfo.COLOR_MODE_DEFAULT
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            window.colorMode = if (enable) ActivityInfo.COLOR_MODE_WIDE_COLOR_GAMUT else ActivityInfo.COLOR_MODE_DEFAULT
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
        // 若上一次请求的 Result 尚未回复（系统对话框仍在显示时再次请求），
        // 先完成旧的 Result，否则对应的 Dart Future 会永久挂起
        pendingPermissionResult?.success(false)
        pendingPermissionResult = result
        ActivityCompat.requestPermissions(this, permissions, REQUEST_STORAGE_PERMISSION_CODE)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQUEST_STORAGE_PERMISSION_CODE) {
            // 与 checkStoragePermission 保持一致：Android 14 "选择照片"仅授予
            // READ_MEDIA_VISUAL_USER_SELECTED 时也视为已授权，避免把成功授权误报为拒绝
            val granted = checkStoragePermission()
            pendingPermissionResult?.success(granted)
            pendingPermissionResult = null
        }
    }

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        runtimeGuard.attachChannel(channel)
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "getRuntimeMemoryInfo" -> {
                    result.success(runtimeGuard.memoryInfo())
                }
                "getRuntimeState" -> {
                    result.success(runtimeGuard.runtimeState())
                }
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
                "hasGainmap" -> ultraHdrEncoder.hasGainmap(call, result)
                "getUltraHdrGainmap" -> ultraHdrEncoder.getUltraHdrGainmap(call, result)
                "processUltraHdrImage" -> ultraHdrEncoder.processUltraHdrImage(call, result)
                "saveImageToGallery" -> mediaStoreHelper.saveImageToGallery(call, result)
                "getRecentPhotos" -> mediaStoreHelper.getRecentPhotos(call, result)
                "scanMotionPhotos" -> mediaStoreHelper.scanMotionPhotos(call, result)
                "getPhotoThumbnail" -> mediaStoreHelper.getPhotoThumbnail(call, result)
                "getPhotoBytes" -> mediaStoreHelper.getPhotoBytes(call, result)
                "getExif" -> mediaStoreHelper.getExif(call, result)
                "compressRgbaToJpeg" -> mediaStoreHelper.compressRgbaToJpeg(call, result)
                "watermarkVideo" -> videoWatermarker.watermarkVideo(call, result)
                "extractMotionPhotoNative" -> motionPhotoProcessor.extractMotionPhotoNative(call, result)
                "compositeMotionPhotoNative" -> motionPhotoProcessor.compositeMotionPhotoNative(call, result)
                else -> result.notImplemented()
            }
        }
    }
}
