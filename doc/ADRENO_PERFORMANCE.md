# Adreno 预览性能

这些改动减少 Flutter 预览的纹理、采样及绘制开销，适用于高通 Adreno，也能让其他 Android GPU 受益。没有连接设备时，不能把功能测试或 APK 编译结果当作实际 GPU 加速数据。

## 已完成的改动

- 预览按长边限制在 1600 像素，小照片和 Logo 不放大。解码器、图片描述符和编码缓冲区均在成功或失败后释放；导出仍使用完整原始分辨率。
- 堆叠背景卡片直接使用 `ImageItem.decodedImage`，不再为同一照片生成额外解码缓存。图片画笔处理 55% 透明度，省去外层 `Opacity`。
- 主卡片在变换内设置重绘边界，切牌时复用照片图层。改变水印参数仍会正常重绘。背景卡片也隔离绘制。
- 实时预览使用 `FilterQuality.medium`，导出保留 `FilterQuality.high`。两者可能有轻微采样差异，最终以导出的照片为准。
- 顶部非重叠的按钮/徽章共享一个 `BackdropGroup`；选择器两个按钮另共享一组。覆盖这些按钮的渐进模糊单独处理，避免共享重叠滤镜的输入。
- 渐进模糊程序只加载一次，Shader/滤镜跟随组件复用与释放。保持 12 个圆盘采样点，预计算偏移，消除 Shader 中显式的逐片元三角函数和平方根；GLES 的纹理翻转不会再反转模糊渐变方向。不支持 Shader 滤镜时回退到普通高斯模糊。
- 导出中取消重复释放图片；合成图片和 Picture 在读回失败时也能释放。

以 3000×4000 的竖图为例，旧预览约为 1600×2133，新预览为 1200×1600。按 RGBA 的四字节像素计算，单张纹理从约 13.0 MiB 减为 7.3 MiB，少约 44%。这是尺寸推算，不包括 mipmap、驱动缓存和临时合成纹理，也不是帧率实测。

ADPF 是性能提示接口；当前 CPU Hint Session 不等于 GPU 提频，也不能保证线程固定在某个大核。不要根据现有代码注释推断 JPEG 编码经过 Adreno 或达到固定 120 FPS。

## 真机复测

连接高通 Android 真机后运行：

```sh
flutter run --profile -t tool/profile_adreno.dart -d <device-id>
```

该入口使用真实应用，跳过最初 60 帧，每 120 帧输出一次 build/raster 的 p50/p90/p99 和超过当前显示帧预算的数量。统计仅在有新绘制帧时推进，因此空闲时不会持续打印。`rasterDuration` 是 Flutter 光栅线程用时，不是硬件 GPU 计数器，`overBudget` 也不是实际丢帧率。日志中的窗口只包含已呈现给 Flutter 的帧，不能反映长时间阻塞中没有生成的帧。

对比基线和优化版本时，保持相同手机、Flutter SDK、渲染后端、系统刷新率、照片和手势流程。先预热，分别连续操作至少三个完整采样窗口，记录机型、Android/One UI、GPU/驱动、温度及实际刷新率。

1. 导入 10 张横图/竖图，包含 12 MP 和 50 MP 照片；反复进入编辑页、返回和重新导入。
2. 连续左右切牌，对比纯色、模糊和纸张背景的 raster p90/p99。
3. 连续调节尺寸、位置、透明度和水印平铺，检查参数变化、清晰度和圆角。
4. 滚动照片选择器并开关弹层，检查顶部到下方的渐进模糊及按钮背景。
5. 批量导出 SDR、Ultra HDR 和动态照片，核对原始尺寸、EXIF、Gainmap 和内嵌视频。

用 Flutter DevTools Performance 视图分析 UI/raster 时间、重绘和离屏图层；需要归因到 Adreno 的纹理带宽、GPU 时钟或硬件负载时，再结合 AGI/Perfetto。Android `dumpsys gfxinfo` 的 View 指标无法完整代表 Flutter 场景。

## 官方参考

- [Flutter 性能最佳实践](https://docs.flutter.dev/perf/best-practices)
- [BackdropFilter：共享输入及重叠限制](https://api.flutter.dev/flutter/widgets/BackdropFilter-class.html)
- [图片解码尺寸与避免放大](https://api.flutter.dev/flutter/dart-ui/instantiateImageCodecWithSize.html)
- [ImageFilter.shader：自动 uniform 和 GLES 翻转](https://api.flutter.dev/flutter/dart-ui/ImageFilter/ImageFilter.shader.html)
- [Flutter FrameTiming](https://api.flutter.dev/flutter/dart-ui/FrameTiming-class.html)

## 当前验证边界

回归测试覆盖横/竖/方图限尺寸、小图不放大、导出完整尺寸、解码失败恢复、背景纹理复用、切牌图层复用和参数变化时的重绘。Android APK 构建检查原生代码和 Shader 编译。设备未连接时，实际 FPS、耗电、温度和 HDR/动态照片真机效果仍待上述流程验证。
