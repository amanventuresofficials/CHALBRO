import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../utils/app_colors.dart';
import '../utils/picked_image.dart';
import '../utils/language_provider.dart';
import '../widgets/language_picker_dialog.dart';
import '../services/auth_service.dart';
import '../services/database_service.dart';

class SettingsScreen extends StatefulWidget {
  final Map<String, dynamic> userData;
  const SettingsScreen({super.key, required this.userData});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final DatabaseService _db = DatabaseService();

  late TextEditingController _nameController;
  late TextEditingController _phoneController;
  late TextEditingController _qualController;
  late String _selectedCity;
  late bool _isOpenForWork;
  late bool _isHiddenFromSearch;
  late bool _leaderboardOptIn;

  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.userData['fullName'] ?? '');
    _phoneController = TextEditingController(text: widget.userData['phone'] ?? '');
    _qualController = TextEditingController(text: widget.userData['qualifications'] ?? '');
    _selectedCity = widget.userData['city'] ?? 'Surat';
    _isOpenForWork = widget.userData['isOpenForWork'] ?? false;
    _isHiddenFromSearch = widget.userData['isHiddenFromSearch'] ?? false;
    _leaderboardOptIn = widget.userData['leaderboardOptIn'] ?? false;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _qualController.dispose();
    super.dispose();
  }

  bool _isValidPhone(String phone) {
    final cleaned = phone.replaceAll(RegExp(r'\s+'), '');
    return RegExp(r'^\d{10}$').hasMatch(cleaned);
  }

  Future<void> _saveProfile() async {
    final s = context.read<LanguageProvider>().strings;
    final phone = _phoneController.text.trim();
    if (phone.isNotEmpty && !_isValidPhone(phone)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(s.settingsInvalidPhone),
          backgroundColor: AppColors.red,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);
    await _db.saveUserProfile(
      fullName: _nameController.text.trim(),
      phone: phone,
      gender: widget.userData['gender'] ?? 'Male',
      city: _selectedCity,
      idProofStatus: widget.userData['idProofStatus'],
      qualifications: _qualController.text.trim(),
    );
    if (!mounted) return;
    setState(() => _isSaving = false);
    final s2 = context.read<LanguageProvider>().strings;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(s2.settingsProfileUpdated),
        backgroundColor: AppColors.success,
      ),
    );
  }

  Future<void> _pickProfilePhoto() async {
    final s = context.read<LanguageProvider>().strings;
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery, imageQuality: 75);
    if (pickedFile != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.settingsUploadingPhoto)));
      await _db.uploadProfilePhoto(await PickedImage.fromXFile(pickedFile));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(s.settingsPhotoUpdated), backgroundColor: AppColors.success),
        );
      }
    }
  }

  Future<void> _pickIdProof() async {
    if (widget.userData['idProofStatus'] == 'Verified') return;
    final s = context.read<LanguageProvider>().strings;
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery, imageQuality: 75);
    if (pickedFile != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.settingsUploadingId)));
      await _db.uploadIdProof(await PickedImage.fromXFile(pickedFile));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(s.settingsIdSubmitted),
            backgroundColor: AppColors.success,
          ),
        );
      }
    }
  }

  Future<void> _showDeleteAccountDialog() async {
    final s = context.read<LanguageProvider>().strings;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          s.settingsDeleteConfirmTitle,
          style: const TextStyle(color: AppColors.red, fontWeight: FontWeight.bold),
        ),
        content: Text(s.settingsDeleteConfirmBody),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s.cancel)),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(s.settingsDeleteAccount, style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm == true && mounted) {
      await AuthService().deleteAccount();
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<LanguageProvider>().strings;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        flexibleSpace: Container(
          decoration: const BoxDecoration(gradient: AppColors.primaryGradient),
        ),
        foregroundColor: Colors.white,
        title: Text(
          s.settingsTitle,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // ── PROFILE SECTION ─────────────────────────────────────────────
          _sectionHeader(s.settingsSectionProfile, Icons.person_outline),
          const SizedBox(height: 12),
          _settingsCard(children: [
            _settingsTile(
              icon: Icons.camera_alt_outlined,
              iconBg: AppColors.pastelPurple,
              iconColor: AppColors.pastelPurpleIcon,
              title: s.settingsProfilePhoto,
              subtitle: s.settingsProfilePhotoSubtitle,
              onTap: _pickProfilePhoto,
            ),
            _divider(),
            _settingsTile(
              icon: Icons.badge_outlined,
              iconBg: widget.userData['idProofStatus'] == 'Verified'
                  ? AppColors.pastelGreen
                  : AppColors.pastelOrange,
              iconColor: widget.userData['idProofStatus'] == 'Verified'
                  ? AppColors.pastelGreenIcon
                  : AppColors.pastelOrangeIcon,
              title: s.settingsGovtId,
              subtitle: widget.userData['idProofStatus'] ?? 'Pending Verification',
              onTap: widget.userData['idProofStatus'] == 'Verified' ? null : _pickIdProof,
            ),
          ]),
          const SizedBox(height: 12),
          _settingsCard(children: [
            _buildTextField(
              controller: _nameController,
              label: s.settingsFullName,
              icon: Icons.person_outline,
            ),
            const SizedBox(height: 4),
            _buildTextField(
              controller: _phoneController,
              label: s.settingsPhone,
              icon: Icons.phone_outlined,
              inputType: TextInputType.phone,
              prefixText: '+91 ',
            ),
            const SizedBox(height: 4),
            _buildTextField(
              controller: _qualController,
              label: s.settingsSkills,
              icon: Icons.work_outline,
              hint: s.settingsSkillsHint,
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: FutureBuilder<List<String>>(
                future: _db.getCities(),
                builder: (context, snapshot) {
                  List<String> cities = [_selectedCity];
                  if (snapshot.hasData) {
                    cities = snapshot.data!;
                    if (!cities.contains(_selectedCity)) cities.add(_selectedCity);
                  }
                  return DropdownButtonFormField<String>(
                    value: _selectedCity,
                    decoration: InputDecoration(
                      labelText: s.settingsCity,
                      prefixIcon: const Icon(Icons.location_city_outlined, color: AppColors.primary),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                    ),
                    items: cities
                        .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                        .toList(),
                    onChanged: (val) => setState(() => _selectedCity = val!),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _saveProfile,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _isSaving
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        )
                      : Text(
                          s.settingsSaveProfile,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                ),
              ),
            ),
          ]),

          // ── ACCOUNT PREFERENCES ──────────────────────────────────────────
          const SizedBox(height: 28),
          _sectionHeader(s.settingsSectionPreferences, Icons.tune_outlined),
          const SizedBox(height: 12),
          _settingsCard(children: [
            _switchTile(
              icon: Icons.work_outline,
              iconBg: AppColors.pastelGreen,
              iconColor: AppColors.pastelGreenIcon,
              title: s.settingsOpenForWork,
              subtitle: s.settingsOpenForWorkSubtitle,
              value: _isOpenForWork,
              onChanged: (val) {
                setState(() => _isOpenForWork = val);
                _db.toggleOpenForWork(val);
              },
            ),
            _divider(),
            _switchTile(
              icon: Icons.visibility_off_outlined,
              iconBg: AppColors.pastelBlue,
              iconColor: AppColors.pastelBlueIcon,
              title: s.settingsHideFromSearch,
              subtitle: s.settingsHideFromSearchSubtitle,
              value: _isHiddenFromSearch,
              onChanged: (val) {
                setState(() => _isHiddenFromSearch = val);
                _db.setHiddenFromSearch(val);
              },
            ),
            _divider(),
            _switchTile(
              icon: Icons.emoji_events_outlined,
              iconBg: AppColors.pastelOrange,
              iconColor: AppColors.pastelOrangeIcon,
              title: s.settingsJoinLeaderboard,
              subtitle: s.settingsJoinLeaderboardSubtitle,
              value: _leaderboardOptIn,
              onChanged: (val) {
                setState(() => _leaderboardOptIn = val);
                _db.setLeaderboardOptIn(val);
              },
            ),
          ]),

          // ── LANGUAGE SECTION ─────────────────────────────────────────────
          const SizedBox(height: 28),
          _sectionHeader(s.settingsSectionLanguage, Icons.language_outlined),
          const SizedBox(height: 12),
          _settingsCard(children: [
            _settingsTile(
              icon: Icons.translate,
              iconBg: AppColors.pastelPurple,
              iconColor: AppColors.pastelPurpleIcon,
              title: s.settingsLanguageLabel,
              subtitle: s.settingsLanguageSubtitle,
              onTap: () => LanguagePickerDialog.show(context),
            ),
          ]),

          // ── PRIVACY NOTE ────────────────────────────────────────────────
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.pastelBlue,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.pastelBlueIcon.withOpacity(0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.privacy_tip_outlined, size: 16, color: AppColors.pastelBlueIcon),
                    const SizedBox(width: 6),
                    Text(s.settingsPrivacyNoteTitle, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.pastelBlueIcon)),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  s.settingsPrivacyNoteBody,
                  style: const TextStyle(fontSize: 12, color: AppColors.darkText, height: 1.5),
                ),
              ],
            ),
          ),

          // ── ACCOUNT / DANGER ZONE ─────────────────────────────────────────
          const SizedBox(height: 28),
          _sectionHeader(s.settingsSectionAccount, Icons.security_outlined),
          const SizedBox(height: 12),
          _settingsCard(children: [
            _settingsTile(
              icon: Icons.logout,
              iconBg: AppColors.pastelRed,
              iconColor: AppColors.pastelRedIcon,
              title: s.settingsLogout,
              subtitle: s.settingsLogoutSubtitle,
              onTap: () => AuthService().signOut(),
              trailing: const SizedBox.shrink(),
            ),
            _divider(),
            _settingsTile(
              icon: Icons.delete_forever_outlined,
              iconBg: const Color(0xFFFFE5E5),
              iconColor: AppColors.red,
              title: s.settingsDeleteAccount,
              subtitle: s.settingsDeleteAccountSubtitle,
              onTap: _showDeleteAccountDialog,
              trailing: const Icon(Icons.chevron_right, color: AppColors.red),
              titleColor: AppColors.red,
            ),
          ]),

          const SizedBox(height: 32),

          // ── APP INFO ────────────────────────────────────────────────────
          Center(
            child: Column(
              children: [
                Container(
                  height: 56,
                  width: 56,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.08),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Image.asset(
                    'assets/images/logo.png',
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'ChalBro',
                  style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.greyText, fontSize: 16),
                ),
                const SizedBox(height: 4),
                const Text('Version 1.0.0', style: TextStyle(color: AppColors.greyText, fontSize: 12)),
                const SizedBox(height: 4),
                const Text(
                  'support@chalbro.com  •  +91 99999 99999',
                  style: TextStyle(color: AppColors.greyText, fontSize: 11),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  // ── BUILDER HELPERS ───────────────────────────────────────────────────────

  Widget _sectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.primary),
        const SizedBox(width: 8),
        Text(
          title.toUpperCase(),
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
            color: AppColors.greyText,
          ),
        ),
      ],
    );
  }

  Widget _settingsCard({required List<Widget> children}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.withOpacity(0.1)),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(children: children),
    );
  }

  Widget _settingsTile({
    required IconData icon,
    required Color iconBg,
    required Color iconColor,
    required String title,
    required String subtitle,
    VoidCallback? onTap,
    Widget? trailing,
    Color? titleColor,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                      color: titleColor ?? AppColors.darkText,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(subtitle, style: const TextStyle(fontSize: 12, color: AppColors.greyText)),
                ],
              ),
            ),
            trailing ?? const Icon(Icons.chevron_right, color: AppColors.greyText, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _switchTile({
    required IconData icon,
    required Color iconBg,
    required Color iconColor,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                    color: AppColors.darkText,
                  ),
                ),
                const SizedBox(height: 2),
                Text(subtitle, style: const TextStyle(fontSize: 12, color: AppColors.greyText)),
              ],
            ),
          ),
          Switch(
            value: value,
            activeColor: Colors.white,
            activeTrackColor: AppColors.primary,
            inactiveThumbColor: Colors.grey,
            inactiveTrackColor: Colors.grey.withOpacity(0.2),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType inputType = TextInputType.text,
    String? prefixText,
    String? hint,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: TextField(
        controller: controller,
        keyboardType: inputType,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          prefixText: prefixText,
          prefixIcon: Icon(icon, color: AppColors.primary, size: 20),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        ),
      ),
    );
  }

  Widget _divider() =>
      const Divider(height: 1, indent: 16, endIndent: 16, color: Color(0xFFEEEEEE));
}
