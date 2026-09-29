import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../services/database_service.dart';
import '../utils/app_colors.dart';
import '../utils/language_provider.dart';

class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  final DatabaseService _db = DatabaseService();
  int _walletBalance = 0;

  @override
  void initState() {
    super.initState();
    _db.streamUserData().listen((doc) {
      if (doc.exists && mounted) {
        final data = doc.data() as Map<String, dynamic>;
        setState(() {
          _walletBalance = (data['walletBalance'] ?? 0).toInt();
        });
      }
    });
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
              ],
            ),
          ),
          
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
                      
                      if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
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

                      final transactions = snapshot.data!.docs;
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
