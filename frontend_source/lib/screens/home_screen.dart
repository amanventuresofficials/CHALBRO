import 'package:flutter/material.dart';
import '../services/payment_mode_service.dart';
import '../utils/wallet_balance.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../services/database_service.dart';
import '../utils/app_colors.dart';
import '../utils/language_provider.dart';
import '../utils/name_utils.dart';
import 'post_task_screen.dart';
import 'notifications_screen.dart';
import 'public_profile_screen.dart';
import 'task_details_screen.dart';

class HomeScreen extends StatefulWidget {
  final void Function(int)? onNavigate;

  const HomeScreen({super.key, this.onNavigate});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final DatabaseService _dbService = DatabaseService();
  String _userCity = "Surat";
  String _userName = "";

  @override
  void initState() {
    super.initState();
    _dbService.streamUserData().listen((doc) {
      if (doc.exists && mounted) {
        final data = doc.data() as Map<String, dynamic>;
        setState(() {
          _userCity = data['city'] ?? "Surat";
          _userName = data['fullName'] ?? (FirebaseAuth.instance.currentUser?.displayName ?? "User");
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<LanguageProvider>().strings;
    return Scaffold(
      backgroundColor: AppColors.surface, 
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildTopBar(),
              _buildQuickStats(),
              _buildHeroBanner(),
              _buildSectionHeader(context, s.homeFeaturedHelpers, onSeeAll: () {
                if (widget.onNavigate != null) widget.onNavigate!(2); // Find Help tab is index 2
              }),
              _buildFeaturedHelpers(),
              _buildSectionHeader(context, s.homeBrowseCategories, onSeeAll: null),
              _buildCategories(),
              _buildSectionHeader(context, s.homeOpenTasks, onSeeAll: () {
                if (widget.onNavigate != null) widget.onNavigate!(3); // Nearby tab is index 3
              }),
              _buildOpenTasks(),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Namaste 👋',
                style: TextStyle(color: AppColors.greyText, fontSize: 14),
              ),
              Text(
                _userName.isNotEmpty ? _userName.split(' ').first.toLowerCase() : 'user',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: AppColors.darkText,
                ),
              ),
            ],
          ),
          StreamBuilder<QuerySnapshot>(
            stream: _dbService.streamMyNotifications(),
            builder: (context, snapshot) {
              int unreadCount = 0;
              if (snapshot.hasData) {
                unreadCount = snapshot.data!.docs.where((d) => (d.data() as Map<String, dynamic>)['isRead'] == false).length;
              }
              return Stack(
                alignment: Alignment.topRight,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.background,
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.notifications_none, color: AppColors.darkText),
                      onPressed: () {
                        Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationsScreen()));
                      },
                    ),
                  ),
                  if (unreadCount > 0)
                    Positioned(
                      right: 4,
                      top: 4,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: AppColors.red,
                          shape: BoxShape.circle,
                        ),
                        constraints: const BoxConstraints(minWidth: 10, minHeight: 10),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildQuickStats() {
    final currentUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 8.0),
      child: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('users').doc(currentUid).snapshots(),
        builder: (context, snapshot) {
          int tasksDone = 0;
          Map<String, dynamic>? userData;
          final s = context.watch<LanguageProvider>().strings;
          if (snapshot.hasData && snapshot.data!.exists) {
            final data = snapshot.data!.data() as Map<String, dynamic>;
            tasksDone = data['tasksDone'] ?? 0;
            userData = data;
          }
          
          return ValueListenableBuilder<bool>(
            valueListenable: PaymentModeService.instance.razorpayOn,
            builder: (context, razorpayOn, _) => Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.tertiary,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.check_circle_outline, color: AppColors.primary),
                      const SizedBox(height: 8),
                      Text('$tasksDone', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.primary)),
                      Text(s.homeTasksDone, style: const TextStyle(fontSize: 12, color: AppColors.greyText)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.success.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.account_balance_wallet_outlined, color: AppColors.success),
                      const SizedBox(height: 8),
                      Text('₹${balanceToShow(userData, razorpayOn: razorpayOn)}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.success)),
                      Text(s.homeWalletBalance, style: const TextStyle(fontSize: 12, color: AppColors.greyText)),
                    ],
                  ),
                ),
              ),
            ],
          ));
        },
      ),
    );
  }

  Widget _buildHeroBanner() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 8.0),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.primary,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Need help with something?',
                  style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Post a task. Helpers nearby will apply.',
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () {
                    if (widget.onNavigate != null) widget.onNavigate!(1); // Post task tab
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: AppColors.primary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    elevation: 0,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Text('Post a Task', style: TextStyle(fontWeight: FontWeight.bold)),
                      SizedBox(width: 4),
                      Icon(Icons.arrow_forward, size: 16),
                    ],
                  ),
                ),
              ],
            ),
            Positioned(
              right: 0,
              bottom: 10,
              child: Icon(Icons.rocket_launch, color: Colors.white.withOpacity(0.2), size: 60),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title, {VoidCallback? onSeeAll}) {
    final s = context.watch<LanguageProvider>().strings;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.darkText),
          ),
          if (onSeeAll != null)
            InkWell(
              onTap: onSeeAll,
              child: Text(
                s.homeSeeAll,
                style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 14),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFeaturedHelpers() {
    return StreamBuilder<QuerySnapshot>(
      stream: _dbService.streamAvailableHelpers(_userCity),
      builder: (context, snapshot) {
        final s = context.watch<LanguageProvider>().strings;
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox(height: 150, child: Center(child: CircularProgressIndicator()));
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(s.homeNoHelpers),
          );
        }

        final currentUid = FirebaseAuth.instance.currentUser?.uid;
        final helpers = snapshot.data!.docs.where((doc) => doc.id != currentUid).take(5).toList();
        
        if (helpers.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(s.homeNoOtherHelpers),
          );
        }

        return SizedBox(
          height: 170,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: helpers.length,
            itemBuilder: (context, index) {
              final data = helpers[index].data() as Map<String, dynamic>;
              // NEW-BUG-05 FIX: Calculate rating from ratingSum/ratingCount instead of non-existent 'rating' field
              final double ratingSum = (data['ratingSum'] ?? 0).toDouble();
              final int ratingCount = data['ratingCount'] ?? 0;
              final double rating = ratingCount == 0 ? 5.0 : (ratingSum / ratingCount);
              
              return GestureDetector(
                onTap: () {
                   Navigator.push(context, MaterialPageRoute(builder: (_) => PublicProfileScreen(targetUid: data['uid'])));
                },
                child: Container(
                  width: 140,
                  margin: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.grey.withOpacity(0.1)),
                    boxShadow: [
                      BoxShadow(color: Colors.grey.withOpacity(0.05), spreadRadius: 2, blurRadius: 8),
                    ],
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircleAvatar(
                        radius: 30,
                        backgroundColor: AppColors.primary.withOpacity(0.8),
                        child: Text(
                          NameUtils.initial(data['fullName'] ?? 'U'),
                          style: const TextStyle(color: Colors.white, fontSize: 24),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        NameUtils.firstName(data['fullName'] ?? 'User'),
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.location_on, color: Colors.grey, size: 12),
                          const SizedBox(width: 2),
                          Text(data['city'] ?? _userCity, style: const TextStyle(color: Colors.grey, fontSize: 12)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF9E6),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.star, color: Colors.orange, size: 12),
                            const SizedBox(width: 4),
                            Text(rating.toStringAsFixed(1), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.orange)),
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
      },
    );
  }

  Widget _buildCategories() {
    final categories = [
      {'icon': Icons.medical_services, 'title': 'Medicine Pickup', 'bg': AppColors.pastelRed, 'fg': AppColors.pastelRedIcon},
      {'icon': Icons.description, 'title': 'Document Delivery', 'bg': AppColors.pastelPurple, 'fg': AppColors.pastelPurpleIcon},
      {'icon': Icons.shopping_basket, 'title': 'Grocery Shopping', 'bg': AppColors.pastelGreen, 'fg': AppColors.pastelGreenIcon},
      {'icon': Icons.inventory_2, 'title': 'Furniture Moving', 'bg': AppColors.pastelOrange, 'fg': AppColors.pastelOrangeIcon},
    ];

    return SizedBox(
      height: 110,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: categories.length,
        itemBuilder: (context, index) {
          final cat = categories[index];
          return GestureDetector(
            onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => PostTaskScreen(initialCategory: cat['title'] as String)));
            },
            child: Container(
              width: 90,
              margin: const EdgeInsets.symmetric(horizontal: 8),
              child: Column(
                children: [
                  Container(
                    height: 64,
                    width: 64,
                    decoration: BoxDecoration(
                      color: cat['bg'] as Color,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Icon(cat['icon'] as IconData, color: cat['fg'] as Color, size: 28),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    cat['title'] as String,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.darkText),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildOpenTasks() {
    return StreamBuilder<QuerySnapshot>(
      stream: _dbService.streamTasksByCity(_userCity),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return const Padding(padding: EdgeInsets.all(20), child: Text('No open tasks near you.'));
        
        final currentUid = FirebaseAuth.instance.currentUser?.uid;
        final tasks = snapshot.data!.docs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          if (data['postedByUid'] == currentUid) return false;
          if (data['status'] != 'open') return false;
          return true;
        }).toList()
          ..sort((a, b) {
            final ta = (a.data() as Map<String, dynamic>)['createdAt'];
            final tb = (b.data() as Map<String, dynamic>)['createdAt'];
            final da = ta is Timestamp ? ta.millisecondsSinceEpoch : 0;
            final db = tb is Timestamp ? tb.millisecondsSinceEpoch : 0;
            return db.compareTo(da); // newest first
          });
        final latestTasks = tasks.take(3).toList();

        if (latestTasks.isEmpty) return const Padding(padding: EdgeInsets.all(20), child: Text('No open tasks near you.'));

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            children: latestTasks.map((doc) {
              final task = doc.data() as Map<String, dynamic>;
              return GestureDetector(
                onTap: () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => TaskDetailsScreen(taskId: doc.id)));
                },
                child: Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.grey.withOpacity(0.1)),
                    boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.03), spreadRadius: 1, blurRadius: 5)],
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.pastelPurple,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Icon(Icons.extension, color: AppColors.pastelPurpleIcon, size: 24),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(task['title'] ?? 'Task', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                const Icon(Icons.location_on_outlined, size: 14, color: AppColors.greyText),
                                const SizedBox(width: 2),
                                Text(task['city'] ?? _userCity, style: const TextStyle(color: AppColors.greyText, fontSize: 13)),
                              ],
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppColors.tertiary,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(
                          '₹${task['price']}',
                          style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        );
      },
    );
  }
}
