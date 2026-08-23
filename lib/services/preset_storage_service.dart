import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../models/saved_preset.dart';

class PresetStorageService {
  static const String _fileName = 'user_watermark_presets.json';

  static Future<File> _getPresetFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File(p.join(dir.path, _fileName));
  }

  /// 加载所有已保存的用户自定义预设
  static Future<List<SavedPreset>> loadPresets() async {
    try {
      final file = await _getPresetFile();
      if (!await file.exists()) {
        return [];
      }
      final content = await file.readAsString();
      final List<dynamic> list = jsonDecode(content);
      return list
          .map((item) => SavedPreset.fromJson(item as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// 保存单个预设
  static Future<void> savePreset(SavedPreset preset) async {
    final presets = await loadPresets();
    presets.removeWhere((p) => p.id == preset.id);
    presets.insert(0, preset);
    await _writePresets(presets);
  }

  /// 删除指定预设
  static Future<void> deletePreset(String presetId) async {
    final presets = await loadPresets();
    presets.removeWhere((p) => p.id == presetId);
    await _writePresets(presets);
  }

  static Future<void> _writePresets(List<SavedPreset> presets) async {
    final file = await _getPresetFile();
    final jsonList = presets.map((p) => p.toJson()).toList();
    await file.writeAsString(jsonEncode(jsonList));
  }
}
