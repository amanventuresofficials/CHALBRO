import 'package:image_picker/image_picker.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/auth_service.dart';
import '../services/database_service.dart';
import '../utils/app_colors.dart';
import '../utils/picked_image.dart';
import 'main_layout.dart';

class CompleteProfileScreen extends StatefulWidget {
  const CompleteProfileScreen({super.key});

  @override
  State<CompleteProfileScreen> createState() => _CompleteProfileScreenState();
}

class _CompleteProfileScreenState extends State<CompleteProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final DatabaseService _dbService = DatabaseService();
  final AuthService _authService = AuthService();

  // ── Step tracking ─────────────────────────────────────────────────────────
  // Steps: 0 = fill profile details, 1 = verify phone
  int _currentStep = 0;

  // ── Profile fields ────────────────────────────────────────────────────────
  late TextEditingController _nameController;
  final _phoneController = TextEditingController();
  String _selectedCity = 'Surat';
  String _selectedGender = 'Male';
  PickedImage? _idProofFile;
  final ImagePicker _picker = ImagePicker();
  final _qualificationsController = TextEditingController();
  final List<String> _genders = ['Male', 'Female', 'Other'];

  // ── Phone OTP verification ────────────────────────────────────────────────
  final _otpController = TextEditingController();
  bool _isPhoneLoading = false;
  bool _isOtpSent = false;
  String? _verificationId;
  String _verifiedPhone = '';

  // ── Save ──────────────────────────────────────────────────────────────────
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    final currentUser = FirebaseAuth.instance.currentUser;
    _nameController =
        TextEditingController(text: currentUser?.displayName ?? '');

    // If user signed in via phone, their number is already verified –
    // prefill and skip the OTP step.
    final phone = currentUser?.phoneNumber;
    if (phone != null && phone.isNotEmpty) {
      _verifiedPhone = phone;
      // Remove +91 prefix for display in the field
      _phoneController.text =
          phone.startsWith('+91') ? phone.substring(3) : phone;
      _isOtpSent = true; // treat as already verified
      _verificationId = 'phone_auth'; // sentinel
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _otpController.dispose();
    _qualificationsController.dispose();
    super.dispose();
  }

  // ── Helpers ────────────────────────────────────────────────────────────────
  bool get _phoneAlreadyVerifiedViaAuth =>
      FirebaseAuth.instance.currentUser?.phoneNumber != null &&
      FirebaseAuth.instance.currentUser!.phoneNumber!.isNotEmpty;

  /// Opens a bottom sheet so the user can pick a photo from Camera or Gallery.
  Future<void> _pickIdProof() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40, height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2)),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                child: Text(
                  'Upload Photo ID',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  'Upload a clear photo of your Aadhaar, PAN, Passport, or Driving Licence.',
                  style: TextStyle(fontSize: 13, color: Colors.black54),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 12),
              ListTile(
                leading: const Icon(Icons.camera_alt_outlined, color: AppColors.primary),
                title: const Text('Take a Photo'),
                onTap: () => Navigator.pop(ctx, ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined, color: AppColors.primary),
                title: const Text('Choose from Gallery'),
                onTap: () => Navigator.pop(ctx, ImageSource.gallery),
              ),
            ],
          ),
        ),
      ),
    );

    if (source == null || !mounted) return;
    final XFile? image = await _picker.pickImage(
      source: source,
      imageQuality: 85,
      maxWidth: 1500,
    );
    if (image != null) {
      final picked = await PickedImage.fromXFile(image);
      if (mounted) setState(() => _idProofFile = picked);
    }
  }

  // ── Phone OTP: Send ───────────────────────────────────────────────────────
  void _sendOTP() async {
    final phone = _phoneController.text.trim();
    if (phone.length < 10) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter a valid 10-digit phone number')));
      return;
    }

    setState(() => _isPhoneLoading = true);

    final fullPhone = phone.startsWith('+') ? phone : '+91$phone';

    await _authService.verifyPhoneNumber(
      phoneNumber: fullPhone,
      codeSent: (verificationId, _) {
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
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                  content: Text(
                      error.message ?? 'Verification failed. Try again.')));
        }
      },
      codeAutoRetrievalTimeout: (verificationId) {
        if (mounted) setState(() => _verificationId = verificationId);
      },
    );
  }

  // ── Phone OTP: Verify ─────────────────────────────────────────────────────
  void _verifyOTP() async {
    final otp = _otpController.text.trim();
    if (otp.length < 6 || _verificationId == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Enter the 6-digit OTP')));
      return;
    }

    setState(() => _isPhoneLoading = true);

    try {
      // Link the verified phone credential to the existing Google account
      final PhoneAuthCredential credential = PhoneAuthProvider.credential(
        verificationId: _verificationId!,
        smsCode: otp,
      );

      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser != null) {
        try {
          // Try to link — if already linked, it will throw. We catch and move on.
          await currentUser.linkWithCredential(credential);
        } on FirebaseAuthException catch (e) {
          // credential-already-in-use or provider-already-linked → still verified
          if (e.code != 'credential-already-in-use' &&
              e.code != 'provider-already-linked') {
            rethrow;
          }
        }
      }

      final phone = _phoneController.text.trim();
      _verifiedPhone = phone.startsWith('+') ? phone : '+91$phone';

      if (mounted) {
        setState(() => _isPhoneLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Phone number verified! ✓')));
        // Advance back to the details step (phone is now confirmed)
        setState(() => _currentStep = 0);
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        setState(() => _isPhoneLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(e.message ?? 'Invalid OTP.')));
      }
    }
  }

  // ── Submit profile ────────────────────────────────────────────────────────
  void _submitProfile() async {
    // Make sure phone is verified before saving
    if (_verifiedPhone.isEmpty) {
      // Navigate to phone verify step
      setState(() => _currentStep = 1);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Please verify your phone number first.')));
      return;
    }

    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    bool success = await _dbService.saveUserProfile(
      fullName: _nameController.text.trim(),
      phone: _verifiedPhone,
      gender: _selectedGender,
      city: _selectedCity,
      // Always 'Pending Verification' — 'Uploaded' was never queried by the admin panel.
      idProofStatus: _idProofFile != null ? 'Pending Verification' : 'Not Uploaded',
      qualifications: _qualificationsController.text.trim().isEmpty
          ? null
          : _qualificationsController.text.trim(),
    );

    if (success && _idProofFile != null) {
      await _dbService.uploadIdProof(_idProofFile!);
    }

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (success) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const MainLayout()),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to save profile. Try again.')),
      );
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        flexibleSpace: Container(
            decoration:
                const BoxDecoration(gradient: AppColors.primaryGradient)),
        title: Text(
          _currentStep == 0 ? 'Complete Your Profile' : 'Verify Phone Number',
          style:
              const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        leading: _currentStep == 1
            ? IconButton(
                icon:
                    const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
                onPressed: () => setState(() {
                  _currentStep = 0;
                  _isOtpSent = false;
                  _otpController.clear();
                }),
              )
            : null,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _currentStep == 0
              ? _buildProfileForm()
              : _buildPhoneVerification(),
    );
  }

  // ── Step 0: Profile Details ───────────────────────────────────────────────
  Widget _buildProfileForm() {
    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Form(
        key: _formKey,
        child: ListView(
          children: [
            const Text(
              'Tell us a bit more about yourself to start using Chalbro.',
              style: TextStyle(color: AppColors.greyText, fontSize: 14),
            ),
            const SizedBox(height: 24),

            // Full Name
            TextFormField(
              controller: _nameController,
              decoration: InputDecoration(
                  labelText: 'Full Name',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16)),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 16)),
              validator: (val) =>
                  val!.isEmpty ? 'Please enter your full name' : null,
            ),
            const SizedBox(height: 16),

            // Phone Number (shows verified badge OR verify button)
            _buildPhoneRow(),
            const SizedBox(height: 16),

            // Gender
            DropdownButtonFormField<String>(
              value: _selectedGender,
              decoration: InputDecoration(
                  labelText: 'Gender',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16)),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 16)),
              items: _genders
                  .map((g) => DropdownMenuItem(value: g, child: Text(g)))
                  .toList(),
              onChanged: (val) => setState(() => _selectedGender = val!),
            ),
            const SizedBox(height: 16),

            // City
            FutureBuilder<List<String>>(
              future: _dbService.getCities(),
              builder: (context, snapshot) {
                List<String> cities = ['Surat'];
                if (snapshot.hasData) {
                  cities = snapshot.data!;
                  if (!cities.contains(_selectedCity)) {
                    _selectedCity = cities.first;
                  }
                }
                return DropdownButtonFormField<String>(
                  value: _selectedCity,
                  decoration: InputDecoration(
                      labelText: 'Primary Operation City',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16)),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 16)),
                  items: cities
                      .map(
                          (c) => DropdownMenuItem(value: c, child: Text(c)))
                      .toList(),
                  onChanged: (val) => setState(() => _selectedCity = val!),
                );
              },
            ),
            const SizedBox(height: 16),

            // Skills / Qualifications
            TextFormField(
              controller: _qualificationsController,
              decoration: InputDecoration(
                labelText: 'Your Skills / Qualifications',
                hintText: 'e.g. Plumber, Electrician, Driver, Tutor',
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16)),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                prefixIcon:
                    const Icon(Icons.work_outline, color: AppColors.primary),
              ),
            ),
            const SizedBox(height: 20),

            // ID Proof
            _buildIdProofCard(),
            const SizedBox(height: 32),

            ElevatedButton(
              onPressed: _submitProfile,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Save & Continue',
                  style: TextStyle(color: Colors.white, fontSize: 16)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIdProofCard() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header row
        Row(
          children: [
            const Icon(Icons.badge_outlined, color: AppColors.primary, size: 20),
            const SizedBox(width: 8),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Photo ID Proof  (Required)',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  Text(
                    'Aadhaar · PAN · Passport · Driving Licence',
                    style: TextStyle(fontSize: 11, color: AppColors.greyText),
                  ),
                ],
              ),
            ),
            TextButton.icon(
              onPressed: _pickIdProof,
              icon: Icon(
                _idProofFile != null ? Icons.edit_outlined : Icons.upload_outlined,
                size: 16,
              ),
              label: Text(_idProofFile != null ? 'Change' : 'Upload'),
              style: TextButton.styleFrom(foregroundColor: AppColors.primary),
            ),
          ],
        ),

        // Preview (shown once a file is selected)
        if (_idProofFile != null) ...[
          const SizedBox(height: 10),
          Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.memory(
                  _idProofFile!.bytes,
                  height: 160,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.success,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check, color: Colors.white, size: 13),
                      SizedBox(width: 4),
                      Text('Photo Selected',
                          style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ] else ...[
          const SizedBox(height: 8),
          Container(
            height: 100,
            decoration: BoxDecoration(
              color: AppColors.tertiary,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade300, style: BorderStyle.solid),
            ),
            child: InkWell(
              onTap: _pickIdProof,
              borderRadius: BorderRadius.circular(12),
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add_photo_alternate_outlined, size: 32, color: AppColors.greyText),
                    SizedBox(height: 6),
                    Text('Tap to upload ID photo', style: TextStyle(color: AppColors.greyText, fontSize: 13)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildPhoneRow() {
    final bool verified = _verifiedPhone.isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        border: Border.all(
          color: verified ? AppColors.success : Colors.grey.shade400,
          width: 1.2,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Icon(
          Icons.phone_android_rounded,
          color: verified ? AppColors.success : AppColors.primary,
        ),
        title: Text(
          verified
              ? (_verifiedPhone.startsWith('+91')
                  ? _verifiedPhone
                  : '+91 $_verifiedPhone')
              : 'Phone number not verified',
          style: TextStyle(
            fontSize: 15,
            color: verified ? Colors.black87 : AppColors.greyText,
            fontWeight: verified ? FontWeight.w500 : FontWeight.normal,
          ),
        ),
        subtitle: Text(
          verified ? 'Verified ✓' : 'Required – tap to verify',
          style: TextStyle(
            color: verified ? AppColors.success : Colors.orange.shade700,
            fontSize: 12,
          ),
        ),
        trailing: verified
            ? null
            : TextButton(
                onPressed: () => setState(() => _currentStep = 1),
                child: const Text('Verify',
                    style: TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600)),
              ),
      ),
    );
  }

  // ── Step 1: Phone Verification ────────────────────────────────────────────
  Widget _buildPhoneVerification() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Banner
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                const Icon(Icons.verified_user_rounded,
                    color: Colors.white, size: 32),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Verify Your Phone Number',
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'We\'ll send an OTP to confirm this number belongs to you.',
                        style: TextStyle(
                            color: Colors.white.withOpacity(0.85),
                            fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),

          if (!_isOtpSent) ...[
            // Phone input
            TextField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              maxLength: 10,
              style: const TextStyle(fontSize: 16),
              decoration: InputDecoration(
                labelText: 'Phone Number',
                prefixText: '+91  ',
                counterText: '',
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16)),
                prefixIcon: const Icon(Icons.phone_android_rounded,
                    color: AppColors.primary),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 18),
              ),
            ),
            const SizedBox(height: 20),
            _isPhoneLoading
                ? const Center(child: CircularProgressIndicator())
                : ElevatedButton(
                    onPressed: _sendOTP,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Send OTP',
                        style: TextStyle(color: Colors.white, fontSize: 16)),
                  ),
          ] else ...[
            // OTP input
            Text(
              'OTP sent to +91 ${_phoneController.text.trim()}',
              style:
                  const TextStyle(color: AppColors.greyText, fontSize: 14),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _otpController,
              keyboardType: TextInputType.number,
              maxLength: 6,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 28,
                  letterSpacing: 12,
                  fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                counterText: '',
                hintText: '––––––',
                hintStyle: TextStyle(
                    color: Colors.grey.shade300,
                    fontSize: 28,
                    letterSpacing: 12),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16)),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 20, vertical: 20),
              ),
            ),
            const SizedBox(height: 20),
            _isPhoneLoading
                ? const Center(child: CircularProgressIndicator())
                : ElevatedButton(
                    onPressed: _verifyOTP,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Verify OTP',
                        style:
                            TextStyle(color: Colors.white, fontSize: 16)),
                  ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: _isPhoneLoading
                  ? null
                  : () => setState(() {
                        _isOtpSent = false;
                        _otpController.clear();
                      }),
              child: const Text(
                'Change phone number',
                style: TextStyle(color: AppColors.greyText),
              ),
            ),
            TextButton(
              onPressed: _isPhoneLoading ? null : _sendOTP,
              child: const Text(
                'Resend OTP',
                style: TextStyle(color: AppColors.primary),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
