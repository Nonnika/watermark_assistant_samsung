import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/frame_watermark_config.dart';
import '../../services/app_strings.dart';
import '../../utils/blurred_dialog_helper.dart';
import '../../utils/date_auto_formatter.dart';

/// 选项卡 3: EXIF 拍摄参数条 (修改参数、显示/隐藏开关)
class FrameExifStrip extends StatelessWidget {
  final FrameWatermarkConfig config;
  final ValueChanged<FrameWatermarkConfig> onChanged;

  const FrameExifStrip({
    super.key,
    required this.config,
    required this.onChanged,
  });

  void _showEditExifDialog(BuildContext context) {
    final modelController = TextEditingController(text: config.exifInfo.model);
    final makeController = TextEditingController(text: config.exifInfo.make);
    final focalController = TextEditingController(text: config.exifInfo.focalLength);
    final fNumberController = TextEditingController(text: config.exifInfo.fNumber);
    final expController = TextEditingController(text: config.exifInfo.exposureTime);
    final isoController = TextEditingController(text: config.exifInfo.iso);
    final dateController = TextEditingController(text: config.exifInfo.dateTime);

    BlurredDialogHelper.showBlurredDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1C1C1E),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              title: Text(
                AppStrings.editExifTitle,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildTextField(modelController, AppStrings.cameraModel, Icons.phone_android_rounded, hint: '如: Galaxy S24 Ultra'),
                    const SizedBox(height: 8),
                    _buildTextField(makeController, AppStrings.brandMake, Icons.branding_watermark_rounded, hint: '如: Samsung, Sony, Leica'),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(child: _buildTextField(focalController, AppStrings.focalLength, Icons.camera_rounded, hint: '如: 24mm')),
                        const SizedBox(width: 6),
                        Expanded(child: _buildTextField(fNumberController, AppStrings.aperture, Icons.brightness_medium_rounded, hint: '如: f/1.7')),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(child: _buildTextField(expController, AppStrings.shutterSpeed, Icons.shutter_speed_rounded, hint: '如: 1/2000s')),
                        const SizedBox(width: 6),
                        Expanded(child: _buildTextField(isoController, AppStrings.iso, Icons.iso_rounded, hint: '如: ISO 50')),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // 拍摄日期时间：智能自动分割匹配输入
                    _buildTextField(
                      dateController,
                      AppStrings.dateTime,
                      Icons.calendar_today_rounded,
                      hint: AppStrings.dateTimeHint,
                      keyboardType: TextInputType.datetime,
                      inputFormatters: [DateTimeAutoSegmentFormatter()],
                      suffixIcon: dateController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear_rounded, size: 16, color: Colors.white38),
                              onPressed: () {
                                dateController.clear();
                                setDialogState(() {});
                              },
                            )
                          : null,
                      onChanged: (_) => setDialogState(() {}),
                    ),
                    const SizedBox(height: 6),

                    // 智能输入提示与快捷填入胶囊
                    Row(
                      children: [
                        InkWell(
                          onTap: () {
                            dateController.text = DateTimeAutoSegmentFormatter.nowFormatted();
                            setDialogState(() {});
                          },
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFD600).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              AppStrings.fillNowTime,
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFFFFD600)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            AppStrings.autoSegmentHint,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 10, color: Colors.white38),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(AppStrings.cancel, style: const TextStyle(color: Colors.white60)),
                ),
                FilledButton(
                  onPressed: () {
                    final normalizedDate = DateTimeAutoSegmentFormatter.normalizeDateTime(dateController.text.trim());
                    final updatedExif = config.exifInfo.copyWith(
                      model: modelController.text.trim(),
                      make: makeController.text.trim(),
                      focalLength: focalController.text.trim(),
                      fNumber: fNumberController.text.trim(),
                      exposureTime: expController.text.trim(),
                      iso: isoController.text.trim(),
                      dateTime: normalizedDate,
                      hasExif: true,
                    );
                    onChanged(config.copyWith(exifInfo: updatedExif));
                    Navigator.pop(context);
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFFFD600),
                    foregroundColor: Colors.black,
                  ),
                  child: Text(AppStrings.saveChanges, style: const TextStyle(fontWeight: FontWeight.w900)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildTextField(
    TextEditingController controller,
    String label,
    IconData icon, {
    String? hint,
    Widget? suffixIcon,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    ValueChanged<String>? onChanged,
  }) {
    return TextField(
      controller: controller,
      style: const TextStyle(fontSize: 13, color: Colors.white),
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white24, fontSize: 11),
        labelStyle: const TextStyle(color: Colors.white60, fontSize: 12),
        prefixIcon: Icon(icon, size: 16, color: Colors.white60),
        suffixIcon: suffixIcon,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        filled: true,
        fillColor: const Color(0xFF2C2C2E),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasExif = config.exifInfo.isNotEmpty;
    final modelName = config.exifInfo.displayModelName;
    final params = config.exifInfo.parametersString;

    String desc = '未检测到拍摄 EXIF 参数';
    if (hasExif) {
      final parts = <String>[];
      if (modelName.isNotEmpty) parts.add(modelName);
      if (params.isNotEmpty) parts.add(params);
      if (parts.isEmpty && config.exifInfo.dateTime.isNotEmpty) {
        parts.add(config.exifInfo.dateTime);
      }
      desc = parts.join(' · ');
    }

    return Row(
      key: const ValueKey('slim_frame_exif'),
      children: [
        Icon(
          hasExif ? Icons.camera_alt_rounded : Icons.info_outline_rounded,
          size: 17,
          color: hasExif ? const Color(0xFFFFD600) : Colors.white38,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            desc,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: hasExif ? FontWeight.w700 : FontWeight.w500,
              color: hasExif ? Colors.white : Colors.white60,
            ),
          ),
        ),
        const SizedBox(width: 8),
        InkWell(
          onTap: () => _showEditExifDialog(context),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E22),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.edit_note_rounded, size: 14, color: Colors.white70),
                const SizedBox(width: 3),
                Text(
                  hasExif ? '修改' : '添加',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white70),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 6),
        InkWell(
          onTap: () => onChanged(config.copyWith(showParameters: !config.showParameters)),
          borderRadius: BorderRadius.circular(12),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: config.showParameters ? const Color(0xFFE2E2E8) : const Color(0xFF1E1E22),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  config.showParameters ? Icons.visibility_rounded : Icons.visibility_off_rounded,
                  size: 14,
                  color: config.showParameters ? const Color(0xFF111113) : Colors.white60,
                ),
                const SizedBox(width: 3),
                Text(
                  config.showParameters ? '显示' : '隐藏',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    color: config.showParameters ? const Color(0xFF111113) : Colors.white60,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
