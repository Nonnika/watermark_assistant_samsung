import 'dart:ui' as ui;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'package:watermark_samsung/main.dart' as app;

/// `flutter run --profile -t tool/profile_adreno.dart -d <device>`
/// Reports Flutter frame timings; hardware GPU counters require AGI/Perfetto.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  const sampleSize = 120;
  var warmupRemaining = 60;
  var window = 0;
  final samples = <ui.FrameTiming>[];

  SchedulerBinding.instance.addTimingsCallback((timings) {
    for (final timing in timings) {
      if (warmupRemaining > 0) {
        warmupRemaining--;
        continue;
      }
      samples.add(timing);
      if (samples.length < sampleSize) continue;

      final views = ui.PlatformDispatcher.instance.views;
      final refreshRate = views.isEmpty
          ? 60.0
          : views.first.display.refreshRate;
      final budgetMs = 1000 / (refreshRate > 0 ? refreshRate : 60);
      final buildMs =
          samples.map((f) => f.buildDuration.inMicroseconds / 1000).toList()
            ..sort();
      final rasterMs =
          samples.map((f) => f.rasterDuration.inMicroseconds / 1000).toList()
            ..sort();
      final overBudget = samples
          .where(
            (f) =>
                f.buildDuration.inMicroseconds / 1000 > budgetMs ||
                f.rasterDuration.inMicroseconds / 1000 > budgetMs,
          )
          .length;

      debugPrint(
        '[Adreno profile ${++window}] frames=$sampleSize '
        'budget=${budgetMs.toStringAsFixed(2)}ms '
        'build p50/p90/p99=${_percentiles(buildMs)}ms '
        'raster p50/p90/p99=${_percentiles(rasterMs)}ms '
        'overBudget=$overBudget/$sampleSize',
      );
      samples.clear();
    }
  });

  app.main();
}

String _percentiles(List<double> values) {
  return [0.50, 0.90, 0.99]
      .map((p) => values[(values.length * p).ceil() - 1].toStringAsFixed(2))
      .join('/');
}
