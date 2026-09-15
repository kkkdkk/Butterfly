import 'package:butterfly/helpers/eink.dart';
import 'package:butterfly/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() => EinkDisplay.enabled = false);

  test('Magic Pie theme uses only achromatic semantic colors', () {
    EinkDisplay.enabled = true;

    final theme = getThemeData('Classic', true);
    final scheme = theme.colorScheme;
    final colors = <Color>[
      scheme.primary,
      scheme.onPrimary,
      scheme.primaryContainer,
      scheme.onPrimaryContainer,
      scheme.secondary,
      scheme.onSecondary,
      scheme.secondaryContainer,
      scheme.onSecondaryContainer,
      scheme.tertiary,
      scheme.onTertiary,
      scheme.tertiaryContainer,
      scheme.onTertiaryContainer,
      scheme.error,
      scheme.onError,
      scheme.errorContainer,
      scheme.onErrorContainer,
      scheme.surface,
      scheme.onSurface,
      scheme.surfaceDim,
      scheme.surfaceBright,
      scheme.surfaceContainerLowest,
      scheme.surfaceContainerLow,
      scheme.surfaceContainer,
      scheme.surfaceContainerHigh,
      scheme.surfaceContainerHighest,
      scheme.onSurfaceVariant,
      scheme.outline,
      scheme.outlineVariant,
    ];

    expect(theme.brightness, Brightness.light);
    expect(
      colors,
      everyElement(
        predicate<Color>((color) {
          return color.r == color.g && color.g == color.b;
        }),
      ),
    );
  });

  test('Magic Pie selected controls invert black and white', () {
    EinkDisplay.enabled = true;

    final theme = getThemeData('', false);
    final selected = <WidgetState>{WidgetState.selected};
    final unselected = <WidgetState>{};
    final disabled = <WidgetState>{WidgetState.disabled};
    final style = theme.segmentedButtonTheme.style!;

    expect(style.backgroundColor!.resolve(selected), Colors.black);
    expect(style.foregroundColor!.resolve(selected), Colors.white);
    expect(style.backgroundColor!.resolve(unselected), Colors.white);
    expect(style.foregroundColor!.resolve(unselected), Colors.black);
    expect(style.backgroundColor!.resolve(disabled), const Color(0xFFE0E0E0));
    expect(style.foregroundColor!.resolve(disabled), const Color(0xFF616161));
  });

  test('normal devices retain the configured color theme', () {
    EinkDisplay.enabled = false;

    final scheme = getThemeData('', false).colorScheme;

    expect(
      scheme.primary.r == scheme.primary.g &&
          scheme.primary.g == scheme.primary.b,
      isFalse,
    );
  });
}
