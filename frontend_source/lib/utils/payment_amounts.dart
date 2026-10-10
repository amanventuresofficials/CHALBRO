/// What a poster pays and what the helper earns for one task.
///
/// Mirrors functions/payments.js so the app and the Cloud Functions agree.
/// The discount is funded by ChalBro: the poster pays less, while the helper's
/// earnings are still based on the full agreed price.
class PaymentAmounts {
  /// ChalBro keeps this share of the agreed price; the helper gets the rest.
  static const double platformFeeFraction = 0.10;

  /// Highest discount an admin can configure.
  static const int maxDiscountPercent = 90;

  final int agreedAmount;
  final int discountPercent;
  final int discountAmount;
  final int payable;
  final double helperEarnings;

  const PaymentAmounts._({
    required this.agreedAmount,
    required this.discountPercent,
    required this.discountAmount,
    required this.payable,
    required this.helperEarnings,
  });

  factory PaymentAmounts.compute(int agreedAmount, int discountPercent) {
    final pct = discountPercent.clamp(0, maxDiscountPercent);
    final discount = (agreedAmount * pct / 100).round();
    final payable = (agreedAmount - discount) < 1 ? 1 : agreedAmount - discount;
    final commission = agreedAmount * platformFeeFraction;
    return PaymentAmounts._(
      agreedAmount: agreedAmount,
      discountPercent: pct,
      discountAmount: discount,
      payable: payable,
      helperEarnings: agreedAmount - commission,
    );
  }

  /// Turns the stored admin settings into a safe whole percent (0 = no discount).
  static int resolveDiscountPercent(Map<String, dynamic>? config) {
    if (config == null || config['discountEnabled'] != true) return 0;
    final raw = config['discountPercent'];
    final pct = raw is num ? raw.round() : int.tryParse('$raw') ?? 0;
    return pct.clamp(0, maxDiscountPercent);
  }
}
