import 'package:butterfly/helpers/async.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('coalesces delayed tasks to the latest scheduled task', () async {
    final runner = CoalescedAsyncRunner(
      delay: const Duration(milliseconds: 16),
    );
    var result = 0;

    final first = runner.schedule(() async => result = 1);
    final second = runner.schedule(() async => result = 2);

    await Future.wait([first, second]);
    expect(result, 2);
    runner.dispose();
  });

  test('disposeAndWait cancels a pending delayed task', () async {
    final runner = CoalescedAsyncRunner(
      delay: const Duration(milliseconds: 16),
    );
    var calls = 0;

    final pending = runner.schedule(() async => calls++);
    await runner.disposeAndWait();
    await pending;
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(calls, 0);
  });
}
