import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../utils/app_colors.dart';

/// Full-screen notices the owner can switch on from the admin panel.
class _GateScaffold extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String message;
  final List<Widget> actions;
  const _GateScaffold({required this.icon, required this.color, required this.title, required this.message, this.actions = const []});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(color: color.withOpacity(0.12), shape: BoxShape.circle),
                    child: Icon(icon, size: 52, color: color),
                  ),
                  const SizedBox(height: 24),
                  Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.darkText)),
                  const SizedBox(height: 12),
                  Text(message, textAlign: TextAlign.center, style: const TextStyle(fontSize: 15, height: 1.5, color: AppColors.greyText)),
                  const SizedBox(height: 28),
                  ...actions,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Shown to everyone while maintenance mode is on.
class MaintenanceScreen extends StatelessWidget {
  final String message;
  const MaintenanceScreen({super.key, this.message = ''});

  @override
  Widget build(BuildContext context) {
    return _GateScaffold(
      icon: Icons.construction_rounded,
      color: AppColors.warning,
      title: 'We\'ll be back soon',
      message: message.trim().isEmpty ? 'ChalBro is being improved right now. Please try again in a little while.' : message.trim(),
      actions: [
        OutlinedButton(onPressed: () => FirebaseAuth.instance.signOut(), child: const Text('Sign out')),
      ],
    );
  }
}

/// Shown when the installed build is older than the owner's minimum build.
class UpdateRequiredScreen extends StatelessWidget {
  const UpdateRequiredScreen({super.key});

  static final Uri _store = Uri.parse('https://play.google.com/store/apps/details?id=com.chalbro.app');

  @override
  Widget build(BuildContext context) {
    return _GateScaffold(
      icon: Icons.system_update_alt_rounded,
      color: AppColors.primary,
      title: 'Please update ChalBro',
      message: 'This version of the app is out of date and can no longer be used. Update to the latest version to continue. Your account and wallet are safe.',
      actions: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14)),
            onPressed: () => launchUrl(_store, mode: LaunchMode.externalApplication),
            icon: const Icon(Icons.shop_two_outlined),
            label: const Text('Update on Google Play'),
          ),
        ),
      ],
    );
  }
}

/// Shown to people without an account while new sign-ups are switched off.
class RegistrationsClosedScreen extends StatelessWidget {
  const RegistrationsClosedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return _GateScaffold(
      icon: Icons.lock_clock_outlined,
      color: AppColors.primary,
      title: 'Sign-ups are closed right now',
      message: 'ChalBro is not accepting new members at the moment. Please check back soon.',
      actions: [
        OutlinedButton(onPressed: () => FirebaseAuth.instance.signOut(), child: const Text('Back')),
      ],
    );
  }
}
