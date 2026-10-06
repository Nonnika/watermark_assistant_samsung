import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';

import '../models/frame_watermark_config.dart';
import '../models/image_item.dart';
import '../models/saved_preset.dart';
import '../models/watermark_config.dart';
import '../services/brand_logos.dart';
import '../services/photo_color_extractor.dart';
import '../services/device_photo_service.dart';
import '../services/preset_watermarks.dart';
import '../services/watermark_processor.dart';
import '../theme/one_ui_theme.dart';
import '../utils/blurred_dialog_helper.dart';

import 'dart:typed_data';

import 'home/editing_workspace.dart';
import 'home/landing_pick_screen.dart';
import 'export_bottom_sheet.dart';
import 'pure_icon_bottom_bar.dart';
import 'sheets/png_source_sheet.dart';
import 'sheets/preset_picker_sheet.dart';
import 'sheets/quick_options_sheet.dart';
import 'sheets/resources_sheet.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  final List<ImageItem> _images = [];
  int _selectedImageIndex = 0;

  // 主模式选择：边框水印 或 自定义 PNG 水印
  WatermarkType _watermarkType = WatermarkType.frame;
  int _activeToolIndex = 0;

  // 是否开启“单独调节当前照片”开关 (true: 仅当前图片生效, false: 批量同步全局)
  bool _isIndividualMode = false;

  // 落地页 ↔ 编辑页切换方向：true = 进入编辑（放大推入），false = 返回落地页（缩小退场）
  bool _enteringEditing = true;

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
  final Map<String, ui.Image> _decodedBrandLogos = {};
  final Map<String, Future<ui.Image>> _pendingBrandLogos = {};

  bool _isLoading = false;
  final ImagePicker _picker = ImagePicker();

  // 当前选中照片的代表色调（后台 isolate 预计算，避免 build() 内全分辨率解码）
  List<Color> _photoPalette = const [];
  int _paletteRequestId = 0;

  @override
  void initState() {
    super.initState();
    _initDefaultState();
  }

  Future<void> _initDefaultState() async {
    await _resolveBrandLogo(_globalFrameConfig);

    final defaultPreset = PresetWatermarkService.presets.first;
    final wmBytes = await defaultPreset.generateBytes();
    final wmDecoded = await WatermarkProcessor.decodeImageFromBytes(wmBytes);

    if (mounted) {
      setState(() {
        _watermarkBytes = wmBytes;
        _decodedWatermark = wmDecoded;
        _watermarkName = defaultPreset.title;
        _presetWatermarkId = defaultPreset.id;
      });
    }
  }

  WatermarkConfig get _activePngConfig {
    if (_isIndividualMode && _images.isNotEmpty) {
      return _images[_selectedImageIndex].individualPngConfig ??
          _globalPngConfig;
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
      return (_isIndividualMode
              ? (_images[_selectedImageIndex].individualFrameConfig ??
                    _globalFrameConfig)
              : _globalFrameConfig)
          .copyWith(exifInfo: _images[_selectedImageIndex].exifInfo);
    }
    return _globalFrameConfig;
  }

  void _updateFrameConfig(FrameWatermarkConfig newConfig) {
    setState(() {
      if (!_isIndividualMode) {
        _globalFrameConfig = newConfig;
      }
      if (_images.isNotEmpty && _selectedImageIndex < _images.length) {
        _images[_selectedImageIndex] = _images[_selectedImageIndex].copyWith(
          exifInfo: newConfig.exifInfo,
          individualFrameConfig: _isIndividualMode ? newConfig : null,
        );
      }
    });
    _refreshBrandLogo();
  }

  ui.Image? _brandLogoForConfig(FrameWatermarkConfig config) {
    if (config.selectedLogoId.startsWith('custom_') ||
        config.selectedLogoId == 'custom') {
      final custom = config.customLogoDecoded;
      if (custom != null) return custom;
    }
    return _decodedBrandLogos[config.selectedLogoId];
  }

  Future<ui.Image> _resolveBrandLogo(FrameWatermarkConfig config) async {
    final cached = _brandLogoForConfig(config);
    if (cached != null) return cached;

    final id = config.selectedLogoId;
    final pending = _pendingBrandLogos.putIfAbsent(id, () async {
      final bytes = await BrandLogoService.getLogoBytes(
        id,
        customBytes: config.customLogoBytes,
      );
      return WatermarkProcessor.decodeImageFromBytes(bytes);
    });
    try {
      final decoded = await pending;
      _decodedBrandLogos[id] = decoded;
      return decoded;
    } finally {
      _pendingBrandLogos.remove(id);
    }
  }

  Future<void> _refreshBrandLogo() async {
    if (_brandLogoForConfig(_activeFrameConfig) != null) return;
    await _resolveBrandLogo(_activeFrameConfig);
    // 完成后按当前配置取缓存，过期解码结果不会替换另一张照片的 Logo。
    if (mounted) setState(() {});
  }

  Future<void> _refreshPhotoPalette() async {
    final bytes = (_images.isNotEmpty && _selectedImageIndex < _images.length)
        ? _images[_selectedImageIndex].bytes
        : null;
    if (bytes == null || bytes.isEmpty) {
      _paletteRequestId++;
      setState(() => _photoPalette = const []);
      return;
    }
    final requestId = ++_paletteRequestId;
    final palette = await PhotoColorExtractor.extractPaletteFromBytesAsync(
      bytes,
    );
    // 丢弃过期结果：等待期间用户可能已切换照片
    if (!mounted || requestId != _paletteRequestId) return;
    setState(() => _photoPalette = palette);
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
        _enteringEditing = true;
      });
      _images.clear();
      for (final photo in photoList) {
        final bytes = await DevicePhotoService.getFullPhotoBytes(photo);
        if (bytes != null && bytes.isNotEmpty) {
          final item = await WatermarkProcessor.createImageItem(
            id: photo.id.isNotEmpty ? photo.id : UniqueKey().toString(),
            name: photo.name.isNotEmpty
                ? photo.name
                : 'Photo_${DateTime.now().millisecondsSinceEpoch}',
            path: photo.path,
            bytes: bytes,
          );
          _images.add(item);
        }
      }

      if (mounted) {
        setState(() {
          _isLoading = false;
          _selectedImageIndex = 0;
        });
        _refreshPhotoPalette();
        _refreshBrandLogo();
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('导入图片失败: $e')));
      }
    }
  }

  Future<void> _onSelectDevicePhoto(DevicePhotoModel photo) async {
    await _onImportWithWatermarkType([photo], WatermarkType.frame);
  }

  Future<void> _onSelectMultipleDevicePhotos(
    List<DevicePhotoModel> photoList,
  ) async {
    await _onImportWithWatermarkType(photoList, WatermarkType.frame);
  }

  void _showQuickOptionsMenu() {
    QuickOptionsSheet.show(context: context, onApplyPreset: _applySavedPreset);
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
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _selectedImageIndex = newIdx;
        _watermarkType = WatermarkType.frame;
        _enteringEditing = true;
      });
      _refreshPhotoPalette();
      _refreshBrandLogo();
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('选择图片失败: $e')));
      }
    }
  }

  Future<void> _pickCustomPngWatermarkDialog() async {
    PngSourceSheet.show(
      context: context,
      onPickFromGallery: _pickPngFromGallery,
      onPickFromFile: _pickPngFromFileManager,
    );
  }

  Future<void> _pickPngFromGallery() async {
    try {
      final XFile? file = await _picker.pickImage(source: ImageSource.gallery);
      if (file != null) {
        final bytes = await file.readAsBytes();
        final decoded = await WatermarkProcessor.decodeImageFromBytes(bytes);
        if (!mounted) return;
        setState(() {
          _watermarkBytes = bytes;
          _decodedWatermark = decoded;
          _watermarkName = file.name.isNotEmpty ? file.name : '自定义相册水印';
          _presetWatermarkId = null;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('从相册导入水印失败: $e')));
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
          if (!mounted) return;
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
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('从文件管理器导入水印失败: $e')));
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
      if (!mounted) return;
      final newConfig = _activePngConfig.copyWith(
        scale: preset.scale,
        opacity: preset.opacity,
        rotation: preset.rotation,
        customX: preset.customX,
        customY: preset.customY,
        isInverted: preset.isInverted,
        mode: preset.mode == 'tiled'
            ? WatermarkMode.tiled
            : WatermarkMode.single,
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
          pngConfig: _globalPngConfig,
          resolveLogoImage: _resolveBrandLogo,
          frameConfig: _globalFrameConfig,
          isIndividualMode: _isIndividualMode,
          initialExportAll: exportAll,
        );
      },
    );
  }

  /// 「单独调节当前照片」开关：开启时把全局配置快照到当前照片的独立配置
  void _onToggleIndividualMode(bool val) {
    setState(() {
      _isIndividualMode = val;
      if (val && _images.isNotEmpty) {
        final item = _images[_selectedImageIndex];
        _images[_selectedImageIndex] = item.copyWith(
          individualPngConfig: item.individualPngConfig ?? _globalPngConfig,
          individualFrameConfig:
              item.individualFrameConfig ??
              _globalFrameConfig.copyWith(exifInfo: item.exifInfo),
        );
      }
    });
    _refreshBrandLogo();
  }

  void _onPreviewIndexChanged(int idx) {
    setState(() => _selectedImageIndex = idx);
    _refreshPhotoPalette();
    _refreshBrandLogo();
  }

  void _onWatermarkDragged(double relX, double relY) {
    final updated = _activePngConfig.copyWith(
      customX: relX,
      customY: relY,
      isCustomDrag: true,
      position: WatermarkPosition.custom,
    );
    _updatePngConfig(updated);
  }

  void _onParamAdjusting(String name, String valStr, double progress) {
    setState(() {
      _isAdjusting = true;
      _adjustingParamName = name;
      _adjustingParamValue = valStr;
      _adjustingProgress = progress;
    });
  }

  void _onParamAdjustEnd() {
    setState(() {
      _isAdjusting = false;
    });
  }

  void _onEditingBack() {
    setState(() {
      _enteringEditing = false;
      _images.clear();
      _selectedImageIndex = 0;
    });
    _refreshPhotoPalette();
    _refreshBrandLogo();
  }

  @override
  Widget build(BuildContext context) {
    final inEditing = _images.isNotEmpty;

    // 编辑页中拦截系统返回（含预测性返回手势）：先动画回到落地页，落地页才允许退出应用
    return PopScope(
      canPop: !inEditing,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _onEditingBack();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
        color: inEditing
            ? const Color(0xFF000000)
            : OneUITheme.landingBackground,
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: AnimatedSwitcher(
            duration: const Duration(milliseconds: 360),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: _buildScreenSwitchTransition,
            child: _images.isEmpty
                ? KeyedSubtree(
                    key: const ValueKey('landing_pick_screen'),
                    child: LandingPickScreen(
                      isLoading: _isLoading,
                      onPickPresetWatermark: _showPresetWatermarkPicker,
                      onOpenQuickOptions: _showQuickOptionsMenu,
                      onImportWithWatermarkType: _onImportWithWatermarkType,
                      onPhotoSelected: _onSelectDevicePhoto,
                      onMultiplePhotosSelected: _onSelectMultipleDevicePhotos,
                    ),
                  )
                : KeyedSubtree(
                    key: const ValueKey('editing_workspace_screen'),
                    child: EditingWorkspace(
                      images: _images,
                      selectedImageIndex: _selectedImageIndex,
                      watermarkType: _watermarkType,
                      activeToolIndex: _activeToolIndex,
                      decodedWatermark: _decodedWatermark,
                      activePngConfig: _activePngConfig,
                      decodedBrandLogo: _brandLogoForConfig(_activeFrameConfig),
                      activeFrameConfig: _activeFrameConfig,
                      isIndividualMode: _isIndividualMode,
                      isAdjusting: _isAdjusting,
                      adjustingParamName: _adjustingParamName,
                      adjustingParamValue: _adjustingParamValue,
                      adjustingProgress: _adjustingProgress,
                      watermarkBytes: _watermarkBytes,
                      watermarkName: _watermarkName,
                      presetWatermarkId: _presetWatermarkId,
                      photoPalette: _photoPalette,
                      onToggleIndividualMode: _onToggleIndividualMode,
                      onIndexChanged: _onPreviewIndexChanged,
                      onWatermarkDragged: _onWatermarkDragged,
                      onPngConfigChanged: _updatePngConfig,
                      onFrameConfigChanged: _updateFrameConfig,
                      onFrameControlsChanged: _updateFrameConfig,
                      onParamAdjusting: _onParamAdjusting,
                      onParamAdjustEnd: _onParamAdjustEnd,
                      onExport: (exportAll) =>
                          _openExportSheet(exportAll: exportAll),
                      onBack: _onEditingBack,
                      onPickCustomWatermark: _pickCustomPngWatermarkDialog,
                      onPickPresetWatermark: _showPresetWatermarkPicker,
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
        ),
      ),
    );
  }

  /// 方向感知的屏幕切换转场：
  /// - 进入编辑：编辑屏自 0.96 放大淡入，落地页作为底层仅渐隐；
  /// - 返回落地页：编辑屏缩至 0.94 淡出、落地页在下层渐显，
  ///   与 Android 预测性返回「上层屏缩小退场、下层屏保持」的视觉语义一致。
  Widget _buildScreenSwitchTransition(
    Widget child,
    Animation<double> animation,
  ) {
    final isEditingChild =
        child.key == const ValueKey('editing_workspace_screen');
    if (!isEditingChild) {
      return FadeTransition(opacity: animation, child: child);
    }
    return FadeTransition(
      opacity: animation,
      child: ScaleTransition(
        scale:
            (_enteringEditing
                    ? Tween<double>(begin: 0.96, end: 1.0)
                    : Tween<double>(begin: 0.94, end: 1.0))
                .animate(animation),
        child: child,
      ),
    );
  }
}
