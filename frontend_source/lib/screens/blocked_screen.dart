import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import '../services/database_service.dart';
import '../utils/picked_image.dart';

/// Shown when a user's account is banned (permanent) or paused (temporary).
///
/// If [isPaused] is true AND [isIdIssue] is true, the screen shows an
/// option to re-upload a photo ID so the user can resolve the issue without
/// needing to contact support.
class BlockedScreen extends StatefulWidget {
  final bool isPaused;
  final String? reason;
  /// Set to true when the pause is specifically because of an ID verification
  /// problem (rejected or invalid photo). Shows the re-upload UI.
  final bool isIdIssue;

  const BlockedScreen({
    super.key,
    required this.isPaused,
    this.reason,
    this.isIdIssue = false,
  });

  @override
  State<BlockedScreen> createState() => _BlockedScreenState();
}

class _BlockedScreenState extends State<BlockedScreen> {
  final DatabaseService _dbService = DatabaseService();
  final ImagePicker _picker = ImagePicker();

  PickedImage? _newIdFile;
  bool _isUploading = false;
  bool _uploadDone = false;

  Future<void> _pickAndUpload() async {
    // Let user choose source
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40, height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                  color: Colors.white24, borderRadius: BorderRadius.circular(2)),
            ),
            const Text('Upload New Photo ID',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 4),
            const Text(
              'Aadhaar · PAN · Passport · Driving Licence',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
            const SizedBox(height: 12),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined, color: Colors.orange),
              title: const Text('Take a Photo', style: TextStyle(color: Colors.white)),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined, color: Colors.orange),
              title: const Text('Choose from Gallery', style: TextStyle(color: Colors.white)),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (source == null || !mounted) return;

    final XFile? picked = await _picker.pickImage(
      source: source,
      imageQuality: 85,
      maxWidth: 1500,
    );
    if (picked == null || !mounted) return;

    final pickedImage = await PickedImage.fromXFile(picked);
    if (!mounted) return;
    setState(() {
      _newIdFile = pickedImage;
      _isUploading = true;
    });

    final url = await _dbService.uploadIdProof(_newIdFile!);

    if (!mounted) return;
    setState(() => _isUploading = false);

    if (url != null) {
      setState(() => _uploadDone = true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ New ID photo submitted! Admin will review shortly.'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 4),
          ),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Upload failed. Please check your connection and try again.'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isIdIssue = widget.isIdIssue;
    final isPaused = widget.isPaused;

    final title = isPaused
        ? (isIdIssue ? 'ID Verification Required' : 'Account Paused')
        : 'Account Suspended';
    final subtitle = isPaused
        ? (isIdIssue
            ? 'Your account has been paused because your ID proof was rejected or is invalid.'
            : 'Your account has been temporarily paused by our team.')
        : 'Your account has been permanently suspended.';
    final icon = isPaused
        ? (isIdIssue ? Icons.badge_outlined : Icons.pause_circle_filled)
        : Icons.block_rounded;
    final accentColor = isPaused
        ? (isIdIssue ? const Color(0xFFFF6B35) : const Color(0xFFFF8C00))
        : const Color(0xFFD32F2F);
    final bgColor = isPaused
        ? (isIdIssue ? const Color(0xFF1A0A00) : const Color(0xFF1A0E00))
        : const Color(0xFF1A0000);

    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: 20),

              // Animated pulsing icon
              _PulsingIcon(icon: icon, color: accentColor),
              const SizedBox(height: 32),

              // Title
              Text(
                title,
                style: TextStyle(
                  color: accentColor,
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 14),

              // Subtitle
              Text(
                subtitle,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.75),
                  fontSize: 15,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),

              // Reason box
              if (widget.reason != null && widget.reason!.isNotEmpty) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: accentColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: accentColor.withOpacity(0.4)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isIdIssue ? 'REASON FOR REJECTION:' : 'REASON:',
                        style: TextStyle(
                          color: accentColor,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        widget.reason!,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.85),
                          fontSize: 14,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
              ],

              // ── ID Re-upload section (only for ID-related pauses) ──
              if (isIdIssue && isPaused) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: accentColor.withOpacity(0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.upload_file_outlined, color: accentColor, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            'Re-upload Your Photo ID',
                            style: TextStyle(
                              color: accentColor,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Upload a clear, valid government photo ID (Aadhaar, PAN, Passport, or Driving Licence). '
                        'Admin will review and re-activate your account.',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.65),
                          fontSize: 12,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Preview
                      if (_newIdFile != null) ...[
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.memory(
                            _newIdFile!.bytes,
                            height: 140,
                            width: double.infinity,
                            fit: BoxFit.cover,
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],

                      if (_uploadDone) ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.green.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.green.withOpacity(0.4)),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.check_circle_outline, color: Colors.green, size: 20),
                              SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Photo submitted! Your account will be reviewed within 24 hours.',
                                  style: TextStyle(color: Colors.green, fontSize: 13),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: accentColor,
                              side: BorderSide(color: accentColor.withOpacity(0.6)),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            icon: const Icon(Icons.refresh, size: 18),
                            label: const Text('Upload Different Photo'),
                            onPressed: _isUploading ? null : _pickAndUpload,
                          ),
                        ),
                      ] else ...[
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: accentColor,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            icon: _isUploading
                                ? const SizedBox(
                                    width: 18, height: 18,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: Colors.white))
                                : const Icon(Icons.upload_rounded, color: Colors.white),
                            label: Text(
                              _isUploading ? 'Uploading…' : 'Upload Photo ID',
                              style: const TextStyle(
                                  color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                            ),
                            onPressed: _isUploading ? null : _pickAndUpload,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 20),
              ],

              // Info card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.04),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withOpacity(0.08)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.mail_outline_rounded, color: Colors.white38, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'For further help, contact support@chalbro.in',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.45),
                          fontSize: 12,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),

              // Sign Out
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white54,
                    side: const BorderSide(color: Colors.white12),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.logout_rounded, size: 18),
                  label: const Text('Sign Out', style: TextStyle(fontSize: 15)),
                  onPressed: () async {
                    await FirebaseAuth.instance.signOut();
                  },
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}

/// A continuously pulsing icon widget for emphasis.
class _PulsingIcon extends StatefulWidget {
  final IconData icon;
  final Color color;
  const _PulsingIcon({required this.icon, required this.color});

  @override
  State<_PulsingIcon> createState() => _PulsingIconState();
}

class _PulsingIconState extends State<_PulsingIcon>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _scaleAnim = Tween<double>(begin: 0.92, end: 1.08).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scaleAnim,
      child: Container(
        width: 100,
        height: 100,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: widget.color.withOpacity(0.15),
          border: Border.all(color: widget.color.withOpacity(0.4), width: 2),
        ),
        child: Icon(widget.icon, color: widget.color, size: 52),
      ),
    );
  }
}
