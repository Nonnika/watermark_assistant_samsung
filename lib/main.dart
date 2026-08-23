import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';

import 'models/frame_watermark_config.dart';
import 'models/image_item.dart';
import 'models/saved_preset.dart';
import 'models/watermark_config.dart';
import 'services/app_strings.dart';
import 'services/brand_logos.dart';
import 'services/photo_color_extractor.dart';
import 'services/device_photo_service.dart';
import 'services/preset_watermarks.dart';
import 'services/watermark_processor.dart';
import 'theme/one_ui_theme.dart';
import 'utils/blurred_dialog_helper.dart';
import 'widgets/about_page.dart';
import 'widgets/card_stack_preview.dart';
import 'widgets/custom_photo_selector.dart';
import 'widgets/export_bottom_sheet.dart';
import 'widgets/floating_controls.dart';
import 'widgets/frame_controls.dart';
import 'widgets/hero_poster_banner.dart';
import 'widgets/sheets/preset_picker_sheet.dart';
import 'widgets/sheets/quick_options_sheet.dart';
import 'widgets/sheets/resources_sheet.dart';
import 'widgets/splash_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  runApp(const WatermarkAssistantApp());
}

class WatermarkAssistantApp extends StatefulWidget {
  final bool showSplashOnInit;

  const WatermarkAssistantApp({super.key, this.showSplashOnInit = true});

  @override
  State<WatermarkAssistantApp> createState() => _WatermarkAssistantAppState();
}

class _WatermarkAssistantAppState extends State<WatermarkAssistantApp> with WidgetsBindingObserver {
  late bool _showSplash;

  @override
  void initState() {
    super.initState();
    _showSplash = widget.showSplashOnInit;
    WidgetsBinding.instance.addObserver(this);
    _detectSystemLocale();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeLocales(List<Locale>? locales) {
    super.didChangeLocales(locales);
    if (locales != null && locales.isNotEmpty) {
      AppStrings.updateFromLocale(locales.first);
    }
  }

  void _detectSystemLocale() {
    final platformLocale = WidgetsBinding.instance.platformDispatcher.locale;
    AppStrings.updateFromLocale(platformLocale);
  }

  void _onSplashFinish() {
    setState(() {
      _showSplash = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLanguage>(
      valueListenable: AppStrings.currentLanguage,
      builder: (context, lang, child) {
        return MaterialApp(
          title: AppStrings.appName,
          debugShowCheckedModeBanner: false,
          theme: OneUITheme.lightTheme(),
          darkTheme: OneUITheme.darkTheme(),
          themeMode: ThemeMode.system, // 自动跟随系统深色/浅色模式
          home: AnimatedSwitcher(
            duration: const Duration(milliseconds: 350),
            child: _showSplash
                ? SplashScreen(
                    key: const ValueKey('splash_screen'),
                    onFinish: _onSplashFinish,
                  )
                : const HomeScreen(
                    key: ValueKey('home_screen'),
                  ),
          ),
        );
      },
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  final List<ImageItem> _images = [];
  int _selectedImageIndex = 0;

  // 主模式选择：边框水印 或 自定义 PNG 水印
  WatermarkType _watermarkType = WatermarkType.frame;
  int _activeToolIndex = 0;

  // 是否开启“单独调节当前照片”开关 (true: 仅当前图片生效, false: 批量同步全局)
  bool _isIndividualMode = false;

  // Snapseed 底部面板参数实时反馈状态
  bool _isAdjusting = false;
  String _adjustingParamName = '';
  String _adjustingParamValue = '';
  double _adjustingProgress = 0.0;

  // 全局自定义 PNG 水印状态
  Uint8List? _watermarkBytes;
  ui.Image? _decodedWatermark;
  String _watermarkName = 'Galaxy 影像水印';
  String? _presetWatermarkId = 'galaxy_s24';
  WatermarkConfig _globalPngConfig = const WatermarkConfig();

  // 全局边框 EXIF 水印状态
  FrameWatermarkConfig _globalFrameConfig = const FrameWatermarkConfig();
  ui.Image? _decodedBrandLogo;

  bool _isLoading = false;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _initDefaultState();
  }

  Future<void> _initDefaultState() async {
    final samsungBytes = await BrandLogoService.getLogoBytes('samsung_blue');
    final samsungDecoded = await WatermarkProcessor.decodeImageFromBytes(samsungBytes);

    final defaultPreset = PresetWatermarkService.presets.first;
    final wmBytes = await defaultPreset.generateBytes();
    final wmDecoded = await WatermarkProcessor.decodeImageFromBytes(wmBytes);

    if (mounted) {
      setState(() {
        _decodedBrandLogo = samsungDecoded;
        _watermarkBytes = wmBytes;
        _decodedWatermark = wmDecoded;
        _watermarkName = defaultPreset.title;
        _presetWatermarkId = defaultPreset.id;
      });
    }
  }

  WatermarkConfig get _activePngConfig {
    if (_isIndividualMode && _images.isNotEmpty) {
      return _images[_selectedImageIndex].individualPngConfig ?? _globalPngConfig;
    }
    return _globalPngConfig;
  }

  void _updatePngConfig(WatermarkConfig newConfig) {
    setState(() {
      if (_isIndividualMode && _images.isNotEmpty) {
        _images[_selectedImageIndex] = _images[_selectedImageIndex].copyWith(
          individualPngConfig: newConfig,
        );
      } else {
        _globalPngConfig = newConfig;
      }
    });
  }

  FrameWatermarkConfig get _activeFrameConfig {
    if (_images.isNotEmpty && _selectedImageIndex < _images.length) {
      return (_isIndividualMode ? (_images[_selectedImageIndex].individualFrameConfig ?? _globalFrameConfig) : _globalFrameConfig)
          .copyWith(exifInfo: _images[_selectedImageIndex].exifInfo);
    }
    return _globalFrameConfig;
  }

  void _updateFrameConfig(FrameWatermarkConfig newConfig) {
    setState(() {
      _globalFrameConfig = newConfig;
      if (_images.isNotEmpty && _selectedImageIndex < _images.length) {
        _images[_selectedImageIndex] = _images[_selectedImageIndex].copyWith(
          exifInfo: newConfig.exifInfo,
          individualFrameConfig: _isIndividualMode ? newConfig : null,
        );
      }
    });
  }

  Future<void> _onImportWithWatermarkType(
    List<DevicePhotoModel> photoList,
    WatermarkType type,
  ) async {
    if (photoList.isEmpty) return;
    try {
      setState(() {
        _isLoading = true;
        _watermarkType = type;
        _activeToolIndex = 0;
      });
      _images.clear();
      for (final photo in photoList) {
        final bytes = await DevicePhotoService.getFullPhotoBytes(photo);
        if (bytes != null && bytes.isNotEmpty) {
          final item = await WatermarkProcessor.createImageItem(
            id: photo.id.isNotEmpty ? photo.id : UniqueKey().toString(),
            name: photo.name.isNotEmpty ? photo.name : 'Photo_${DateTime.now().millisecondsSinceEpoch}',
            path: photo.path,
            bytes: bytes,
          );
          _images.add(item);
        }
      }

      setState(() {
        _isLoading = false;
        _selectedImageIndex = 0;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导入图片失败: $e')),
        );
      }
    }
  }

  Future<void> _onSelectDevicePhoto(DevicePhotoModel photo) async {
    await _onImportWithWatermarkType([photo], WatermarkType.frame);
  }

  Future<void> _onSelectMultipleDevicePhotos(List<DevicePhotoModel> photoList) async {
    await _onImportWithWatermarkType(photoList, WatermarkType.frame);
  }

  void _showQuickOptionsMenu() {
    QuickOptionsSheet.show(
      context: context,
      onApplyPreset: _applySavedPreset,
    );
  }

  Future<void> _pickImagesFromGallery() async {
    try {
      setState(() => _isLoading = true);
      final List<XFile> pickedFiles = await _picker.pickMultiImage();
      if (pickedFiles.isEmpty) {
        setState(() => _isLoading = false);
        return;
      }

      for (final file in pickedFiles) {
        final bytes = await file.readAsBytes();
        final item = await WatermarkProcessor.createImageItem(
          id: UniqueKey().toString(),
          name: file.name,
          path: file.path,
          bytes: bytes,
        );
        _images.add(item);
      }

      final newIdx = _images.length - pickedFiles.length;
      setState(() {
        _isLoading = false;
        _selectedImageIndex = newIdx;
        _watermarkType = WatermarkType.frame;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('选择图片失败: $e')),
        );
      }
    }
  }

  Future<void> _pickCustomPngWatermarkDialog() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    BlurredDialogHelper.showBlurredBottomSheet(
      context: context,
      builder: (context) {
        return Container(
          decoration: BoxDecoration(
            color: isDark ? OneUITheme.darkCardBg : OneUITheme.lightCardBg,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white24 : Colors.black12,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '导入自定义 PNG 水印',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: isDark ? OneUITheme.darkTextPrimary : OneUITheme.lightTextPrimary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    decoration: BoxDecoration(
                      color: isDark ? OneUITheme.darkCardSubtle : OneUITheme.lightCardSubtle,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        InkWell(
                          onTap: () {
                            Navigator.pop(context);
                            _pickPngFromGallery();
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                            child: Row(
                              children: [
                                Container(
                                  width: 34,
                                  height: 34,
                                  decoration: const BoxDecoration(
                                    color: OneUITheme.primaryBlue,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.photo_library_rounded, color: Colors.white, size: 17),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text('从手机系统相册选择', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                      const SizedBox(height: 3),
                                      Text('相册里的透明 PNG / 签名图片', style: TextStyle(fontSize: 12, color: isDark ? OneUITheme.darkTextSecondary : OneUITheme.lightTextSecondary)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        InkWell(
                          onTap: () {
                            Navigator.pop(context);
                            _pickPngFromFileManager();
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                            child: Row(
                              children: [
                                Container(
                                  width: 34,
                                  height: 34,
                                  decoration: const BoxDecoration(
                                    color: Color(0xFF5E35B1),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.folder_open_rounded, color: Colors.white, size: 17),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text('从文件管理器选择', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                      const SizedBox(height: 3),
                                      Text('手机下载目录选取 PNG / WEBP', style: TextStyle(fontSize: 12, color: isDark ? OneUITheme.darkTextSecondary : OneUITheme.lightTextSecondary)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _pickPngFromGallery() async {
    try {
      final XFile? file = await _picker.pickImage(source: ImageSource.gallery);
      if (file != null) {
        final bytes = await file.readAsBytes();
        final decoded = await WatermarkProcessor.decodeImageFromBytes(bytes);
        setState(() {
          _watermarkBytes = bytes;
          _decodedWatermark = decoded;
          _watermarkName = file.name.isNotEmpty ? file.name : '自定义相册水印';
          _presetWatermarkId = null;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('从相册导入水印失败: $e')),
        );
      }
    }
  }

  Future<void> _pickPngFromFileManager() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['png', 'webp'],
        withData: true,
      );

      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        var bytes = file.bytes;
        if (bytes == null && file.path != null) {
          bytes = await File(file.path!).readAsBytes();
        }

        if (bytes != null) {
          final decoded = await WatermarkProcessor.decodeImageFromBytes(bytes);
          setState(() {
            _watermarkBytes = bytes;
            _decodedWatermark = decoded;
            _watermarkName = file.name;
            _presetWatermarkId = null;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('从文件管理器导入水印失败: $e')),
        );
      }
    }
  }

  void _showPresetWatermarkPicker() {
    PresetPickerSheet.show(
      context: context,
      currentWatermarkName: _watermarkName,
      onPresetSelected: (bytes, decoded, title, presetId) {
        setState(() {
          _watermarkBytes = bytes;
          _decodedWatermark = decoded;
          _watermarkName = title;
          _presetWatermarkId = presetId;
        });
      },
    );
  }

  void _applySavedPreset(SavedPreset preset) async {
    Uint8List? bytes = preset.watermarkBytes;
    if (bytes == null && preset.presetId != null) {
      final builtin = PresetWatermarkService.presets.firstWhere(
        (p) => p.id == preset.presetId,
        orElse: () => PresetWatermarkService.presets.first,
      );
      bytes = await builtin.generateBytes();
    }

    if (bytes != null) {
      final decoded = await WatermarkProcessor.decodeImageFromBytes(bytes);
      final newConfig = _activePngConfig.copyWith(
        scale: preset.scale,
        opacity: preset.opacity,
        rotation: preset.rotation,
        customX: preset.customX,
        customY: preset.customY,
        isInverted: preset.isInverted,
        mode: preset.mode == 'tiled' ? WatermarkMode.tiled : WatermarkMode.single,
        tileSpacingX: preset.tileSpacingX,
        tileSpacingY: preset.tileSpacingY,
        tileStaggered: preset.tileStaggered,
        isCustomDrag: true,
        position: WatermarkPosition.custom,
      );

      setState(() {
        _watermarkBytes = bytes;
        _decodedWatermark = decoded;
        _watermarkName = preset.name;
        _presetWatermarkId = preset.presetId;
        _watermarkType = WatermarkType.floatingPng;
        _activeToolIndex = 0;
      });

      _updatePngConfig(newConfig);
    }
  }

  void _showResourcesSheet() {
    ResourcesSheet.show(
      context: context,
      imageCount: _images.length,
      activePngConfig: _activePngConfig,
      watermarkBytes: _watermarkBytes,
      presetWatermarkId: _presetWatermarkId,
      onPickMoreImages: _pickImagesFromGallery,
      onApplyPreset: _applySavedPreset,
    );
  }

  void _openExportSheet({bool exportAll = true}) {
    if (_images.isEmpty) return;

    BlurredDialogHelper.showBlurredBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return ExportBottomSheet(
          watermarkType: _watermarkType,
          images: _images,
          currentIndex: _selectedImageIndex,
          watermarkImage: _decodedWatermark,
          pngConfig: _activePngConfig,
          logoImage: _decodedBrandLogo,
          frameConfig: _activeFrameConfig,
          isIndividualMode: _isIndividualMode,
          initialExportAll: exportAll,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final inEditing = _images.isNotEmpty;

    return Scaffold(
      backgroundColor: inEditing ? const Color(0xFF000000) : const Color(0xFF0C0C10),
      body: SafeArea(
        top: inEditing,
        bottom: inEditing,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 380),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, animation) {
            return FadeTransition(
              opacity: animation,
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.96, end: 1.0).animate(
                  CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
                ),
                child: child,
              ),
            );
          },
          child: _images.isEmpty
              ? KeyedSubtree(
                  key: const ValueKey('landing_pick_screen'),
                  child: _buildLandingPickScreen(isDark),
                )
              : KeyedSubtree(
                  key: const ValueKey('editing_workspace_screen'),
                  child: _buildEditingWorkspace(),
                ),
        ),
      ),
      bottomNavigationBar: AnimatedSize(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
        child: _images.isNotEmpty
            ? PureIconBottomBar(
                watermarkType: _watermarkType,
                activeToolIndex: _activeToolIndex,
                onToolSelected: (toolIdx) {
                  setState(() {
                    _activeToolIndex = toolIdx;
                    _isAdjusting = false;
                  });
                },
                onOpenResources: _showResourcesSheet,
              )
            : const SizedBox.shrink(),
      ),
    );
  }

  Widget _buildTopAboutButton(bool isDark) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          AboutPage.open(context);
        },
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.42),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.info_outline_rounded,
                size: 16,
                color: Colors.white,
              ),
              SizedBox(width: 5),
              Text(
                '关于',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  letterSpacing: -0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLandingPickScreen(bool isDark) {
    final topPadding = MediaQuery.of(context).padding.top;

    return Stack(
      children: [
        // 1. 顶部大图海报轮播 (独立渲染层, 拖拽底部面板时不触发重绘)
        Positioned.fill(
          child: RepaintBoundary(
            child: HeroPosterBanner(
              onActionButtonTap: () {
                _showPresetWatermarkPicker();
              },
              onMoreOptionsTap: () {
                _showQuickOptionsMenu();
              },
            ),
          ),
        ),

        // 2. 底部可向上拖拽全屏的自制照片选择器 (独立渲染层)
        RepaintBoundary(
          child: CustomPhotoSelector(
            onImportWithWatermarkType: _onImportWithWatermarkType,
            onPhotoSelected: _onSelectDevicePhoto,
            onMultiplePhotosSelected: _onSelectMultipleDevicePhotos,
          ),
        ),

        // 3. 顶部右上角「关于」按钮
        Positioned(
          top: (topPadding > 0 ? topPadding : 16) + 8,
          right: 16,
          child: _buildTopAboutButton(isDark),
        ),

        // 4. 图片导入加载中遮罩
        if (_isLoading)
          Positioned.fill(
            child: Container(
              color: Colors.black45,
              child: const Center(
                child: CircularProgressIndicator(
                  color: Color(0xFFFFD600),
                  strokeWidth: 2.5,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildEditingWorkspace() {
    return Container(
      color: const Color(0xFF000000),
      child: Column(
        children: [
          // 1. 照片全屏预览区 (纯黑背景，占满全屏)
          Expanded(
            child: CardStackPreview(
              images: _images,
              currentIndex: _selectedImageIndex,
              watermarkType: _watermarkType,
              activeToolIndex: _activeToolIndex,
              watermarkImage: _decodedWatermark,
              pngConfig: _activePngConfig,
              logoImage: _decodedBrandLogo,
              frameConfig: _activeFrameConfig,
              isIndividualMode: _isIndividualMode,
              onToggleIndividualMode: (val) {
                setState(() {
                  _isIndividualMode = val;
                  if (val && _images[_selectedImageIndex].individualPngConfig == null) {
                    _images[_selectedImageIndex] = _images[_selectedImageIndex].copyWith(
                      individualPngConfig: _globalPngConfig,
                      individualFrameConfig: _globalFrameConfig.copyWith(
                        exifInfo: _images[_selectedImageIndex].exifInfo,
                      ),
                    );
                  }
                });
              },
              onIndexChanged: (idx) {
                setState(() => _selectedImageIndex = idx);
              },
              onWatermarkDragged: (relX, relY) {
                final updated = _activePngConfig.copyWith(
                  customX: relX,
                  customY: relY,
                  isCustomDrag: true,
                  position: WatermarkPosition.custom,
                );
                _updatePngConfig(updated);
              },
              onPngConfigChanged: (cfg) => _updatePngConfig(cfg),
              onFrameConfigChanged: (cfg) => _updateFrameConfig(cfg),
              onParamAdjusting: (name, valStr, progress) {
                setState(() {
                  _isAdjusting = true;
                  _adjustingParamName = name;
                  _adjustingParamValue = valStr;
                  _adjustingProgress = progress;
                });
              },
              onParamAdjustEnd: () {
                setState(() {
                  _isAdjusting = false;
                });
              },
              onExport: (exportAll) => _openExportSheet(exportAll: exportAll),
              onBack: () {
                setState(() {
                  _images.clear();
                  _selectedImageIndex = 0;
                });
              },
            ),
          ),

          // 2. 超薄单行工具操作条 (纯黑背景，深灰胶囊，浅灰选中，平滑切换)
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 260),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) {
              return FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 0.2),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              );
            },
            child: _watermarkType == WatermarkType.frame
                ? KeyedSubtree(
                    key: const ValueKey('frame_controls_container'),
                    child: FrameControls(
                      activeToolIndex: _activeToolIndex,
                      config: _activeFrameConfig,
                      photoColors: _images.isNotEmpty && _selectedImageIndex < _images.length
                          ? PhotoColorExtractor.extractPaletteFromBytes(_images[_selectedImageIndex].bytes)
                          : const [],
                      photoBytes: _images.isNotEmpty && _selectedImageIndex < _images.length
                          ? _images[_selectedImageIndex].bytes
                          : null,
                      isAdjusting: _isAdjusting,
                      adjustingParamName: _adjustingParamName,
                      adjustingParamValue: _adjustingParamValue,
                      adjustingProgress: _adjustingProgress,
                      onChanged: (newCfg) async {
                        if (newCfg.selectedLogoId != _activeFrameConfig.selectedLogoId) {
                          if (newCfg.customLogoDecoded != null && newCfg.selectedLogoId.startsWith('custom_')) {
                            setState(() {
                              _decodedBrandLogo = newCfg.customLogoDecoded;
                            });
                          } else {
                            final logoBytes = await BrandLogoService.getLogoBytes(
                              newCfg.selectedLogoId,
                              customBytes: newCfg.customLogoBytes,
                            );
                            final decoded = await WatermarkProcessor.decodeImageFromBytes(logoBytes);
                            setState(() {
                              _decodedBrandLogo = decoded;
                            });
                          }
                        }
                        _updateFrameConfig(newCfg);
                      },
                    ),
                  )
                : KeyedSubtree(
                    key: const ValueKey('floating_controls_container'),
                    child: FloatingControls(
                      activeToolIndex: _activeToolIndex,
                      config: _activePngConfig,
                      watermarkBytes: _watermarkBytes,
                      decodedWatermark: _decodedWatermark,
                      watermarkName: _watermarkName,
                      presetWatermarkId: _presetWatermarkId,
                      isAdjusting: _isAdjusting,
                      adjustingParamName: _adjustingParamName,
                      adjustingParamValue: _adjustingParamValue,
                      adjustingProgress: _adjustingProgress,
                      onPickCustomWatermark: _pickCustomPngWatermarkDialog,
                      onPickPresetWatermark: _showPresetWatermarkPicker,
                      onChanged: (newCfg) => _updatePngConfig(newCfg),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// 64dp 纯图标底部工具栏 (黄色焦点高亮，无大阴影，直接使用纯黑界面背景)
class PureIconBottomBar extends StatelessWidget {
  final WatermarkType watermarkType;
  final int activeToolIndex;
  final ValueChanged<int> onToolSelected;
  final VoidCallback onOpenResources;

  const PureIconBottomBar({
    super.key,
    required this.watermarkType,
    required this.activeToolIndex,
    required this.onToolSelected,
    required this.onOpenResources,
  });

  @override
  Widget build(BuildContext context) {
    const activeYellow = Color(0xFFFFD600); // 焦点黄色
    const inactiveColor = Color(0xFF8E8E93); // 未选中灰白

    final toolIcons = watermarkType == WatermarkType.frame
        ? [
            {'icon': Icons.branding_watermark_rounded, 'tooltip': AppStrings.toolBrandLogo},
            {'icon': Icons.palette_rounded, 'tooltip': AppStrings.toolFrameColor},
            {'icon': Icons.crop_free_rounded, 'tooltip': AppStrings.toolFrameParams},
            {'icon': Icons.camera_alt_rounded, 'tooltip': AppStrings.toolExifParams},
          ]
        : [
            {'icon': Icons.folder_open_rounded, 'tooltip': AppStrings.toolPngLibrary},
            {'icon': Icons.grid_view_rounded, 'tooltip': AppStrings.toolPngPosition},
            {'icon': Icons.auto_awesome_rounded, 'tooltip': AppStrings.toolPngEffects},
          ];

    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      color: Colors.transparent,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          // 工具项 (黄色焦点，无水波纹，动态缩放)
          ...List.generate(toolIcons.length, (idx) {
            final isSelected = activeToolIndex == idx;
            final item = toolIcons[idx];

            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onToolSelected(idx),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                child: TweenAnimationBuilder<double>(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutBack,
                  tween: Tween<double>(begin: 1.0, end: isSelected ? 1.15 : 1.0),
                  builder: (context, scale, child) {
                    return Transform.scale(
                      scale: scale,
                      child: Icon(
                        item['icon'] as IconData,
                        size: 22,
                        color: isSelected ? activeYellow : inactiveColor,
                      ),
                    );
                  },
                ),
              ),
            );
          }),

          // 资源与预设
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onOpenResources,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: const Icon(Icons.folder_special_outlined, size: 22, color: inactiveColor),
            ),
          ),
        ],
      ),
    );
  }
}

