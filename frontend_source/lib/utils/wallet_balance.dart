/// A person has TWO balances on their user document:
///   walletBalance  practice (test) credit, used while Razorpay is OFF. Cannot be withdrawn.
///   realBalance    real money earned through Razorpay payments. Can be withdrawn.
/// The app shows only the one that matches the owner's Razorpay switch.
int balanceToShow(Map<String, dynamic>? userData, {required bool razorpayOn}) {
  final value = userData?[razorpayOn ? 'realBalance' : 'walletBalance'];
  return value is num ? value.toInt() : 0;
}

/// Wallet-history entries written by a Razorpay payment carry `real: true`;
/// everything else (the practice wallet) does not.
bool isRealTransaction(Map<String, dynamic> tx) => tx['real'] == true;

/// Should [tx] appear in the wallet history for the current mode?
bool transactionVisible(Map<String, dynamic> tx, {required bool razorpayOn}) => isRealTransaction(tx) == razorpayOn;
