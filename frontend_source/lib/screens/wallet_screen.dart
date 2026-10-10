import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../services/database_service.dart';
import '../services/payment_mode_service.dart';
import '../utils/app_colors.dart';
import '../utils/language_provider.dart';
import '../utils/wallet_balance.dart';
import '../utils/withdrawal.dart';

class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  final DatabaseService _db = DatabaseService();
  late final Stream<QuerySnapshot> _withdrawals = _db.streamMyWithdrawals();
  Map<String, dynamic>? _userData;

  // Razorpay on = the REAL balance (withdrawable). Off = the practice balance (test credit, never withdrawable).
  bool get _real => PaymentModeService.instance.razorpayOn.value;
  int get _walletBalance => balanceToShow(_userData, razorpayOn: _real);

  void _onPaymentMode() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _db.streamUserData().listen((doc) {
      if (doc.exists && mounted) {
        setState(() => _userData = doc.data() as Map<String, dynamic>);
      }
    });
    PaymentModeService.instance.razorpayOn.addListener(_onPaymentMode);
  }

  @override
  void dispose() {
    PaymentModeService.instance.razorpayOn.removeListener(_onPaymentMode);
    super.dispose();
  }

  // ── Withdraw ──────────────────────────────────────────────────────────────
  Future<void> _openWithdrawDialog() async {
    final messenger = ScaffoldMessenger.of(context);
    final outcome = await showDialog<_WithdrawOutcome>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _WithdrawDialog(balance: _walletBalance, db: _db),
    );
    if (outcome == null) return;
    messenger.showSnackBar(SnackBar(content: Text(_resultMessage(outcome.result, outcome.amount, outcome.upi))));
  }

  String _resultMessage(WithdrawResult r, String amount, String upi) {
    switch (r) {
      case WithdrawResult.sent:
        return 'Request sent. ChalBro will pay ₹$amount to $upi soon.';
      case WithdrawResult.notAvailable:
        return 'Withdrawals are not open yet.';
      case WithdrawResult.notEnough:
        return 'There is not enough money in your wallet.';
      case WithdrawResult.badAmount:
        return 'Please check the amount.';
      case WithdrawResult.badUpi:
        return 'Please check the UPI ID.';
      case WithdrawResult.failed:
        return 'Could not send the request. Please try again.';
    }
  }

  Widget _withdrawalRequests() {
    return StreamBuilder<QuerySnapshot>(
      stream: _withdrawals,
      builder: (context, snapshot) {
        final docs = [...(snapshot.data?.docs ?? const <QueryDocumentSnapshot>[])];
        if (docs.isEmpty) return const SizedBox.shrink();
        DateTime when(QueryDocumentSnapshot d) =>
            ((d.data() as Map<String, dynamic>)['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now();
        docs.sort((a, b) => when(b).compareTo(when(a)));
        return Container(
          width: double.infinity,
          margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Your withdrawal requests', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 8),
              for (final d in docs.take(4)) _requestRow(d.data() as Map<String, dynamic>),
            ],
          ),
        );
      },
    );
  }

  Widget _requestRow(Map<String, dynamic> w) {
    final status = (w['status'] ?? 'pending').toString();
    final (label, color) = switch (status) {
      'approved' => ('Paid', AppColors.success),
      'rejected' => ('Not paid, money returned', AppColors.red),
      _ => ('Waiting to be paid', Colors.orange),
    };
    final ts = w['timestamp'] as Timestamp?;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text('₹${w['amount']}', style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '${w['paymentDetails'] ?? ''}${ts == null ? '' : ' · ${DateFormat('d MMM').format(ts.toDate())}'}',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(child: Text(label, textAlign: TextAlign.end, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<LanguageProvider>().strings;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(s.walletTitle, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Column(
        children: [
          // Balance Card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: const BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(32)),
            ),
            child: Column(
              children: [
                Text(s.walletAvailableBalance, style: const TextStyle(color: Colors.white70, fontSize: 16)),
                const SizedBox(height: 8),
                Text('₹$_walletBalance', style: const TextStyle(color: Colors.white, fontSize: 48, fontWeight: FontWeight.w900)),
                const SizedBox(height: 4),
                Text(
                  _real ? 'Real money from Razorpay payments' : 'Practice balance, not real money. It cannot be withdrawn.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
                if (_real) ...[
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _walletBalance >= kMinWithdrawal ? _openWithdrawDialog : null,
                    icon: const Icon(Icons.north_east_rounded, size: 18),
                    label: const Text('Withdraw money', style: TextStyle(fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: AppColors.primary,
                      disabledBackgroundColor: Colors.white24,
                      disabledForegroundColor: Colors.white60,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    ),
                  ),
                  if (_walletBalance < kMinWithdrawal)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text('You can withdraw from ₹$kMinWithdrawal', style: TextStyle(color: Colors.white70, fontSize: 12)),
                    ),
                ],
              ],
            ),
          ),

          if (_real) _withdrawalRequests(),

          // Transaction History
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
                  child: Text(s.walletTransactionHistory, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.darkText)),
                ),
                Expanded(
                  child: StreamBuilder<QuerySnapshot>(
                    stream: _db.streamTransactions(),
                    builder: (context, snapshot) {
                      if (snapshot.hasError) return Center(child: Text('Error: ${snapshot.error}'));
                      if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());

                      // Each mode has its own history: real (Razorpay) entries or practice-wallet entries.
                      final shown = (snapshot.data?.docs ?? const <QueryDocumentSnapshot>[])
                          .where((d) => transactionVisible(d.data() as Map<String, dynamic>, razorpayOn: _real))
                          .toList();
                      if (shown.isEmpty) {
                        return Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.receipt_long, size: 64, color: Colors.grey.shade300),
                              const SizedBox(height: 16),
                              Text(s.walletNoTransactions, style: const TextStyle(color: Colors.grey, fontSize: 16)),
                            ],
                          ),
                        );
                      }

                      final transactions = shown;
                      return ListView.separated(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        itemCount: transactions.length,
                        separatorBuilder: (context, index) => Divider(color: Colors.grey.shade200),
                        itemBuilder: (context, index) {
                          final tx = transactions[index].data() as Map<String, dynamic>;
                          final isCredit = tx['type'] == 'credit';
                          final date = tx['timestamp'] != null
                              ? DateFormat('MMM d, yyyy • h:mm a').format((tx['timestamp'] as Timestamp).toDate())
                              : 'Just now';

                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: isCredit ? AppColors.success.withOpacity(0.1) : AppColors.red.withOpacity(0.1),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                isCredit ? Icons.arrow_downward : Icons.arrow_upward,
                                color: isCredit ? AppColors.success : AppColors.red,
                              ),
                            ),
                            title: Text(tx['title'] ?? 'Transaction', style: const TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Text(date, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                            trailing: Text(
                              '${isCredit ? '+' : '-'}₹${tx['amount']}',
                              style: TextStyle(
                                color: isCredit ? AppColors.success : AppColors.darkText,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WithdrawOutcome {
  final WithdrawResult result;
  final String amount;
  final String upi;
  const _WithdrawOutcome(this.result, this.amount, this.upi);
}

/// The "Withdraw money" form. It owns its text controllers, so they are only freed
/// when the dialog has really left the screen (freeing them right after pop() made the
/// closing animation use a disposed controller).
class _WithdrawDialog extends StatefulWidget {
  final int balance;
  final DatabaseService db;
  const _WithdrawDialog({required this.balance, required this.db});

  @override
  State<_WithdrawDialog> createState() => _WithdrawDialogState();
}

class _WithdrawDialogState extends State<_WithdrawDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amountCtrl = TextEditingController();
  final _upiCtrl = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _amountCtrl.dispose();
    _upiCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    final amountText = _amountCtrl.text.trim();
    final upi = _upiCtrl.text.trim();
    final result = await widget.db.requestWithdrawal(amount: int.parse(amountText), upiId: upi);
    if (mounted) Navigator.pop(context, _WithdrawOutcome(result, amountText, upi));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Withdraw money'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('In your wallet: ₹${widget.balance}', style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              TextFormField(
                controller: _amountCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
                decoration: InputDecoration(labelText: 'Amount (₹)', helperText: 'At least ₹$kMinWithdrawal'),
                validator: (v) => withdrawalAmountProblem(int.tryParse((v ?? '').trim()), widget.balance),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _upiCtrl,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                decoration: const InputDecoration(labelText: 'Your UPI ID', hintText: 'name@bank'),
                validator: (v) => isValidUpiId(v ?? '') ? null : 'Enter a UPI ID like name@bank',
              ),
              const SizedBox(height: 12),
              Text(
                'ChalBro will send the money to this UPI ID. The amount leaves your wallet now. '
                'If the request cannot be paid, it comes back to your wallet.',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600, height: 1.4),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: _busy ? null : _submit,
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
          child: _busy
              ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Send request'),
        ),
      ],
    );
  }
}
