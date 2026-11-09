# One UI 图标

「水印助手」当前图标为一张位图设计稿：蓝紫渐变鹅卵石底板、半透明相片卡片、Android 机器人、白色水印笔刷与四角星。

- 设计源图：`assets/app_icon_source.png`（1254px，浅色背景上的完整图标，未打包进应用）
- 应用内图标：`assets/logo/app_icon.png`（512px，透明圆角），由 `AppPebbleIcon` 使用（启动页、关于面板）
- Android legacy 图标：`android/app/src/main/res/mipmap-*/ic_launcher_oneui.png`
- Android 自适应图标：`mipmap-anydpi-v26/ic_launcher_oneui.xml`，整幅图稿放在背景层 `drawable-xxxhdpi/ic_launcher_oneui_background.png`，前景层透明
- 生成脚本：`tool/generate_icons.py`

## 生成流程

```sh
python3 tool/generate_icons.py            # 默认读取 assets/app_icon_source.png
python3 tool/generate_icons.py path/to/new_icon.png
```

依赖 Pillow 与 numpy。脚本会：

1. 按 `CROP_BOX` 从源图裁出鹅卵石区域，并用拟合得到的超椭圆（`EXPONENT = 3.75`）重新生成干净的抗锯齿轮廓，剔除源图背景和投影。
2. 轮廓边缘一圈像素混有背景色，改由内部颜色向外平滑延展（push-pull 填充）。
3. 自适应图标：鹅卵石占 108dp 图层中的 `ADAPTIVE_ART_DP = 76dp`，四周用延展色铺满。启动器只显示中间 72dp，因此原轮廓被遮罩隐藏，主体图形保持在 66dp 安全区内。规范参考：[Android adaptive icons](https://developer.android.com/develop/ui/compose/system/icon_design_adaptive)。

更换源图时，若构图或画布尺寸不同，需要重新测量 `CROP_BOX` 并检查 `EXPONENT`。
