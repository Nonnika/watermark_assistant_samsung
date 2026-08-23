import 'package:flutter/material.dart';

enum AppLanguage {
  zh, // 中文
  en, // English
}

class AppStrings {
  static final ValueNotifier<AppLanguage> currentLanguage = ValueNotifier<AppLanguage>(AppLanguage.zh);

  static bool get isZh => currentLanguage.value == AppLanguage.zh;

  static void toggleLanguage() {
    currentLanguage.value = isZh ? AppLanguage.en : AppLanguage.zh;
  }

  static void updateFromLocale(Locale? locale) {
    if (locale == null) return;
    if (locale.languageCode.toLowerCase().startsWith('zh')) {
      currentLanguage.value = AppLanguage.zh;
    } else {
      currentLanguage.value = AppLanguage.en;
    }
  }

  // App & Header
  static String get appName => isZh ? '水印助手' : 'Watermark Assistant';
  static String get headerSubtitle => isZh ? '感受更强大的水印体验' : 'Experience a More Powerful Watermark Tool';
  static String get landingTitle => isZh ? '批量照片水印助手' : 'Batch Photo Watermark Assistant';
  static String get landingSubtitle => isZh
      ? '支持一次选择多张照片批量处理\n搭载原版品牌 Logo 与自由 PNG 水印引擎'
      : 'Batch process multiple photos simultaneously\nEquipped with authentic brand logos & free PNG watermark engine';
  static String get selectPhotos => isZh ? '选择多张图片开始' : 'Select Photos to Start';
  static String get importingPhotos => isZh ? '正在导入图片...' : 'Importing photos...';
  static String get toggleTheme => isZh ? '切换主题' : 'Toggle Theme';
  static String get toggleLang => isZh ? 'English' : '中文';

  // Bottom Toolbars
  static String get toolBrandLogo => isZh ? '品牌 Logo' : 'Brand Logo';
  static String get toolFrameColor => isZh ? '相框颜色' : 'Frame Color';
  static String get toolFrameParams => isZh ? '留白与参数(Snapseed)' : 'Padding & Size';
  static String get toolExifParams => isZh ? 'EXIF拍摄参数' : 'EXIF Metadata';

  static String get toolPngLibrary => isZh ? '水印图库' : 'Watermarks';
  static String get toolPngPosition => isZh ? '位置(Snapseed)' : 'Position';
  static String get toolPngEffects => isZh ? '尺寸与效果(Snapseed)' : 'Size & Effects';
  static String get toolPngTiled => isZh ? '满铺排列' : 'Tiled Layout';

  // Logo Strip
  static String get logoBlue => isZh ? '蓝标' : 'Blue';
  static String get logoBlack => isZh ? '黑标' : 'Black';
  static String get logoWhite => isZh ? '白标' : 'White';
  static String get logoAdd => isZh ? '添加' : 'Add';
  static String get logoInvert => isZh ? '反色' : 'Invert';
  static String get roundedCorners => isZh ? '圆角' : 'Round';

  // Snapseed Parameters
  static String get paramPadding => isZh ? '四周留白比例' : 'Padding Ratio';
  static String get paramBottomBar => isZh ? '底部参数栏高度' : 'Bottom Bar Height';
  static String get paramLogoScale => isZh ? 'Logo 尺寸大小' : 'Logo Scale';
  static String get paramLogoOffsetX => isZh ? 'Logo 左右位置' : 'Logo Horizontal Offset';
  static String get paramLogoOffsetY => isZh ? 'Logo 上下位置' : 'Logo Vertical Offset';
  static String get paramTextOffsetX => isZh ? '文字左右位置' : 'Text Horizontal Offset';
  static String get paramTextOffsetY => isZh ? '文字上下位置' : 'Text Vertical Offset';
  static String get paramCornerRadius => isZh ? '照片圆角弧度' : 'Corner Radius';
  static String get paramShadow => isZh ? '照片外阴影' : 'Outer Shadow';
  static String get paramCustomX => isZh ? '水平 X 坐标' : 'Horizontal X';
  static String get paramCustomY => isZh ? '垂直 Y 坐标' : 'Vertical Y';
  static String get paramScale => isZh ? '等比缩放尺寸' : 'Scale Size';
  static String get paramOpacity => isZh ? '不透明度' : 'Opacity';
  static String get paramRotation => isZh ? '旋转角度' : 'Rotation';
  static String get gestureHint => isZh ? '在照片上：上下滑切参数，左右滑调数值' : 'On photo: drag up/down to switch, left/right to adjust';

  // Color Palette
  static String get paletteTitle => isZh ? '边框背景色板' : 'Frame Color Palette';
  static String get palettePhotoGroup => isZh ? '来自当前照片的颜色' : 'Extracted Photo Palette';
  static String get paletteMonochrome => isZh ? '经典黑白灰' : 'Classic Monochrome';
  static String get paletteVintage => isZh ? '复古胶片与米白' : 'Vintage & Off-White';
  static String get paletteMorandi => isZh ? '莫兰迪色系' : 'Morandi Hues';
  static String get paletteBrands => isZh ? '相机品牌与纯彩' : 'Camera Brands & Pure Colors';
  static String get paletteDark => isZh ? '深邃暗夜影调' : 'Deep Night Shades';

  // Dialogs & Menus
  static String get editCurrentOnly => isZh ? '仅编辑当前照片位置' : 'Edit Current Photo Only';
  static String get exportCurrent => isZh ? '导出当前照片' : 'Export Current Photo';
  static String exportAll(int count) => isZh ? '批量导出全部照片 (当前 $count 张)' : 'Batch Export All Photos ($count)';
  static String get moreResources => isZh ? '更多资源与预设' : 'Resources & Presets';
  static String addMorePhotos(int count) => isZh ? '继续添加照片 (当前 $count 张)' : 'Add More Photos (Current: $count)';
  static String get addMorePhotosSub => isZh ? '批量选择更多图片加入处理列表' : 'Select more images to add to the batch list';
  static String get myPresets => isZh ? '我的预设库' : 'My Presets';
  static String get myPresetsSub => isZh ? '查看与套用已保存的水印参数' : 'View and apply saved watermark presets';
  static String get saveAsPreset => isZh ? '保存当前配置为预设' : 'Save Current as Preset';
  static String get saveAsPresetSub => isZh ? '保存当前水印图片与全部参数到本地' : 'Save current watermark & settings to local presets';

  // Custom Logo Dialog
  static String get addCustomLogoTitle => isZh ? '添加自定义 Logo' : 'Add Custom Logo';
  static String get logoLabelName => isZh ? 'Logo 标签名称' : 'Logo Label Name';
  static String get logoLabelHint => isZh ? '如：Leica、Sony、我的标志' : 'e.g. Leica, Sony, My Brand';
  static String get autoInvertLogo => isZh ? 'Logo 自动反色 (如黑转白)' : 'Auto Invert Logo Color';
  static String get cancel => isZh ? '取消' : 'Cancel';
  static String get confirmAdd => isZh ? '确认添加' : 'Confirm Add';
  static String get delete => isZh ? '删除' : 'Delete';
  static String deleteLogoConfirm(String name) => isZh ? '删除 Logo "$name"?' : 'Delete Logo "$name"?';

  // EXIF Dialog
  static String get editExifTitle => isZh ? '编辑 EXIF 拍摄参数' : 'Edit EXIF Metadata';
  static String get cameraModel => isZh ? '相机/机型' : 'Camera / Model';
  static String get brandMake => isZh ? '品牌厂商' : 'Brand / Make';
  static String get focalLength => isZh ? '焦距' : 'Focal Length';
  static String get aperture => isZh ? '光圈' : 'Aperture';
  static String get shutterSpeed => isZh ? '快门速度' : 'Shutter Speed';
  static String get iso => isZh ? 'ISO' : 'ISO';
  static String get dateTime => isZh ? '拍摄日期时间' : 'Capture Date & Time';
  static String get autoSegmentHint => isZh ? '输入纯数字自动分割匹配 (如 202408211430)' : 'Type numbers to auto-segment (e.g. 202408211430)';
  static String get fillNowTime => isZh ? '当前时间' : 'Current Time';
  static String get clearTime => isZh ? '清空' : 'Clear';
  static String get dateTimeHint => isZh ? '自动分割: 2024.08.21 14:30' : 'Auto format: 2024.08.21 14:30';
  static String get saveChanges => isZh ? '保存修改' : 'Save Changes';

  // Motion Photo (动态照片)
  static String get motionPhotoBadge => isZh ? '动态照片' : 'Motion Photo';
  static String get motionPhotoPlaying => isZh ? '正在播放动态效果' : 'Playing Motion Photo';
  static String get motionPhotoExportMode => isZh ? '动态照片导出处理' : 'Motion Photo Export';
  static String get motionPhotoPreserve => isZh ? '保留动态照片 (推荐)' : 'Preserve Motion Photo (Recommended)';
  static String get motionPhotoPreserveSub => isZh ? '加水印后重新合成原汁原味的动态照片' : 'Re-embed live video with watermark';
  static String get motionPhotoStaticOnly => isZh ? '转换为普通静态照片' : 'Static Photo Only';
  static String get motionPhotoStaticOnlySub => isZh ? '仅保存高清静态水印封面' : 'Save high-res still cover only';
  static String get motionPhotoExtractMp4 => isZh ? '单独导出 MP4 视频' : 'Export Video Only (MP4)';
  static String get motionPhotoExtractMp4Sub => isZh ? '提取保存内嵌的完整短视频' : 'Extract embedded MP4 video file';
}
