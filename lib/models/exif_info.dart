class ExifInfo {
  final String make;
  final String model;
  final String lens;
  final String focalLength;
  final String fNumber;
  final String exposureTime;
  final String iso;
  final String dateTime;
  final bool hasExif;

  const ExifInfo({
    this.make = '',
    this.model = '',
    this.lens = '',
    this.focalLength = '',
    this.fNumber = '',
    this.exposureTime = '',
    this.iso = '',
    this.dateTime = '',
    this.hasExif = false,
  });

  ExifInfo copyWith({
    String? make,
    String? model,
    String? lens,
    String? focalLength,
    String? fNumber,
    String? exposureTime,
    String? iso,
    String? dateTime,
    bool? hasExif,
  }) {
    return ExifInfo(
      make: make ?? this.make,
      model: model ?? this.model,
      lens: lens ?? this.lens,
      focalLength: focalLength ?? this.focalLength,
      fNumber: fNumber ?? this.fNumber,
      exposureTime: exposureTime ?? this.exposureTime,
      iso: iso ?? this.iso,
      dateTime: dateTime ?? this.dateTime,
      hasExif: hasExif ?? this.hasExif,
    );
  }

  bool get isEmpty =>
      make.isEmpty &&
      model.isEmpty &&
      focalLength.isEmpty &&
      fNumber.isEmpty &&
      exposureTime.isEmpty &&
      iso.isEmpty &&
      dateTime.isEmpty;

  bool get isNotEmpty => !isEmpty;

  /// 组合完整的拍摄参数字符串（仅包含实际存在的非空字段）
  String get parametersString {
    final list = <String>[];
    if (focalLength.isNotEmpty) list.add(focalLength);
    if (fNumber.isNotEmpty) list.add(fNumber);
    if (exposureTime.isNotEmpty) list.add(exposureTime);
    if (iso.isNotEmpty) list.add(iso);
    return list.join('  ');
  }

  String get displayModelName {
    if (model.isNotEmpty && make.isNotEmpty) {
      if (model.toLowerCase().contains(make.toLowerCase())) {
        return model;
      }
      return '$make $model';
    }
    if (model.isNotEmpty) return model;
    if (make.isNotEmpty) return make;
    return '';
  }
}
