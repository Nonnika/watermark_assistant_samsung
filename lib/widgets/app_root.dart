import 'package:flutter/material.dart';

import '../services/app_strings.dart';
import '../theme/one_ui_theme.dart';
import 'home_screen.dart';
import 'splash_screen.dart';

/// 应用根组件：语言环境监听 + MaterialApp/OneUI 主题 + 启动页到主界面的过渡
class WatermarkAssistantApp extends StatefulWidget {
  final bool showSplashOnInit;

  const WatermarkAssistantApp({super.key, this.showSplashOnInit = true});

  @override
  State<WatermarkAssistantApp> createState() => _WatermarkAssistantAppState();
}

class _WatermarkAssistantAppState extends State<WatermarkAssistantApp>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  /// 启动页仍在树上（含淡出过程）
  late bool _splashVisible;

  /// 主页已挂载：启动页动效静止后即在其下方预构建，切换时无需首帧集中构建
  late bool _homeMounted;

  /// 启动页开始退场，主页恢复动画与交互
  bool _revealing = false;

  late final AnimationController _exitController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 380),
  );
  late final CurvedAnimation _exitFade = CurvedAnimation(
    parent: _exitController,
    curve: Curves.easeInCubic,
  );
  late final CurvedAnimation _exitZoom = CurvedAnimation(
    parent: _exitController,
    curve: Curves.easeOutCubic,
  );
  late final Animation<double> _splashOpacity = ReverseAnimation(_exitFade);
  late final Animation<double> _splashScale = Tween<double>(
    begin: 1.0,
    end: 1.06,
  ).animate(_exitZoom);

  @override
  void initState() {
    super.initState();
    _splashVisible = widget.showSplashOnInit;
    _homeMounted = !widget.showSplashOnInit;
    _revealing = !widget.showSplashOnInit;
    WidgetsBinding.instance.addObserver(this);
    _detectSystemLocale();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _exitFade.dispose();
    _exitZoom.dispose();
    _exitController.dispose();
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

  void _onSplashMotionSettled() {
    if (_homeMounted) return;
    setState(() => _homeMounted = true);
  }

  void _onSplashFinish() {
    if (_revealing) return;
    final needsHomeBuild = !_homeMounted;
    setState(() {
      _homeMounted = true;
      _revealing = true;
    });
    void startExit() {
      if (!mounted) return;
      _exitController.forward().whenComplete(() {
        if (mounted) setState(() => _splashVisible = false);
      });
    }

    // 提前跳过时主页尚未构建：等构建帧结束后再开始淡出，避免首帧掉帧
    if (needsHomeBuild) {
      WidgetsBinding.instance.addPostFrameCallback((_) => startExit());
    } else {
      startExit();
    }
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
          home: ColoredBox(
            color: OneUITheme.landingBackground,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // 主页静止垫在下方：退场期间不缩放、不透明度不变，免去整页（含背景模糊）逐帧重新光栅化
                if (_homeMounted)
                  TickerMode(
                    enabled: _revealing,
                    child: IgnorePointer(
                      ignoring: !_revealing,
                      child: const HomeScreen(key: ValueKey('home_screen')),
                    ),
                  ),
                // 仅启动页这一轻量图层做淡出 + 轻微放大；退场开始即放行触摸给主页
                if (_splashVisible)
                  IgnorePointer(
                    ignoring: _revealing,
                    child: FadeTransition(
                      opacity: _splashOpacity,
                      child: ScaleTransition(
                        scale: _splashScale,
                        child: SplashScreen(
                          key: const ValueKey('splash_screen'),
                          onFinish: _onSplashFinish,
                          onMotionSettled: _onSplashMotionSettled,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
