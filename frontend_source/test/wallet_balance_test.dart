import 'package:flutter_test/flutter_test.dart';
import 'package:chalbroo/utils/wallet_balance.dart';

void main() {
  final user = {'walletBalance': 500, 'realBalance': 270.5};

  test('Razorpay off shows the practice wallet, on shows the real balance', () {
    expect(balanceToShow(user, razorpayOn: false), 500);
    expect(balanceToShow(user, razorpayOn: true), 270);
  });

  test('a missing or odd value is 0, never a crash', () {
    expect(balanceToShow(null, razorpayOn: true), 0);
    expect(balanceToShow({'walletBalance': 500}, razorpayOn: true), 0); // no real balance yet
    expect(balanceToShow({'realBalance': 'x'}, razorpayOn: true), 0);
  });

  test('the history shows only the entries of the current mode', () {
    final practice = {'title': 'Paid for task', 'type': 'debit'};
    final real = {'title': 'Earned from task (Razorpay payment)', 'type': 'credit', 'real': true};
    expect(transactionVisible(practice, razorpayOn: false), true);
    expect(transactionVisible(real, razorpayOn: false), false);
    expect(transactionVisible(real, razorpayOn: true), true);
    expect(transactionVisible(practice, razorpayOn: true), false);
  });
}
