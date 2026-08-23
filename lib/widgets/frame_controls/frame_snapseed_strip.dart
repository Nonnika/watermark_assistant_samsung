import 'package:flutter/material.dart';
import '../../services/app_strings.dart';

/// 选项卡 2: 留白与照片参数 (深灰胶囊手势提示与嵌入式进度条)
class FrameSnapseedStrip extends StatelessWidget {
  const FrameSnapseedStrip({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('slim_frame_snapseed_params'),
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E22),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.touch_app_rounded, size: 18, color: Color(0xFFFFD600)),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              AppStrings.gestureHint,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.white70,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 用户操作时嵌入在面板内的 Snapseed 进度条 (黄色高亮焦点)
class FrameSnapseedProgressBar extends StatelessWidget {
  final String paramName;
  final String paramValue;
  final double progress;

  const FrameSnapseedProgressBar({
    super.key,
    required this.paramName,
    required this.paramValue,
    required this.progress,
  });

  @override
  Widget build(BuildContext context) {
    const accentYellow = Color(0xFFFFD600);

    return Padding(
      key: const ValueKey('embedded_snapseed_bar'),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                paramName,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: accentYellow),
              ),
              Text(
                paramValue,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: accentYellow),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: progress.clamp(0.0, 1.0),
              backgroundColor: const Color(0xFF2C2C2E),
              valueColor: const AlwaysStoppedAnimation<Color>(accentYellow),
              minHeight: 4.5,
            ),
          ),
        ],
      ),
    );
  }
}
