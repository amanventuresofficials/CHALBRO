import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Created on first use, which only ever happens on Android/iOS. On the web the
  // google_sign_in plugin starts loading the moment the object exists and fails
  // with "ClientID not set" (an "Uncaught Error" every time a screen creates an
  // AuthService), while web sign-in goes through Firebase's own popup instead.
  late final GoogleSignIn _googleSignIn = GoogleSignIn();

  // Stream to listen to authentication state changes
  Stream<User?> get user => _auth.authStateChanges();

  // Sign in with Google
  Future<UserCredential?> signInWithGoogle() async {
    try {
      // On the web, Firebase's own popup flow replaces the google_sign_in plugin.
      if (kIsWeb) {
        return await _auth.signInWithPopup(GoogleAuthProvider());
      }

      // Trigger the authentication flow
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) return null; // User canceled the sign-in

      // Obtain the auth details from the request
      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

      // Create a new credential
      final AuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      // Once signed in, return the UserCredential
      return await _auth.signInWithCredential(credential);
    } catch (e) {
      debugPrint("Error during Google Sign-In: $e");
      return null;
    }
  }

  // Phone Authentication
  Future<void> verifyPhoneNumber({
    required String phoneNumber,
    required Function(String verificationId, int? resendToken) codeSent,
    required Function(FirebaseAuthException e) verificationFailed,
    required Function(String verificationId) codeAutoRetrievalTimeout,
  }) async {
    debugPrint('📱 Sending OTP to: $phoneNumber');

    // verifyPhoneNumber is mobile-only. On the web the SMS is sent with
    // signInWithPhoneNumber (invisible reCAPTCHA is handled by the SDK), and
    // its verificationId works with PhoneAuthProvider.credential as usual.
    if (kIsWeb) {
      try {
        final confirmation = await _auth.signInWithPhoneNumber(phoneNumber);
        codeSent(confirmation.verificationId, null);
      } on FirebaseAuthException catch (e) {
        verificationFailed(e);
      } catch (e) {
        // A browser/script problem (not a Firebase answer) must not leave the
        // "Send OTP" spinner running forever.
        debugPrint('❌ Phone verification failed: $e');
        verificationFailed(FirebaseAuthException(
          code: 'unknown',
          message: 'Could not send the OTP. Please check your connection and try again.',
        ));
      }
      return;
    }

    await _auth.verifyPhoneNumber(
      phoneNumber: phoneNumber,
      timeout: const Duration(seconds: 60),
      verificationCompleted: (PhoneAuthCredential credential) async {
        // Auto sign-in on Android when SMS is auto-retrieved
        debugPrint('✅ Auto verification completed');
        try {
          await _auth.signInWithCredential(credential);
        } catch (e) {
          debugPrint("Error auto-signing in: $e");
        }
      },
      verificationFailed: (FirebaseAuthException e) {
        debugPrint('❌ Phone verification failed: [${e.code}] ${e.message}');
        verificationFailed(e);
      },
      codeSent: (String verificationId, int? resendToken) {
        debugPrint('📨 OTP code sent, verificationId: $verificationId');
        codeSent(verificationId, resendToken);
      },
      codeAutoRetrievalTimeout: (String verificationId) {
        debugPrint('⏱ Auto-retrieval timeout');
        codeAutoRetrievalTimeout(verificationId);
      },
    );
  }

  // Sign in with OTP
  Future<UserCredential?> signInWithOTP(String verificationId, String smsCode) async {
    try {
      PhoneAuthCredential credential = PhoneAuthProvider.credential(
        verificationId: verificationId,
        smsCode: smsCode,
      );
      return await _auth.signInWithCredential(credential);
    } catch (e) {
      debugPrint("Error signing in with OTP: $e");
      return null;
    }
  }

  // Sign Out
  Future<void> signOut() async {
    try {
      if (!kIsWeb) await _googleSignIn.signOut();
      await _auth.signOut();
    } catch (e) {
      debugPrint("Error signing out: $e");
    }
  }

  /// Deletes the user's Firestore document then deletes the Firebase Auth account.
  /// The user will be signed out automatically once the auth account is deleted.
  Future<bool> deleteAccount() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return false;
      // Delete Firestore profile first
      await FirebaseFirestore.instance.collection('users').doc(user.uid).delete();
      // Delete the Firebase Auth account
      await user.delete();
      return true;
    } catch (e) {
      debugPrint('Error deleting account: $e');
      return false;
    }
  }
}
