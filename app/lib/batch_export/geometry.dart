import 'dart:math' as math;
import 'dart:ui';

bool isFiniteExportRect(Rect rect) =>
    rect.left.isFinite &&
    rect.top.isFinite &&
    rect.right.isFinite &&
    rect.bottom.isFinite &&
    rect.width.isFinite &&
    rect.height.isFinite;

Map<String, double> exportRectJson(Rect rect) => {
  'x': rect.left,
  'y': rect.top,
  'width': rect.width,
  'height': rect.height,
};

/// Infinite paper has no natural extent. Empty pages use a finite blank sheet.
Rect exportContentBounds(Iterable<Rect?> rects, {double margin = 24}) {
  if (!margin.isFinite || margin < 0) {
    throw ArgumentError('margin must be finite and nonnegative');
  }
  Rect? bounds;
  for (final rect in rects) {
    if (rect == null) continue;
    if (!isFiniteExportRect(rect)) {
      throw const FormatException('Page contains non-finite element bounds');
    }
    if (rect.isEmpty) continue;
    bounds = bounds?.expandToInclude(rect) ?? rect;
  }
  return bounds?.inflate(margin) ?? const Rect.fromLTWH(0, 0, 1024, 768);
}

class ExportGeometry {
  final Rect bounds;
  final double requestedScale, actualScale;
  final int width, height;

  ExportGeometry._(
    this.bounds,
    this.requestedScale,
    this.actualScale,
    this.width,
    this.height,
  );

  factory ExportGeometry.fit(
    Rect bounds, {
    double scale = 2,
    int maxDimension = 4096,
    int maxPixels = 16777216,
  }) {
    if (!isFiniteExportRect(bounds) || bounds.isEmpty) {
      throw ArgumentError('Export bounds must be finite and nonempty');
    }
    if (!scale.isFinite || scale <= 0) {
      throw ArgumentError('scale must be finite and positive');
    }
    if (maxDimension < 1 || maxDimension > 16384) {
      throw ArgumentError('maxDimension must be between 1 and 16384');
    }
    if (maxPixels < 1 || maxPixels > 67108864) {
      throw ArgumentError('maxPixels must be between 1 and 67108864');
    }
    var actualScale = math.min(
      scale,
      math.min(maxDimension / bounds.width, maxDimension / bounds.height),
    );
    bool fits(double value) {
      final width = (bounds.width * value).ceil();
      final height = (bounds.height * value).ceil();
      return width <= maxDimension &&
          height <= maxDimension &&
          width * height <= maxPixels;
    }

    // Ceil-rounded dimensions, not floating area, define the memory budget.
    if (!fits(actualScale)) {
      var low = 0.0;
      var high = actualScale;
      for (var i = 0; i < 64; i++) {
        final middle = (low + high) / 2;
        if (fits(middle)) {
          low = middle;
        } else {
          high = middle;
        }
      }
      actualScale = low;
    }
    final width = (bounds.width * actualScale).ceil();
    final height = (bounds.height * actualScale).ceil();
    if (actualScale <= 0 || width < 1 || height < 1) {
      throw ArgumentError('Bounds cannot fit the requested pixel budget');
    }
    return ExportGeometry._(bounds, scale, actualScale, width, height);
  }

  bool get limited => actualScale < requestedScale;

  Map<String, Object> toJson() => {
    'bounds': exportRectJson(bounds),
    'width': width,
    'height': height,
    'requestedScale': requestedScale,
    'actualScale': actualScale,
    'limited': limited,
  };
}
