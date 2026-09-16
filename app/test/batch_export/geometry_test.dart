import 'dart:ui';

import 'package:butterfly/batch_export/geometry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('content bounds preserve negative origins and add margin', () {
    expect(
      exportContentBounds([
        const Rect.fromLTWH(-40, -20, 50, 60),
        const Rect.fromLTWH(20, 30, 10, 10),
      ], margin: 8),
      const Rect.fromLTRB(-48, -28, 38, 48),
    );
  });

  test('empty infinite paper has a finite blank-page fallback', () {
    expect(exportContentBounds([]), const Rect.fromLTWH(0, 0, 1024, 768));
  });

  test('requested density is honored when within limits', () {
    final result = ExportGeometry.fit(const Rect.fromLTWH(10, 20, 100, 50));
    expect(result.width, 200);
    expect(result.height, 100);
    expect(result.actualScale, 2);
    expect(result.limited, isFalse);
  });

  test('large page is proportionally downscaled to a finite maximum', () {
    final result = ExportGeometry.fit(
      const Rect.fromLTWH(-50, 20, 10000, 5000),
      maxDimension: 2048,
    );
    expect(result.width, 2048);
    expect(result.height, 1024);
    expect(result.actualScale, 0.2048);
    expect(result.limited, isTrue);
  });

  test('ceil-rounded dimensions do not exceed the pixel budget', () {
    for (final maxPixels in [1, 3, 7, 101, 10000]) {
      final result = ExportGeometry.fit(
        const Rect.fromLTWH(0, 0, 100.1, 300.9),
        maxPixels: maxPixels,
      );
      expect(result.width * result.height, lessThanOrEqualTo(maxPixels));
      expect(result.width, greaterThan(0));
      expect(result.height, greaterThan(0));
    }
  });

  test('invalid or unbounded geometry fails before allocating an image', () {
    expect(
      () =>
          exportContentBounds([const Rect.fromLTWH(0, 0, double.infinity, 1)]),
      throwsFormatException,
    );
    expect(() => ExportGeometry.fit(Rect.zero), throwsArgumentError);
    expect(
      () => ExportGeometry.fit(const Rect.fromLTWH(0, 0, 1, 1), scale: 0),
      throwsArgumentError,
    );
    expect(
      () =>
          ExportGeometry.fit(const Rect.fromLTWH(0, 0, 1, 1), maxDimension: 0),
      throwsArgumentError,
    );
  });
}
