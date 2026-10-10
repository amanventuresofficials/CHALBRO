import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:chalbroo/services/error_logger.dart';

void main() {
  group('Stream.logErrors', () {
    test('passes data through', () async {
      final out = await Stream.fromIterable([1, 2, 3]).logErrors('t').toList();
      expect(out, [1, 2, 3]);
    });

    // Regression: Firestore code declares `Query query` (Query<Object?>) but the stream
    // really carries QuerySnapshot<Map<String, dynamic>>. A StreamTransformer<T, T> made
    // that crash on the Home screen on Android ("is not a subtype of 'streamTransformer'").
    test('works when the declared element type is wider than the real one', () async {
      final Stream<Iterable<Object?>> wide = Stream<List<int>>.fromIterable([
        [1],
        [2, 3],
      ]);
      final out = await wide.logErrors('t').toList();
      expect(out, [
        [1],
        [2, 3],
      ]);
    });

    test('errors still reach the listener, then the stream goes on', () async {
      final c = StreamController<int>();
      final seen = <Object>[];
      final data = <int>[];
      final done = Completer<void>();
      c.stream.logErrors('t').listen(data.add, onError: seen.add, onDone: done.complete);
      c
        ..add(1)
        ..addError(StateError('boom'))
        ..add(2);
      await c.close();
      await done.future;
      expect(data, [1, 2]);
      expect(seen.single, isA<StateError>());
    });

    test('a broadcast stream stays broadcast', () {
      final c = StreamController<int>.broadcast();
      expect(c.stream.logErrors('t').isBroadcast, true);
      c.close();
    });
  });
}
