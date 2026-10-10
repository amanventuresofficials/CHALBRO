import 'package:flutter_test/flutter_test.dart';
import 'package:chalbroo/services/error_logger.dart';

void main() {
  group('ErrorLogger.fingerprint', () {
    test('the same problem with different ids/numbers groups together', () {
      final a = ErrorLogger.fingerprint('database', 'cloud_firestore/permission-denied',
          'Missing or insufficient permissions for tasks/AbCdEfGhIjKlMnOpQrSt', null);
      final b = ErrorLogger.fingerprint('database', 'cloud_firestore/permission-denied',
          'Missing or insufficient permissions for tasks/ZyXwVuTsRqPoNmLkJiHg', null);
      expect(a, b);
    });

    test('different category, type or message gives a different fingerprint', () {
      final base = ErrorLogger.fingerprint('database', 'x', 'boom', null);
      expect(ErrorLogger.fingerprint('payment', 'x', 'boom', null), isNot(base));
      expect(ErrorLogger.fingerprint('database', 'y', 'boom', null), isNot(base));
      expect(ErrorLogger.fingerprint('database', 'x', 'bang', null), isNot(base));
    });

    test('the same message in two different places is two different problems', () {
      final home = ErrorLogger.fingerprint('database', 'cloud_firestore/permission-denied', 'denied', null, context: 'Live: tasks by city');
      final wallet = ErrorLogger.fingerprint('database', 'cloud_firestore/permission-denied', 'denied', null, context: 'Live: my wallet history');
      expect(home, isNot(wallet));
      expect(home, ErrorLogger.fingerprint('database', 'cloud_firestore/permission-denied', 'denied', null, context: 'LIVE: tasks by city'));
    });

    test('line and column numbers in the stack do not change the fingerprint', () {
      final s1 = StackTrace.fromString('#0      _HomeState.build (package:chalbroo/screens/home_screen.dart:120:7)\n#1 other');
      final s2 = StackTrace.fromString('#0      _HomeState.build (package:chalbroo/screens/home_screen.dart:131:9)\n#1 other');
      expect(ErrorLogger.fingerprint('app', 'StateError', 'bad', s1),
          ErrorLogger.fingerprint('app', 'StateError', 'bad', s2));
    });

    test('is short and stable (8 hex chars)', () {
      final fp = ErrorLogger.fingerprint('app', 'T', 'm', null);
      expect(fp, matches(RegExp(r'^[0-9a-f]{8}$')));
      expect(ErrorLogger.fingerprint('app', 'T', 'm', null), fp);
    });
  });
}
