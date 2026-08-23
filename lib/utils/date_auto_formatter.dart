import 'package:flutter/services.dart';

/// 智能拍摄时间自动分割与格式化输入器
/// 用户只需连续输入纯数字（如 202408211430），程序将实时自动匹配并分割为 2024.08.21 14:30
class DateTimeAutoSegmentFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text;
    
    // 如果用户在删除内容且删到了分隔符，支持顺畅回退
    if (oldValue.text.length > text.length) {
      return newValue;
    }

    // 提取用户输入的全部纯数字
    final digits = text.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) {
      return newValue.copyWith(text: '', selection: const TextSelection.collapsed(offset: 0));
    }

    // 限制最多 14 位数字 (YYYYMMDDHHmmss)
    final clamped = digits.length > 14 ? digits.substring(0, 14) : digits;
    final buffer = StringBuffer();

    for (int i = 0; i < clamped.length; i++) {
      if (i == 4) buffer.write('.');       // 年份后加点: 2024.
      if (i == 6) buffer.write('.');       // 月份后加点: 2024.08.
      if (i == 8) buffer.write(' ');       // 日期后加空格: 2024.08.21 
      if (i == 10) buffer.write(':');      // 小时后加冒号: 2024.08.21 14:
      if (i == 12) buffer.write(':');      // 分钟后加冒号: 2024.08.21 14:30:
      buffer.write(clamped[i]);
    }

    final formatted = buffer.toString();
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }

  /// 智能从任意输入（如 2024-8-21 14:30、2024/08/21、2024:08:21 14:30:00）解析并标准化
  static String normalizeDateTime(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return '';

    // 提取全部纯数字
    final digits = trimmed.replaceAll(RegExp(r'\D'), '');
    if (digits.length >= 8) {
      final y = digits.substring(0, 4);
      final m = digits.substring(4, 6);
      final d = digits.substring(6, 8);
      
      if (digits.length >= 12) {
        final hh = digits.substring(8, 10);
        final mm = digits.substring(10, 12);
        if (digits.length >= 14) {
          final ss = digits.substring(12, 14);
          return '$y.$m.$d $hh:$mm:$ss';
        }
        return '$y.$m.$d $hh:$mm';
      }
      return '$y.$m.$d';
    }

    return trimmed;
  }

  /// 获取当前时间标准格式化字符串
  static String nowFormatted() {
    final now = DateTime.now();
    final y = now.year.toString().padLeft(4, '0');
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    final hh = now.hour.toString().padLeft(2, '0');
    final mm = now.minute.toString().padLeft(2, '0');
    return '$y.$m.$d $hh:$mm';
  }
}
