import 'package:flutter_test/flutter_test.dart';
import 'package:chalbroo/utils/withdrawal.dart';

void main() {
  group('isValidUpiId', () {
    test('accepts normal UPI ids', () {
      for (final ok in ['ravi.k@okhdfc', '9876543210@ybl', 'a_b-c@paytm', ' ravi@upi ']) {
        expect(isValidUpiId(ok), true, reason: ok);
      }
    });
    test('rejects things that are not UPI ids', () {
      for (final bad in ['', 'ravi', 'ravi@', '@ybl', 'ra vi@ybl', 'ravi@@ybl', 'r@ybl', 'ravi@y', 'a@b@c', 'rá@ybl']) {
        expect(isValidUpiId(bad), false, reason: bad);
      }
    });
  });

  group('withdrawalAmountProblem', () {
    test('a valid amount has no problem', () {
      expect(withdrawalAmountProblem(100, 100), isNull);
      expect(withdrawalAmountProblem(250, 1000), isNull);
    });
    test('explains each way it can be wrong', () {
      expect(withdrawalAmountProblem(null, 500), isNotNull);
      expect(withdrawalAmountProblem(0, 500), isNotNull);
      expect(withdrawalAmountProblem(99, 500), contains('smallest'));
      expect(withdrawalAmountProblem(600, 500), contains('only have'));
      expect(withdrawalAmountProblem(100001, 999999), contains('largest'));
    });
  });
}
