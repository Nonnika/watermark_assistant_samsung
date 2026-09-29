# Watermark Assistant for Samsung & Android

> Although it's normal to make application with agent like codex or claude code, I have to say this project is made by agent

<div align="center">

![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?style=for-the-badge&logo=flutter&logoColor=white)
![Android](https://img.shields.io/badge/Android-10.0+-3DDC84?style=for-the-badge&logo=android&logoColor=white)
![Platform](https://img.shields.io/badge/Platform-One%20UI%20%7C%20Android-blue?style=for-the-badge)
![Ultra HDR](https://img.shields.io/badge/HDR-Ultra%20HDR%20%7C%20Gainmap-FFB300?style=for-the-badge)
![Motion Photo](https://img.shields.io/badge/Live%20Photo-Samsung%20SEF%20%7C%20XMP-9C27B0?style=for-the-badge)
![License](https://img.shields.io/badge/License-CC%20BY--NC--SA%204.0-orange?style=for-the-badge)

**A flagship-grade batch photo watermarking application tailored for Android and Samsung Galaxy (One UI).**  
*Full Ultra HDR Gainmap preservation · Lossless Motion Photo (HEIC/JPG) export · Camera EXIF frames · Floating PNG watermarks · Snapseed-style gesture controls*

[Screenshots](#screenshots) • [Features](#features) • [Architecture & Native Engine](#architecture--native-engine) • [Design System](#design-system) • [Getting Started](#getting-started) • [Disclaimer & Trademarks](#disclaimer--trademarks) • [License](#license)

</div>

---

## Screenshots

<div align="center">
  <table>
    <tr>
      <td align="center" width="25%">
        <img src="doc/Screenshot_20260823_114315_Watermark%20Assistant.jpg" width="100%" alt="Batch Photo Selection & Gallery" />
        <br />
      </td>
      <td align="center" width="25%">
        <img src="doc/Screenshot_20260823_114322_Watermark%20Assistant.jpg" width="100%" alt="EXIF Frame Watermark Editor" />
        <br />
      </td>
      <td align="center" width="25%">
        <img src="doc/Screenshot_20260823_114329_Watermark%20Assistant.jpg" width="100%" alt="Color Palette & Brand Customization" />
        <br />
      </td>
      <td align="center" width="25%">
        <img src="doc/Screenshot_20260823_114358_Watermark%20Assistant.jpg" width="100%" alt="Floating Watermarks & Gesture Controls" />
        <br />
      </td>
    </tr>
  </table>
</div>

---


## Getting Started

### Prerequisites
- **Flutter SDK**: `>= 3.13.1`
- **Android SDK**: `API Level 34+` (Android 14+ recommended)
- **Gradle**: `8.x` / `9.x` (Java 17+)
- *Note: This project is exclusively developed for Android; iOS and desktop build targets are not configured.*

### Build & Run Instructions

1. **Clone the repository**:
   ```bash
   git clone https://github.com/your-username/watermark_samsung.git
   cd watermark_samsung
   ```

2. **Install dependencies**:
   ```bash
   flutter pub get
   ```

3. **Run unit tests**:
   ```bash
   flutter test
   ```

4. **Run static analysis**:
   ```bash
   flutter analyze
   ```

5. **Build APK**:
   ```bash
   # Build Debug APK
   flutter build apk --debug

   # Build Release APK
   flutter build apk --release
   ```

---

## Disclaimer & Trademarks

- **Samsung, Galaxy, and One UI** are registered trademarks of **Samsung Electronics Co., Ltd.** All Samsung-related logos, brand assets, and product names referenced in this application belong entirely to Samsung Electronics Co., Ltd.
- This application is an independent third-party open-source project and is **not** officially affiliated with, endorsed by, or sponsored by Samsung Electronics Co., Ltd.
- All other brand logos and camera trademarks (such as Leica, Sony, Canon, Nikon, Hasselblad, Fujifilm, Apple, Xiaomi, Zeiss) displayed in this project belong to their respective owners and are used solely for EXIF watermarking identification and demonstration purposes.

---

## License

This project is licensed under the **Creative Commons Attribution-NonCommercial-ShareAlike 4.0 International (CC BY-NC-SA 4.0)**. See the [LICENSE](LICENSE) file for details.
