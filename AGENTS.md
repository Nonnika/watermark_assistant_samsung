# AGENTS.md

Android-only Flutter app (Samsung Galaxy / One UI styled photo watermarking tool). There is no `ios/`, `web/`, or desktop platform folder — don't run or configure builds for them.

## Commands

- `flutter analyze` — lint/typecheck (uses `flutter_lints`; keep it clean)
- `flutter test` — tests live in `test/` (pure-Dart service/model tests + widget tests; no `integration_test/`)
- Single test: `flutter test test/<file>.dart --plain-name '<test name>'`
- Run: `flutter run` on an Android device/emulator (most features require real platform channels)
- Debug build (validates the Kotlin side): `flutter build apk --debug`
- Frame-timing profiling on a real device: `flutter run --profile -t tool/profile_adreno.dart -d <device-id>`

## Architecture

- Entry point: `lib/main.dart` (bootstrap + `export` of `WatermarkAssistantApp`). Root widget/locale handling lives in `lib/widgets/app_root.dart`; all app state lives in the single `_HomeScreenState` in `lib/widgets/home_screen.dart` (editing workspace and landing screen are pure StatelessWidgets under `lib/widgets/home/`); there is no router/state-management package.
- **Single native channel**: every service (`UltraHdrService`, `MotionPhotoService`, `ExifService`, `WatermarkProcessor`, `DevicePhotoService`) talks to the same MethodChannel `com.example.watermark_samsung/ultra_hdr`. The Dart side keeps thin facade classes (`exif_service.dart`, `ultra_hdr_service.dart`, `motion_photo_service.dart`) over implementations in `lib/services/exif/`, `lib/services/ultra_hdr/`, `lib/services/motion_photo/` — keep that pattern when the files grow. The Kotlin side is split the same way: `MainActivity.kt` only wires the channel/permissions/HDR window mode and delegates to `UltraHdrEncoder.kt`, `MediaStoreHelper.kt`, `VideoWatermarker.kt`, `MotionPhotoProcessor.kt`, `SefTrailerCodec.kt` and `Performance.kt` (ADPF helper) in the same package. Changes to native save/Ultra HDR/Motion Photo behavior usually touch both sides of this one channel.
- Image compositing (frames, floating PNG overlays, EXIF preservation, gain-map synthesis) is done in Dart with the `image` package under `lib/services/` and `lib/services/canvas/`; the native side handles MediaStore saves and codec-level work.
- `shaders/progressive_blur.frag` is the only Flutter fragment shader (declared under `flutter.shaders` in `pubspec.yaml`); load the `FragmentProgram` once and reuse it, and keep the non-shader gaussian-blur fallback working. Theming lives in `lib/theme/one_ui_theme.dart`.
- Read before touching these areas: `doc/ADRENO_PERFORMANCE.md` (preview/rendering performance rules and measurement caveats) and `doc/ONE_UI_ICON.md` (launcher-icon regeneration procedure).
- Localization is NOT via `.arb` files: `lib/services/app_strings.dart` holds all zh/en strings behind a global mutable `AppStrings.currentLanguage` ValueNotifier (default **Chinese**). Add new UI strings there. Tests set locale to zh-CN and assert Chinese text; reset language state if you change it in a test.

## Gotchas

- `tool/generate_icons.dart` and `test/generate_icons_test.dart` are codegen: they render launcher icons from `PebbleShadowAndCardPainter` and write PNGs into `android/app/src/main/res/mipmap-*`. Running the full suite rewrites those files.
- Assets are declared for both `res/` and `assets/images/` in `pubspec.yaml`; banner images exist duplicated in both directories — keep both in sync or pick one.
- Release builds sign with debug keys (no release signing config yet); `applicationId` is still the template `com.example.watermark_samsung`.
- Manifest sets `largeHeap`, `requestLegacyExternalStorage`, and `android:colorMode="hdr"` — required for full-size image decoding and Ultra HDR output; don't remove casually.
- `CLAUDE.md` is a symlink to `AGENTS.md` — edit `AGENTS.md` only; don't create a divergent copy.
