import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../services/database_service.dart';
import '../services/razorpay_service.dart';
import '../utils/app_colors.dart';
import '../utils/payment_amounts.dart';
import 'razorpay_simulation_sheet.dart';

/// Shows the task-payment sheet and drives it to completion.
///
/// Which payment path runs is controlled by the admin-only
/// metadata/paymentConfig Firestore document (see DatabaseService.getPaymentConfig):
/// - paymentsEnabled = false: payment is blocked entirely.
/// - useRazorpay = false (default): pays from the dummy in-app wallet.
/// - useRazorpay = true: runs a real Razorpay checkout; the poster's wallet
///   is NOT debited in this case since they paid real money instead.
///
/// onPaymentComplete is called once, with the outcome, regardless of which
/// path ran -- the caller just needs to react to success/failure.
Future<void> showPaymentBottomSheet({
  required BuildContext context,
  required String taskId,
  required String workerUid,
  required int amount,
  required void Function(bool success, String message) onPaymentComplete,
  String posterName = '',
  String posterContact = '',
}) async {
  final config = await DatabaseService().getPaymentConfig();
  if (config['paymentsEnabled'] != true) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Payments are currently disabled.'), backgroundColor: AppColors.red),
      );
    }
    return;
  }
  final bool useRazorpay = config['useRazorpay'] == true;

  // razorpay_flutter is mobile-only; real payments aren't available in the web build yet.
  if (kIsWeb && useRazorpay) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Payments are only available in the ChalBro mobile app for now.'),
          backgroundColor: AppColors.red,
        ),
      );
    }
    return;
  }

  if (!context.mounted) return;
  double givenRating = 5.0;

  // Admin-set discount: the poster pays less; the helper still earns on the full price.
  final int discountPercent = (config['discountPercent'] as int?) ?? 0;
  final amounts = PaymentAmounts.compute(amount, discountPercent);

  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setState) {
          return Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom + 20,
              top: 20,
              left: 20,
              right: 20,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: const [
                    Icon(Icons.payment, color: AppColors.primary, size: 28),
                    SizedBox(width: 12),
                    Text(
                      'Complete Payment',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.darkText),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Task Amount', style: TextStyle(color: AppColors.greyText)),
                          Text('₹$amount', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        ],
                      ),
                      if (amounts.discountAmount > 0) ...[
                        const SizedBox(height: 10),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Discount (${amounts.discountPercent}%)', style: const TextStyle(color: AppColors.success, fontWeight: FontWeight.w600)),
                            Text('-₹${amounts.discountAmount}', style: const TextStyle(color: AppColors.success, fontWeight: FontWeight.bold, fontSize: 16)),
                          ],
                        ),
                      ],
                      const Divider(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Total to Pay', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          Text('₹${amounts.payable}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: AppColors.primary)),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                const Text('Rate Worker (1-5):', style: TextStyle(fontWeight: FontWeight.bold)),
                Slider(
                  value: givenRating,
                  min: 1,
                  max: 5,
                  divisions: 4,
                  activeColor: AppColors.primary,
                  label: givenRating.toString(),
                  onChanged: (val) => setState(() => givenRating = val),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          side: const BorderSide(color: AppColors.primary),
                        ),
                        child: const Text('Cancel', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.pop(context); // Close bottom sheet

                          if (useRazorpay) {
                            final razorpay = RazorpayService();
                            razorpay.payForTask(
                              taskId: taskId,
                              givenRating: givenRating,
                              posterName: posterName,
                              posterContact: posterContact,
                              onSuccess: () {
                                onPaymentComplete(true, 'Task completed and worker paid!');
                                razorpay.dispose();
                              },
                              onError: (message) {
                                onPaymentComplete(false, message);
                                razorpay.dispose();
                              },
                            );
                          } else {
                            RazorpaySimulationSheet.show(
                              context,
                              amount: amounts.payable,
                              title: 'Task Payment',
                              onSuccess: () async {
                                final result = await DatabaseService().payAndCompleteTask(
                                    taskId, workerUid, amount, givenRating,
                                    discountPercent: discountPercent);
                                onPaymentComplete(
                                  result == 'success',
                                  result == 'success' ? 'Task completed and worker paid!' : 'Payment failed: $result',
                                );
                              },
                            );
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.success,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        child: Text('Pay ₹${amounts.payable}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Center(
                  child: Text(
                    useRazorpay ? 'Secured by Razorpay' : 'Secured by Chalbroo Payments',
                    style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                  ),
                ),
              ],
            ),
          );
        }
      );
    },
  );
}
