import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/app_colors.dart';
import '../services/database_service.dart';
import 'public_profile_screen.dart';
import 'chat_screen.dart';

class TaskApplicantsScreen extends StatelessWidget {
  final String taskId;
  final List<String> applicants;
  final Map<String, dynamic> bids;

  const TaskApplicantsScreen({
    super.key,
    required this.taskId,
    required this.applicants,
    required this.bids,
  });

  void _confirmAssign(BuildContext context, String helperUid, String anonymousId, int helperBid) {
    final priceController = TextEditingController(text: helperBid.toString());

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Propose Task Assignment'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Assign this task to $anonymousId?'),
            const SizedBox(height: 12),
            const Text('Proposed Price (₹):', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            TextField(
              controller: priceController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                prefixText: '₹ ',
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              ),
            ),
            const SizedBox(height: 8),
            const Text('If you change this price, it will be sent as a counter-offer.', style: TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.success,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            onPressed: () async {
              int proposedPrice = int.tryParse(priceController.text.trim()) ?? helperBid;
              Navigator.pop(context); // Close dialog
              await DatabaseService().proposeTask(taskId, helperUid, proposedPrice);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Offer sent for ₹$proposedPrice!'), backgroundColor: AppColors.success),
                );
                Navigator.pop(context); // Go back to my tasks
              }
            },
            child: const Text('Send Offer', style: TextStyle(color: Colors.white)),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        flexibleSpace: Container(
            decoration: const BoxDecoration(gradient: AppColors.primaryGradient)),
        title: const Text('Review Applicants', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        foregroundColor: Colors.white,
      ),
      body: applicants.isEmpty
          ? const Center(child: Text('No applicants yet.'))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: applicants.length,
              itemBuilder: (context, index) {
                String helperUid = applicants[index];

                return FutureBuilder<DocumentSnapshot>(
                  future: FirebaseFirestore.instance.collection('users').doc(helperUid).get(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: Padding(
                        padding: EdgeInsets.all(8.0),
                        child: CircularProgressIndicator(),
                      ));
                    }

                    if (!snapshot.hasData || !snapshot.data!.exists) {
                      return const SizedBox.shrink();
                    }

                    final userData = snapshot.data!.data() as Map<String, dynamic>;
                    String fullName = userData['fullName'] ?? 'Unknown Helper';
                    
                    double ratingSum = (userData['ratingSum'] ?? 0).toDouble();
                    int ratingCount = userData['ratingCount'] ?? 0;
                    double trustScore = ratingCount == 0 ? 5.0 : (ratingSum / ratingCount);
                    int tasksDone = userData['tasksDone'] ?? 0;
                    
                    int bidPrice = bids[helperUid] ?? 0;

                    return Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4)),
                        ],
                      ),
                      child: Column(
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              InkWell(
                                onTap: () {
                                  Navigator.push(context, MaterialPageRoute(builder: (_) => PublicProfileScreen(targetUid: helperUid)));
                                },
                                child: const CircleAvatar(
                                  radius: 28,
                                  backgroundColor: AppColors.pastelPurple,
                                  child: Icon(Icons.person, color: AppColors.primary, size: 30),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(fullName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppColors.darkText)),
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        const Icon(Icons.star, color: AppColors.warning, size: 16),
                                        const SizedBox(width: 4),
                                        Text(trustScore.toStringAsFixed(1), style: const TextStyle(fontWeight: FontWeight.bold)),
                                        const SizedBox(width: 12),
                                        const Icon(Icons.check_circle_outline, color: AppColors.greyText, size: 16),
                                        const SizedBox(width: 4),
                                        Text('$tasksDone tasks', style: const TextStyle(color: AppColors.greyText)),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: AppColors.success.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Text('₹$bidPrice', style: const TextStyle(color: AppColors.success, fontWeight: FontWeight.bold, fontSize: 16)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: SizedBox(
                                  height: 48,
                                  child: OutlinedButton(
                                    onPressed: () async {
                                      final chatId = await DatabaseService().getOrCreateChat(helperUid);
                                      if (context.mounted) {
                                        Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(chatId: chatId, otherUid: helperUid, otherName: fullName)));
                                      }
                                    },
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: AppColors.primary,
                                      side: const BorderSide(color: AppColors.primary),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                    ),
                                    child: const Text('Chat', style: TextStyle(fontWeight: FontWeight.bold)),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: SizedBox(
                                  height: 48,
                                  child: ElevatedButton(
                                    onPressed: () => _confirmAssign(context, helperUid, fullName, bidPrice),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.success,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                    ),
                                    child: const Text('Assign', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}
