# One UI 图标设计

为「水印助手」设计的新版图标。先使用内置 imagegen 制作视觉方案，再以 Flutter Canvas 矢量绘制制作最终成品，确保轮廓干净、各尺寸一致。

- 成品：`assets/app_icon_oneui.png`
- 概念参考：`assets/app_icon_oneui_concept.png`（imagegen 原始输出，透明边缘有杂点，未用于启动图标）
- 绘制源文件：`lib/widgets/one_ui_icon_artwork.dart`
- 视觉：圆润鹅卵石轮廓、钴蓝至蓝紫渐变、叠放相片、青绿色山景、暖黄色太阳，以及四角星水印标记。
- 不包含文字，适合小尺寸显示。
- 已接入 Android 启动图标和应用内 `AppPebbleIcon`，保留旧 PNG 图标文件。
- Android 前景与背景分别导出为 108dp 图层，关键图形位于居中的 66dp 圆形安全区域。规范参考：[Android adaptive icons](https://developer.android.com/develop/ui/compose/system/icon_design_adaptive)。

## 重新生成

```sh
dart run tool/generate_icons.dart
```

也可直接运行 `flutter test test/generate_icons_test.dart`。此生成器输出 1024px 成品、五种 Android legacy 密度图标及自适应图标的前景和背景。所有输出使用同一份绘制源文件，无外部图片或私人绝对路径依赖。

## 生成提示词（内置 imagegen）

```text
Use case: logo-brand.
Asset type: a finished Android launcher icon for an independent photo watermark app called Watermark Assistant; no words should appear.
Primary request: Design one exceptionally polished, beautiful Samsung One UI inspired app icon. Friendly bold simplified geometry, restrained dimensionality, crisp silhouette, balanced negative space, readable at 48 pixels.
Scene/backdrop: One large continuous superellipse / soft pebble squircle fills the 1024x1024 square canvas, reaching the middle of all four edges, with transparent pixels only outside its curved corners. Background is a rich luminous cobalt-to-periwinkle gradient, brighter blue upper left and deep blue-violet lower right, subtle broad lighting, perfectly smooth, no texture.
Subject: A centered pair of subtly overlapping rounded photographic cards occupying about 64% of the icon width. A slightly tilted pale lavender rear card is visible mostly on the left. The main off-white photo card is slightly tilted counterclockwise, front-facing without perspective distortion, with generous rounded corners. Its inset photo window depicts a beautifully simplified sky-blue sky and two rounded sweeping aqua / turquoise mountain silhouettes, with one small buttery yellow sun. The broad white footer contains one very short muted blue rounded capsule representing a watermark line, absolutely no text. A compact crisp blue-violet four-point sparkle rests near the lower right of the photo window as the app's watermark signature, separated from the scenery by a white outline, integrated and tasteful; no extra badge or background circles.
Style/medium: premium flat vector-like app icon illustration with very gentle soft card shadows, matte white cards, a tiny amount of surface lighting. Modern One UI family resemblance, original artwork, no Samsung trademarks.
Composition/framing: a single icon only, straight-on square canvas, visually centered with sufficient breathing room. Entire image is the icon itself, not an icon sitting on a backdrop. Strong large shapes, smooth polished curves. No outer cast shadow beyond the squircle.
Constraints: exactly one icon, actual transparent corners, no lettering, no watermarks or signatures from the generator, no border around the full image, no mockup, no device, no grid, no presentation board, no labels, no multiple options. No metallic chrome, no glass tubes, no heavy extrusion, no photorealism, no excessive tiny details.
```

## 边缘修整提示词

```text
Use case: precise-object-edit.
Edit target: the attached Watermark Assistant app icon.
Change only the outer silhouette and alpha edge of the blue squircle background. Remove ALL stray cyan or purple pixels outside the silhouette and ALL ragged / speckled / noisy edge artifacts. The outer shape must be a perfectly clean, symmetric, continuous, smoothly antialiased Samsung-style superellipse pebble with generous rounded corners. Transparent pixels outside the curved corners must have alpha exactly zero; the blue squircle itself must be fully opaque. The shape should occupy 96% of the square canvas, with an even tiny transparent margin so none of the edge is clipped.
Preserve invariants: keep the original blue to violet gradient, the two overlapping white photographic cards, the turquoise mountain landscape, yellow sun, footer capsule, blue-violet sparkle with white outline, positions, proportions, lighting and shadows unchanged. This is an edge cleanup, not a redesign. Exactly one icon. No text, no backdrop, no outer shadow, no added objects. Polished vector-like edges.
```
