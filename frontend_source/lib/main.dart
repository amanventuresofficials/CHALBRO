import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'firebase_options.dart';
import 'screens/main_layout.dart';
import 'screens/complete_profile_screen.dart';
import 'screens/terms_screen.dart';
import 'screens/blocked_screen.dart';
import 'auth_screen.dart';
import 'services/auth_service.dart';
import 'utils/app_colors.dart';
import 'utils/language_provider.dart';
import 'widgets/language_picker_dialog.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Make the status bar transparent
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
  ));

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(
    ChangeNotifierProvider(
      create: (_) => LanguageProvider(),
      child: const ChalbroApp(),
    ),
  );
}

class ChalbroApp extends StatelessWidget {
  const ChalbroApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Chalbro - Human Marketplace',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        scaffoldBackgroundColor: AppColors.background,
        useMaterial3: true,
        fontFamily: 'Roboto',
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
      ),
      home: const AuthWrapper(),
    );
  }
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: AuthService().user,
      builder: (context, authSnapshot) {
        if (authSnapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }

        // Not logged in → show login screen
        if (!authSnapshot.hasData) {
          return const AuthScreen();
        }

        // Logged in → watch Firestore user document
        return StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance
              .collection('users')
              .doc(authSnapshot.data!.uid)
              .snapshots(),
          builder: (context, profileSnapshot) {
            if (profileSnapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                  body: Center(child: CircularProgressIndicator()));
            }

            final docExists = profileSnapshot.hasData && profileSnapshot.data!.exists;

            // --- GATE 0: Account suspension check ---
            // If the user document exists and they are banned or paused,
            // show the BlockedScreen wall regardless of any other state.
            if (docExists) {
              final userData = profileSnapshot.data!.data() as Map<String, dynamic>;
              final isBanned = userData['isBanned'] == true;
              final isPaused = userData['isPaused'] == true;
              if (isBanned || isPaused) {
                // Detect if this pause/ban is specifically ID-related so we can
                // show the re-upload option instead of just the generic wall.
                final reason = (userData['banReason'] as String? ?? '').toLowerCase();
                final idStatus = (userData['idProofStatus'] as String? ?? '');
                final isIdIssue = isPaused && !isBanned && (
                  idStatus == 'Rejected' ||
                  reason.contains('id') ||
                  reason.contains('photo') ||
                  reason.contains('proof') ||
                  reason.contains('verification') ||
                  reason.contains('document') ||
                  reason.contains('aadhaar') ||
                  reason.contains('passport')
                );
                return BlockedScreen(
                  isPaused: isPaused && !isBanned,
                  reason: userData['banReason'] as String?,
                  isIdIssue: isIdIssue,
                );
              }
            }

            // --- GATE 1: Terms & Conditions ---
            // If the user document doesn't exist yet OR termsAccepted is not true,
            // force them to read and accept the terms first.
            if (!docExists ||
                (profileSnapshot.data!.data() as Map<String, dynamic>?)?['termsAccepted'] != true) {
              return const TermsScreen();
            }

            // --- GATE 2: Profile completion ---
            // termsAccepted == true but profile fields not filled yet
            // (saveUserProfile is only called from CompleteProfileScreen)
            final data = profileSnapshot.data!.data() as Map<String, dynamic>;
            if (data['fullName'] == null || data['fullName'].toString().isEmpty) {
              return const CompleteProfileScreen();
            }

            // All gates passed → check for first-run language selection
            final langProvider = context.watch<LanguageProvider>();
            if (langProvider.isFirstRun) {
              // Use a one-time post-frame callback to show the language picker
              // after the first frame so we don't call showModal during build.
              return _LanguagePickerGate();
            }
            return const MainLayout();
          },
        );
      },
    );
  }
}

/// Shown in place of MainLayout when the user hasn't picked a language yet.
/// It immediately shows the language picker and waits for the user to choose.
class _LanguagePickerGate extends StatefulWidget {
  @override
  State<_LanguagePickerGate> createState() => _LanguagePickerGateState();
}

class _LanguagePickerGateState extends State<_LanguagePickerGate> {
  @override
  void initState() {
    super.initState();
    // Show the dialog after the first frame renders.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        LanguagePickerDialog.show(context, isFirstRun: true);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Display a loading screen behind the dialog.
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              height: 96,
              width: 96,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(22),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withOpacity(0.18),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: Image.asset(
                'assets/images/logo.png',
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Choose your language\nभाषा चुनें',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppColors.darkText,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
