# Watermark Assistant for Samsung & Android

<div align="center">

![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?style=for-the-badge&logo=flutter&logoColor=white)
![Android](https://img.shields.io/badge/Android-10.0+-3DDC84?style=for-the-badge&logo=android&logoColor=white)
![Platform](https://img.shields.io/badge/Platform-One%20UI%20%7C%20Android-blue?style=for-the-badge)
![Ultra HDR](https://img.shields.io/badge/HDR-Ultra%20HDR%20%7C%20Gainmap-FFB300?style=for-the-badge)
![Motion Photo](https://img.shields.io/badge/Live%20Photo-Samsung%20SEF%20%7C%20XMP-9C27B0?style=for-the-badge)
![License](https://img.shields.io/badge/License-MIT-green?style=for-the-badge)

**A flagship-grade batch photo watermarking application tailored for Android and Samsung Galaxy (One UI).**  
*Full Ultra HDR Gainmap preservation · Lossless Motion Photo (HEIC/JPG) export · Camera EXIF frames · Floating PNG watermarks · Snapseed-style gesture controls*

[Features](#features) • [Architecture & Native Engine](#architecture--native-engine) • [Design System](#design-system) • [Getting Started](#getting-started) • [License](#license)

</div>

---

## Features

### 1. Professional Camera EXIF Frame Watermarks
- **Accurate EXIF Metadata Extraction**: Automatically parses camera model, lens model, equivalent focal length, aperture, shutter speed, ISO sensitivity, and capture timestamp. Supports manual editing and intelligent numeric date formatting.
- **Authentic Brand Vector Logo Library**: Built-in vector logos including Samsung, Leica (Red, Black, and White editions), Sony, Canon, Nikon, Hasselblad, Fujifilm, Apple, Xiaomi, Zeiss, and more. Supports custom logo imports with color inversion.
- **Aesthetic Frame Customization**:
  - Customizable border padding and bottom parameter bar dimensions.
  - Smooth corner rounding and realistic outer shadow elevation effects.
  - Paper texture backgrounds with light/dark adaptive contrast modes.
  - **Dynamic Palette Extraction**: Automatically extracts the dominant color palette from the input photo, along with curated Morandi tones, vintage film hues, monochrome shades, and brand-specific theme colors.

### 2. Floating & Tiled PNG Watermarks
- **Snapseed-Style Gesture Engine**: Drag up/down on the canvas to switch between adjustment parameters (horizontal offset, vertical offset, scale, opacity, rotation angle), and drag left/right to adjust values smoothly.
- **9-Grid Smart Snapping**: Quickly snap watermarks to top-left, center, bottom-right, and other composition anchor points.
- **Full Tiled Layout**: Instantly generate staggered diagonal watermark grids across the entire image to safeguard intellectual property.

### 3. Ultra HDR High Dynamic Range Preservation (Android 14+)
- Native detection of Android 14 / One UI 6+ Ultra HDR signatures and embedded Gainmaps.
- Uses native dual-layer compositing shaders to preserve original gainmap metadata at 100% fidelity, delivering vibrant highlights on HDR AMOLED displays.

### 4. Native Motion Photo (Live Photo) Extraction & Re-Assembly
- **Dual Format Support**: Full compatibility with Samsung Galaxy HEIC and standard JPEG Motion Photos.
- **Lossless Embedded MP4 Stream Handling**: Accurately parses Samsung SEF (Samsung Extra Field) multi-entry directories (`MotionPhoto_Data`) and Google GContainer XMP, preserving the full 3.0s+ video clip and precise shutter keyframe timestamp (`PresentationTimestampUs`).
- **Synchronized Video Watermarking**: Optional hardware-accelerated transcoding to composite frame watermarks into the embedded MP4 video frames simultaneously.

### 5. High-Performance Batch Processing & Presets
- **Multithreaded Gallery Scanning**: Native parallel processing to scan thousands of device photos and identify HDR and Motion Photo attributes within milliseconds.
- **Batch Export Pipeline**: Apply unified templates across multiple photos or fine-tune individual adjustments in batch mode.
- **Local Preset Manager**: Save customized logo selections, border ratios, colors, and typography settings to presets for instant one-tap reuse.
- **Bilingual Interface**: Instant switching between English and Simplified Chinese across the entire UI.

---

## Architecture & Native Engine

```
lib/
├── main.dart                          # Application entry point, global state, and reactive UI
├── models/                            # Domain models (ImageItem, ExifInfo, WatermarkConfig, SavedPreset)
├── services/
│   ├── app_strings.dart               # Dynamic localization controller
│   ├── brand_logos.dart               # Vector brand logo assets and custom logo management
│   ├── device_photo_service.dart      # MediaStore reader and native batch scanning bridge
│   ├── exif_service.dart              # EXIF extraction, formatting, and APP1 segment preservation
│   ├── motion_photo_service.dart      # Motion Photo SEF/XMP extraction and compositing bridge
│   ├── photo_color_extractor.dart     # Palette extraction engine
│   ├── ultra_hdr_service.dart         # Ultra HDR gainmap detection and synthesis dispatcher
│   └── watermark_processor.dart       # Full-resolution 1:1 lossless rendering pipeline
├── widgets/                           # One UI components (Frame controls, 9-grid, sheets, dialogs)
└── theme/                             # One UI squircle clipping, blur shaders, and styling

android/app/src/main/kotlin/.../
└── MainActivity.kt                    # Native MethodChannel engine (~1800 lines)
    ├── MediaStore volume URI normalization and background file loading
    ├── Qualcomm ADPF CPU boosting and MediaCodec hardware acceleration (c2.qti.avc.encoder)
    ├── Samsung SEF trailer multi-entry parser and assembler
    ├── Google GContainer and XMP APP1 segment injector
    └── Ultra HDR Gainmap extraction and lossless synthesis
```

### Key Technical Optimizations
- **Non-blocking UI Rendering**: Thumbnail decoding and gallery indexing are offloaded to dedicated background worker thread pools with lower priority, augmented by Android ADPF (Adaptive Performance Framework) to eliminate UI thread jitter.
- **Direct Filesystem Path I/O**: Direct `File(path)` reads bypass platform channel byte buffer memory limits when processing large 15MB-30MB high-resolution images and HEIC motion clips.

---

## Design System

The application strictly adheres to the **Samsung One UI** design language:
- **Pebble Squircles**: Icons, cards, and interactive controls are clipped using continuous superellipse curves.
- **Progressive Frosted Glass**: Control surfaces and floating menus feature smooth backdrop blur materials.
- **One-Handed Usability**: Interactive elements and adjustments are anchored to the lower portion of the viewport for comfortable single-handed operation.
- **Tactile Haptic Feedback**: Subtle haptic vibrations accompany slider adjustments, button taps, and grid snapping.

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

## License

This project is open-sourced under the **MIT License**. See the [LICENSE](LICENSE) file for details.

