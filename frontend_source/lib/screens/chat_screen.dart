import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../services/database_service.dart';
import '../utils/app_colors.dart';

class ChatScreen extends StatefulWidget {
  final String chatId;
  final String otherUid;
  final String otherName;

  const ChatScreen({
    super.key,
    required this.chatId,
    required this.otherUid,
    required this.otherName,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final DatabaseService _db = DatabaseService();
  final TextEditingController _msgController = TextEditingController();
  final String currentUid = FirebaseAuth.instance.currentUser?.uid ?? '';

  void _sendMessage() async {
    final text = _msgController.text.trim();
    if (text.isEmpty) return;

    _msgController.clear();
    await _db.sendMessage(widget.chatId, text, widget.otherUid);
  }

  @override
  void initState() {
    super.initState();
    _db.markChatAsRead(widget.chatId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(widget.otherName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _db.streamMessages(widget.chatId),
              builder: (context, snapshot) {
                if (snapshot.hasError) return Center(child: Text('Error: ${snapshot.error}'));
                if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                
                final messages = snapshot.data?.docs ?? [];
                
                return ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.all(16),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final msg = messages[index].data() as Map<String, dynamic>;
                    final bool isMe = msg['senderId'] == currentUid;
                    final time = msg['timestamp'] != null 
                        ? DateFormat('h:mm a').format((msg['timestamp'] as Timestamp).toDate()) 
                        : 'Sending...';

                    return Align(
                      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: isMe ? AppColors.primary : Colors.white,
                          borderRadius: BorderRadius.circular(20).copyWith(
                            bottomRight: isMe ? const Radius.circular(0) : const Radius.circular(20),
                            bottomLeft: !isMe ? const Radius.circular(0) : const Radius.circular(20),
                          ),
                          border: isMe ? null : Border.all(color: Colors.grey.withOpacity(0.2)),
                        ),
                        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                        child: Column(
                          crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                          children: [
                            Text(
                              msg['text'] ?? '',
                              style: TextStyle(color: isMe ? Colors.white : AppColors.darkText, fontSize: 15),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              time,
                              style: TextStyle(color: isMe ? Colors.white70 : Colors.grey, fontSize: 10),
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
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(color: Colors.grey.withOpacity(0.1), spreadRadius: 1, blurRadius: 10, offset: const Offset(0, -2))
              ],
            ),
            child: SafeArea(
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _msgController,
                      decoration: InputDecoration(
                        hintText: 'Type a message...',
                        hintStyle: TextStyle(color: Colors.grey.shade400),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        fillColor: AppColors.surface,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                      ),
                      textCapitalization: TextCapitalization.sentences,
                    ),
                  ),
                  const SizedBox(width: 12),
                  CircleAvatar(
                    backgroundColor: AppColors.primary,
                    radius: 24,
                    child: IconButton(
                      icon: const Icon(Icons.send, color: Colors.white, size: 20),
                      onPressed: _sendMessage,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
