import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import '../services/database_service.dart';
import '../services/hired_contacts.dart';
import '../utils/app_colors.dart';
import '../utils/language_provider.dart';
import '../utils/name_utils.dart';
import 'chat_screen.dart';

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  final DatabaseService _db = DatabaseService();
  final String currentUid = FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  Widget build(BuildContext context) {
    final s = context.watch<LanguageProvider>().strings;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(s.chatTitle, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _db.streamMyChats(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return Center(child: Text('Error: ${snapshot.error}'));
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.chat_bubble_outline, size: 64, color: Colors.grey.shade300),
                  const SizedBox(height: 16),
                  Text(s.chatEmpty, style: const TextStyle(color: Colors.grey, fontSize: 16)),
                ],
              ),
            );
          }

          final chats = snapshot.data!.docs;
          return ListView.separated(
            itemCount: chats.length,
            separatorBuilder: (context, index) => Divider(color: Colors.grey.shade200, height: 1),
            itemBuilder: (context, index) {
              final chatData = chats[index].data() as Map<String, dynamic>;
              final participants = List<String>.from(chatData['participants'] ?? []);
              final otherUid = participants.firstWhere((uid) => uid != currentUid, orElse: () => '');
              final unreadCounts = Map<String, dynamic>.from(chatData['unreadCounts'] ?? {});
              final myUnreadCount = (unreadCounts[currentUid] ?? 0) as int;
              
              if (otherUid.isEmpty) return const SizedBox.shrink();

              return FutureBuilder<DocumentSnapshot>(
                future: FirebaseFirestore.instance.collection('users').doc(otherUid).get(),
                builder: (context, userSnapshot) {
                  if (!userSnapshot.hasData) return const ListTile(title: Text('Loading...'));
                  final userData = userSnapshot.data!.data() as Map<String, dynamic>? ?? {};
                  final String otherName = userData['fullName'] ?? 'Unknown User';

                  // Privacy: full name only once a hire exists between you two.
                  return ListenableBuilder(
                    listenable: HiredContacts.instance,
                    builder: (context, _) {
                  final shownName = HiredContacts.instance.nameFor(otherUid, otherName);
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    leading: CircleAvatar(
                      backgroundColor: AppColors.primary.withOpacity(0.1),
                      child: Text(NameUtils.initial(shownName), style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
                    ),
                    title: Text(shownName, style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(
                      chatData['lastMessage'] ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: myUnreadCount > 0 ? FontWeight.bold : FontWeight.normal,
                        color: myUnreadCount > 0 ? AppColors.darkText : AppColors.greyText,
                      ),
                    ),
                    trailing: myUnreadCount > 0 
                      ? Container(
                          padding: const EdgeInsets.all(8),
                          decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                          child: Text(myUnreadCount.toString(), style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                        )
                      : null,
                    onTap: () {
                      _db.markChatAsRead(chats[index].id);
                      Navigator.push(context, MaterialPageRoute(
                        builder: (_) => ChatScreen(chatId: chats[index].id, otherUid: otherUid, otherName: otherName)
                      ));
                    },
                  );
                    },
                  );
                }
              );
            },
          );
        },
      ),
    );
  }
}
