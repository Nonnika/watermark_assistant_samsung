import 'package:flutter/material.dart';
import 'one_ui_pressable.dart';
import 'package:flutter/services.dart';
import '../models/watermark_config.dart';
import '../services/device_photo_service.dart';
import 'selector/selector_bottom_action.dart';
import 'selector/selector_grid_page.dart';
import 'selector/selector_tab_bar.dart';

typedef OnImportWithWatermarkType = void Function(List<DevicePhotoModel> photos, WatermarkType watermarkType);

/// 专为高通 Adreno GPU 优化的高质感全屏/半屏上拉照片选择器
/// 采用 GPU 矩阵平移（Transform.translate）与固定渲染视口，动画期间实现 0 Relayout 与 0 Widget 重建
class CustomPhotoSelector extends StatefulWidget {
  final ValueChanged<DevicePhotoModel>? onPhotoSelected;
  final ValueChanged<List<DevicePhotoModel>>? onMultiplePhotosSelected;
  final OnImportWithWatermarkType? onImportWithWatermarkType;
  final VoidCallback? onAddManualFile;

  const CustomPhotoSelector({
    super.key,
    this.onPhotoSelected,
    this.onMultiplePhotosSelected,
    this.onImportWithWatermarkType,
    this.onAddManualFile,
  });

  @override
  State<CustomPhotoSelector> createState() => _CustomPhotoSelectorState();
}

class _CustomPhotoSelectorState extends State<CustomPhotoSelector>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late AnimationController _animController;
  late Animation<double> _factorAnimation;
  final ValueNotifier<double> _sheetFactorNotifier = ValueNotifier<double>(_minFactor);
  final ValueNotifier<bool> _isExpandedNotifier = ValueNotifier<bool>(false);
  final PageController _pageController = PageController(initialPage: 0);

  static const double _minFactor = 1.0 / 3.0; // 提升至 1/3 屏幕高度
  static const double _maxFactor = 0.94;

  int _selectedTab = 0; // 0: 全部照片, 1: 仅动态照片
  bool _isLoading = true;
  bool _hasPermission = true;
  List<DevicePhotoModel> _photos = [];
  List<DevicePhotoModel> _motionPhotos = [];
  bool _motionScanDone = false;
  final Set<String> _selectedIds = {};
  final ScrollController _allGridScrollController = ScrollController();
  final ScrollController _motionGridScrollController = ScrollController();

  List<DevicePhotoModel> get _currentList => _selectedTab == 0 ? _photos : _motionPhotos;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _factorAnimation = _animController.drive(
      Tween<double>(begin: _minFactor, end: _minFactor),
    );

    _sheetFactorNotifier.addListener(_onSheetFactorChanged);

    _loadPhotos();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_hasPermission) {
      _loadPhotos();
    }
  }

  @override
  void didHaveMemoryPressure() {
    DevicePhotoService.clearThumbnailCache();
  }

  void _onSheetFactorChanged() {
    // 仅在完全到达顶部展开位置时切换为展开态 (无中间停留档位)
    final isExp = _sheetFactorNotifier.value >= _maxFactor - 0.01;
    if (_isExpandedNotifier.value != isExp) {
      _isExpandedNotifier.value = isExp;
      if (!isExp) {
        // 折叠时网格物理从 Bouncing 切换为 NeverScrollable，会中断正在进行的
        // 回弹动画，可能把滚动偏移冻结在负值（第一行上方露出黑色空白），
        // 这里立即钳制回有效范围
        _clampGridOffset(_allGridScrollController);
        _clampGridOffset(_motionGridScrollController);
      }
    }
  }

  void _clampGridOffset(ScrollController controller) {
    if (!controller.hasClients) return;
    final position = controller.position;
    if (position.pixels < 0) {
      position.jumpTo(0);
    } else if (position.pixels > position.maxScrollExtent) {
      position.jumpTo(position.maxScrollExtent);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sheetFactorNotifier.removeListener(_onSheetFactorChanged);
    _sheetFactorNotifier.dispose();
    _isExpandedNotifier.dispose();
    _pageController.dispose();
    _animController.dispose();
    _allGridScrollController.dispose();
    _motionGridScrollController.dispose();
    super.dispose();
  }

  Future<void> _loadPhotos() async {
    setState(() => _isLoading = true);
    final hasPerm = await DevicePhotoService.checkPermission();
    if (!hasPerm) {
      if (mounted) {
        setState(() {
          _hasPermission = false;
          _photos = [];
          _motionPhotos = [];
          _isLoading = false;
        });
      }
      return;
    }

    if (mounted && !_hasPermission) {
      setState(() => _hasPermission = true);
    }

    try {
      final list = await DevicePhotoService.getRecentPhotos(limit: 0);
      if (mounted) {
        setState(() {
          _photos = list;
          _isLoading = false;
        });
      }

      // 预热前 24 张缩略图 (保证首屏瞬时直出)
      if (mounted && list.isNotEmpty) {
        DevicePhotoService.preloadThumbnails(
          list.take(24).toList(),
          shouldContinue: () => mounted && identical(_photos, list),
        );
      }

      // 后台异步并发检测动态照片
      _scanMotionPhotos(list);
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _requestPermission() async {
    final granted = await DevicePhotoService.requestPermission();
    if (granted) {
      await _loadPhotos();
    } else {
      final hasPerm = await DevicePhotoService.checkPermission();
      if (!hasPerm) {
        await DevicePhotoService.openAppSettings();
      }
      await _loadPhotos();
    }
  }

  Future<void> _scanMotionPhotos(List<DevicePhotoModel> list) async {
    if (list.isEmpty) {
      if (mounted) {
        setState(() {
          _motionPhotos = [];
          _motionScanDone = true;
        });
      }
      return;
    }

    final motions = await DevicePhotoService.filterMotionPhotos(
      list,
      onProgress: (partial) {
        if (mounted) {
          setState(() {
            _motionPhotos = partial;
            if (partial.isNotEmpty) {
              _motionScanDone = true;
            }
          });
        }
      },
    );
    if (mounted) {
      setState(() {
        _motionPhotos = motions;
        _motionScanDone = true;
      });
    }
  }

  void _animateTo(double targetFactor) {
    _animController.stop();
    _animController.removeListener(_onAnimTick);
    _factorAnimation = Tween<double>(
      begin: _sheetFactorNotifier.value,
      end: targetFactor,
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.fastOutSlowIn));

    _animController.addListener(_onAnimTick);
    _animController.forward(from: 0.0).then((_) {
      _animController.removeListener(_onAnimTick);
    });
  }

  void _onAnimTick() {
    _sheetFactorNotifier.value = _factorAnimation.value;
  }

  void _toggleExpand() {
    HapticFeedback.selectionClick();
    if (_sheetFactorNotifier.value > (_minFactor + _maxFactor) / 2) {
      _animateTo(_minFactor);
    } else {
      _animateTo(_maxFactor);
    }
  }

  void _handleDragStart(DragStartDetails details) {
    _animController.stop();
    _animController.removeListener(_onAnimTick);
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    final screenHeight = MediaQuery.of(context).size.height;
    if (screenHeight <= 0) return;
    final deltaFactor = -details.primaryDelta! / screenHeight;
    _sheetFactorNotifier.value = (_sheetFactorNotifier.value + deltaFactor).clamp(_minFactor, _maxFactor);
  }

  void _handleDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0.0;
    if (velocity < -120) {
      // 向上滑动 -> 直接平滑吸附至全屏展开档位
      _animateTo(_maxFactor);
    } else if (velocity > 120) {
      // 向下滑动 -> 直接平滑吸附至底部折叠档位
      _animateTo(_minFactor);
    } else {
      // 仅保留底部折叠与全屏展开两个档位，彻底删除中间停顿档位
      if (_sheetFactorNotifier.value > (_minFactor + 0.06)) {
        _animateTo(_maxFactor);
      } else {
        _animateTo(_minFactor);
      }
    }
  }

  void _switchTab(int index) {
    if (_selectedTab == index) return;
    HapticFeedback.selectionClick();
    setState(() => _selectedTab = index);
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }

  void _confirmImport(WatermarkType type) {
    final selected = _currentList.where((p) => _selectedIds.contains(p.id)).toList();
    if (selected.isEmpty) return;
    HapticFeedback.mediumImpact();
    if (widget.onImportWithWatermarkType != null) {
      widget.onImportWithWatermarkType!(selected, type);
    } else {
      if (selected.length == 1) {
        widget.onPhotoSelected?.call(selected.first);
      } else {
        widget.onMultiplePhotosSelected?.call(selected);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final screenHeight = MediaQuery.of(context).size.height;
    final maxSheetHeight = screenHeight * _maxFactor;

    return Align(
      alignment: Alignment.bottomCenter,
      child: AnimatedBuilder(
        animation: _sheetFactorNotifier,
        builder: (context, child) {
          final factor = _sheetFactorNotifier.value;
          final currentHeight = factor * screenHeight;
          final dy = maxSheetHeight - currentHeight;

          return Transform.translate(
            offset: Offset(0, dy),
            child: child,
          );
        },
        // child 保持固定尺寸，GPU 平移时不触发任何子树重构与 Layout
        child: SizedBox(
          height: maxSheetHeight,
          width: double.infinity,
          child: Container(
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF000000) : const Color(0xFF0E0E12),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.7),
                  blurRadius: 28,
                  offset: const Offset(0, -8),
                ),
              ],
            ),
            child: Stack(
              children: [
                // 1. 面板主体层：拖拽手柄 + Tab 栏 + 已选计数条 + 1:1 相册网格
                SafeArea(
                  top: false,
                  bottom: false,
                  child: Column(
                    children: [
                      // 顶部拖动手柄 (支持点击切换展开/折叠与竖直拖拽)
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: _toggleExpand,
                        onVerticalDragStart: _handleDragStart,
                        onVerticalDragUpdate: _handleDragUpdate,
                        onVerticalDragEnd: _handleDragEnd,
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.only(top: 12, bottom: 10),
                          child: Center(
                            child: Container(
                              width: 44,
                              height: 5,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.5),
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                          ),
                        ),
                      ),

                      // 标签栏（「照片」与「动态照片」双 Tab）
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onVerticalDragStart: _handleDragStart,
                        onVerticalDragUpdate: _handleDragUpdate,
                        onVerticalDragEnd: _handleDragEnd,
                        child: SelectorTabBar(
                          selectedTab: _selectedTab,
                          photoCount: _photos.length,
                          motionPhotoCount: _motionPhotos.length,
                          onTabChanged: _switchTab,
                        ),
                      ),

                      // 已选照片数量提示条 (在 Tab 下方，仅在已选不为空时显示)
                      AnimatedSize(
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOutCubic,
                        child: _selectedIds.isNotEmpty
                            ? Padding(
                                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                                child: Row(
                                  children: [
                                    Text(
                                      '已选择 ${_selectedIds.length} 张照片',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.white.withValues(alpha: 0.85),
                                        letterSpacing: -0.2,
                                      ),
                                    ),
                                    const Spacer(),
                                    OneUIPressable(
                                      onTap: () {
                                        HapticFeedback.selectionClick();
                                        setState(() => _selectedIds.clear());
                                      },
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                        child: Text(
                                          '取消选择',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w500,
                                            color: Colors.white.withValues(alpha: 0.5),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            : const SizedBox.shrink(),
                      ),

                      // 内容区：支持滑动分页（Pages 效果）的 1:1 正方形相册网格
                      Expanded(
                        child: ValueListenableBuilder<bool>(
                          valueListenable: _isExpandedNotifier,
                          builder: (context, isExpanded, _) {
                            return _buildContent(isExpanded);
                          },
                        ),
                      ),
                    ],
                  ),
                ),

                // 2. 底部叠加层：高通 GPU 优化的操作胶囊栏 (0 GMEM Resolve)
                SelectorBottomAction(
                  isVisible: _selectedIds.isNotEmpty,
                  onSelectType: _confirmImport,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(bool isExpanded) {
    return PageView(
      controller: _pageController,
      physics: const BouncingScrollPhysics(),
      onPageChanged: (index) {
        HapticFeedback.selectionClick();
        setState(() => _selectedTab = index);
      },
      children: [
        // Page 0: 全部照片
        SelectorGridPage(
          items: _photos,
          scrollController: _allGridScrollController,
          isExpanded: isExpanded,
          isLoading: _isLoading,
          hasPermission: _hasPermission,
          emptyTitle: '暂未发现相册照片',
          emptyIcon: Icons.photo_library_outlined,
          selectedIds: _selectedIds,
          onTogglePhoto: _togglePhotoSelection,
          onRequestPermission: _requestPermission,
          onRefresh: _loadPhotos,
          onCollapseRequest: () => _animateTo(_minFactor),
          onDragStart: _handleDragStart,
          onDragUpdate: _handleDragUpdate,
          onDragEnd: _handleDragEnd,
        ),

        // Page 1: 动态照片
        SelectorGridPage(
          items: _motionPhotos,
          scrollController: _motionGridScrollController,
          isExpanded: isExpanded,
          isLoading: _isLoading || !_motionScanDone,
          loadingTitle: '正在检测动态照片...',
          emptyTitle: '未在相册中发现动态照片 (Motion Photo)',
          emptyIcon: Icons.motion_photos_off_rounded,
          hasPermission: _hasPermission,
          selectedIds: _selectedIds,
          onTogglePhoto: _togglePhotoSelection,
          onRequestPermission: _requestPermission,
          onRefresh: _loadPhotos,
          onCollapseRequest: () => _animateTo(_minFactor),
          onDragStart: _handleDragStart,
          onDragUpdate: _handleDragUpdate,
          onDragEnd: _handleDragEnd,
        ),
      ],
    );
  }

  void _togglePhotoSelection(DevicePhotoModel photo) {
    HapticFeedback.selectionClick();
    setState(() {
      if (_selectedIds.contains(photo.id)) {
        _selectedIds.remove(photo.id);
      } else {
        _selectedIds.add(photo.id);
      }
    });
  }
}
