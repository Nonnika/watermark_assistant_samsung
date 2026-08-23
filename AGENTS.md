# AGENTS.md

Android-only Flutter app (Samsung Galaxy / One UI styled photo watermarking tool). There is no `ios/`, `web/`, or desktop platform folder — don't run or configure builds for them.

## Commands

- `flutter analyze` — lint/typecheck (uses `flutter_lints`; keep it clean)
- `flutter test` — all tests live in `test/widget_test.dart` plus `test/generate_icons_test.dart`
- Single test: `flutter test test/widget_test.dart --plain-name '<test name>'`
- Run: `flutter run` on an Android device/emulator (most features require real platform channels)

## Architecture

- Entry point: `lib/main.dart` → `WatermarkAssistantApp`. All state lives in this single StatefulWidget; there is no router/state-management package.
- **Single native channel**: every service (`UltraHdrService`, `MotionPhotoService`, `ExifService`, `WatermarkProcessor`, `DevicePhotoService`, `MediaStoreHelper`) talks to the same MethodChannel `com.example.watermark_samsung/ultra_hdr`, implemented entirely in `android/app/src/main/kotlin/com/example/watermark_samsung/MainActivity.kt` (~950 lines). Changes to native save/Ultra HDR/Motion Photo behavior usually touch both sides of this one file.
- Image compositing (frames, floating PNG overlays, EXIF preservation, gain-map synthesis) is done in Dart with the `image` package under `lib/services/`; the native side handles MediaStore saves and codec-level work.
- Localization is NOT via `.arb` files: `lib/services/app_strings.dart` holds all zh/en strings behind a global mutable `AppStrings.currentLanguage` ValueNotifier (default **Chinese**). Add new UI strings there. Tests set locale to zh-CN and assert Chinese text; reset language state if you change it in a test.

## Gotchas

- `tool/generate_icons.dart` and `test/generate_icons_test.dart` are codegen: they render launcher icons from `PebbleShadowAndCardPainter` and write PNGs into `android/app/src/main/res/mipmap-*`. Running the full suite rewrites those files.
- Assets are declared for both `res/` and `assets/images/` in `pubspec.yaml`; banner images exist duplicated in both directories — keep both in sync or pick one.
- Release builds sign with debug keys (no release signing config yet); `applicationId` is still the template `com.example.watermark_samsung`.
- Manifest sets `largeHeap`, `requestLegacyExternalStorage`, and `android:colorMode="hdr"` — required for full-size image decoding and Ultra HDR output; don't remove casually.
