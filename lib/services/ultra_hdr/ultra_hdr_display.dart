import 'dart:io';
import 'package:flutter/services.dart';

/// 屏幕级 HDR 显示状态查询与窗口色彩模式切换
class UltraHdrDisplay {
  static const MethodChannel _nativeChannel = MethodChannel('com.example.watermark_samsung/ultra_hdr');

  /// 检查当前设备屏幕是否支持硬件级 HDR / Ultra HDR 显示
  static Future<bool> isHdrDisplaySupported() async {
    if (!Platform.isAndroid) return false;
    try {
      final supported = await _nativeChannel.invokeMethod<bool>('isHdrDisplaySupported');
      return supported ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 获取当前屏幕的 HDR/SDR 动态亮度提升比例 (1.0 代表标准无提升，>1.0 代表开启 HDR 峰值高光)
  static Future<double> getHdrSdrRatio() async {
    if (!Platform.isAndroid) return 1.0;
    try {
      final ratio = await _nativeChannel.invokeMethod<double>('getHdrSdrRatio');
      return ratio ?? 1.0;
    } catch (_) {
      return 1.0;
    }
  }

  /// 动态启用/关闭窗口级 Ultra HDR 显示色彩模式 (COLOR_MODE_HDR)
  static Future<bool> setHdrDisplayMode(bool enable) async {
    if (!Platform.isAndroid) return false;
    try {
      final ok = await _nativeChannel.invokeMethod<bool>('setHdrDisplayMode', {'enable': enable});
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }
}
