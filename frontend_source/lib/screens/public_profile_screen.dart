import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/app_colors.dart';
import 'post_task_screen.dart'; // BUG-08 FIX: for hire button

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

          int tasksDone = userData['tasksDone'] ?? 0;
          double ratingSum = (userData['ratingSum'] ?? 0).toDouble();
          int ratingCount = userData['ratingCount'] ?? 0;
          bool isOpenForWork = userData['isOpenForWork'] ?? false;
          String idProofStatus = userData['idProofStatus'] ?? 'Unverified';
          String qualifications = userData['qualifications'] ?? 'No qualifications listed';
          String city = userData['city'] ?? 'Unknown City';

          double trustScore = ratingCount == 0 ? 5.0 : (ratingSum / ratingCount);

          String fullName = userData['fullName'] ?? 'Unknown Helper';

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
                                backgroundImage: NetworkImage('https://ui-avatars.com/api/?name=${Uri.encodeComponent(fullName)}&background=random&size=200'),
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
                                  fullName,
                                  style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 4),
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
                  isOpenForWork ? AppColors.success : Colors.grey
                ),
                const SizedBox(height: 24),
                // BUG-08 FIX: Add hire button on public profile
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: isOpenForWork ? () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => PostTaskScreen(
                            targetHelperUid: targetUid,
                            targetHelperName: fullName,
                          ),
                        ),
                      );
                    } : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isOpenForWork ? AppColors.primary : Colors.grey.shade400,
                      disabledBackgroundColor: Colors.grey.shade300,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    icon: Icon(isOpenForWork ? Icons.send : Icons.block, color: isOpenForWork ? Colors.white : Colors.grey.shade600, size: 18),
                    label: Text(
                      isOpenForWork ? 'Send Work Request to $fullName' : 'Currently Not Open For Work',
                      style: TextStyle(color: isOpenForWork ? Colors.white : Colors.grey.shade600, fontWeight: FontWeight.bold),
                    ),
                  ),
                  ),
                  const SizedBox(height: 24),
                  const Text('Recent Reviews', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.darkText)),
                  const SizedBox(height: 12),
                  StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance.collection('tasks')
                        .where('acceptedByUid', isEqualTo: targetUid)
                        .where('status', isEqualTo: 'completed')
                        .snapshots(),
                    builder: (context, taskSnapshot) {
                      if (!taskSnapshot.hasData) return const Center(child: CircularProgressIndicator());
                      final completedTasks = taskSnapshot.data!.docs;
                      if (completedTasks.isEmpty) return const Text('No reviews yet.', style: TextStyle(color: Colors.grey));

                      return ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: completedTasks.length > 5 ? 5 : completedTasks.length,
                        itemBuilder: (context, index) {
                          final task = completedTasks[index].data() as Map<String, dynamic>;
                          final double rating = (task['workerRating'] ?? 0.0).toDouble();
                          if (rating == 0) return const SizedBox.shrink();

                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.grey.withOpacity(0.1)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Icon(Icons.star, color: Colors.amber, size: 16),
                                    const SizedBox(width: 4),
                                    Text(rating.toStringAsFixed(1), style: const TextStyle(fontWeight: FontWeight.bold)),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(task['title'] ?? 'Task', style: const TextStyle(color: AppColors.greyText, fontSize: 13)),
                              ],
                            ),
                          );
                        },
                      );
                    }
                  ),
                  const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
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
