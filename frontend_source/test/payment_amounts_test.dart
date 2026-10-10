import 'package:flutter_test/flutter_test.dart';
import 'package:chalbroo/utils/payment_amounts.dart';

// The same cases are checked for the Cloud Function in functions/payments.js,
// so the app and the server always agree on who pays and earns what.
void main() {
  group('PaymentAmounts.resolveDiscountPercent', () {
    test('no config / disabled / garbage means no discount', () {
      expect(PaymentAmounts.resolveDiscountPercent(null), 0);
      expect(PaymentAmounts.resolveDiscountPercent({}), 0);
      expect(PaymentAmounts.resolveDiscountPercent({'discountEnabled': false, 'discountPercent': 20}), 0);
      expect(PaymentAmounts.resolveDiscountPercent({'discountEnabled': 'true', 'discountPercent': 20}), 0);
      expect(PaymentAmounts.resolveDiscountPercent({'discountEnabled': true, 'discountPercent': 'abc'}), 0);
      expect(PaymentAmounts.resolveDiscountPercent({'discountEnabled': true, 'discountPercent': -5}), 0);
    });

    test('enabled discount is used, capped at the maximum', () {
      expect(PaymentAmounts.resolveDiscountPercent({'discountEnabled': true, 'discountPercent': 20}), 20);
      expect(PaymentAmounts.resolveDiscountPercent({'discountEnabled': true, 'discountPercent': '15'}), 15);
      expect(PaymentAmounts.resolveDiscountPercent({'discountEnabled': true, 'discountPercent': 99}),
          PaymentAmounts.maxDiscountPercent);
    });
  });

  group('PaymentAmounts.compute', () {
    test('no discount keeps the existing behaviour exactly', () {
      final a = PaymentAmounts.compute(200, 0);
      expect([a.discountAmount, a.payable, a.helperEarnings], [0, 200, 180.0]);
    });

    test('10% discount: poster pays 180, helper still earns 180', () {
      final a = PaymentAmounts.compute(200, 10);
      expect([a.discountAmount, a.payable, a.helperEarnings], [20, 180, 180.0]);
    });

    test('rounds half up like the server (25% of 150 -> 38 off)', () {
      final a = PaymentAmounts.compute(150, 25);
      expect([a.discountAmount, a.payable, a.helperEarnings], [38, 112, 135.0]);
    });

    test('poster never pays less than one rupee', () {
      expect(PaymentAmounts.compute(1, 90).payable, 1);
    });

    test('odd prices keep the fractional fee', () {
      expect(PaymentAmounts.compute(155, 0).helperEarnings, 139.5);
    });

    test('discount above the cap is clamped', () {
      expect(PaymentAmounts.compute(100, 150).discountPercent, PaymentAmounts.maxDiscountPercent);
    });
  });
}
