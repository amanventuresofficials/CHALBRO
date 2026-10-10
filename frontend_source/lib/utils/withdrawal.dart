/// Rules for asking to take money out of the wallet. The same limits are enforced by
/// the Firestore rules (firestore.rules, "withdrawals"), so keep the two in step.
const int kMinWithdrawal = 100;
const int kMaxWithdrawal = 100000;

final RegExp _upiPattern = RegExp(r'^[A-Za-z0-9._-]{2,64}@[A-Za-z0-9]{2,32}$');

/// `name@bank`, e.g. `ravi.k@okhdfc` or `9876543210@ybl`.
bool isValidUpiId(String value) => _upiPattern.hasMatch(value.trim());

/// Why [amount] cannot be withdrawn with [balance] in the wallet, or null if it can.
String? withdrawalAmountProblem(int? amount, int balance) {
  if (amount == null || amount <= 0) return 'Enter the amount in rupees';
  if (amount < kMinWithdrawal) return 'The smallest withdrawal is ₹$kMinWithdrawal';
  if (amount > kMaxWithdrawal) return 'The largest withdrawal is ₹$kMaxWithdrawal';
  if (amount > balance) return 'You only have ₹$balance in your wallet';
  return null;
}
