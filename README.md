# 水印助手 · 为 Samsung Galaxy 制作
> 虽然使用 Codex、Claude Code 等 AI 智能体开发应用已经很常见，但仍需说明：本项目由 AI 智能体开发。

<div align="center">

![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?style=for-the-badge&logo=flutter&logoColor=white)
![Android](https://img.shields.io/badge/Android-10.0+-3DDC84?style=for-the-badge&logo=android&logoColor=white)
![平台](https://img.shields.io/badge/Platform-One%20UI%20%7C%20Android-blue?style=for-the-badge)
![Ultra HDR](https://img.shields.io/badge/HDR-Ultra%20HDR%20%7C%20Gainmap-FFB300?style=for-the-badge)
![动态照片](https://img.shields.io/badge/Live%20Photo-Samsung%20SEF%20%7C%20XMP-9C27B0?style=for-the-badge)
![许可证](https://img.shields.io/badge/License-CC%20BY--NC--SA%204.0-orange?style=for-the-badge)

**专为 Android 与 Samsung Galaxy（One UI）打造的旗舰级批量照片水印应用。**<br />
*完整保留 Ultra HDR 增益图（Gainmap）· 无损导出动态照片（HEIC/JPG）· 相机 EXIF 参数边框 · 浮动 PNG 水印 · Snapseed 风格手势操作*

</div>

---

## 应用截图

<div align="center">
  <table>
    <tr>
      <td align="center" width="25%">
        <img src="doc/Screenshot_20260823_114315_Watermark%20Assistant.jpg" width="100%" alt="批量照片选择与相册" />
        <br />
      </td>
      <td align="center" width="25%">
        <img src="doc/Screenshot_20260823_114322_Watermark%20Assistant.jpg" width="100%" alt="EXIF 边框水印编辑器" />
        <br />
      </td>
      <td align="center" width="25%">
        <img src="doc/Screenshot_20260823_114329_Watermark%20Assistant.jpg" width="100%" alt="配色与品牌自定义" />
        <br />
      </td>
      <td align="center" width="25%">
        <img src="doc/Screenshot_20260823_114358_Watermark%20Assistant.jpg" width="100%" alt="浮动水印与手势操作" />
        <br />
      </td>
    </tr>
  </table>
</div>

---


## 快速开始

### 环境要求

- **Flutter SDK**： `>= 3.13.1`
- **Android SDK**：`API Level 34+`（推荐 Android 14 及以上版本）
- **Gradle**： `8.x` / `9.x` （Java 17 及以上版本）
- *注意：本项目仅面向 Android 开发，未配置 iOS、Web 或桌面平台构建目标。*

### 构建与运行

1. **克隆仓库**：
   ```bash
   git clone https://github.com/your-username/watermark_samsung.git
   cd watermark_samsung
   ```

2. **安装依赖**：
   ```bash
   flutter pub get
   ```

3. **运行单元测试**：
   ```bash
   flutter test
   ```

4. **运行静态检查**：
   ```bash
   flutter analyze
   ```

5. **构建 APK**：
   ```bash
   # 构建调试版 APK
   flutter build apk --debug

   # 构建发布版 APK
   flutter build apk --release
   ```

---

## 免责声明与商标

- **Samsung、Galaxy 和 One UI** 是**三星电子株式会社（Samsung Electronics Co., Ltd.）**的注册商标。本应用涉及的所有三星相关标志、品牌素材及产品名称均归三星电子株式会社所有。
- 本应用是独立的第三方开源项目，与三星电子株式会社**没有官方关联，也未获得其认可或赞助**。
- 本项目中展示的其他品牌标志及相机商标（如 Leica、Sony、Canon、Nikon、Hasselblad、Fujifilm、Apple、Xiaomi、Zeiss）均归各自权利人所有，仅用于 EXIF 水印标识及演示。

---

## 许可证

本项目采用 **知识共享 署名—非商业性使用—相同方式共享 4.0 国际许可协议（CC BY-NC-SA 4.0）**。详情请参阅 [LICENSE](LICENSE) 文件。
