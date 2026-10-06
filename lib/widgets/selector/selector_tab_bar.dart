import 'package:flutter/material.dart';
import '../one_ui_pressable.dart';

/// 照片选择器顶部分段胶囊滑动 Tab 栏（「照片」与「动态照片」双 Tab）
class SelectorTabBar extends StatelessWidget {
  final int selectedTab;
  final int photoCount;
  final int motionPhotoCount;
  final ValueChanged<int> onTabChanged;

  const SelectorTabBar({
    super.key,
    required this.selectedTab,
    required this.photoCount,
    required this.motionPhotoCount,
    required this.onTabChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Row(
        children: [
          // 分段胶囊滑动底座 (聚焦胶囊平滑平移滑动)
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: const Color(0xFF14141A),
              borderRadius: BorderRadius.circular(22),
            ),
            child: Stack(
              children: [
                // 平移滑动的聚焦胶囊 (Sliding Pill Indicator)
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOutCubic,
                  left: selectedTab == 0 ? 0 : 104,
                  top: 0,
                  bottom: 0,
                  width: selectedTab == 0 ? 104 : 122,
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF26262E),
                      borderRadius: BorderRadius.circular(19),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.35),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                  ),
                ),

                // Tab 内容按钮行
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Tab 1: 「照片」
                    OneUIPressable(
                      onTap: () => onTabChanged(0),
                      child: Container(
                        width: 104,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        alignment: Alignment.center,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.photo_library_rounded,
                              size: 15,
                              color: selectedTab == 0 ? const Color(0xFFFFD600) : const Color(0xFF8E8E93),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              '照片',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: selectedTab == 0 ? FontWeight.w800 : FontWeight.w600,
                                color: selectedTab == 0 ? Colors.white : const Color(0xFF8E8E93),
                                letterSpacing: -0.2,
                              ),
                            ),
                            if (photoCount > 0) ...[
                              const SizedBox(width: 4),
                              Text(
                                '$photoCount',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: selectedTab == 0 ? Colors.white70 : const Color(0xFF6E6E73),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),

                    // Tab 2: 「动态照片」
                    OneUIPressable(
                      onTap: () => onTabChanged(1),
                      child: Container(
                        width: 122,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        alignment: Alignment.center,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.motion_photos_on_rounded,
                              size: 15,
                              color: selectedTab == 1 ? const Color(0xFFFFD600) : const Color(0xFF8E8E93),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              '动态照片',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: selectedTab == 1 ? FontWeight.w800 : FontWeight.w600,
                                color: selectedTab == 1 ? Colors.white : const Color(0xFF8E8E93),
                                letterSpacing: -0.2,
                              ),
                            ),
                            if (motionPhotoCount > 0) ...[
                              const SizedBox(width: 4),
                              Text(
                                '$motionPhotoCount',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: selectedTab == 1 ? Colors.white70 : const Color(0xFF6E6E73),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
