import 'package:cloud_firestore/cloud_firestore.dart';

class ChatSession {
  final String id;
  final List<String> participants;
  final String lastMessage;
  final Timestamp? lastMessageTime;
  final Map<String, dynamic> unreadCounts;

  ChatSession({
    required this.id,
    required this.participants,
    required this.lastMessage,
    this.lastMessageTime,
    required this.unreadCounts,
  });

  factory ChatSession.fromMap(String id, Map<String, dynamic> data) {
    return ChatSession(
      id: id,
      participants: List<String>.from(data['participants'] ?? []),
      lastMessage: data['lastMessage'] ?? '',
      lastMessageTime: data['lastMessageTime'] as Timestamp?,
      unreadCounts: Map<String, dynamic>.from(data['unreadCounts'] ?? {}),
    );
  }
}

class ChatMessage {
  final String id;
  final String senderId;
  final String text;
  final Timestamp? timestamp;

  ChatMessage({
    required this.id,
    required this.senderId,
    required this.text,
    this.timestamp,
  });

  factory ChatMessage.fromMap(String id, Map<String, dynamic> data) {
    return ChatMessage(
      id: id,
      senderId: data['senderId'] ?? '',
      text: data['text'] ?? '',
      timestamp: data['timestamp'] as Timestamp?,
    );
  }
}
