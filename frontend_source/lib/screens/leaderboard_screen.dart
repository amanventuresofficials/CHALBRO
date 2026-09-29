import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/database_service.dart';
import '../utils/app_colors.dart';
import 'public_profile_screen.dart';

class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> {
  final DatabaseService _db = DatabaseService();
  String _userCity = 'Surat';
  Map<String, dynamic>? _currentUserData;
  final String? _currentUid = FirebaseAuth.instance.currentUser?.uid;

  @override
  void initState() {
    super.initState();
    _db.streamUserData().listen((doc) {
      if (doc.exists && mounted) {
        setState(() {
          final data = doc.data() as Map<String, dynamic>;
          _userCity = data['city'] ?? 'Surat';
          _currentUserData = data;
        });
      }
    });
  }

  String _maskName(String fullName) {
    if (fullName.isEmpty) return 'Anonymous';
    final first = fullName.split(' ')[0];
    if (first.length <= 2) return first.padRight(first.length + 3, '*');
    return '${first.substring(0, 2)}${'*' * (first.length - 2)}';
  }

  Future<void> _showOptInDialog() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.emoji_events, color: Colors.amber),
            SizedBox(width: 8),
            Text('Join the Leaderboard?'),
          ],
        ),
        content: const Text(
          'By joining, your full name will be publicly visible in the leaderboard '
          'rankings. Other users can also tap your entry to view your profile.\n\n'
          'You can opt out at any time from Settings -> Preferences.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Not now'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Join Leaderboard', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (result == true && mounted) {
      await _db.setLeaderboardOptIn(true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("You are now on the leaderboard!"),
            backgroundColor: AppColors.success,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool currentUserQualifies = (_currentUserData != null) &&
        ((_currentUserData!['tasksDone'] ?? 0) > 0);
    final bool currentUserOptedIn = _currentUserData?['leaderboardOptIn'] == true;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        flexibleSpace: Container(
          decoration: const BoxDecoration(gradient: AppColors.primaryGradient),
        ),
        title: Text(
          'Top Helpers in $_userCity',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          if (currentUserQualifies && !currentUserOptedIn)
            InkWell(
              onTap: _showOptInDialog,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                decoration: const BoxDecoration(gradient: AppColors.primaryGradient),
                child: const Row(
                  children: [
                    Icon(Icons.emoji_events, color: Colors.amber, size: 22),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        "You have completed tasks! Want to join the leaderboard?",
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                      ),
                    ),
                    Icon(Icons.chevron_right, color: Colors.white),
                  ],
                ),
              ),
            ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .where('city', isEqualTo: _userCity)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(child: Text('No helpers found in your city.'));
                }

                final docs = snapshot.data!.docs.where((doc) {
                  final d = doc.data() as Map<String, dynamic>;
                  return (d['tasksDone'] ?? 0) > 0;
                }).toList();

                if (docs.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.emoji_events_outlined, size: 64, color: AppColors.greyText),
                          SizedBox(height: 16),
                          Text(
                            'No completed tasks yet in your city.\nBe the first!',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: AppColors.greyText, fontSize: 16),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                docs.sort((a, b) {
                  final dA = a.data() as Map<String, dynamic>;
                  final dB = b.data() as Map<String, dynamic>;
                  final double rA = dA['ratingCount'] != null && dA['ratingCount'] > 0
                      ? (dA['ratingSum'] ?? 0) / dA['ratingCount']
                      : 0.0;
                  final double rB = dB['ratingCount'] != null && dB['ratingCount'] > 0
                      ? (dB['ratingSum'] ?? 0) / dB['ratingCount']
                      : 0.0;
                  if (rA != rB) return rB.compareTo(rA);
                  return ((dB['tasksDone'] ?? 0) as int).compareTo((dA['tasksDone'] ?? 0) as int);
                });

                final topHelpers = docs.take(20).toList();

                return ListView.builder(
                  padding: const EdgeInsets.all(20),
                  itemCount: topHelpers.length,
                  itemBuilder: (context, index) {
                    final data = topHelpers[index].data() as Map<String, dynamic>;
                    final String uid = topHelpers[index].id;
                    final String fullName = data['fullName'] ?? 'Unknown';
                    final int tasksDone = data['tasksDone'] ?? 0;
                    final bool optedIn = data['leaderboardOptIn'] == true;
                    final bool isCurrentUser = uid == _currentUid;
                    final String displayName = (optedIn || isCurrentUser)
                        ? fullName
                        : _maskName(fullName);
                    final double rating =
                        data['ratingCount'] != null && data['ratingCount'] > 0
                            ? (data['ratingSum'] ?? 0) / data['ratingCount']
                            : 0.0;

                    Color rankColor = Colors.grey;
                    if (index == 0) rankColor = Colors.amber;
                    else if (index == 1) rankColor = Colors.grey.shade400;
                    else if (index == 2) rankColor = Colors.brown.shade300;

                    return GestureDetector(
                      onTap: optedIn
                          ? () => Navigator.push(context, MaterialPageRoute(builder: (_) => PublicProfileScreen(targetUid: uid)))
                          : null,
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: isCurrentUser ? AppColors.tertiary : Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: isCurrentUser
                                ? AppColors.primary.withOpacity(0.4)
                                : index < 3
                                    ? rankColor.withOpacity(0.5)
                                    : Colors.grey.withOpacity(0.1),
                            width: (isCurrentUser || index < 3) ? 2 : 1,
                          ),
                          boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.05), spreadRadius: 1, blurRadius: 5)],
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 40, height: 40,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: index < 3 ? rankColor.withOpacity(0.2) : Colors.grey.withOpacity(0.1),
                                shape: BoxShape.circle,
                              ),
                              child: index == 0
                                  ? const Text('🥇', style: TextStyle(fontSize: 20))
                                  : index == 1
                                      ? const Text('🥈', style: TextStyle(fontSize: 20))
                                      : index == 2
                                          ? const Text('🥉', style: TextStyle(fontSize: 20))
                                          : Text('#${index + 1}', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey.shade600, fontSize: 14)),
                            ),
                            const SizedBox(width: 16),
                            CircleAvatar(
                              backgroundColor: AppColors.primary.withOpacity(0.1),
                              child: Text(displayName[0].toUpperCase(), style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Flexible(
                                        child: Text(displayName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16), overflow: TextOverflow.ellipsis),
                                      ),
                                      if (isCurrentUser) ...[
                                        const SizedBox(width: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(8)),
                                          child: const Text('You', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                                        ),
                                      ],
                                      if (!optedIn && !isCurrentUser) ...[
                                        const SizedBox(width: 6),
                                        const Icon(Icons.lock_outline, size: 13, color: AppColors.greyText),
                                      ],
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text('$tasksDone Task${tasksDone == 1 ? "" : "s"} Done', style: const TextStyle(color: AppColors.greyText, fontSize: 12)),
                                ],
                              ),
                            ),
                            Row(
                              children: [
                                const Icon(Icons.star, color: Colors.amber, size: 18),
                                const SizedBox(width: 4),
                                Text(rating.toStringAsFixed(1), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                              ],
                            ),
                          ],
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
    );
  }
}
