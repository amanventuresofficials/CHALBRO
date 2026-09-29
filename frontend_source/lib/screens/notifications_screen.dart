import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../services/database_service.dart';
import '../utils/app_colors.dart';
import '../utils/language_provider.dart';
import 'task_details_screen.dart';

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final DatabaseService dbService = DatabaseService();
    final s = context.watch<LanguageProvider>().strings;

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        flexibleSpace: Container(
          decoration: const BoxDecoration(gradient: AppColors.primaryGradient),
        ),
        title: Text(s.notificationsTitle, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: dbService.streamMyNotifications(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text(s.notificationsError));
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.notifications_off_outlined, size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  Text(s.notificationsEmpty, style: const TextStyle(color: Colors.grey, fontSize: 16)),
                ],
              ),
            );
          }

          final docs = snapshot.data!.docs;

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final doc = docs[index];
              final data = doc.data() as Map<String, dynamic>;
              
              final String title = data['title'] ?? 'Notification';
              final String message = data['message'] ?? '';
              final bool isRead = data['isRead'] ?? false;
              final Timestamp? createdAt = data['createdAt'];
              
              String timeStr = '';
              if (createdAt != null) {
                timeStr = timeago.format(createdAt.toDate());
              }

              return InkWell(
                onTap: () async {
                  // Mark as read (delete)
                  dbService.markNotificationRead(doc.id);

                  // BUG-02 FIX: Navigate to task details if taskId exists
                  final String? taskId = data['taskId'];
                  if (taskId != null && taskId.isNotEmpty && !taskId.startsWith('debug_')) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => TaskDetailsScreen(taskId: taskId),
                      ),
                    );
                  }
                },
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  decoration: BoxDecoration(
                    color: isRead ? Colors.white : AppColors.tertiary,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isRead ? Colors.grey.shade200 : AppColors.secondary,
                    ),
                  ),
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: isRead ? Colors.grey.shade100 : AppColors.primary.withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.notifications_active,
                          color: isRead ? Colors.grey : AppColors.primary,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: TextStyle(
                                fontWeight: isRead ? FontWeight.normal : FontWeight.bold,
                                fontSize: 16,
                                color: isRead ? Colors.black87 : Colors.black,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              message,
                              style: TextStyle(
                                color: isRead ? Colors.grey.shade600 : Colors.black87,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              timeStr,
                              style: const TextStyle(color: Colors.grey, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      if (!isRead)
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
