import 'package:flutter/material.dart';
import '../utils/app_colors.dart';

class RazorpaySimulationSheet extends StatefulWidget {
  final int amount;
  final String title;
  final VoidCallback onSuccess;

  const RazorpaySimulationSheet({
    super.key,
    required this.amount,
    required this.title,
    required this.onSuccess,
  });

  static Future<void> show(BuildContext context, {required int amount, required String title, required VoidCallback onSuccess}) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => RazorpaySimulationSheet(amount: amount, title: title, onSuccess: onSuccess),
    );
  }

  @override
  State<RazorpaySimulationSheet> createState() => _RazorpaySimulationSheetState();
}

class _RazorpaySimulationSheetState extends State<RazorpaySimulationSheet> {
  bool _isLoading = false;

  void _processPayment() async {
    setState(() => _isLoading = true);
    // Simulate network delay
    await Future.delayed(const Duration(seconds: 2));
    
    if (mounted) {
      setState(() => _isLoading = false);
      Navigator.pop(context); // Close the sheet
      widget.onSuccess(); // Call the success callback
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        top: 24,
        left: 20,
        right: 20,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(
            child: Container(
              width: 40, height: 5,
              decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(10)),
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF0C2461).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.security, color: Color(0xFF0C2461), size: 28), // Razorpay-like color
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.darkText)),
                    const SizedBox(height: 4),
                    const Text('Secured by Razorpay (Simulated)', style: TextStyle(color: AppColors.greyText, fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),
          const Text('Amount to Pay', style: TextStyle(color: AppColors.greyText, fontSize: 14)),
          const SizedBox(height: 8),
          Text(
            '₹${widget.amount}',
            style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w900, color: AppColors.darkText),
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _processPayment,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF3399CC), // Razorpay Blue
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              child: _isLoading 
                ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Text('Pay Now', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(height: 16),
          const Text('Will link actual gateway later', style: TextStyle(color: Colors.grey, fontSize: 12)),
        ],
      ),
    );
  }
}
