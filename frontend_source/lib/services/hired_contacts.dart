import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../utils/name_utils.dart';

/// Tracks which other users the signed-in user has hired, or been hired by
/// (a task that is assigned or completed between the two of them).
///
/// A person's personal details (full name, skills, city) are shown to someone
/// else only while such a hire exists; before that only the first name is shown.
class HiredContacts extends ChangeNotifier {
  HiredContacts._();
  static final HiredContacts instance = HiredContacts._();

  static const _hiredStatuses = {'assigned', 'completed'};

  final Set<String> _workersIHired = {};
  final Set<String> _postersWhoHiredMe = {};
  StreamSubscription<QuerySnapshot>? _postedSub;
  StreamSubscription<QuerySnapshot>? _workedSub;
  StreamSubscription<User?>? _authSub;
  String? _uid;

  /// Safe to call repeatedly; follows sign-in / sign-out automatically.
  void start() {
    _authSub ??= FirebaseAuth.instance.authStateChanges().listen(_onUserChanged);
    _onUserChanged(FirebaseAuth.instance.currentUser);
  }

  void _onUserChanged(User? user) {
    if (user?.uid == _uid) return;
    _postedSub?.cancel();
    _workedSub?.cancel();
    final hadData = _workersIHired.isNotEmpty || _postersWhoHiredMe.isNotEmpty;
    _workersIHired.clear();
    _postersWhoHiredMe.clear();
    _uid = user?.uid;
    if (hadData) notifyListeners();
    if (user == null) return;

    final tasks = FirebaseFirestore.instance.collection('tasks');

    _postedSub = tasks.where('postedByUid', isEqualTo: user.uid).snapshots().listen(
      (snap) {
        final hired = <String>{};
        for (final doc in snap.docs) {
          final data = doc.data();
          final accepted = data['acceptedByUid'];
          if (accepted is String && accepted.isNotEmpty && _hiredStatuses.contains(data['status'])) {
            hired.add(accepted);
          }
        }
        if (!setEquals(hired, _workersIHired)) {
          _workersIHired
            ..clear()
            ..addAll(hired);
          notifyListeners();
        }
      },
      onError: (e) => debugPrint('HiredContacts posted stream: $e'),
    );

    _workedSub = tasks.where('acceptedByUid', isEqualTo: user.uid).snapshots().listen(
      (snap) {
        final posters = <String>{};
        for (final doc in snap.docs) {
          final data = doc.data();
          final poster = data['postedByUid'];
          if (poster is String && poster.isNotEmpty && _hiredStatuses.contains(data['status'])) {
            posters.add(poster);
          }
        }
        if (!setEquals(posters, _postersWhoHiredMe)) {
          _postersWhoHiredMe
            ..clear()
            ..addAll(posters);
          notifyListeners();
        }
      },
      onError: (e) => debugPrint('HiredContacts worked stream: $e'),
    );
  }

  /// True for yourself, and for anyone you have hired or been hired by.
  bool canSeeDetails(String otherUid) =>
      otherUid == _uid || _workersIHired.contains(otherUid) || _postersWhoHiredMe.contains(otherUid);

  /// Full name once hired (or for yourself), otherwise just the first name.
  String nameFor(String otherUid, String fullName) =>
      canSeeDetails(otherUid) ? fullName : NameUtils.firstName(fullName);
}
