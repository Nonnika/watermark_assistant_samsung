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
    with WidgetsBindingObserver {
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
          home: ColoredBox(
            color: OneUITheme.landingBackground,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 350),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) {
                return FadeTransition(
                  opacity: animation,
                  child: ScaleTransition(
                    scale: Tween<double>(
                      begin: 1.02,
                      end: 1.0,
                    ).animate(animation),
                    child: child,
                  ),
                );
              },
              child: _showSplash
                  ? SplashScreen(
                      key: const ValueKey('splash_screen'),
                      onFinish: _onSplashFinish,
                    )
                  : const HomeScreen(key: ValueKey('home_screen')),
            ),
          ),
        );
      },
    );
  }
}
