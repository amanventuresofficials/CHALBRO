import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../utils/app_colors.dart';
import '../utils/name_utils.dart';
import '../services/database_service.dart';
import 'public_profile_screen.dart';
import 'task_applicants_screen.dart';
import '../widgets/payment_bottom_sheet.dart';
import '../widgets/report_sheet.dart';
import 'chat_screen.dart';
import 'package:intl/intl.dart';

class TaskDetailsScreen extends StatefulWidget {
  final String taskId;

  const TaskDetailsScreen({super.key, required this.taskId});

  @override
  State<TaskDetailsScreen> createState() => _TaskDetailsScreenState();
}

class _TaskDetailsScreenState extends State<TaskDetailsScreen> {
  final DatabaseService _db = DatabaseService();
  final String? currentUid = FirebaseAuth.instance.currentUser?.uid;

  void _showBidDialog(String posterUid, String taskTitle, int originalPrice) {
    final bidController = TextEditingController(text: originalPrice.toString());
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Apply for Task'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('The poster has budgeted ₹$originalPrice.'),
            const SizedBox(height: 12),
            const Text('Your Bid Price (₹):', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            TextField(
              controller: bidController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                prefixText: '₹ ',
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            onPressed: () async {
              int bidPrice = int.tryParse(bidController.text.trim()) ?? originalPrice;
              Navigator.pop(context); // close dialog before async call
              await _db.applyForTask(widget.taskId, posterUid, taskTitle, bidPrice);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Application submitted for ₹$bidPrice'), backgroundColor: AppColors.success),
                );
              }
            },
            child: const Text('Submit Application', style: TextStyle(color: Colors.white)),
          )
        ],
      ),
    );
  }

  void _showPayWorkerDialog(String workerUid, int originalPrice, Map<String, dynamic> bids) {
    final int agreedPrice = (bids[workerUid] as int?) ?? originalPrice;

    showPaymentBottomSheet(
      context: context,
      taskId: widget.taskId,
      workerUid: workerUid,
      amount: agreedPrice,
      onPaymentComplete: (success, message) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(message),
              backgroundColor: success ? AppColors.success : AppColors.red,
              duration: Duration(seconds: success ? 3 : 5),
            ),
          );
        }
      },
    );
  }

  /// Plain-words version of the stored task status.
  static String _statusLabel(String status) {
    switch (status) {
      case 'open':
        return 'OPEN';
      case 'pending_worker_acceptance':
        return 'WAITING FOR HELPER';
      case 'pending_poster_acceptance':
      case 'pending_acceptance':
        return 'WAITING FOR POSTER';
      case 'assigned':
        return 'IN PROGRESS';
      case 'completed':
        return 'COMPLETED';
      case 'expired':
        return 'EXPIRED';
      default:
        return status.replaceAll('_', ' ').toUpperCase();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        flexibleSpace: Container(
            decoration: const BoxDecoration(gradient: AppColors.primaryGradient)),
        title: const Text('Task Details', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('tasks').doc(widget.taskId).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            // A task that has been hired out is private to the poster and the
            // hired person; anyone else gets a permission error from Firestore.
            final err = snapshot.error;
            final bool noAccess = err is FirebaseException && err.code == 'permission-denied';
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(noAccess ? Icons.lock_outline : Icons.error_outline, size: 48, color: Colors.grey.shade400),
                    const SizedBox(height: 12),
                    Text(
                      noAccess ? 'This task is no longer available.' : 'Could not load this task. Please try again.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 16, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            );
          }
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());

          if (!snapshot.hasData || !snapshot.data!.exists) {
            return const Center(child: Text('Task not found.'));
          }

          final task = snapshot.data!.data() as Map<String, dynamic>;
          final String posterUid = task['postedByUid'] ?? '';
          final bool isMyTask = posterUid == currentUid;
          final String status = task['status'] ?? 'open';
          final applicants = List<String>.from(task['applicants'] ?? []);
          final bool hasApplied = applicants.contains(currentUid);
          final String acceptedByUid = task['acceptedByUid'] ?? '';
          final bool isAcceptedByMe = acceptedByUid == currentUid;
          final bool workerCompleted = task['workerCompleted'] ?? false;
          
          bool isExpired = false;
          if (task['endTime'] != null && status == 'open') {
            final endTime = (task['endTime'] as Timestamp).toDate();
            if (endTime.isBefore(DateTime.now())) isExpired = true;
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header / Title Card
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4)),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: AppColors.secondary,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              task['category'] ?? 'Task',
                              style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 12),
                            ),
                          ),
                          if (task['isUrgent'] == true)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: AppColors.red.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: const Text(
                                'URGENT',
                                style: TextStyle(color: AppColors.red, fontWeight: FontWeight.bold, fontSize: 12),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        task['title'] ?? '',
                        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.black87),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          const Icon(Icons.location_on_outlined, size: 16, color: Colors.grey),
                          const SizedBox(width: 4),
                          Text(task['city'] ?? 'Unknown City', style: const TextStyle(color: Colors.grey, fontSize: 14)),
                          const SizedBox(width: 16),
                          const Icon(Icons.access_time, size: 16, color: Colors.grey),
                          const SizedBox(width: 4),
                          Text(
                            task['createdAt'] != null ? DateFormat('MMM dd, yyyy').format((task['createdAt'] as Timestamp).toDate()) : '',
                            style: const TextStyle(color: Colors.grey, fontSize: 14),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8F9FE),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.withOpacity(0.2)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Budget', style: TextStyle(color: Colors.grey, fontSize: 12)),
                                const SizedBox(height: 4),
                                Text('₹${task['price']}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black87)),
                              ],
                            ),
                            const SizedBox(width: 12),
                            // Flexible + a readable label: raw values such as
                            // "PENDING_WORKER_ACCEPTANCE" are one long word and ran off the card.
                            Flexible(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  const Text('Status', style: TextStyle(color: Colors.grey, fontSize: 12)),
                                  const SizedBox(height: 4),
                                  Text(
                                    _statusLabel(status),
                                    textAlign: TextAlign.end,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: status == 'open' ? AppColors.primary : (status == 'completed' ? AppColors.success : Colors.orange),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Details Card
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4)),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Description', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87)),
                      const SizedBox(height: 12),
                      Text(
                        task['description'] ?? 'No description provided.',
                        style: const TextStyle(fontSize: 15, color: Colors.black54, height: 1.5),
                      ),
                      
                      if (task['startLocation'] != null || task['destinationLocation'] != null) ...[
                        const SizedBox(height: 20),
                        const Divider(),
                        const SizedBox(height: 16),
                        const Text('Location Details', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87)),
                        const SizedBox(height: 12),
                        if (task['startLocation'] != null)
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.my_location, color: AppColors.primary, size: 20),
                              const SizedBox(width: 8),
                              Expanded(child: Text('Start: ${task['startLocation']}', style: const TextStyle(fontSize: 14, color: Colors.black87))),
                            ],
                          ),
                        if (task['startLocation'] != null && task['destinationLocation'] != null)
                          const SizedBox(height: 8),
                        if (task['destinationLocation'] != null)
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.flag, color: AppColors.red, size: 20),
                              const SizedBox(width: 8),
                              Expanded(child: Text('Destination: ${task['destinationLocation']}', style: const TextStyle(fontSize: 14, color: Colors.black87))),
                            ],
                          ),
                      ],
                      if (task['imageUrl'] != null) ...[
                        const SizedBox(height: 20),
                        const Divider(),
                        const SizedBox(height: 16),
                        const Text('Attached Photo', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87)),
                        const SizedBox(height: 12),
                        GestureDetector(
                          onTap: () {
                            showDialog(
                              context: context,
                              builder: (_) => Dialog(
                                insetPadding: EdgeInsets.zero,
                                child: Stack(
                                  children: [
                                    InteractiveViewer(
                                      child: Image.network(
                                        task['imageUrl'],
                                        width: double.infinity,
                                        height: double.infinity,
                                        fit: BoxFit.contain,
                                      ),
                                    ),
                                    Positioned(
                                      top: 40,
                                      right: 16,
                                      child: IconButton(
                                        icon: const Icon(Icons.close, color: Colors.grey, size: 30),
                                        onPressed: () => Navigator.pop(context),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.network(
                              task['imageUrl'],
                              width: double.infinity,
                              height: 200,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Poster Info Card
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4)),
                    ],
                  ),
                  child: Row(
                    children: [
                      InkWell(
                        onTap: () {
                           Navigator.push(context, MaterialPageRoute(builder: (_) => PublicProfileScreen(targetUid: posterUid)));
                        },
                        child: const CircleAvatar(
                          radius: 24,
                          backgroundColor: AppColors.tertiary,
                          child: Icon(Icons.person, color: AppColors.primary, size: 28),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Posted by', style: TextStyle(color: Colors.grey, fontSize: 12)),
                            const SizedBox(height: 4),
                            Text(
                              isMyTask
                                  ? 'You'
                                  // Once you are the hired helper, you may see who you work for.
                                  : (isAcceptedByMe &&
                                          (status == 'assigned' || status == 'completed') &&
                                          '${task['postedByName'] ?? ''}'.trim().isNotEmpty)
                                      ? '${task['postedByName']}'.trim()
                                      : 'User-${posterUid.substring(0, 4).toUpperCase()}',
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
                        onPressed: () {
                          Navigator.push(context, MaterialPageRoute(builder: (_) => PublicProfileScreen(targetUid: posterUid)));
                        },
                      ),
                    ],
                  ),
                ),

                // The helper you hired: their full details are revealed only now.
                if (isMyTask && (status == 'assigned' || status == 'completed') && acceptedByUid.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _buildHiredHelperCard(acceptedByUid),
                ],

                const SizedBox(height: 32),

                // Dynamic Action Area
                if (isExpired)
                   const Center(
                     child: Text(
                       'This task has expired.',
                       style: TextStyle(color: AppColors.red, fontWeight: FontWeight.bold, fontSize: 16),
                     ),
                   )
                else if (status == 'open')
                  isMyTask
                    ? Column(
                        children: [
                          SizedBox(
                            width: double.infinity,
                            height: 54,
                            child: ElevatedButton(
                              onPressed: applicants.isEmpty ? null : () {
                                Map<String, dynamic> bids = task['bids'] ?? {};
                                Navigator.push(context, MaterialPageRoute(builder: (_) => TaskApplicantsScreen(taskId: widget.taskId, applicants: applicants, bids: bids)));
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                disabledBackgroundColor: Colors.grey.shade300,
                              ),
                              child: Text(
                                applicants.isEmpty ? 'Waiting for applicants...' : 'Review Applicants (${applicants.length})',
                                style: TextStyle(color: applicants.isEmpty ? Colors.grey.shade600 : Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            height: 54,
                            child: OutlinedButton(
                              onPressed: () async {
                                final confirm = await showDialog<bool>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                    title: const Text('Cancel Task?'),
                                    content: const Text('Are you sure you want to cancel and delete this task? This cannot be undone.'),
                                    actions: [
                                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No')),
                                      TextButton(
                                        onPressed: () => Navigator.pop(ctx, true),
                                        child: const Text('Cancel Task', style: TextStyle(color: AppColors.red)),
                                      ),
                                    ],
                                  ),
                                );
                                if (confirm == true && mounted) {
                                  await _db.deleteTask(widget.taskId);
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Task cancelled.')));
                                    Navigator.pop(context);
                                  }
                                }
                              },
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.red,
                                side: const BorderSide(color: AppColors.red),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              ),
                              child: const Text('Cancel Task', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                            ),
                          ),
                        ],
                      )
                    : SizedBox(
                        width: double.infinity,
                        height: 54,
                        child: ElevatedButton(
                          onPressed: hasApplied ? null : () => _showBidDialog(posterUid, task['title'] ?? '', task['price'] ?? 0),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                          child: Text(
                            hasApplied ? 'Application Submitted' : 'Apply for Task',
                            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                        ),
                      )
                else if (status == 'pending_acceptance')
                  isMyTask
                    ? Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(color: AppColors.tertiary, borderRadius: BorderRadius.circular(12)),
                        child: Column(
                          children: [
                            const Icon(Icons.access_time, color: AppColors.primary, size: 48),
                            const SizedBox(height: 12),
                            const Text('Offer Sent', style: TextStyle(color: AppColors.primary, fontSize: 16, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 8),
                            Text('Waiting for the helper to accept your offer of ₹${task['proposedPrice'] ?? task['price']}.', style: const TextStyle(color: Colors.black87, fontSize: 14), textAlign: TextAlign.center),
                          ],
                        ),
                      )
                    : (task['targetHelperUid'] == currentUid)
                        ? Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(color: AppColors.tertiary, borderRadius: BorderRadius.circular(12)),
                            child: Column(
                              children: [
                                const Icon(Icons.local_offer, color: AppColors.primary, size: 48),
                                const SizedBox(height: 12),
                                const Text('You Have an Offer!', style: TextStyle(color: AppColors.primary, fontSize: 16, fontWeight: FontWeight.bold)),
                                const SizedBox(height: 8),
                                Text('The poster has offered you ₹${task['proposedPrice'] ?? task['price']} to do this task.', style: const TextStyle(color: Colors.black87, fontSize: 14), textAlign: TextAlign.center),
                                const SizedBox(height: 16),
                                Row(
                                  children: [
                                    Expanded(
                                      child: OutlinedButton(
                                        onPressed: () async {
                                          await _db.declineProposedTask(widget.taskId);
                                          if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Offer declined.')));
                                        },
                                        style: OutlinedButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(vertical: 14),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                          side: const BorderSide(color: AppColors.red),
                                        ),
                                        child: const Text('Decline', style: TextStyle(color: AppColors.red, fontWeight: FontWeight.bold)),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: ElevatedButton(
                                        onPressed: () async {
                                          await _db.acceptProposedTask(widget.taskId);
                                          if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Offer accepted! You are now assigned.'), backgroundColor: AppColors.success));
                                        },
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: AppColors.success,
                                          padding: const EdgeInsets.symmetric(vertical: 14),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                        ),
                                        child: const Text('Accept', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          )
                        : const Center(
                            child: Text('This task is pending assignment to someone else.', style: TextStyle(color: Colors.grey, fontSize: 16)),
                          )
                else if (status == 'assigned')
                  isMyTask
                    ? Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(16),
                            margin: const EdgeInsets.only(bottom: 16),
                            decoration: BoxDecoration(
                              color: workerCompleted ? AppColors.success.withOpacity(0.1) : AppColors.tertiary,
                              borderRadius: BorderRadius.circular(12),
                              border: workerCompleted ? Border.all(color: AppColors.success) : null,
                            ),
                            child: Row(
                              children: [
                                Icon(workerCompleted ? Icons.check_circle : Icons.handshake, color: workerCompleted ? AppColors.success : AppColors.primary),
                                const SizedBox(width: 12),
                                Expanded(child: Text(
                                  workerCompleted 
                                      ? 'The worker has marked this task as DONE! Please pay them.'
                                      : 'Task is assigned. Once work is completed, please pay the worker.', 
                                  style: TextStyle(color: workerCompleted ? AppColors.success : AppColors.primary, fontWeight: FontWeight.bold)
                                )),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            height: 54,
                            child: ElevatedButton(
                              onPressed: () => _showPayWorkerDialog(acceptedByUid, task['price'] ?? 0, Map<String, dynamic>.from(task['bids'] ?? {})),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.success,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              ),
                              child: const Text(
                                'Pay Worker & Complete',
                                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            height: 54,
                            child: OutlinedButton.icon(
                              onPressed: () async {
                                final chatId = await _db.getOrCreateChat(acceptedByUid);
                                final workerDoc = await FirebaseFirestore.instance.collection('users').doc(acceptedByUid).get();
                                final workerName = workerDoc.data()?['fullName'] ?? 'Worker';
                                if (mounted) {
                                  Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(chatId: chatId, otherUid: acceptedByUid, otherName: workerName)));
                                }
                              },
                              icon: const Icon(Icons.chat_bubble_outline),
                              label: const Text('Chat with Worker'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.primary,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                side: const BorderSide(color: AppColors.primary),
                              ),
                            ),
                          ),
                        ],
                      )
                    : isAcceptedByMe
                        ? Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: AppColors.tertiary,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              children: [
                                Icon(workerCompleted ? Icons.check_circle : Icons.handyman, color: AppColors.primary, size: 48),
                                const SizedBox(height: 12),
                                Text(
                                  workerCompleted 
                                      ? 'You marked this task as done!' 
                                      : 'You have been assigned to this task!',
                                  style: const TextStyle(color: AppColors.primary, fontSize: 16, fontWeight: FontWeight.bold),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  workerCompleted 
                                      ? 'Waiting for the poster to confirm and pay you.'
                                      : 'Coordinate with the poster. Press the button below when you finish the work.',
                                  style: const TextStyle(color: Colors.black87, fontSize: 14),
                                  textAlign: TextAlign.center,
                                ),
                                if (!workerCompleted) ...[
                                  const SizedBox(height: 16),
                                  ElevatedButton(
                                    onPressed: () async {
                                      await _db.markTaskAsWorkerCompleted(widget.taskId);
                                    },
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.primary,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                    ),
                                    child: const Text('Mark as Done', style: TextStyle(color: Colors.white)),
                                  )
                                ],
                                const SizedBox(height: 12),
                                SizedBox(
                                  width: double.infinity,
                                  child: OutlinedButton.icon(
                                    onPressed: () async {
                                      final chatId = await _db.getOrCreateChat(posterUid);
                                      final posterDoc = await FirebaseFirestore.instance.collection('users').doc(posterUid).get();
                                      final pName = posterDoc.data()?['fullName'] ?? 'Poster';
                                      if (mounted) {
                                        Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(chatId: chatId, otherUid: posterUid, otherName: pName)));
                                      }
                                    },
                                    icon: const Icon(Icons.chat_bubble_outline),
                                    label: const Text('Chat with Poster'),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: AppColors.primary,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                      side: const BorderSide(color: AppColors.primary),
                                      padding: const EdgeInsets.symmetric(vertical: 12),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          )
                        : const Center(
                            child: Text(
                              'Task is assigned to someone else.',
                              style: TextStyle(color: Colors.grey, fontSize: 16),
                            ),
                          )
                else if (status == 'completed')
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppColors.success.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.success.withOpacity(0.3)),
                    ),
                    child: const Column(
                      children: [
                        Icon(Icons.verified, color: AppColors.success, size: 48),
                        SizedBox(height: 12),
                        Text(
                          'Task Completed Successfully',
                          style: TextStyle(color: AppColors.success, fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),

                const SizedBox(height: 32),

                // Anyone but the poster can flag this task for the admin team.
                if (!isMyTask && posterUid.isNotEmpty)
                  Center(
                    child: TextButton.icon(
                      onPressed: () => showReportSheet(
                        context,
                        targetType: 'task',
                        targetId: widget.taskId,
                        targetOwnerUid: posterUid,
                        targetTitle: (task['title'] ?? '').toString(),
                      ),
                      icon: const Icon(Icons.flag_outlined, size: 18),
                      label: const Text('Report this task'),
                      style: TextButton.styleFrom(foregroundColor: Colors.grey),
                    ),
                  ),

                // ---- TASK ACTIVITY LOG (Traceability) ----
                _buildTaskActivityLog(),

                const SizedBox(height: 40),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildHiredHelperCard(String helperUid) {
    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance.collection('users').doc(helperUid).get(),
      builder: (context, snap) {
        if (!snap.hasData || !snap.data!.exists) return const SizedBox.shrink();
        final u = snap.data!.data() as Map<String, dynamic>;
        final String name = u['fullName'] ?? 'Helper';
        final String skills = u['qualifications'] ?? 'Not specified';
        final String city = u['city'] ?? '';
        final double ratingSum = (u['ratingSum'] ?? 0).toDouble();
        final int ratingCount = u['ratingCount'] ?? 0;
        final double rating = ratingCount == 0 ? 5.0 : ratingSum / ratingCount;

        return GestureDetector(
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PublicProfileScreen(targetUid: helperUid))),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4)),
              ],
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: AppColors.tertiary,
                  child: Text(
                    NameUtils.initial(name),
                    style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 20),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Hired helper', style: TextStyle(color: Colors.grey, fontSize: 12)),
                      const SizedBox(height: 2),
                      Text(name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87)),
                      const SizedBox(height: 2),
                      Text(skills, style: const TextStyle(fontSize: 13, color: AppColors.primary)),
                      if (city.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Row(
                            children: [
                              const Icon(Icons.location_on_outlined, size: 13, color: Colors.grey),
                              const SizedBox(width: 2),
                              Text(city, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                Column(
                  children: [
                    const Icon(Icons.star, color: Colors.orange, size: 16),
                    Text(rating.toStringAsFixed(1), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTaskActivityLog() {
    return StreamBuilder<QuerySnapshot>(
      stream: _db.streamTaskLog(widget.taskId),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const SizedBox.shrink();
        }
        final logs = snapshot.data!.docs;
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2)),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: const [
                  Icon(Icons.timeline, size: 18, color: AppColors.primary),
                  SizedBox(width: 8),
                  Text('Activity Log', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87)),
                ],
              ),
              const SizedBox(height: 12),
              ...logs.map((doc) {
                final data = doc.data() as Map<String, dynamic>;
                final String action = data['action'] ?? '';
                final String details = data['details'] ?? '';
                final ts = data['timestamp'] as Timestamp?;
                final timeStr = ts != null ? DateFormat('MMM dd, hh:mm a').format(ts.toDate()) : 'just now';

                IconData icon;
                Color iconColor;
                switch (action) {
                  case 'task_created':
                    icon = Icons.add_circle_outline;
                    iconColor = AppColors.primary;
                    break;
                  case 'assigned':
                    icon = Icons.handshake_outlined;
                    iconColor = Colors.orange;
                    break;
                  case 'worker_marked_done':
                    icon = Icons.check_circle_outline;
                    iconColor = AppColors.success;
                    break;
                  case 'payment_completed':
                    icon = Icons.payment;
                    iconColor = AppColors.success;
                    break;
                  default:
                    icon = Icons.info_outline;
                    iconColor = Colors.grey;
                }

                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(icon, size: 18, color: iconColor),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              action.replaceAll('_', ' ').toUpperCase(),
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: iconColor),
                            ),
                            if (details.isNotEmpty)
                              Text(details, style: const TextStyle(fontSize: 12, color: Colors.black54)),
                          ],
                        ),
                      ),
                      Text(timeStr, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                    ],
                  ),
                );
              }).toList(),
            ],
          ),
        );
      },
    );
  }
}
