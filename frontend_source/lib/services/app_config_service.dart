import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../utils/app_info.dart';

/// Switches the owner controls from the admin panel's "App Settings" screen
/// (Firestore document metadata/appConfig). Every field has a harmless default, so
/// a missing document, a missing field or a failed read means "no restriction":
/// the app never locks itself out because of a configuration problem.
class AppConfig {
  final bool maintenanceMode;
  final String maintenanceMessage;
  final int minBuildNumber;
  final bool allowNewRegistrations;
  final int minTaskPrice; // 0 = no limit
  final int maxTaskPrice; // 0 = no limit

  const AppConfig({
    this.maintenanceMode = false,
    this.maintenanceMessage = '',
    this.minBuildNumber = 0,
    this.allowNewRegistrations = true,
    this.minTaskPrice = 0,
    this.maxTaskPrice = 0,
  });

  static const AppConfig defaults = AppConfig();

  factory AppConfig.fromMap(Map<String, dynamic>? d) {
    if (d == null) return defaults;
    int asInt(dynamic v) => v is num ? v.round() : (int.tryParse('$v') ?? 0);
    return AppConfig(
      maintenanceMode: d['maintenanceMode'] == true,
      maintenanceMessage: (d['maintenanceMessage'] ?? '').toString(),
      minBuildNumber: asInt(d['minBuildNumber']),
      allowNewRegistrations: d['allowNewRegistrations'] != false,
      minTaskPrice: asInt(d['minTaskPrice']),
      maxTaskPrice: asInt(d['maxTaskPrice']),
    );
  }

  /// True when the installed build is older than the owner's minimum. Never true
  /// on the web (a page reload is always the newest version) or when the build
  /// number could not be read.
  bool needsUpdate({int? build, bool isWeb = kIsWeb}) {
    final b = build ?? AppInfo.build;
    if (isWeb || b <= 0 || minBuildNumber <= 0) return false;
    return b < minBuildNumber;
  }

  /// Why [price] is not allowed, or null when it is fine.
  String? priceProblem(int price) {
    if (minTaskPrice > 0 && price < minTaskPrice) return 'The lowest price allowed for a task is ₹$minTaskPrice.';
    if (maxTaskPrice > 0 && price > maxTaskPrice) return 'The highest price allowed for a task is ₹$maxTaskPrice.';
    return null;
  }
}

/// Keeps the latest [AppConfig] in [config] while someone is signed in.
class AppConfigService {
  AppConfigService._();
  static final AppConfigService instance = AppConfigService._();

  final ValueNotifier<AppConfig> config = ValueNotifier<AppConfig>(AppConfig.defaults);
  StreamSubscription<DocumentSnapshot>? _sub;
  bool _started = false;

  /// Call once at start-up. Reading the document needs a signed-in user, so this
  /// follows sign-in and sign-out by itself.
  void start() {
    if (_started) return;
    _started = true;
    FirebaseAuth.instance.authStateChanges().listen((user) {
      _sub?.cancel();
      _sub = null;
      if (user == null) {
        config.value = AppConfig.defaults;
        return;
      }
      _sub = FirebaseFirestore.instance.collection('metadata').doc('appConfig').snapshots().listen(
        (snap) => config.value = AppConfig.fromMap(snap.data() as Map<String, dynamic>?),
        onError: (_) => config.value = AppConfig.defaults, // fail open
      );
    });
  }
}
