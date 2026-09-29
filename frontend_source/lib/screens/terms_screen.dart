import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import '../utils/app_colors.dart';
import '../utils/language_provider.dart';

/// Full-screen Terms & Disclaimer screen shown to every new user.
/// The user CANNOT proceed into the app until they scroll through and tap "I Accept".
class TermsScreen extends StatefulWidget {
  const TermsScreen({super.key});

  @override
  State<TermsScreen> createState() => _TermsScreenState();
}

class _TermsScreenState extends State<TermsScreen> {
  final ScrollController _scrollController = ScrollController();
  bool _hasScrolledToBottom = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (!_hasScrolledToBottom) {
      final maxScroll = _scrollController.position.maxScrollExtent;
      final currentScroll = _scrollController.position.pixels;
      // Enable the accept button when user has read at least 90% of the content
      if (currentScroll >= maxScroll * 0.9) {
        setState(() => _hasScrolledToBottom = true);
      }
    }
  }

  Future<void> _acceptTerms() async {
    setState(() => _isSaving = true);
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'termsAccepted': true,
        'termsAcceptedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
    // The AuthWrapper StreamBuilder will automatically navigate
    // to the next screen once termsAccepted is true in Firestore.
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<LanguageProvider>().strings;
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.primaryGradient),
        child: SafeArea(
          child: Column(
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.gavel_rounded, color: Colors.white, size: 36),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      s.termsTitle,
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      s.termsSubtitle,
                      style: TextStyle(fontSize: 14, color: Colors.white.withOpacity(0.85)),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),

              // Scrollable Content
              Expanded(
                child: Container(
                  margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: SingleChildScrollView(
                      controller: _scrollController,
                      padding: const EdgeInsets.all(24),
                      child: _TermsContent(s: s),
                    ),
                  ),
                ),
              ),

              // Scroll-to-read hint
              if (!_hasScrolledToBottom)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.keyboard_arrow_down, color: Colors.white, size: 20),
                      Text(
                        s.termsScrollHint,
                        style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 13),
                      ),
                    ],
                  ),
                ),

              // Accept Button
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                child: _isSaving
                    ? const Center(child: CircularProgressIndicator(color: Colors.white))
                    : ElevatedButton(
                        onPressed: _hasScrolledToBottom ? _acceptTerms : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          disabledBackgroundColor: Colors.white.withOpacity(0.4),
                          minimumSize: const Size.fromHeight(56),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          elevation: 0,
                        ),
                        child: Text(
                          _hasScrolledToBottom ? s.termsAcceptButton : s.termsReadAll,
                          style: TextStyle(
                            color: _hasScrolledToBottom ? AppColors.primary : Colors.white70,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TermsContent extends StatelessWidget {
  final dynamic s;
  const _TermsContent({required this.s});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(s.termsS0Title),
        _Body(s.termsS0Body),
        const SizedBox(height: 16),
        _SectionHeader(s.termsS1Title),
        _Body(s.termsS1Body),
        const SizedBox(height: 16),
        _SectionHeader(s.termsS2Title),
        _Body(s.termsS2Body),
        const SizedBox(height: 16),
        _SectionHeader(s.termsS3Title),
        _Body(s.termsS3Body),
        const SizedBox(height: 16),
        _SectionHeader(s.termsS4Title),
        _Body(s.termsS4Body),
        const SizedBox(height: 16),
        _SectionHeader(s.termsS5Title),
        _Body(s.termsS5Body),
        const SizedBox(height: 16),
        _SectionHeader(s.termsS6Title),
        _Body(s.termsS6Body),
        const SizedBox(height: 16),
        _SectionHeader(s.termsS7Title),
        _Body(s.termsS7Body),
        const SizedBox(height: 16),
        _SectionHeader(s.termsS8Title),
        _Body(s.termsS8Body),
        const SizedBox(height: 16),
        _SectionHeader(s.termsS9Title),
        _Body(s.termsS9Body),
        const SizedBox(height: 16),
        _SectionHeader(s.termsS10Title),
        _Body(s.termsS10Body),
        const SizedBox(height: 16),
        _SectionHeader(s.termsS11Title),
        _Body(s.termsS11Body),
        const SizedBox(height: 24),
        const Divider(),
        const SizedBox(height: 12),
        Text(
          s.termsFooter,
          style: const TextStyle(
            fontSize: 13,
            color: Colors.black87,
            fontStyle: FontStyle.italic,
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.bold,
        color: AppColors.darkText,
      ),
    );
  }
}

class _Body extends StatelessWidget {
  final String text;
  const _Body(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 14,
        color: AppColors.greyText,
        height: 1.6,
      ),
    );
  }
}
