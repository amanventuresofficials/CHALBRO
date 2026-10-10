import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import '../utils/payment_amounts.dart';
import '../utils/picked_image.dart';
import 'error_logger.dart';
import '../utils/withdrawal.dart';

/// Outcome of sending a report (see [DatabaseService.submitReport]).
enum WithdrawResult { sent, notAvailable, notEnough, badAmount, badUpi, failed }

enum ReportResult { sent, alreadyReported, failed }

class DatabaseService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // ── PERFORMANCE: Static city list cache ──────────────────────────────────
  // getCities() fetches a rarely-changing metadata document. Cache it for the
  // lifetime of the app session so it is only read from Firestore once.
  static List<String>? _citiesCache;

  // --- USER PROFILE METHODS ---
  Future<bool> checkUserProfileExists() async {
    final user = _auth.currentUser;
    if (user == null) return false;
    final doc = await _db.collection('users').doc(user.uid).get();
    return doc.exists;
  }

  Future<bool> saveUserProfile({
    required String fullName,
    required String phone,
    required String gender,
    required String city,
    String? idProofStatus,
    String? qualifications,
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return false;

      // ── PERFORMANCE: Avoid double-read ─────────────────────────────────
      // Check for the 'createdAt' field to detect first-ever saves without
      // an extra get(); we only need one get() here.
      final existingDoc = await _db.collection('users').doc(user.uid).get();
      final existingData = existingDoc.data() as Map<String, dynamic>?;
      final isNewProfile = !existingDoc.exists || existingData?.containsKey('createdAt') != true;

      await _db.collection('users').doc(user.uid).set({
        'uid': user.uid,
        'email': user.email,
        'fullName': fullName,
        'phone': phone,
        'gender': gender,
        'city': city,
        'idProofStatus': idProofStatus ?? 'Pending Verification',
        'qualifications': qualifications ?? 'Not specified',
        'updatedAt': FieldValue.serverTimestamp(),
        // Initialize economy & helper stats only on first-ever profile save
        if (isNewProfile) ...{
          'createdAt': FieldValue.serverTimestamp(),
          'walletBalance': 500, // practice credit; the real balance starts at 0 and only Razorpay earnings raise it
          'ratingSum': 0.0,
          'ratingCount': 0,
          'tasksDone': 0,
          'isOpenForWork': false, // Default to NOT visible in Find Helpers
        }
      }, SetOptions(merge: true));
      return true;
    } catch (e, st) {
      ErrorLogger.instance.log(error: e, stack: st, category: 'database', context: 'Save profile');
      return false;
    }
  }


  /// Records that the user has accepted the Terms & Conditions.
  /// Called from TermsScreen. Writes termsAccepted + timestamp to Firestore.
  Future<void> acceptTerms() async {
    final user = _auth.currentUser;
    if (user == null) return;
    await _db.collection('users').doc(user.uid).set({
      'termsAccepted': true,
      'termsAcceptedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  // Toggle "Open for Work" status.
  Future<void> toggleOpenForWork(bool isOpen) async {
    final user = _auth.currentUser;
    if (user != null) {
      await _db
          .collection('users')
          .doc(user.uid)
          .set({'isOpenForWork': isOpen}, SetOptions(merge: true));
    }
  }

  /// Toggles whether this user is hidden from the Find Helpers search results.
  Future<void> setHiddenFromSearch(bool isHidden) async {
    final user = _auth.currentUser;
    if (user != null) {
      await _db
          .collection('users')
          .doc(user.uid)
          .set({'isHiddenFromSearch': isHidden}, SetOptions(merge: true));
    }
  }

  /// Opt in or out of the public leaderboard.
  /// When opted in AND tasksDone > 0, the user's full name shows on the leaderboard.
  Future<void> setLeaderboardOptIn(bool optIn) async {
    final user = _auth.currentUser;
    if (user != null) {
      await _db
          .collection('users')
          .doc(user.uid)
          .set({'leaderboardOptIn': optIn}, SetOptions(merge: true));
    }
  }

  Future<String?> uploadProfilePhoto(PickedImage image) async {
    final user = _auth.currentUser;
    if (user == null) return null;
    try {
      final storageRef = FirebaseStorage.instance
          .ref()
          .child('profile_photos')
          .child('${user.uid}.jpg');
      final uploadTask = await storageRef.putData(
          image.bytes, SettableMetadata(contentType: image.mimeType));
      final url = await uploadTask.ref.getDownloadURL();
      await _db.collection('users').doc(user.uid).update({'profilePhotoUrl': url});
      return url;
    } catch (e, st) {
      debugPrint('Error uploading profile photo: $e');
      ErrorLogger.instance.log(error: e, stack: st, category: 'database', context: 'Upload profile photo');
      return null;
    }
  }

  Future<String?> uploadIdProof(PickedImage image) async {
    final user = _auth.currentUser;
    if (user == null) return null;
    try {
      final storageRef = FirebaseStorage.instance
          .ref()
          .child('id_proofs')
          .child('${user.uid}.${image.extension}');
      final uploadTask = await storageRef.putData(
          image.bytes, SettableMetadata(contentType: image.mimeType));
      final url = await uploadTask.ref.getDownloadURL();
      await _db.collection('users').doc(user.uid).update({
        'idProofUrl': url,
        'idProofStatus': 'Pending Verification',
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return url;
    } catch (e, st) {
      debugPrint('Error uploading ID proof: $e');
      ErrorLogger.instance.log(error: e, stack: st, category: 'database', context: 'Upload ID proof');
      return null;
    }
  }

  Stream<DocumentSnapshot> streamUserData() {
    final user = _auth.currentUser;
    if (user == null) return const Stream.empty();
    return _db.collection('users').doc(user.uid).snapshots().logErrors('Live: my profile');
  }

  // --- HELPER STREAM ---
  // Stream users who have toggled "Open for Work" to true in the same city.
  // Limited to 50 results to prevent unbounded reads in large cities.
  // NOTE: isHiddenFromSearch is checked client-side (not in the query) because
  // existing users may not have this field, causing Firestore to exclude them.
  Stream<QuerySnapshot> streamAvailableHelpers(String city) {
    return _db
        .collection('users')
        .where('city', isEqualTo: city)
        .where('isOpenForWork', isEqualTo: true)
        .limit(50)
        .snapshots()
        .logErrors('Live: helpers in my city');
  }

// Replace your existing postTask method with this:
  Future<bool> postTask({
    required String title,
    required String description,
    required int price,
    required String category,
    required String city,
    required String postedByName,
    bool isUrgent = false,
    String? targetHelperUid,
    String? startLocation,
    String? destinationLocation,
    required DateTime endTime,
    PickedImage? image, // Optional task photo
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return false;

      String? imageUrl;
      if (image != null) {
        try {
          final storageRef = FirebaseStorage.instance
              .ref()
              .child('task_images')
              .child('${DateTime.now().millisecondsSinceEpoch}_${user.uid}.jpg');
          final uploadTask = await storageRef.putData(
              image.bytes, SettableMetadata(contentType: image.mimeType));
          imageUrl = await uploadTask.ref.getDownloadURL();
        } catch (e, st) {
          // If storage fails, log it but don't set a fake URL
          debugPrint('Error uploading task image: $e');
          ErrorLogger.instance.log(
              error: e, stack: st, category: 'database', severity: 'warning', context: 'Upload task photo');
        }
      }
      // imageUrl stays null if no file was picked — tasks without images show a default icon in UI

      final docRef = await _db.collection('tasks').add({
        'postedByUid': user.uid,
        'postedByName': postedByName,
        'title': title,
        'description': description,
        'price': price,
        'category': category,
        'city': city,
        'isUrgent': isUrgent,
        'status': 'open',
        'targetHelperUid': targetHelperUid,
        if (startLocation != null && startLocation.isNotEmpty) 'startLocation': startLocation,
        if (destinationLocation != null && destinationLocation.isNotEmpty) 'destinationLocation': destinationLocation,
        if (imageUrl != null) 'imageUrl': imageUrl,
        'createdAt': FieldValue.serverTimestamp(),
        'endTime': Timestamp.fromDate(endTime),
        'applicants': [],
        'bids': {},
      });

      // Log task creation for traceability
      await _logTaskActivity(
        taskId: docRef.id,
        action: 'task_created',
        actorUid: user.uid,
        details: 'Task "$title" posted in $city for ₹$price. Urgent: $isUrgent. Ends: ${endTime.toIso8601String()}',
      );

      // NEW: Send Notification if a specific helper is targeted
      if (targetHelperUid != null) {
        // Extract up to the first 2 words of the poster's name
        List<String> nameParts = postedByName.split(' ');
        String shortName = nameParts.take(2).join(' ');

        await _db
            .collection('users')
            .doc(targetHelperUid)
            .collection('notifications')
            .add({
          'fromUid': user.uid,
          'taskId': docRef.id,
          'title': 'New Direct Request',
          'message':
              '$shortName posted u work accept or reject', // The exact string you requested
          'createdAt': FieldValue.serverTimestamp(),
          'isRead': false,
        });
      } else if (isUrgent) {
        // Query users in the same city who are open for work
        final querySnapshot = await _db
            .collection('users')
            .where('city', isEqualTo: city)
            .where('isOpenForWork', isEqualTo: true)
            .get();

        WriteBatch batch = _db.batch();
        for (var doc in querySnapshot.docs) {
          if (doc.id != user.uid) { // Don't notify the poster themselves
            final notifRef = _db
                .collection('users')
                .doc(doc.id)
                .collection('notifications')
                .doc();
            
            batch.set(notifRef, {
              'fromUid': user.uid,
              'taskId': docRef.id,
              'title': 'Urgent Task Available!',
              'message': 'A new urgent $category task was posted in your city.',
              'createdAt': FieldValue.serverTimestamp(),
              'isRead': false,
            });
          }
        }
        await batch.commit();
      }

      return true;
    } catch (e, st) {
      ErrorLogger.instance.log(error: e, stack: st, category: 'database', context: 'Post task');
      return false;
    }
  }

  Future<void> applyForTask(String taskId, String posterUid, String taskTitle, int bidPrice) async {
    final user = _auth.currentUser;
    if (user == null) return;
    
    // Add to applicants array and save bid price
    await _db.collection('tasks').doc(taskId).update({
      'applicants': FieldValue.arrayUnion([user.uid]),
      'bids.${user.uid}': bidPrice,
    });

    // Notify the poster
    await _db
        .collection('users')
        .doc(posterUid)
        .collection('notifications')
        .add({
      'fromUid': user.uid,
      'taskId': taskId,
      'title': 'New Applicant!',
      'message': 'A helper has applied for your task: $taskTitle for ₹$bidPrice',
      'createdAt': FieldValue.serverTimestamp(),
      'isRead': false,
    });
  }

  Future<void> proposeTask(String taskId, String helperUid, int proposedPrice) async {
    final posterUid = _auth.currentUser?.uid;
    if (posterUid == null) return;

    final taskDoc = await _db.collection('tasks').doc(taskId).get();
    final taskTitle = (taskDoc.data() as Map<String, dynamic>?)?['title'] ?? 'A task';

    await _db.collection('tasks').doc(taskId).update({
      'status': 'pending_worker_acceptance',
      'targetHelperUid': helperUid,
      'applicants': FieldValue.arrayUnion([helperUid]), // Add to applicants so it shows in worker's My Tasks
      'proposedPrice': proposedPrice,
      'proposedAt': FieldValue.serverTimestamp(),
    });

    await _logTaskActivity(
      taskId: taskId,
      action: 'proposed',
      actorUid: posterUid,
      details: 'Task proposed to helper $helperUid for ₹$proposedPrice',
    );

    await _db
        .collection('users')
        .doc(helperUid)
        .collection('notifications')
        .add({
      'fromUid': posterUid,
      'taskId': taskId,
      'title': 'New Task Offer!',
      'message': 'You were offered to do "$taskTitle" for ₹$proposedPrice. Accept or Decline.',
      'createdAt': FieldValue.serverTimestamp(),
      'isRead': false,
      'type': 'task_proposed',
    });
  }

  Future<void> acceptProposedTask(String taskId, {bool isPosterAccepting = false}) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    final taskDoc = await _db.collection('tasks').doc(taskId).get();
    final taskData = taskDoc.data() as Map<String, dynamic>?;
    if (taskData == null) return;

    final posterUid = taskData['postedByUid'];
    final proposedPrice = taskData['proposedPrice'] ?? taskData['price'];
    final taskTitle = taskData['title'] ?? 'A task';

    final helperUid = isPosterAccepting ? taskData['targetHelperUid'] : uid;
    
    await _db.collection('tasks').doc(taskId).update({
      'status': 'assigned',
      'acceptedByUid': helperUid,
      'assignedAt': FieldValue.serverTimestamp(),
      'bids.$helperUid': proposedPrice, // Update bid to the agreed price
    });

    await _logTaskActivity(
      taskId: taskId,
      action: 'assigned',
      actorUid: uid!,
      details: '${isPosterAccepting ? 'Poster' : 'Helper'} accepted the task offer for ₹$proposedPrice',
    );

    await _db
        .collection('users')
        .doc(posterUid)
        .collection('notifications')
        .add({
      'fromUid': uid,
      'taskId': taskId,
      'title': 'Offer Accepted!',
      'message': 'Helper accepted your offer for "$taskTitle".',
      'createdAt': FieldValue.serverTimestamp(),
      'isRead': false,
      'type': 'offer_accepted',
    });
  }

  Future<void> declineProposedTask(String taskId, {bool isPosterDeclining = false}) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    final taskDoc = await _db.collection('tasks').doc(taskId).get();
    final taskData = taskDoc.data() as Map<String, dynamic>?;
    if (taskData == null) return;

    final posterUid = taskData['postedByUid'];
    final taskTitle = taskData['title'] ?? 'A task';

    await _db.collection('tasks').doc(taskId).update({
      'status': 'open',
      'targetHelperUid': FieldValue.delete(),
      'proposedPrice': FieldValue.delete(),
      'proposedAt': FieldValue.delete(),
    });

    await _logTaskActivity(
      taskId: taskId,
      action: 'offer_declined',
      actorUid: uid!,
      details: '${isPosterDeclining ? 'Poster' : 'Helper'} declined the task offer',
    );

    await _db
        .collection('users')
        .doc(isPosterDeclining ? taskData['targetHelperUid'] : posterUid)
        .collection('notifications')
        .add({
      'fromUid': uid,
      'taskId': taskId,
      'title': 'Offer Declined',
      'message': '${isPosterDeclining ? 'Poster' : 'Helper'} declined the offer for "$taskTitle".',
      'createdAt': FieldValue.serverTimestamp(),
      'isRead': false,
      'type': 'offer_declined',
    });
  }

  Future<void> reviseTaskPrice(String taskId, int newPrice, {required bool isWorkerRevise}) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    final taskDoc = await _db.collection('tasks').doc(taskId).get();
    final taskData = taskDoc.data() as Map<String, dynamic>?;
    if (taskData == null) return;

    final String newStatus = isWorkerRevise ? 'pending_poster_acceptance' : 'pending_worker_acceptance';
    final targetNotifyUid = isWorkerRevise ? taskData['postedByUid'] : taskData['targetHelperUid'];
    
    await _db.collection('tasks').doc(taskId).update({
      'status': newStatus,
      'proposedPrice': newPrice,
      'proposedAt': FieldValue.serverTimestamp(),
    });

    await _logTaskActivity(
      taskId: taskId,
      action: 'price_revised',
      actorUid: uid,
      details: '${isWorkerRevise ? 'Helper' : 'Poster'} revised the price to ₹$newPrice',
    );

    await _db.collection('users').doc(targetNotifyUid).collection('notifications').add({
      'fromUid': uid,
      'taskId': taskId,
      'title': 'Counter Offer!',
      'message': '${isWorkerRevise ? 'Helper' : 'Poster'} sent a counter-offer of ₹$newPrice for "${taskData['title']}".',
      'createdAt': FieldValue.serverTimestamp(),
      'isRead': false,
      'type': 'offer_revised',
    });
  }

  // --- TASK ACTIVITY LOG (for traceability) ---
  Future<void> _logTaskActivity({
    required String taskId,
    required String action,
    required String actorUid,
    String? details,
  }) async {
    await _db
        .collection('tasks')
        .doc(taskId)
        .collection('taskLog')
        .add({
      'action': action,
      'actorUid': actorUid,
      'details': details ?? '',
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  // Stream the activity log for a task (for admin/debug viewing)
  Stream<QuerySnapshot> streamTaskLog(String taskId) {
    return _db
        .collection('tasks')
        .doc(taskId)
        .collection('taskLog')
        .orderBy('timestamp', descending: false)
        .snapshots()
        .logErrors('Live: task activity log');
  }

  /// Pays for a task from the in-app wallet (the dummy-wallet payment path).
  ///
  /// [discountPercent] is the admin-set discount: the poster pays less, while
  /// the helper's earnings stay based on the full agreed [priceAmount].
  Future<String> payAndCompleteTask(String taskId, String workerUid,
      int priceAmount, double givenRating, {int discountPercent = 0}) async {
    try {
      final posterUid = _auth.currentUser?.uid;
      if (posterUid == null) return "User not logged in";
      if (workerUid.isEmpty) return "Worker UID is empty";

      final amounts = PaymentAmounts.compute(priceAmount, discountPercent);

      // BUG-06 FIX: Check wallet balance BEFORE deducting
      final posterDoc = await _db.collection('users').doc(posterUid).get();
      final currentBalance = (posterDoc.data() as Map<String, dynamic>?)?['walletBalance'] ?? 0;
      if (currentBalance < amounts.payable) {
        return "Insufficient wallet balance (₹$currentBalance available, ₹${amounts.payable} needed)";
      }

      // The task's category goes on the public review (the task itself stays private).
      final taskSnap = await _db.collection('tasks').doc(taskId).get();
      final String category = (taskSnap.data() as Map<String, dynamic>?)?['category'] ?? 'Task';

      // Helper gets the agreed price minus the 10% platform fee.
      final double commission = priceAmount * PaymentAmounts.platformFeeFraction;
      final double helperEarnings = amounts.helperEarnings;

      WriteBatch batch = _db.batch();

      DocumentReference taskRef = _db.collection('tasks').doc(taskId);
      batch.set(taskRef, {
        'status': 'completed',
        'completedAt': FieldValue.serverTimestamp(),
        'finalPricePaid': priceAmount,
        'amountPaidByPoster': amounts.payable,
        'discountPercent': amounts.discountPercent,
        'discountAmount': amounts.discountAmount,
        'workerRating': givenRating,
      }, SetOptions(merge: true));

      DocumentReference posterRef = _db.collection('users').doc(posterUid);
      batch.set(posterRef, {'walletBalance': FieldValue.increment(-amounts.payable)}, SetOptions(merge: true));

      // Log transaction for poster
      DocumentReference posterTxRef = posterRef.collection('transactions').doc();
      batch.set(posterTxRef, {
        'amount': amounts.payable,
        'type': 'debit',
        'title': amounts.discountAmount > 0
            ? 'Paid for task (₹${amounts.discountAmount} discount applied)'
            : 'Paid for task',
        'taskId': taskId,
        'timestamp': FieldValue.serverTimestamp(),
      });

      // Public review: rating + category only, so the hired-out task can stay private.
      batch.set(_db.collection('reviews').doc(taskId), {
        'taskId': taskId,
        'workerUid': workerUid,
        'posterUid': posterUid,
        'rating': givenRating,
        'category': category,
        'createdAt': FieldValue.serverTimestamp(),
      });

      DocumentReference workerRef = _db.collection('users').doc(workerUid);
      batch.set(workerRef, {
        'walletBalance': FieldValue.increment(helperEarnings),
        'ratingSum': FieldValue.increment(givenRating),
        'ratingCount': FieldValue.increment(1),
        'tasksDone': FieldValue.increment(1),
      }, SetOptions(merge: true));

      // Log transaction for worker
      DocumentReference workerTxRef = workerRef.collection('transactions').doc();
      batch.set(workerTxRef, {
        'amount': helperEarnings,
        'type': 'credit',
        'title': 'Earned from task',
        'taskId': taskId,
        'timestamp': FieldValue.serverTimestamp(),
      });

      await batch.commit();

      // Log the payment for traceability
      await _logTaskActivity(
        taskId: taskId,
        action: 'payment_completed',
        actorUid: posterUid,
        details: 'Poster paid ₹${amounts.payable} for a ₹$priceAmount task'
            '${amounts.discountAmount > 0 ? ' (₹${amounts.discountAmount} / ${amounts.discountPercent}% discount)' : ''}; '
            'worker gets ₹${helperEarnings.toStringAsFixed(0)}, platform fee ₹${commission.toStringAsFixed(0)}. Rating: $givenRating',
      );

      // Notify worker of payment
      await _db
          .collection('users')
          .doc(workerUid)
          .collection('notifications')
          .add({
        'fromUid': posterUid,
        'taskId': taskId,
        'title': '💰 Payment received!',
        'message': 'You received ₹${helperEarnings.toStringAsFixed(0)} for your work. Great job!',
        'createdAt': FieldValue.serverTimestamp(),
        'isRead': false,
        'type': 'payment_received',
      });

      return "success";
    } catch (e, st) {
      debugPrint("Payment Error: $e");
      ErrorLogger.instance.log(
        error: e,
        stack: st,
        category: 'payment',
        context: 'Wallet payment (payAndCompleteTask)',
        taskId: taskId,
        extra: {'agreedAmount': '$priceAmount', 'discountPercent': '$discountPercent'},
      );
      return e.toString();
    }
  }

  Future<void> markTaskAsWorkerCompleted(String taskId) async {
    final workerUid = _auth.currentUser?.uid;
    await _db.collection('tasks').doc(taskId).update({
      'workerCompleted': true,
      'workerCompletedAt': FieldValue.serverTimestamp(),
    });

    // Log for traceability
    if (workerUid != null) {
      await _logTaskActivity(
        taskId: taskId,
        action: 'worker_marked_done',
        actorUid: workerUid,
        details: 'Worker marked task as completed. Waiting for poster confirmation.',
      );

      // Get task info to notify poster
      final taskDoc = await _db.collection('tasks').doc(taskId).get();
      final taskData = taskDoc.data() as Map<String, dynamic>?;
      final posterUid = taskData?['postedByUid'] ?? '';
      final taskTitle = taskData?['title'] ?? 'your task';

      if (posterUid.isNotEmpty) {
        await _db
            .collection('users')
            .doc(posterUid)
            .collection('notifications')
            .add({
          'fromUid': workerUid,
          'taskId': taskId,
          'title': '✅ Worker marked task as done!',
          'message': '"$taskTitle" has been marked complete by the worker. Please review and pay.',
          'createdAt': FieldValue.serverTimestamp(),
          'isRead': false,
          'type': 'worker_done',
        });
      }
    }
  }

// Replace your existing streamAvailableCityTasks with this:
  Stream<QuerySnapshot> streamAvailableCityTasks(String city) {
    // Removed the isNotEqualTo query to avoid complex Firestore index requirements.
    // We will filter out the user's own tasks in the UI code.
    return _db
        .collection('tasks')
        .where('city', isEqualTo: city)
        .where('status', isEqualTo: 'open')
        .snapshots()
        .logErrors('Live: open tasks in my city');
  }

  // --- NEW METHOD FOR SENDING NOTIFICATIONS ---
  Future<void> sendRequestNotification(String targetHelperUid) async {
    final user = _auth.currentUser;
    if (user == null) return;

    // Fetch the sender's profile to include their name
    final senderDoc = await _db.collection('users').doc(user.uid).get();
    final senderName = senderDoc.data()?['fullName'] ?? 'Someone';

    // Add a notification to the target helper's subcollection
    await _db
        .collection('users')
        .doc(targetHelperUid)
        .collection('notifications')
        .add({
      'fromUid': user.uid,
      'title': 'New Request!',
      'message': '$senderName has requested your help for a task.',
      'createdAt': FieldValue.serverTimestamp(),
      'isRead': false,
    });
  }

  Stream<QuerySnapshot> streamMyAcceptedTasks() {
    return _db
        .collection('tasks')
        .where('acceptedByUid', isEqualTo: _auth.currentUser?.uid)
        .where('status', isEqualTo: 'assigned')
        .snapshots()
        .logErrors('Live: my accepted tasks');
  }

  Stream<QuerySnapshot> streamMyCompletedTasks() {
    return _db
        .collection('tasks')
        .where('acceptedByUid', isEqualTo: _auth.currentUser?.uid)
        .where('status', isEqualTo: 'completed')
        .snapshots()
        .logErrors('Live: my completed tasks');
  }

  Stream<QuerySnapshot> streamTasksIPosted() {
    return _db
        .collection('tasks')
        .where('postedByUid', isEqualTo: _auth.currentUser?.uid)
        .snapshots()
        .logErrors('Live: tasks I posted');
  }

  /// Every task the signed-in user is involved in as a helper: open tasks they
  /// applied to, offers made to them, and tasks they were hired for.
  ///
  /// This is three queries instead of one `applicants array-contains` query
  /// because a task that has been hired out to someone else is no longer
  /// readable by the other applicants (see firestore.rules), and Firestore
  /// rejects any query that could return a document the user may not read.
  Stream<List<QueryDocumentSnapshot>> streamMyWorkerTasks() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return Stream.value(const <QueryDocumentSnapshot>[]);

    final tasks = _db.collection('tasks');
    final sources = <Stream<QuerySnapshot>>[
      tasks
          .where('applicants', arrayContains: uid)
          .where('status', isEqualTo: 'open')
          .snapshots(),
      tasks.where('targetHelperUid', isEqualTo: uid).snapshots(),
      tasks.where('acceptedByUid', isEqualTo: uid).snapshots(),
    ];

    final latest = List<List<QueryDocumentSnapshot>?>.filled(sources.length, null);
    final subs = <StreamSubscription<QuerySnapshot>>[];
    late final StreamController<List<QueryDocumentSnapshot>> controller;

    void emit() {
      if (latest.any((l) => l == null)) return; // wait until each query has answered once
      final byId = <String, QueryDocumentSnapshot>{};
      for (final docs in latest) {
        for (final d in docs!) {
          byId[d.id] = d;
        }
      }
      controller.add(byId.values.toList());
    }

    controller = StreamController<List<QueryDocumentSnapshot>>(
      onListen: () {
        for (var i = 0; i < sources.length; i++) {
          subs.add(sources[i].listen(
            (snap) {
              latest[i] = snap.docs;
              emit();
            },
            onError: (Object e, StackTrace st) {
              // One failing query (e.g. an index still building) shouldn't hide the others.
              debugPrint('streamMyWorkerTasks query $i failed: $e');
              ErrorLogger.instance.log(
                  error: e, stack: st, category: 'database', context: 'Live: my work tasks (query ${i + 1} of 3)');
              latest[i] = const <QueryDocumentSnapshot>[];
              emit();
            },
          ));
        }
      },
      onCancel: () async {
        for (final s in subs) {
          await s.cancel();
        }
      },
    );
    return controller.stream;
  }

  // Open tasks in a city. Once a task is hired out it is private to the poster
  // and the hired person (see firestore.rules), so any list query must be
  // limited to status == 'open'. Equality filters only, so no index is needed;
  // callers sort by createdAt themselves.
  Stream<QuerySnapshot> streamTasksByCity(String city,
      {bool urgentOnly = false}) {
    Query query = _db
        .collection('tasks')
        .where('city', isEqualTo: city)
        .where('status', isEqualTo: 'open');
    if (urgentOnly) query = query.where('isUrgent', isEqualTo: true);
    return query.snapshots().logErrors('Live: tasks by city');
  }

  // --- NEW: Notification Methods ---

  Stream<QuerySnapshot> streamMyNotifications() {
    final user = _auth.currentUser;
    if (user == null) return const Stream.empty();
    return _db
        .collection('users')
        .doc(user.uid)
        .collection('notifications')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .logErrors('Live: my notifications');
  }

  Future<void> markNotificationRead(String notificationId) async {
    final user = _auth.currentUser;
    if (user == null) return;
    // NEW-BUG-10 FIX: Update isRead instead of deleting the notification
    await _db
        .collection('users')
        .doc(user.uid)
        .collection('notifications')
        .doc(notificationId)
        .update({'isRead': true});
  }

  // --- TASK CLEANUP ---
  Future<void> cleanupExpiredTasks() async {
    try {
      final now = Timestamp.now();
      final querySnapshot = await _db
          .collection('tasks')
          .where('status', isEqualTo: 'open')
          .where('endTime', isLessThan: now)
          .get();

      if (querySnapshot.docs.isEmpty) return;

      WriteBatch batch = _db.batch();
      for (var doc in querySnapshot.docs) {
        batch.update(doc.reference, {'status': 'expired'});
      }
      await batch.commit();
      debugPrint('Cleaned up ${querySnapshot.docs.length} expired tasks.');
    } catch (e, st) {
      debugPrint('Error cleaning up expired tasks: $e');
      ErrorLogger.instance.log(
          error: e, stack: st, category: 'database', severity: 'warning', context: 'Expire old tasks');
    }
  }

  // --- PAYMENT CONFIG ---
  // Admin-controlled toggle, set via Firebase Console in metadata/paymentConfig.
  // paymentsEnabled: master on/off switch for the "Pay" flow.
  // useRazorpay: false = dummy in-app wallet, true = real Razorpay checkout.
  // discountPercent: whole percent off what the poster pays (0 = no discount).
  Future<Map<String, dynamic>> getPaymentConfig() async {
    try {
      final doc = await _db.collection('metadata').doc('paymentConfig').get();
      final data = doc.data();
      return {
        'paymentsEnabled': data?['paymentsEnabled'] ?? true,
        'useRazorpay': data?['useRazorpay'] ?? false,
        'discountPercent': PaymentAmounts.resolveDiscountPercent(data),
      };
    } catch (e, st) {
      debugPrint('Error reading payment config: $e');
      ErrorLogger.instance.log(
          error: e, stack: st, category: 'payment', severity: 'warning', context: 'Read payment settings');
      return {'paymentsEnabled': true, 'useRazorpay': false, 'discountPercent': 0};
    }
  }

  // --- WALLET METHODS ---
  Stream<QuerySnapshot> streamTransactions() {
    final user = _auth.currentUser;
    if (user == null) return const Stream.empty();
    return _db
        .collection('users')
        .doc(user.uid)
        .collection('transactions')
        .orderBy('timestamp', descending: true)
        .snapshots()
        .logErrors('Live: my wallet history');
  }

  /// Asks ChalBro to pay [amount] rupees from the wallet to the person's UPI id.
  /// The money is held at once: the request and the REAL-balance debit are ONE batch, and the
  /// Firestore rules check that the wallet really went down by exactly [amount]. An admin
  /// pays it by hand and marks it paid; a rejection puts the money back.
  /// Only open while Razorpay is on (then a wallet holds real earnings).
  Future<WithdrawResult> requestWithdrawal({required int amount, required String upiId}) async {
    final user = _auth.currentUser;
    if (user == null) return WithdrawResult.failed;
    final upi = upiId.trim();
    if (!isValidUpiId(upi)) return WithdrawResult.badUpi;
    if (amount < kMinWithdrawal || amount > kMaxWithdrawal) return WithdrawResult.badAmount;
    try {
      final config = await getPaymentConfig();
      if (config['useRazorpay'] != true) return WithdrawResult.notAvailable;

      final userRef = _db.collection('users').doc(user.uid);
      final data = (await userRef.get()).data() as Map<String, dynamic>?;
      final balance = (data?['realBalance'] ?? 0) as num; // real money only, never the practice wallet
      if (balance < amount) return WithdrawResult.notEnough;

      final requestRef = _db.collection('withdrawals').doc();
      final batch = _db.batch();
      batch.set(requestRef, {
        'uid': user.uid,
        'userName': (data?['fullName'] ?? '').toString(),
        'amount': amount,
        'paymentDetails': upi,
        'status': 'pending',
        'timestamp': FieldValue.serverTimestamp(),
      });
      batch.update(userRef, {'realBalance': FieldValue.increment(-amount)});
      batch.set(userRef.collection('transactions').doc(), {
        'amount': amount,
        'type': 'debit',
        'real': true,
        'title': 'Withdrawal requested (UPI $upi)',
        'withdrawalId': requestRef.id,
        'timestamp': FieldValue.serverTimestamp(),
      });
      await batch.commit();
      return WithdrawResult.sent;
    } catch (e, st) {
      ErrorLogger.instance.log(error: e, stack: st, category: 'database', context: 'Request withdrawal');
      return WithdrawResult.failed;
    }
  }

  /// The person's own withdrawal requests (newest first is done by the screen: sorting
  /// here would need a composite index).
  Stream<QuerySnapshot> streamMyWithdrawals() {
    final user = _auth.currentUser;
    if (user == null) return const Stream.empty();
    return _db
        .collection('withdrawals')
        .where('uid', isEqualTo: user.uid)
        .limit(50)
        .snapshots()
        .logErrors('Live: my withdrawals');
  }

  // --- TASK MANAGEMENT ---
  Future<bool> deleteTask(String taskId) async {
    final user = _auth.currentUser;
    if (user == null) return false;
    try {
      final taskDoc = await _db.collection('tasks').doc(taskId).get();
      if (!taskDoc.exists) return false;
      final data = taskDoc.data() as Map<String, dynamic>;
      if (data['postedByUid'] != user.uid) return false; // Only owner can delete
      await _db.collection('tasks').doc(taskId).delete();
      return true;
    } catch (e, st) {
      debugPrint('Error deleting task: $e');
      ErrorLogger.instance.log(error: e, stack: st, category: 'database', context: 'Delete task');
      return false;
    }
  }

  // Update user profile fields
  Future<bool> updateUserProfile({
    String? fullName,
    String? phone,
    String? qualifications,
    String? city,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return false;
    try {
      final Map<String, dynamic> updates = {};
      if (fullName != null) updates['fullName'] = fullName;
      if (phone != null) updates['phone'] = phone;
      if (qualifications != null) updates['qualifications'] = qualifications;
      if (city != null) updates['city'] = city;
      if (updates.isEmpty) return true;
      await _db.collection('users').doc(user.uid).update(updates);
      return true;
    } catch (e, st) {
      debugPrint('Error updating profile: $e');
      ErrorLogger.instance.log(error: e, stack: st, category: 'database', context: 'Update profile');
      return false;
    }
  }

  // --- REPORTS (flag a task or a person for the admin team) ---
  /// One report per person per target: the document id says so and the rules do not
  /// allow overwriting, so a second attempt is refused and reported as
  /// [ReportResult.alreadyReported].
  Future<ReportResult> submitReport({
    required String targetType,
    required String targetId,
    required String targetOwnerUid,
    String targetTitle = '',
    required String reason,
    String details = '',
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return ReportResult.failed;
    final title = targetTitle.length > 160 ? targetTitle.substring(0, 160) : targetTitle;
    try {
      await _db.collection('reports').doc('${uid}_${targetType}_$targetId').set({
        'reporterUid': uid,
        'targetType': targetType,
        'targetId': targetId,
        'targetOwnerUid': targetOwnerUid,
        if (title.isNotEmpty) 'targetTitle': title,
        'reason': reason,
        if (details.isNotEmpty) 'details': details,
        'status': 'open',
        'createdAt': FieldValue.serverTimestamp(),
      });
      return ReportResult.sent;
    } on FirebaseException catch (e, st) {
      // The only way a well-formed report is refused is that this person already
      // sent one (or their account is paused): both end the same for them.
      if (e.code == 'permission-denied') return ReportResult.alreadyReported;
      ErrorLogger.instance.log(error: e, stack: st, category: 'database', context: 'Send report');
      return ReportResult.failed;
    } catch (e, st) {
      ErrorLogger.instance.log(error: e, stack: st, category: 'database', context: 'Send report');
      return ReportResult.failed;
    }
  }

  // --- METADATA ---
  Future<List<String>> getCities() async {
    // ── PERFORMANCE: Return cached result if available ──────────────────────
    if (_citiesCache != null) return _citiesCache!;
    try {
      final doc = await _db.collection('metadata').doc('locations').get();
      if (doc.exists) {
        _citiesCache = List<String>.from(doc.data()?['cities'] ?? ['Surat', 'Mumbai', 'Delhi', 'Bengaluru']);
        return _citiesCache!;
      }
      _citiesCache = ['Surat', 'Mumbai', 'Delhi', 'Bengaluru'];
      return _citiesCache!;
    } catch (e) {
      return ['Surat', 'Mumbai', 'Delhi', 'Bengaluru'];
    }
  }

  // --- CHAT METHODS ---
  Future<String> getOrCreateChat(String otherUid) async {
    final user = _auth.currentUser;
    if (user == null) return '';

    // A consistent chat ID based on the two UIDs
    final List<String> uids = [user.uid, otherUid];
    uids.sort();
    final String chatId = '${uids[0]}_${uids[1]}';

    try {
      final doc = await _db.collection('chats').doc(chatId).get();
      if (!doc.exists) {
        await _db.collection('chats').doc(chatId).set({
          'participants': uids,
          'lastMessage': '',
          'lastMessageTime': FieldValue.serverTimestamp(),
          'unreadCounts': {
            uids[0]: 0,
            uids[1]: 0,
          }
        });
      }
    } catch (e) {
      // If get() fails due to Firestore security rules (document doesn't exist), create it
      await _db.collection('chats').doc(chatId).set({
        'participants': uids,
        'lastMessage': '',
        'lastMessageTime': FieldValue.serverTimestamp(),
        'unreadCounts': {
          uids[0]: 0,
          uids[1]: 0,
        }
      });
    }
    return chatId;
  }

  Stream<QuerySnapshot> streamMyChats() {
    final user = _auth.currentUser;
    if (user == null) return const Stream.empty();
    return _db
        .collection('chats')
        .where('participants', arrayContains: user.uid)
        .orderBy('lastMessageTime', descending: true)
        .snapshots()
        .logErrors('Live: my chats');
  }

  Stream<QuerySnapshot> streamMessages(String chatId) {
    return _db
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .orderBy('timestamp', descending: true)
        .snapshots()
        .logErrors('Live: chat messages');
  }

  Future<void> sendMessage(String chatId, String text, String otherUid) async {
    final user = _auth.currentUser;
    if (user == null) return;

    WriteBatch batch = _db.batch();
    DocumentReference chatRef = _db.collection('chats').doc(chatId);
    DocumentReference msgRef = chatRef.collection('messages').doc();

    batch.set(msgRef, {
      'senderId': user.uid,
      'text': text,
      'timestamp': FieldValue.serverTimestamp(),
    });

    batch.update(chatRef, {
      'lastMessage': text,
      'lastMessageTime': FieldValue.serverTimestamp(),
      'unreadCounts.$otherUid': FieldValue.increment(1),
    });

    await batch.commit();
  }
  
  Future<void> markChatAsRead(String chatId) async {
    final user = _auth.currentUser;
    if (user == null) return;
    await _db.collection('chats').doc(chatId).update({
      'unreadCounts.${user.uid}': 0,
    });
  }
}

