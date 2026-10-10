import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/hired_contacts.dart';
import '../widgets/report_sheet.dart';
import '../utils/app_colors.dart';
import '../utils/name_utils.dart';
import 'post_task_screen.dart'; // BUG-08 FIX: for hire button

/// A helper's profile.
///
/// Privacy: until the viewer has hired this person (a task assigned between
/// them), only the first name, rating and availability are shown. Full name,
/// skills and city appear once hired. Your own profile always shows everything.
class PublicProfileScreen extends StatelessWidget {
  final String targetUid;

  const PublicProfileScreen({super.key, required this.targetUid});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: FutureBuilder<DocumentSnapshot>(
        future: FirebaseFirestore.instance.collection('users').doc(targetUid).get(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || !snapshot.data!.exists) {
            return const Center(child: Text("Profile not found."));
          }

          final userData = snapshot.data!.data() as Map<String, dynamic>;

          return ListenableBuilder(
            listenable: HiredContacts.instance,
            builder: (context, _) => _buildProfile(context, userData),
          );
        },
      ),
    );
  }

  Widget _buildProfile(BuildContext context, Map<String, dynamic> userData) {
    final bool canSeeDetails = HiredContacts.instance.canSeeDetails(targetUid);

    int tasksDone = userData['tasksDone'] ?? 0;
    double ratingSum = (userData['ratingSum'] ?? 0).toDouble();
    int ratingCount = userData['ratingCount'] ?? 0;
    bool isOpenForWork = userData['isOpenForWork'] ?? false;
    String idProofStatus = userData['idProofStatus'] ?? 'Unverified';
    String qualifications = userData['qualifications'] ?? 'No qualifications listed';
    String city = userData['city'] ?? 'Unknown City';

    double trustScore = ratingCount == 0 ? 5.0 : (ratingSum / ratingCount);

    final String fullName = userData['fullName'] ?? 'Helper';
    final String displayName = HiredContacts.instance.nameFor(targetUid, fullName);

    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: AppColors.darkText),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const Spacer(),
                  // Flag this person for the admin team (not on your own profile).
                  if (targetUid != FirebaseAuth.instance.currentUser?.uid)
                    TextButton.icon(
                      onPressed: () => showReportSheet(
                        context,
                        targetType: 'user',
                        targetId: targetUid,
                        targetOwnerUid: targetUid,
                        targetTitle: NameUtils.firstName(userData['fullName'] ?? ''),
                      ),
                      icon: const Icon(Icons.flag_outlined, size: 18),
                      label: const Text('Report'),
                      style: TextButton.styleFrom(foregroundColor: Colors.grey),
                    ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20.0),
              child: Text(
                'Helper Profile',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: AppColors.darkText),
              ),
            ),
            const SizedBox(height: 16),

            // Purple User Card
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Row(
                  children: [
                    Stack(
                      children: [
                        CircleAvatar(
                          radius: 32,
                          backgroundColor: Colors.white.withOpacity(0.2),
                          child: Text(
                            NameUtils.initial(displayName),
                            style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold),
                          ),
                        ),
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                            child: const Icon(Icons.verified, color: AppColors.primary, size: 16),
                          ),
                        )
                      ],
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            displayName,
                            style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          if (canSeeDetails) ...[
                            Text(
                              qualifications,
                              style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 14),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                const Icon(Icons.location_on, size: 14, color: Colors.white),
                                const SizedBox(width: 4),
                                Text(city, style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 14)),
                              ],
                            ),
                          ] else
                            Row(
                              children: [
                                Icon(Icons.lock_outline, size: 14, color: Colors.white.withOpacity(0.85)),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    'Full details are shown once you hire $displayName',
                                    style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 13),
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Stats Row
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.grey.withOpacity(0.1)),
                        boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.05), blurRadius: 10, spreadRadius: 2)],
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(trustScore.toStringAsFixed(1), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.darkText)),
                              const SizedBox(width: 4),
                              const Icon(Icons.star, color: Colors.orange, size: 20),
                            ],
                          ),
                          const SizedBox(height: 4),
                          const Text('Trust Score', style: TextStyle(color: AppColors.greyText, fontSize: 12)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.grey.withOpacity(0.1)),
                        boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.05), blurRadius: 10, spreadRadius: 2)],
                      ),
                      child: Column(
                        children: [
                          Text('$tasksDone', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.darkText)),
                          const SizedBox(height: 4),
                          const Text('Tasks Done', style: TextStyle(color: AppColors.greyText, fontSize: 12)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0),
              child: Column(
                children: [
                  _buildInfoTile(Icons.verified_user, 'ID Verification', idProofStatus, AppColors.primary),
                  _buildInfoTile(
                    Icons.work,
                    'Availability',
                    isOpenForWork ? 'Open for Work' : 'Currently Unavailable',
                    isOpenForWork ? AppColors.success : Colors.grey,
                  ),
                  const SizedBox(height: 24),
                  // BUG-08 FIX: Add hire button on public profile
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton.icon(
                      onPressed: isOpenForWork
                          ? () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => PostTaskScreen(
                                    targetHelperUid: targetUid,
                                    targetHelperName: displayName,
                                  ),
                                ),
                              );
                            }
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isOpenForWork ? AppColors.primary : Colors.grey.shade400,
                        disabledBackgroundColor: Colors.grey.shade300,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      icon: Icon(isOpenForWork ? Icons.send : Icons.block, color: isOpenForWork ? Colors.white : Colors.grey.shade600, size: 18),
                      label: Text(
                        isOpenForWork ? 'Send Work Request to $displayName' : 'Currently Not Open For Work',
                        style: TextStyle(color: isOpenForWork ? Colors.white : Colors.grey.shade600, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Recent Reviews', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.darkText)),
                  ),
                  const SizedBox(height: 12),
                  _buildReviews(),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Reviews live in their own collection (written when a task is paid) so that
  // the tasks themselves can stay private to the poster and the hired person.
  Widget _buildReviews() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('reviews')
          .where('workerUid', isEqualTo: targetUid)
          .limit(30)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Align(
            alignment: Alignment.centerLeft,
            child: Text('Reviews are unavailable right now.', style: TextStyle(color: Colors.grey)),
          );
        }
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

        final reviews = snapshot.data!.docs
            .map((d) => d.data() as Map<String, dynamic>)
            .where((r) => ((r['rating'] ?? 0) as num) > 0)
            .toList()
          ..sort((a, b) {
            final ta = a['createdAt'];
            final tb = b['createdAt'];
            final ma = ta is Timestamp ? ta.millisecondsSinceEpoch : 0;
            final mb = tb is Timestamp ? tb.millisecondsSinceEpoch : 0;
            return mb.compareTo(ma); // newest first
          });

        if (reviews.isEmpty) {
          return const Align(
            alignment: Alignment.centerLeft,
            child: Text('No reviews yet.', style: TextStyle(color: Colors.grey)),
          );
        }

        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: reviews.length > 5 ? 5 : reviews.length,
          itemBuilder: (context, index) {
            final review = reviews[index];
            final double rating = (review['rating'] as num).toDouble();
            final String category = review['category'] ?? 'Task';

            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey.withOpacity(0.1)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.star, color: Colors.amber, size: 16),
                  const SizedBox(width: 4),
                  Text(rating.toStringAsFixed(1), style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(category, style: const TextStyle(color: AppColors.greyText, fontSize: 13)),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildInfoTile(IconData icon, String title, String value, Color iconColor) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.withOpacity(0.1)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: AppColors.darkText, size: 20),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.darkText)),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              value,
              style: TextStyle(color: iconColor, fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
