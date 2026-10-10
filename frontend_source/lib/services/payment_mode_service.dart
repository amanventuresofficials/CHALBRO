import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Keeps track of the owner's Razorpay switch (metadata/paymentConfig.useRazorpay) so the
/// wallet, home and profile screens can show the REAL balance while Razorpay is on and
/// the practice balance while it is off. Anything unreadable counts as "off".
class PaymentModeService {
  PaymentModeService._();
  static final PaymentModeService instance = PaymentModeService._();

  final ValueNotifier<bool> razorpayOn = ValueNotifier<bool>(false);
  StreamSubscription<DocumentSnapshot>? _sub;
  bool _started = false;

  /// Call once at start-up; it follows sign-in and sign-out by itself.
  void start() {
    if (_started) return;
    _started = true;
    FirebaseAuth.instance.authStateChanges().listen((user) {
      _sub?.cancel();
      _sub = null;
      if (user == null) {
        razorpayOn.value = false;
        return;
      }
      _sub = FirebaseFirestore.instance.collection('metadata').doc('paymentConfig').snapshots().listen(
        (snap) => razorpayOn.value = (snap.data() as Map<String, dynamic>?)?['useRazorpay'] == true,
        onError: (_) => razorpayOn.value = false,
      );
    });
  }
}
