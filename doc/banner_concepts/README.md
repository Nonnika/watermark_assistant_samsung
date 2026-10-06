# 四张首页竖屏海报 · 功能成片

2026-10-06。根据用户选定的「功能成片风格」与竖屏要求，四张轮播图已全部替换。照片由内置 imagegen 生成，品牌水印和 EXIF 参数由项目实际渲染器合成；演示参数不代表照片真实 EXIF。海报为静态功能示例。

## 当前方案：同图模糊背景与柔和主图

[四页当前效果](all_four_homepage_soft.png)。每页使用对应的无水印原照片铺满屏幕并做 20dp 高斯模糊，前面保留清晰成片。主图宽度为屏宽的 80%～83%，按可见高度限制，采用不同的约 1°～1.4° 倾角与少量水平错位。16dp 圆角、约 6～7dp 边缘透明渐变与柔和阴影减轻硬边割裂；照片中心与水印保持清晰。

背景图为 `assets/images/banner_{frame,overlay,gesture,motion}_background.jpg`，同步到 `res/`。背景按 360px 宽解码，使用复用的 ImageFilter；主图与遮罩隔离为 RepaintBoundary。未新增 FragmentProgram，也未修改照片导出渲染器。未做真机 GPU 性能测量。

下方旧版预览保留作对照。

- [四页首页总览](all_four_homepage_portrait.png)：四页实际 Flutter 首页组件渲染，含应用原生标题与选图面板。
- [叠加水印首页](overlay_homepage_portrait.png)：海岸照片加实际 FloatingPngRenderer 渲染的 Samsung 白色 PNG，右下角，scale=0.28、opacity=0.95、margin=0.06。
- [手势操作首页](gesture_homepage_portrait.png)：山路边框成片，使用应用原有 FrameSnapseedProgressBar 展示底部参数栏高度 13%；切换和调值说明沿用本地化文案。
- [动态照片首页](motion_homepage_portrait.png)：海浪黑色边框成片，采用应用现有黄色动态照片图标与文字样式。该海报不包含内嵌视频。

四个最终资产分别为 `banner_frame_scenery.jpg`、`banner_classic_vintage.jpg`、`banner_gesture_minimal.jpg`、`banner_dynamic_photo.jpeg`，位于 `assets/images/` 并同步到 `res/`。全部采用 contain 完整显示，保留底部三分之一选图面板与 16dp 间距。已检查四页轮播切换、资产纵向尺寸、可见区域和 Flutter 异常。

[其余三张照片的内置 imagegen 提示词](REMAINING_PROMPTS.md)。

- [当前竖屏首页](frame_homepage_portrait.png)：实际 Flutter 首页组件离屏渲染，1200×2600，包含原生标题和选图面板；相册数据为空。
- [竖版边框成片](frame_output_portrait.png)：1162×1674，Logo 与参数完整保留。
- [竖版源照片](source_photo_portrait.jpg)：1086×1448，内置 imagegen 根据已认可的横图扩展、重构竖向构图。

暗色遮罩只淡出到上部，底部水印保持清晰。以下横版文件留作之前的对照。

- [边框成片](frame_output.png)：应用边框渲染器的留白、Logo 尺寸与参数排版；参数为演示值。
- [首页构图预览](frame_preview.png)：暗色背景、原生文案与大幅成片，主体位于照片选择面板上方；底部空白由应用面板覆盖。
- [新照片源文件](source_photo.jpg)：使用内置 imagegen 生成的照片，不是真实地点的实拍照片。

渲染使用 `lib/services/canvas/frame_canvas_renderer.dart` 的预览副本，仅指定离屏字体以避免 Flutter 测试字体替换为方块；未修改应用渲染器。使用项目自带的 Samsung 黑色 Logo，paddingRatio=0.035，bottomBarRatio=0.13，参数为 24mm / f/1.8 / 1/250s / ISO 50。

## 第一张照片的内置 imagegen 提示词

```text
Use case: photorealistic-natural. Generate one exceptionally convincing editorial landscape photograph, horizontal 3:2 composition, suitable for a high-end photography app's finished watermark example. Scene: a quiet alpine lake beneath rugged layered mountain ridges just before sunrise, a narrow line of warm light touching the high peaks, dark pine silhouettes and a subtle reflection in deep still water. Strong simple composition, photograph fills the entire image, sophisticated restrained colors, cool slate blue and a small warm amber accent, natural realistic atmospheric haze, fine photographic texture and real optical detail. A professional full-frame camera photograph, restrained dynamic range and understated sharpness, no overprocessed HDR, no over-saturated turquoise, no glossy 3D material, no impossible geometry, no artificial symmetry. Clear mountain and lake subject, no people, no buildings, no devices, no smartphone, no UI, no lettering, no logo, no watermark, no photo frame, no border. Produce only the source photograph: the application will render the real watermark frame separately.
```

## 竖版编辑提示词（内置 imagegen）

```text
Use case: photorealistic-natural. Edit target: the attached approved alpine lake photograph. Primary request: adapt this SAME photograph into a refined PORTRAIT 3:4 photograph for a vertical mobile homepage, by naturally extending the sky and calm water and reframing around the sunlit mountain peaks. Preserve the existing photographic quality, rugged mountain identity, realistic snow and rock textures, cool slate blue palette, subtle amber sunrise, pine shoreline, reflections, natural detail and understated processing. The dominant sunlit peak should remain clearly readable in the upper-middle and the lake reflection in the lower half. Do not squeeze or distort the landscape. Output must be clearly vertical/taller than wide, around 1536x2048 if possible. Only generate the source photograph, edge to edge. No text, no logo, no watermark, no white border, no phone, no app interface. The application will separately render its authentic white watermark frame. Keep the scene convincingly photographic; avoid artificial symmetry, saturated turquoise, glossy CGI or overly sharpened HDR.
```
