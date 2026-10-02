import 'package:flutter/material.dart';

import '../../services/app_strings.dart';

/// 留白与照片参数的手势提示。
class FrameSnapseedStrip extends StatelessWidget {
  const FrameSnapseedStrip({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('slim_frame_snapseed_params'),
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF222225),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.swipe_rounded, size: 18, color: Colors.white60),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              AppStrings.gestureHint,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                height: 1.25,
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
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: accentYellow,
                ),
              ),
              Text(
                paramValue,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  color: accentYellow,
                ),
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
