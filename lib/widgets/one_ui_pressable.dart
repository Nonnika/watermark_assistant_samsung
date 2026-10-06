import 'package:flutter/material.dart';

/// 全部按钮共用的按压反馈：整块小圆角矩形缓慢亮起，快速点按也完整播放。
/// 仅动画绘制层，点击、长按、键盘和无障碍操作仍由 InkWell 处理。
class OneUIPressable extends StatefulWidget {
  const OneUIPressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.borderRadius,
    this.highlightColor,
    this.splashColor,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final BorderRadius? borderRadius;
  final Color? highlightColor;
  final Color? splashColor;

  @override
  State<OneUIPressable> createState() => _OneUIPressableState();
}

class _OneUIPressableState extends State<OneUIPressable> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null || widget.onLongPress != null;
    return Semantics(
      button: true,
      enabled: enabled,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: widget.onTap,
          onLongPress: widget.onLongPress,
          onHighlightChanged: (pressed) => setState(() => _pressed = pressed),
          splashFactory: NoSplash.splashFactory,
          highlightColor: Colors.transparent,
          borderRadius: OneUIPressFeedback.borderRadius,
          child: OneUIPressFeedback(
            pressed: enabled && _pressed,
            color: widget.highlightColor ?? widget.splashColor ?? Colors.white12,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

/// Material 按钮和自定义按钮使用同一动画，视觉反馈不延迟回调。
class OneUIPressFeedback extends StatefulWidget {
  const OneUIPressFeedback({
    super.key,
    required this.pressed,
    required this.color,
    required this.child,
  });

  static const borderRadius = BorderRadius.all(Radius.circular(10));
  static const pressDuration = Duration(milliseconds: 220);
  static const releaseDuration = Duration(milliseconds: 360);

  final bool pressed;
  final Color color;
  final Widget child;

  static ButtonStyle buttonStyle({Color? color}) => ButtonStyle(
    shape: const WidgetStatePropertyAll(
      RoundedRectangleBorder(borderRadius: borderRadius),
    ),
    animationDuration: releaseDuration,
    splashFactory: NoSplash.splashFactory,
    overlayColor: const WidgetStatePropertyAll(Colors.transparent),
    backgroundBuilder: (context, states, child) => OneUIPressFeedback(
      pressed: states.contains(WidgetState.pressed),
      color: color ?? Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.12),
      child: child ?? const SizedBox.shrink(),
    ),
  );

  @override
  State<OneUIPressFeedback> createState() => _OneUIPressFeedbackState();
}

class _OneUIPressFeedbackState extends State<OneUIPressFeedback>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: OneUIPressFeedback.pressDuration,
    reverseDuration: OneUIPressFeedback.releaseDuration,
  )..addStatusListener(_handleStatus);
  late final Animation<double> _opacity = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeInOutCubic,
  );
  bool _disableAnimations = false;

  void _handleStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && !widget.pressed) {
      _controller.reverse();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _disableAnimations = MediaQuery.disableAnimationsOf(context);
    _updateAnimation();
  }

  @override
  void didUpdateWidget(OneUIPressFeedback oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pressed != widget.pressed) _updateAnimation();
  }

  void _updateAnimation() {
    if (_disableAnimations) {
      _controller.value = widget.pressed ? 1 : 0;
    } else if (widget.pressed) {
      _controller.forward();
    } else if (_controller.status == AnimationStatus.completed) {
      _controller.reverse();
    }
    // 快速松手时先完成亮起，再渐隐；避免在一帧内按下/松开而看不到反馈。
  }

  @override
  void dispose() {
    (_opacity as CurvedAnimation).dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CustomPaint(
    foregroundPainter: _PressPainter(_opacity, widget.color),
    child: widget.child,
  );
}

class _PressPainter extends CustomPainter {
  _PressPainter(this.opacity, this.color) : super(repaint: opacity);

  final Animation<double> opacity;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (opacity.value == 0) return;
    canvas.drawRRect(
      OneUIPressFeedback.borderRadius.toRRect(Offset.zero & size),
      Paint()..color = color.withValues(alpha: color.a * opacity.value),
    );
  }

  @override
  bool shouldRepaint(_PressPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.opacity != opacity;
}
