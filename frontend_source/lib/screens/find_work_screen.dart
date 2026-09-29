import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../services/database_service.dart';
import '../utils/app_colors.dart';
import 'task_details_screen.dart';
import 'notifications_screen.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class FindWorkScreen extends StatefulWidget {
  const FindWorkScreen({super.key});

  @override
  State<FindWorkScreen> createState() => _FindWorkScreenState();
}

class _FindWorkScreenState extends State<FindWorkScreen> {
  final DatabaseService _db = DatabaseService();

  // Nullable: null = city not yet loaded from Firestore → prevents showing wrong city tasks
  String? _userCity;

  String _selectedSort = 'Newest';
  String _selectedCategory = 'All';
  final List<String> _categories = [
    'All', 'Assignment', 'Transport', 'Home Svcs', 'Education',
    'Events', 'Shopping', 'Repairs', 'Daily Help', 'Other'
  ];

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool _isReady = false;
  bool _showMap = false;

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _isReady = true);
    });

    // Listen to user's city from Firestore (live)
    _db.streamUserData().listen((doc) {
      if (doc.exists && mounted) {
        final city = (doc.data() as Map<String, dynamic>)['city'];
        if (city != null && city.toString().isNotEmpty) {
          setState(() => _userCity = city.toString());
        }
      }
    });

    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.trim().toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _showBidDialog(String taskId, String posterUid, String taskTitle, int originalPrice) {
    final bidController = TextEditingController(text: originalPrice.toString());
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Send Offer'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Original Budget: ₹$originalPrice'),
            const SizedBox(height: 16),
            TextField(
              controller: bidController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Your Offer (₹)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            onPressed: () async {
              int bidPrice = int.tryParse(bidController.text.trim()) ?? originalPrice;
              await _db.applyForTask(taskId, posterUid, taskTitle, bidPrice);
              if (context.mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Offer sent successfully!'), backgroundColor: AppColors.success),
                );
              }
            },
            child: const Text('Send', style: TextStyle(color: Colors.white)),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildTopBar(),
            _buildToggle(),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20.0),
              child: Text(
                'Nearby Tasks',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: AppColors.darkText),
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Search tasks by keyword...',
                  prefixIcon: const Icon(Icons.search, color: AppColors.greyText),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: Colors.grey.withOpacity(0.2)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: Colors.grey.withOpacity(0.2)),
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 0),
                ),
              ),
            ),
            const SizedBox(height: 16),
            _buildCategoryFilters(),
            const SizedBox(height: 12),
            _buildSortFilters(),
            const SizedBox(height: 16),
            Expanded(
              child: _buildListView(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.tertiary,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                const Icon(Icons.location_on, size: 16, color: AppColors.primary),
                const SizedBox(width: 4),
                // Show 'Loading...' until city is fetched from Firestore
                Text(_userCity ?? 'Loading...', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                const Icon(Icons.keyboard_arrow_down, size: 16),
              ],
            ),
          ),
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.refresh, color: AppColors.darkText),
                onPressed: () { setState(() {}); },
              ),
              Stack(
                alignment: Alignment.topRight,
                children: [
                  IconButton(
                    icon: const Icon(Icons.notifications_none, color: AppColors.darkText),
                    onPressed: () {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationsScreen()));
                    },
                  ),
                  Positioned(
                    right: 8,
                    top: 8,
                    child: Container(
                      width: 8, height: 8,
                      decoration: const BoxDecoration(color: AppColors.red, shape: BoxShape.circle),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildToggle() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.grey.withOpacity(0.1)),
        ),
        child: Row(
          children: [
            Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _showMap = false),
                child: Container(
                  decoration: BoxDecoration(
                    color: !_showMap ? AppColors.primary : Colors.transparent,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Center(
                    child: Text('List View', style: TextStyle(color: !_showMap ? Colors.white : Colors.grey, fontWeight: FontWeight.bold)),
                  ),
                ),
              ),
            ),
            Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _showMap = true),
                child: Container(
                  decoration: BoxDecoration(
                    color: _showMap ? AppColors.primary : Colors.transparent,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Center(
                    child: Text('Map View', style: TextStyle(color: _showMap ? Colors.white : Colors.grey, fontWeight: FontWeight.bold)),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryFilters() {
    return SizedBox(
      height: 36,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _categories.length,
        itemBuilder: (context, index) {
          final cat = _categories[index];
          final isSelected = cat == _selectedCategory;
          return GestureDetector(
            onTap: () => setState(() => _selectedCategory = cat),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: isSelected ? AppColors.primary : AppColors.background,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: isSelected ? AppColors.primary : Colors.grey.withOpacity(0.2)),
              ),
              child: Center(
                child: Text(
                  cat,
                  style: TextStyle(
                    color: isSelected ? Colors.white : AppColors.darkText,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSortFilters() {
    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          _buildSortChip('Distance', Icons.near_me),
          _buildSortChip('Budget', Icons.money),
          _buildSortChip('Newest', Icons.access_time),
        ],
      ),
    );
  }

  Widget _buildSortChip(String label, IconData icon) {
    final isSelected = _selectedSort == label;
    return GestureDetector(
      onTap: () => setState(() => _selectedSort = label),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isSelected ? AppColors.primary : Colors.grey.withOpacity(0.3)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 14, color: isSelected ? AppColors.primary : Colors.grey),
            const SizedBox(width: 6),
            Text(
              'Sort: $label',
              style: TextStyle(
                color: isSelected ? AppColors.primary : Colors.grey,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildListView() {
    // Show spinner until city is loaded from Firestore — prevents showing wrong city's tasks
    if (!_isReady || _userCity == null) {
      return const Center(child: CircularProgressIndicator(color: AppColors.primary));
    }

    final String city = _userCity!;

    return StreamBuilder<QuerySnapshot>(
      stream: _db.streamAvailableCityTasks(city),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Center(child: Text('No open tasks in $city.'));
        }

        final currentUid = FirebaseAuth.instance.currentUser?.uid;
        var tasks = snapshot.data!.docs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          // Don't show the user's own tasks
          if (data['postedByUid'] == currentUid) return false;
          // Category filter
          if (_selectedCategory != 'All' && data['category'] != _selectedCategory) return false;
          // Filter expired tasks
          if (data['endTime'] != null && data['status'] == 'open') {
            final endTime = (data['endTime'] as Timestamp).toDate();
            if (endTime.isBefore(DateTime.now())) return false;
          }
          // Search filter
          if (_searchQuery.isNotEmpty) {
            final title = (data['title'] ?? '').toString().toLowerCase();
            final desc = (data['description'] ?? '').toString().toLowerCase();
            if (!title.contains(_searchQuery) && !desc.contains(_searchQuery)) return false;
          }
          return true;
        }).toList();

        // Apply sorting
        if (_selectedSort == 'Budget') {
          tasks.sort((a, b) {
            final priceA = ((a.data() as Map<String, dynamic>)['price'] ?? 0) as int;
            final priceB = ((b.data() as Map<String, dynamic>)['price'] ?? 0) as int;
            return priceB.compareTo(priceA); // High to low
          });
        } else if (_selectedSort == 'Newest') {
          tasks.sort((a, b) {
            final timeA = (a.data() as Map<String, dynamic>)['createdAt'] as Timestamp?;
            final timeB = (b.data() as Map<String, dynamic>)['createdAt'] as Timestamp?;
            if (timeA == null || timeB == null) return 0;
            return timeB.compareTo(timeA);
          });
        }

        if (tasks.isEmpty) {
          return Center(child: Text('No open tasks in $city matching your filters.'));
        }

        if (_showMap) {
          return _buildMapView(tasks);
        }

        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          itemCount: tasks.length,
          itemBuilder: (context, index) {
            final doc = tasks[index];
            final data = doc.data() as Map<String, dynamic>;
            final String taskId = doc.id;
            final List applicants = data['applicants'] ?? [];
            final bool hasApplied = applicants.contains(currentUid);
            final Timestamp? createdAt = data['createdAt'];

            return GestureDetector(
              onTap: () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => TaskDetailsScreen(taskId: taskId)));
              },
              child: Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.grey.withOpacity(0.1)),
                  boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.05), spreadRadius: 2, blurRadius: 10)],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.pastelPurple,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Icon(Icons.extension, color: AppColors.pastelPurpleIcon, size: 28),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(data['title'] ?? 'Task', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppColors.darkText)),
                              const SizedBox(height: 4),
                              FutureBuilder<DocumentSnapshot>(
                                future: FirebaseFirestore.instance.collection('users').doc(data['postedByUid']).get(),
                                builder: (context, posterSnapshot) {
                                  String posterName = data['postedByName'] ?? 'User';
                                  String initial = posterName.isNotEmpty ? posterName[0].toUpperCase() : 'U';
                                  double posterRating = 5.0;
                                  if (posterSnapshot.hasData && posterSnapshot.data!.exists) {
                                    final posterData = posterSnapshot.data!.data() as Map<String, dynamic>;
                                    posterName = posterData['fullName'] ?? posterName;
                                    initial = posterName.isNotEmpty ? posterName[0].toUpperCase() : 'U';
                                    // Mask name for privacy: show first 2 chars + asterisks
                                    if (posterName.length > 2) {
                                      posterName = '${posterName.substring(0, 2)}${'*' * (posterName.length - 2)}';
                                    }
                                    final rSum = (posterData['ratingSum'] ?? 0).toDouble();
                                    final rCount = posterData['ratingCount'] ?? 0;
                                    posterRating = rCount == 0 ? 5.0 : (rSum / rCount);
                                  }
                                  return Row(
                                    children: [
                                      CircleAvatar(radius: 8, backgroundColor: AppColors.primary, child: Text(initial, style: const TextStyle(color: Colors.white, fontSize: 10))),
                                      const SizedBox(width: 6),
                                      Text(posterName, style: const TextStyle(fontSize: 13, color: AppColors.greyText)),
                                      const SizedBox(width: 6),
                                      const Icon(Icons.star, color: Colors.orange, size: 12),
                                      Text(' ${posterRating.toStringAsFixed(1)}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.greyText)),
                                    ],
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Text('₹${data['price']}', style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w900, fontSize: 20)),
                        const SizedBox(width: 16),
                        const Icon(Icons.location_on_outlined, size: 14, color: AppColors.greyText),
                        const SizedBox(width: 4),
                        Text(data['city'] ?? city, style: const TextStyle(color: AppColors.greyText, fontSize: 13)),
                        const SizedBox(width: 16),
                        const Icon(Icons.access_time, size: 14, color: AppColors.greyText),
                        const SizedBox(width: 4),
                        Text(createdAt != null ? timeago.format(createdAt.toDate()) : '', style: const TextStyle(color: AppColors.greyText, fontSize: 13)),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Divider(color: Colors.grey.withOpacity(0.1), height: 1),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: hasApplied ? null : () => _showBidDialog(taskId, data['postedByUid'], data['title'], data['price']),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.primary,
                              side: BorderSide(color: hasApplied ? Colors.grey : AppColors.primary),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            ),
                            child: Text(hasApplied ? 'Applied' : 'Send Offer', style: const TextStyle(fontWeight: FontWeight.bold)),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: hasApplied ? null : () {
                              _db.applyForTask(taskId, data['postedByUid'], data['title'], data['price']);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Application submitted at full price!'), backgroundColor: AppColors.success),
                              );
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              disabledBackgroundColor: Colors.grey.shade300,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              elevation: 0,
                            ),
                            child: Text(hasApplied ? 'Applied' : 'Apply at Full Price', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildMapView(List<QueryDocumentSnapshot> tasks) {
    final initialPosition = const CameraPosition(
      target: LatLng(21.1702, 72.8311),
      zoom: 12,
    );

    final Set<Marker> markers = {};

    for (var doc in tasks) {
      final data = doc.data() as Map<String, dynamic>;
      double latOffset = (doc.id.hashCode % 100) / 2000.0 - 0.025;
      double lngOffset = ((doc.id.hashCode ~/ 100) % 100) / 2000.0 - 0.025;

      markers.add(Marker(
        markerId: MarkerId(doc.id),
        position: LatLng(21.1702 + latOffset, 72.8311 + lngOffset),
        infoWindow: InfoWindow(
          title: data['title'] ?? 'Task',
          snippet: '₹${data['price']} • ${data['category']}',
          onTap: () {
            Navigator.push(context, MaterialPageRoute(builder: (_) => TaskDetailsScreen(taskId: doc.id)));
          },
        ),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueViolet),
      ));
    }

    return ClipRRect(
      borderRadius: const BorderRadius.only(topLeft: Radius.circular(24), topRight: Radius.circular(24)),
      child: GoogleMap(
        initialCameraPosition: initialPosition,
        markers: markers,
        myLocationEnabled: true,
        myLocationButtonEnabled: true,
      ),
    );
  }
}
