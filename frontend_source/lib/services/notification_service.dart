import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'error_logger.dart';

class NotificationService {
  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // Initialize notifications
  Future<void> init() async {
    // Web push needs a service worker + VAPID key; not set up for the web build.
    if (kIsWeb) return;

    // 1. Request Permission
    NotificationSettings settings = await _firebaseMessaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      debugPrint('User granted notification permission');
      
      // 2. Get the token and save it
      final token = await _firebaseMessaging.getToken();
      if (token != null) {
        await saveTokenToDatabase(token);
      }

      // 3. Listen to token updates
      _firebaseMessaging.onTokenRefresh.listen(saveTokenToDatabase);
    } else {
      debugPrint('User declined or has not accepted permission');
    }
  }

  // Save token to Firestore
  Future<void> saveTokenToDatabase(String token) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    try {
      await _db.collection('users').doc(uid).set({
        'fcmTokens': FieldValue.arrayUnion([token]),
      }, SetOptions(merge: true));
      debugPrint('FCM Token saved: $token');
    } catch (e, st) {
      debugPrint('Failed to save FCM token: $e');
      ErrorLogger.instance.log(
          error: e, stack: st, category: 'database', severity: 'warning', context: 'Save push-notification token');
    }
  }
}
