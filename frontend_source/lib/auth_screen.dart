import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'services/auth_service.dart';
import '../utils/app_colors.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen>
    with SingleTickerProviderStateMixin {
  final AuthService _authService = AuthService();

  // Which option the user has tapped: null = initial, 'phone' = phone flow
  String? _activeMethod;

  // Google loading
  bool _isGoogleLoading = false;

  // Phone Auth State
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _otpController = TextEditingController();
  final FocusNode _phoneFocus = FocusNode();
  final FocusNode _otpFocus = FocusNode();
  String? _phoneError;
  String? _otpError;
  bool _isPhoneLoading = false;
  bool _isOtpSent = false;
  String? _verificationId;

  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _fadeAnimation =
        CurvedAnimation(parent: _fadeController, curve: Curves.easeInOut);
    _fadeController.forward();
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _otpController.dispose();
    _phoneFocus.dispose();
    _otpFocus.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  // ── Google Sign-In ─────────────────────────────────────────────────────────
  void _handleGoogleSignIn() async {
    setState(() => _isGoogleLoading = true);
    final userCredential = await _authService.signInWithGoogle();
    if (userCredential == null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Sign-in failed or canceled. Please try again.')),
      );
    }
    if (mounted) setState(() => _isGoogleLoading = false);
  }

  // ── Phone: Send OTP ────────────────────────────────────────────────────────
  void _handleSendOTP() async {
    final phone = _phoneController.text.trim();
    if (phone.isEmpty || phone.length < 10) {
      // Say what is missing and put the cursor back in that field.
      setState(() => _phoneError = phone.isEmpty
          ? 'Enter your 10-digit phone number to continue'
          : 'Phone number needs 10 digits — you entered ${phone.length}');
      _phoneFocus.requestFocus();
      return;
    }

    // Dismiss keyboard first to avoid layout jumps
    FocusScope.of(context).unfocus();
    setState(() {
      _phoneError = null;
      _isPhoneLoading = true;
    });

    final fullPhone = phone.startsWith('+') ? phone : '+91$phone';

    await _authService.verifyPhoneNumber(
      phoneNumber: fullPhone,
      codeSent: (verificationId, resendToken) {
        if (mounted) {
          setState(() {
            _verificationId = verificationId;
            _isOtpSent = true;
            _isPhoneLoading = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('OTP sent successfully!')));
        }
      },
      verificationFailed: (error) {
        if (mounted) {
          setState(() => _isPhoneLoading = false);
          final msg = '${error.code}: ${error.message ?? 'Verification failed'}';
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(msg), duration: const Duration(seconds: 6)));
        }
      },
      codeAutoRetrievalTimeout: (verificationId) {
        if (mounted) {
          setState(() => _verificationId = verificationId);
        }
      },
    );
  }

  // ── Phone: Verify OTP ──────────────────────────────────────────────────────
  void _handleVerifyOTP() async {
    final otp = _otpController.text.trim();
    if (otp.length < 6 || _verificationId == null) {
      setState(() => _otpError = otp.isEmpty
          ? 'Enter the 6-digit OTP we sent to your phone'
          : 'The OTP has 6 digits — you entered ${otp.length}');
      _otpFocus.requestFocus();
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _otpError = null;
      _isPhoneLoading = true;
    });

    final userCredential =
        await _authService.signInWithOTP(_verificationId!, otp);

    if (userCredential == null && mounted) {
      setState(() => _isPhoneLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invalid OTP. Please try again.')));
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────
  void _selectMethod(String method) {
    setState(() {
      _activeMethod = method;
      _isOtpSent = false;
      _phoneError = null;
      _otpError = null;
      _phoneController.clear();
      _otpController.clear();
    });
  }

  void _resetMethod() {
    FocusScope.of(context).unfocus();
    setState(() {
      _activeMethod = null;
      _isOtpSent = false;
      _isPhoneLoading = false;
      _phoneController.clear();
      _otpController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final isKeyboardOpen = bottom > 100;

    return Scaffold(
      // Let the scaffold resize when keyboard opens
      resizeToAvoidBottomInset: true,
      body: Container(
        decoration: const BoxDecoration(
          gradient: AppColors.primaryGradient,
        ),
        child: SafeArea(
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: SingleChildScrollView(
              // Ensures content shifts up when keyboard appears
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.fromLTRB(28, 0, 28, bottom > 0 ? 16 : 0),
              child: ConstrainedBox(
                // Fills the screen height so content is centered when keyboard is closed
                constraints: BoxConstraints(
                  minHeight: MediaQuery.of(context).size.height -
                      MediaQuery.of(context).padding.top -
                      MediaQuery.of(context).padding.bottom,
                ),
                child: IntrinsicHeight(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // ── Spacer top (shrinks when keyboard is open) ─────────
                      SizedBox(height: isKeyboardOpen ? 24 : 60),

                      // ── Logo ───────────────────────────────────────────────
                      if (!isKeyboardOpen) ...[
                        Center(
                          child: Container(
                            height: 110,
                            width: 110,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(24),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.2),
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
                        ),
                        const SizedBox(height: 16),

                        // ── Title ──────────────────────────────────────────
                        const Text(
                          'ChalBro',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 34,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.5,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          "India's Human Marketplace",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: Colors.white.withOpacity(0.9),
                            letterSpacing: 0.3,
                          ),
                        ),
                      ] else ...[
                        // Compact header when keyboard is open
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              height: 38,
                              width: 38,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(10),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.12),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: Image.asset(
                                'assets/images/logo.png',
                                fit: BoxFit.cover,
                              ),
                            ),
                            const SizedBox(width: 10),
                            const Text(
                              'ChalBro',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ],

                      const Spacer(),

                      // ── Sign-in label ──────────────────────────────────────
                      Text(
                        _activeMethod == null
                            ? 'Choose how to sign in'
                            : _activeMethod == 'phone'
                                ? _isOtpSent
                                    ? 'Enter the OTP sent to your phone'
                                    : 'Enter your phone number'
                                : '',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.white.withOpacity(0.8),
                          fontWeight: FontWeight.w500,
                          letterSpacing: 0.4,
                        ),
                      ),
                      const SizedBox(height: 16),

                      // ── Content area ───────────────────────────────────────
                      if (_activeMethod == null) ...[
                        // Option 1 – Phone
                        _MethodCard(
                          icon: Icons.phone_android_rounded,
                          label: 'Continue with Phone',
                          onTap: () => _selectMethod('phone'),
                        ),
                        const SizedBox(height: 14),

                        // Divider
                        Row(
                          children: [
                            Expanded(
                                child: Divider(
                                    color: Colors.white.withOpacity(0.35),
                                    thickness: 1)),
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 14),
                              child: Text('OR',
                                  style: TextStyle(
                                      color: Colors.white.withOpacity(0.7),
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600)),
                            ),
                            Expanded(
                                child: Divider(
                                    color: Colors.white.withOpacity(0.35),
                                    thickness: 1)),
                          ],
                        ),
                        const SizedBox(height: 14),

                        // Option 2 – Google
                        _isGoogleLoading
                            ? const Center(
                                child: CircularProgressIndicator(
                                    color: Colors.white))
                            : _MethodCard(
                                imageUrl:
                                    'https://upload.wikimedia.org/wikipedia/commons/c/c1/Google_%22G%22_logo.svg',
                                label: 'Continue with Google',
                                onTap: _handleGoogleSignIn,
                              ),
                      ] else if (_activeMethod == 'phone') ...[
                        // ── Phone flow ──────────────────────────────────────
                        if (!_isOtpSent) ...[
                          _WhiteTextField(
                            controller: _phoneController,
                            focusNode: _phoneFocus,
                            errorText: _phoneError,
                            onChanged: () {
                              if (_phoneError != null) setState(() => _phoneError = null);
                            },
                            hintText: 'Phone number (e.g. 9876543210)',
                            prefixText: '+91  ',
                            icon: Icons.phone_android_rounded,
                            keyboardType: TextInputType.phone,
                          ),
                          const SizedBox(height: 16),
                          _isPhoneLoading
                              ? const Center(
                                  child: CircularProgressIndicator(
                                      color: Colors.white))
                              : _PrimaryButton(
                                  label: 'Send OTP',
                                  onPressed: _handleSendOTP,
                                ),
                        ] else ...[
                          // OTP field
                          _WhiteTextField(
                            controller: _otpController,
                            focusNode: _otpFocus,
                            errorText: _otpError,
                            onChanged: () {
                              if (_otpError != null) setState(() => _otpError = null);
                            },
                            hintText: 'Enter 6-digit OTP',
                            icon: Icons.lock_outline_rounded,
                            keyboardType: TextInputType.number,
                            maxLength: 6,
                          ),
                          const SizedBox(height: 16),
                          _isPhoneLoading
                              ? const Center(
                                  child: CircularProgressIndicator(
                                      color: Colors.white))
                              : _PrimaryButton(
                                  label: 'Verify & Sign In',
                                  onPressed: _handleVerifyOTP,
                                ),
                          const SizedBox(height: 12),
                          TextButton(
                            onPressed: () =>
                                setState(() => _isOtpSent = false),
                            child: Text(
                              'Change phone number',
                              style: TextStyle(
                                  color: Colors.white.withOpacity(0.85),
                                  fontSize: 13),
                            ),
                          ),
                        ],
                        const SizedBox(height: 12),
                        TextButton.icon(
                          onPressed: _resetMethod,
                          icon: const Icon(Icons.arrow_back_ios_new_rounded,
                              size: 14, color: Colors.white70),
                          label: Text(
                            'Back to sign-in options',
                            style: TextStyle(
                                color: Colors.white.withOpacity(0.8),
                                fontSize: 13),
                          ),
                        ),
                      ],

                      const Spacer(),

                      // ── Terms ──────────────────────────────────────────────
                      Wrap(
                        alignment: WrapAlignment.center,
                        children: [
                          Text(
                            'By signing in, you agree to our ',
                            style: TextStyle(
                                fontSize: 12,
                                color: Colors.white.withOpacity(0.65)),
                          ),
                          GestureDetector(
                            onTap: () => launchUrl(
                                Uri.parse('https://chalbroo.app/terms'),
                                mode: LaunchMode.externalApplication),
                            child: Text(
                              'Terms of Service',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.white.withOpacity(0.9),
                                  decoration: TextDecoration.underline,
                                  decorationColor: Colors.white60),
                            ),
                          ),
                          Text(
                            ' & ',
                            style: TextStyle(
                                fontSize: 12,
                                color: Colors.white.withOpacity(0.65)),
                          ),
                          GestureDetector(
                            onTap: () => launchUrl(
                                Uri.parse('https://chalbroo.app/privacy'),
                                mode: LaunchMode.externalApplication),
                            child: Text(
                              'Privacy Policy',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.white.withOpacity(0.9),
                                  decoration: TextDecoration.underline,
                                  decorationColor: Colors.white60),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Reusable widgets ──────────────────────────────────────────────────────────

class _MethodCard extends StatelessWidget {
  final IconData? icon;
  final String? imageUrl;
  final String label;
  final VoidCallback onTap;

  const _MethodCard({
    this.icon,
    this.imageUrl,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
          child: Row(
            children: [
              if (imageUrl != null)
                Image.network(
                  imageUrl!,
                  height: 26,
                  width: 26,
                  errorBuilder: (_, __, ___) => const Icon(
                    Icons.g_mobiledata,
                    size: 26,
                    color: Colors.black87,
                  ),
                )
              else
                Icon(icon, size: 24, color: AppColors.primary),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
              ),
              const Icon(Icons.arrow_forward_ios_rounded,
                  size: 14, color: Colors.black38),
            ],
          ),
        ),
      ),
    );
  }
}

class _WhiteTextField extends StatelessWidget {
  final TextEditingController controller;
  final String hintText;
  final String? prefixText;
  final IconData icon;
  final TextInputType? keyboardType;
  final int? maxLength;
  final FocusNode? focusNode;
  final String? errorText;
  final VoidCallback? onChanged;

  const _WhiteTextField({
    required this.controller,
    required this.hintText,
    this.prefixText,
    required this.icon,
    this.keyboardType,
    this.maxLength,
    this.focusNode,
    this.errorText,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final errorBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: Colors.orangeAccent, width: 2),
    );
    return TextField(
      controller: controller,
      focusNode: focusNode,
      keyboardType: keyboardType,
      maxLength: maxLength,
      onChanged: onChanged == null ? null : (_) => onChanged!(),
      style: const TextStyle(fontSize: 16, color: Colors.black87),
      decoration: InputDecoration(
        hintText: hintText,
        prefixText: prefixText,
        counterText: '',
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        errorText: errorText,
        // The screen background is a purple gradient, so errors are white (red would not read).
        errorStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
        errorMaxLines: 2,
        errorBorder: errorBorder,
        focusedErrorBorder: errorBorder,
        prefixIcon: Icon(icon, color: AppColors.primary),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;

  const _PrimaryButton({required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: AppColors.primary,
        ),
      ),
    );
  }
}
