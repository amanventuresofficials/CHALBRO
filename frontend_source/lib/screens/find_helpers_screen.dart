import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import '../utils/app_colors.dart';
import '../utils/app_strings.dart';
import '../utils/language_provider.dart';
import '../utils/name_utils.dart';
import '../services/database_service.dart';
import 'post_task_screen.dart';
import 'leaderboard_screen.dart';
import 'public_profile_screen.dart';

class FindHelpersScreen extends StatefulWidget {
  const FindHelpersScreen({super.key});

  @override
  State<FindHelpersScreen> createState() => _FindHelpersScreenState();
}

class _FindHelpersScreenState extends State<FindHelpersScreen> {
  final DatabaseService _dbService = DatabaseService();
  String? _userCity; // null until loaded from Firestore
  String _selectedFilterKey = 'All'; // internal key, always English
  // Internal filter keys (used for logic)
  static const List<String> _filterKeys = [
    'All', 'High Rated', 'Plumbers', 'Electricians', 'Tutors', 'Drivers', 'Cleaners'
  ];
  // Display labels — first two are translated, rest are proper nouns kept as-is
  List<String> _filterLabels(AppStrings s) => [
    s.findHelpersFilterAll,
    s.findHelpersFilterHighRated,
    'Plumbers', 'Electricians', 'Tutors', 'Drivers', 'Cleaners'
  ];

  @override
  void initState() {
    super.initState();
    // Get the current user's city so we search nearby helpers
    _dbService.streamUserData().listen((doc) {
      if (doc.exists && mounted) {
        setState(() => _userCity =
            (doc.data() as Map<String, dynamic>)['city'] ?? 'Surat');
      }
    });
  }


  @override
  Widget build(BuildContext context) {
    if (_userCity == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // Use local variable so Dart can promote the type from String? to String
    final String city = _userCity!;
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    final s = context.watch<LanguageProvider>().strings;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        s.findHelpersTitle,
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: AppColors.darkText,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.leaderboard,
                            color: AppColors.primary, size: 28),
                        onPressed: () {
                          Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const LeaderboardScreen()));
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${s.findHelpersAvailableIn} $city',
                    style: TextStyle(
                      fontSize: 16,
                      color: AppColors.greyText,
                    ),
                  ),
                ],
              ),
            ),
            // Placeholder horizontal filter chips
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20.0),
              child: Row(
                children: List.generate(_filterKeys.length, (i) {
                  final key = _filterKeys[i];
                  final label = _filterLabels(s)[i];
                  return Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: _buildFilterChip(label, key, key == _selectedFilterKey),
                  );
                }),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: _dbService.streamAvailableHelpers(city),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (!snapshot.hasData) {
                    return Center(
                        child: Text(s.findHelpersNoHelpers));
                  }

                  final helpers = snapshot.data!.docs.where((doc) {
                    final helper = doc.data() as Map<String, dynamic>;

                    // Exclude yourself — use doc.id (always the UID) rather than
                    // helper['uid'] which may be missing from older documents.
                    if (doc.id == currentUserId) return false;

                    // Exclude users who are not open for work (double-check in UI
                    // in case Firestore index hasn't propagated yet).
                    final bool openForWork = helper['isOpenForWork'] == true;
                    if (!openForWork) return false;

                    // CLIENT-SIDE: Exclude users who chose to hide from search.
                    // This is done here (not in the Firestore query) because existing
                    // users don't have this field, so a Firestore where-clause would
                    // incorrectly exclude them.
                    if (helper['isHiddenFromSearch'] == true) return false;

                    if (_selectedFilterKey == 'High Rated') {
                      int count = helper['ratingCount'] ?? 0;
                      double sum = (helper['ratingSum'] ?? 0).toDouble();
                      double score = count == 0 ? 5.0 : (sum / count);
                      if (score < 4.0) return false;
                    } else if (_selectedFilterKey != 'All') {
                      String quals =
                          (helper['qualifications'] ?? '').toLowerCase();
                      String filterStr = _selectedFilterKey.toLowerCase();
                      if (filterStr.endsWith('s')) {
                        filterStr =
                            filterStr.substring(0, filterStr.length - 1);
                      }
                      if (!quals.contains(filterStr)) return false;
                    }

                    return true;
                  }).toList();

                  // Show empty state AFTER filtering (e.g. if you're the only
                  // open-for-work user in your city, helpers will be empty).
                  if (helpers.isEmpty) {
                    return Center(
                        child: Text(s.findHelpersNoHelpers));
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: helpers.length,
                    itemBuilder: (context, index) {
                      final helper =
                          helpers[index].data() as Map<String, dynamic>;

                      // Privacy: only the first name is shown until this helper is hired.
                      final String displayName =
                          NameUtils.firstName(helper['fullName'] ?? 'Helper');
                      double ratingSum = (helper['ratingSum'] ?? 0).toDouble();
                      int ratingCount = helper['ratingCount'] ?? 0;
                      double trustScore =
                          ratingCount == 0 ? 5.0 : (ratingSum / ratingCount);
                      int tasksDone = helper['tasksDone'] ?? 0;

                      return Card(
                          elevation: 0,
                          margin: const EdgeInsets.only(bottom: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                            side: BorderSide(color: Colors.grey.shade200),
                          ),
                          child: InkWell(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => PublicProfileScreen(
                                      targetUid: helper['uid']),
                                ),
                              );
                            },
                            borderRadius: BorderRadius.circular(16),
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Row(
                                children: [
                                  // Avatar & Active Dot
                                  Stack(
                                    children: [
                                      CircleAvatar(
                                        radius: 28,
                                        backgroundColor:
                                            AppColors.primary.withOpacity(0.1),
                                        child: const Icon(Icons.person,
                                            color: AppColors.primary, size: 30),
                                      ),
                                      Positioned(
                                        bottom: 0,
                                        right: 0,
                                        child: Container(
                                          width: 14,
                                          height: 14,
                                          decoration: BoxDecoration(
                                            color: AppColors
                                                .success, // Green because they are fetched as 'isOpenForWork == true'
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                                color: Colors.white, width: 2),
                                          ),
                                        ),
                                      )
                                    ],
                                  ),
                                  const SizedBox(width: 16),
                                  // Helper Details
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(displayName,
                                            style: const TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold,
                                                color: AppColors.darkText)),
                                        const SizedBox(height: 6),
                                        Row(
                                          children: [
                                            const Icon(Icons.star,
                                                color: AppColors.warning,
                                                size: 14),
                                            const SizedBox(width: 4),
                                            Text(trustScore.toStringAsFixed(1),
                                                style: const TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 12)),
                                            const SizedBox(width: 12),
                                            const Icon(
                                                Icons.check_circle_outline,
                                                color: AppColors.greyText,
                                                size: 14),
                                            const SizedBox(width: 4),
                                            Text('$tasksDone ${s.findHelpersTasks}',
                                                style: const TextStyle(
                                                    color: AppColors.greyText,
                                                    fontSize: 12)),
                                          ],
                                        )
                                      ],
                                    ),
                                  ),
                                  // Action Button
                                  ElevatedButton(
                                    onPressed: () {
                                      // Navigate to Post Task screen and pass the helper's details
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) => PostTaskScreen(
                                            targetHelperUid: helper['uid'],
                                            targetHelperName: displayName,
                                          ),
                                        ),
                                      );
                                    },
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.primary,
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(16)),
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 16, vertical: 8),
                                    ),
                                    child: Text(s.request,
                                        style: const TextStyle(
                                            color: Colors.white, fontSize: 12)),
                                  ),
                                ],
                              ),
                            ),
                          ));
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label, String key, bool isSelected) {
    return GestureDetector(
      onTap: () => setState(() => _selectedFilterKey = key),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? AppColors.primary : Colors.grey.shade300,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : AppColors.darkText,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}
