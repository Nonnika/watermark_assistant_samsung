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

    // 按分隔符切出数字组，再逐组补零对齐，避免 "2024-8-21" 被拉平成 "2024821" 后错位解析
    final groups = trimmed
        .split(RegExp(r'\D+'))
        .where((g) => g.isNotEmpty)
        .toList();

    int y = 0, m = 0, d = 0, hh = 0, mm = 0, ss = 0;
    if (groups.length >= 3) {
      y = int.tryParse(groups[0]) ?? 0;
      m = int.tryParse(groups[1].padLeft(2, '0')) ?? 0;
      d = int.tryParse(groups[2].padLeft(2, '0')) ?? 0;
    } else if (groups.length == 1 && groups[0].length >= 8) {
      // 纯数字连写：202408211430
      final digits = groups[0];
      y = int.tryParse(digits.substring(0, 4)) ?? 0;
      m = int.tryParse(digits.substring(4, 6)) ?? 0;
      d = int.tryParse(digits.substring(6, 8)) ?? 0;
      if (digits.length >= 12) hh = int.tryParse(digits.substring(8, 10)) ?? 0;
      if (digits.length >= 12) mm = int.tryParse(digits.substring(10, 12)) ?? 0;
      if (digits.length >= 14) ss = int.tryParse(digits.substring(12, 14)) ?? 0;
    } else {
      return trimmed;
    }

    if (groups.length >= 4) hh = int.tryParse(groups[3].padLeft(2, '0')) ?? 0;
    if (groups.length >= 5) mm = int.tryParse(groups[4].padLeft(2, '0')) ?? 0;
    if (groups.length >= 6) ss = int.tryParse(groups[5].padLeft(2, '0')) ?? 0;

    final dateValid = y >= 1 && m >= 1 && m <= 12 && d >= 1 && d <= 31;
    if (!dateValid) return trimmed;

    final y4 = y.toString().padLeft(4, '0');
    final m2 = m.toString().padLeft(2, '0');
    final d2 = d.toString().padLeft(2, '0');
    if (hh > 0 || mm > 0 || ss > 0 || groups.length >= 4) {
      final hh2 = hh.toString().padLeft(2, '0');
      final mm2 = mm.toString().padLeft(2, '0');
      final ss2 = ss.toString().padLeft(2, '0');
      if (ss > 0 || groups.length >= 6) {
        return '$y4.$m2.$d2 $hh2:$mm2:$ss2';
      }
      return '$y4.$m2.$d2 $hh2:$mm2';
    }
    return '$y4.$m2.$d2';
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
