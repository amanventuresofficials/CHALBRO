import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../utils/app_colors.dart';
import '../services/database_service.dart';
import 'task_details_screen.dart';
import 'chat_screen.dart';
import 'public_profile_screen.dart';

class MyTasksScreen extends StatefulWidget {
  const MyTasksScreen({super.key});

  @override
  State<MyTasksScreen> createState() => _MyTasksScreenState();
}

class _MyTasksScreenState extends State<MyTasksScreen> {
  final DatabaseService _db = DatabaseService();
  String? _userCity;
  bool _showPosted = false;
  String _selectedSort = 'Newest';
  bool _isReady = false;

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _isReady = true);
    });

    _db.streamUserData().listen((doc) {
      if (doc.exists && mounted) {
        setState(() => _userCity = (doc.data() as Map<String, dynamic>)['city'] ?? "Surat");
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_userCity == null) {
      return const Scaffold(
        backgroundColor: AppColors.surface,
        body: Center(child: CircularProgressIndicator(color: AppColors.primary)),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'My Tasks',
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: AppColors.darkText),
                  ),
                  IconButton(
                    icon: const Icon(Icons.filter_list, color: AppColors.primary),
                    onPressed: _showSortBottomSheet,
                  ),
                ],
              ),
            ),
            _buildSegmentedControl(),
            const SizedBox(height: 16),
            Expanded(
              child: _showPosted ? _buildMyPostedTasks() : _buildMyWorkerTasks(),
            ),
          ],
        ),
      ),
    );
  }

  void _showSortBottomSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Sort By', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.darkText)),
                const SizedBox(height: 16),
                _buildSortOption('Newest'),
                _buildSortOption('Price (High to Low)'),
                _buildSortOption('Price (Low to High)'),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSortOption(String sortType) {
    return ListTile(
      title: Text(sortType, style: TextStyle(fontWeight: _selectedSort == sortType ? FontWeight.bold : FontWeight.normal)),
      trailing: _selectedSort == sortType ? const Icon(Icons.check, color: AppColors.primary) : null,
      onTap: () {
        setState(() => _selectedSort = sortType);
        Navigator.pop(context);
      },
    );
  }

  Widget _buildSegmentedControl() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20.0),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _showPosted = true),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: _showPosted ? Colors.white : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: _showPosted
                        ? [BoxShadow(color: Colors.grey.withOpacity(0.1), spreadRadius: 1, blurRadius: 4)]
                        : [],
                  ),
                  child: Center(
                    child: Text(
                      'Posted',
                      style: TextStyle(
                        color: _showPosted ? AppColors.primary : AppColors.greyText,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _showPosted = false),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: !_showPosted ? Colors.white : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: !_showPosted
                        ? [BoxShadow(color: Colors.grey.withOpacity(0.1), spreadRadius: 1, blurRadius: 4)]
                        : [],
                  ),
                  child: Center(
                    child: Text(
                      'I Applied/Accepted',
                      style: TextStyle(
                        color: !_showPosted ? AppColors.primary : AppColors.greyText,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(String message, String subMessage) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.description_outlined, size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(message, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.darkText)),
          const SizedBox(height: 8),
          Text(subMessage, style: const TextStyle(color: AppColors.greyText)),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () {
              // Usually handled by the main navigation, but we just trigger a state change or tab jump if needed.
              // For now, doing nothing as we can't easily jump from inside this tab's state.
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              elevation: 0,
            ),
            child: const Text('Post a Task', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          )
        ],
      ),
    );
  }

  Widget _buildMyPostedTasks() {
    if (!_isReady) return const Center(child: CircularProgressIndicator(color: AppColors.primary));

    return StreamBuilder<QuerySnapshot>(
      stream: _db.streamTasksIPosted(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: AppColors.primary));
        
        final List<QueryDocumentSnapshot> tasks = snapshot.hasData ? snapshot.data!.docs.toList() : [];
        _sortTasks(tasks);

        final activeTasks = tasks.where((doc) => (doc.data() as Map<String, dynamic>)['status'] != 'completed').toList();
        final completedTasks = tasks.where((doc) => (doc.data() as Map<String, dynamic>)['status'] == 'completed').toList();

        if (tasks.isEmpty) {
          return _buildEmptyState('No tasks here yet', 'Post your first task to get started');
        }

        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          children: [
            ...activeTasks.map((doc) => _buildTaskCard(doc.data() as Map<String, dynamic>, doc.id, isPosted: true)),
            if (completedTasks.isNotEmpty)
              ExpansionTile(
                initiallyExpanded: true,
                title: Text('Completed Tasks (${completedTasks.length})', style: const TextStyle(fontWeight: FontWeight.bold)),
                children: completedTasks.map((doc) => _buildTaskCard(doc.data() as Map<String, dynamic>, doc.id, isPosted: true)).toList(),
              ),
          ],
        );
      },
    );
  }

  Widget _buildMyWorkerTasks() {
    if (!_isReady) return const Center(child: CircularProgressIndicator(color: AppColors.primary));

    // Shows all tasks where the user is involved (applied, offered, or assigned)
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('tasks')
          .where('applicants', arrayContains: uid)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: AppColors.primary));
        
        final List<QueryDocumentSnapshot> allTasks = snapshot.hasData ? snapshot.data!.docs.toList() : [];
        _sortTasks(allTasks);

        // Filter out tasks assigned to SOMEONE ELSE
        final tasks = allTasks.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          if (data['status'] == 'assigned' || data['status'] == 'completed') {
            return data['acceptedByUid'] == uid;
          }
          return true;
        }).toList();

        final activeTasks = tasks.where((doc) => (doc.data() as Map<String, dynamic>)['status'] != 'completed').toList();
        final completedTasks = tasks.where((doc) => (doc.data() as Map<String, dynamic>)['status'] == 'completed').toList();

        if (tasks.isEmpty) {
          return _buildEmptyState('No tasks yet', 'Find nearby tasks to help with');
        }

        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          children: [
            ...activeTasks.map((doc) => _buildTaskCard(doc.data() as Map<String, dynamic>, doc.id, isPosted: false)),
            if (completedTasks.isNotEmpty)
              ExpansionTile(
                initiallyExpanded: true,
                title: Text('Completed Tasks (${completedTasks.length})', style: const TextStyle(fontWeight: FontWeight.bold)),
                children: completedTasks.map((doc) => _buildTaskCard(doc.data() as Map<String, dynamic>, doc.id, isPosted: false)).toList(),
              ),
          ],
        );
      },
    );
  }

  Widget _buildTaskCard(Map<String, dynamic> task, String taskId, {required bool isPosted}) {
    final String status = task['status'] ?? 'open';
    Color statusColor;
    switch (status) {
      case 'assigned': statusColor = AppColors.success; break;
      case 'completed': statusColor = Colors.blue; break;
      case 'pending_worker_acceptance': statusColor = AppColors.warning; break;
      case 'pending_poster_acceptance': statusColor = AppColors.warning; break;
      case 'expired': statusColor = Colors.grey; break;
      default: statusColor = AppColors.primary;
    }

    return GestureDetector(
      onTap: () {
        Navigator.push(context, MaterialPageRoute(builder: (_) => TaskDetailsScreen(taskId: taskId)));
      },
      onLongPress: isPosted && status == 'open' ? () async {
        final confirm = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text('Delete Task?'),
            content: Text('Are you sure you want to delete "${task['title']}"? This cannot be undone.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Delete', style: TextStyle(color: AppColors.red)),
              ),
            ],
          ),
        );
        if (confirm == true && mounted) {
          await _db.deleteTask(taskId);
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Task deleted.')));
        }
      } : null,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.withOpacity(0.1)),
          boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.05), spreadRadius: 1, blurRadius: 5)],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.assignment, color: statusColor, size: 24),
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
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              task['category'] ?? 'Task',
                              style: const TextStyle(color: AppColors.primary, fontSize: 10, fontWeight: FontWeight.bold),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: statusColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              status.toUpperCase().replaceAll('_', ' '),
                              style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.bold),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text('₹${task['price']}', style: const TextStyle(color: AppColors.greyText, fontSize: 12)),
                        ],
                      ),
                      if (isPosted && status == 'open')
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text('Long press to delete', style: TextStyle(fontSize: 10, color: Colors.grey.shade400)),
                        ),
                    ],
                  ),
                ),
                const Icon(Icons.arrow_forward_ios, size: 14, color: AppColors.greyText),
              ],
            ),
            
            // ACTION BUTTONS SECTION
            if (!isPosted && status == 'open') ...[
               const SizedBox(height: 12),
               SizedBox(
                 height: 36,
                 child: OutlinedButton.icon(
                   onPressed: () async {
                     final chatId = await _db.getOrCreateChat(task['postedByUid']);
                     if (context.mounted) {
                       Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(chatId: chatId, otherUid: task['postedByUid'], otherName: "Poster")));
                     }
                   },
                   icon: const Icon(Icons.chat_bubble_outline, size: 16),
                   label: const Text('Chat with Poster'),
                   style: OutlinedButton.styleFrom(
                     foregroundColor: AppColors.primary,
                     side: const BorderSide(color: AppColors.primary),
                     shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                   ),
                 ),
               ),
            ],
            
            if ((!isPosted && status == 'pending_worker_acceptance') || 
                (isPosted && status == 'pending_poster_acceptance')) ...[
               const SizedBox(height: 12),
               Text('Proposed Price: ₹${task['proposedPrice']}', style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.darkText)),
               const SizedBox(height: 8),
               Wrap(
                 spacing: 8,
                 runSpacing: 8,
                 children: [
                   SizedBox(
                     height: 36,
                     child: ElevatedButton(
                       onPressed: () async {
                         await _db.acceptProposedTask(taskId, isPosterAccepting: isPosted);
                         if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Offer Accepted!'), backgroundColor: AppColors.success));
                       },
                       style: ElevatedButton.styleFrom(backgroundColor: AppColors.success),
                       child: const Text('Accept', style: TextStyle(color: Colors.white)),
                     ),
                   ),
                   SizedBox(
                     height: 36,
                     child: OutlinedButton(
                       onPressed: () => _showReviseDialog(taskId, task['proposedPrice'], !isPosted),
                       style: OutlinedButton.styleFrom(foregroundColor: AppColors.primary, side: const BorderSide(color: AppColors.primary)),
                       child: const Text('Revise'),
                     ),
                   ),
                   SizedBox(
                     height: 36,
                     child: OutlinedButton(
                       onPressed: () async {
                         await _db.declineProposedTask(taskId, isPosterDeclining: isPosted);
                         if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Offer Declined.', style: TextStyle(color: Colors.white)), backgroundColor: AppColors.red));
                       },
                       style: OutlinedButton.styleFrom(foregroundColor: AppColors.red, side: const BorderSide(color: AppColors.red)),
                       child: const Text('Decline'),
                     ),
                   ),
                 ],
               ),
            ],
          ],
        ),
      ),
    );
  }
  void _showReviseDialog(String taskId, int currentProposed, bool isWorkerRevise) {
    final priceController = TextEditingController(text: currentProposed.toString());
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Revise Price'),
        content: TextField(
          controller: priceController,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(prefixText: '₹ ', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              int newPrice = int.tryParse(priceController.text.trim()) ?? currentProposed;
              Navigator.pop(ctx);
              await _db.reviseTaskPrice(taskId, newPrice, isWorkerRevise: isWorkerRevise);
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            child: const Text('Send Offer', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _sortTasks(List<QueryDocumentSnapshot> tasks) {
    if (_selectedSort == 'Price (High to Low)') {
      tasks.sort((a, b) => ((b.data() as Map<String, dynamic>)['price'] ?? 0).compareTo((a.data() as Map<String, dynamic>)['price'] ?? 0));
    } else if (_selectedSort == 'Price (Low to High)') {
      tasks.sort((a, b) => ((a.data() as Map<String, dynamic>)['price'] ?? 0).compareTo((b.data() as Map<String, dynamic>)['price'] ?? 0));
    } else {
      // Default: Newest (Timestamp descending)
      tasks.sort((a, b) {
        final dataA = a.data() as Map<String, dynamic>;
        final dataB = b.data() as Map<String, dynamic>;
        Timestamp? tA = dataA['createdAt'];
        Timestamp? tB = dataB['createdAt'];
        if (tA == null && tB == null) return 0;
        if (tA == null) return 1;
        if (tB == null) return -1;
        return tB.compareTo(tA);
      });
    }
  }
}
