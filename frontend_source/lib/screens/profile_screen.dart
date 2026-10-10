import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import '../utils/app_colors.dart';
import '../utils/picked_image.dart';
import '../services/auth_service.dart';
import '../services/database_service.dart';
import '../services/payment_mode_service.dart';
import '../utils/wallet_balance.dart';
import 'wallet_screen.dart';
import 'settings_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  void _onPaymentMode() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    PaymentModeService.instance.razorpayOn.addListener(_onPaymentMode);
  }

  @override
  void dispose() {
    PaymentModeService.instance.razorpayOn.removeListener(_onPaymentMode);
    super.dispose();
  }

  // Single DatabaseService instance — avoids creating a new stream on every rebuild
  final DatabaseService _db = DatabaseService();

  // Profile edit is now in SettingsScreen


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: StreamBuilder<DocumentSnapshot>(
        stream: _db.streamUserData(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: AppColors.primary));
          }
          if (!snapshot.hasData || !snapshot.data!.exists) {
            return const Center(child: Text("Profile load issue."));
          }

          final userData = snapshot.data!.data() as Map<String, dynamic>;

          int wallet = balanceToShow(userData, razorpayOn: PaymentModeService.instance.razorpayOn.value);
          int tasksDone = userData['tasksDone'] ?? 0;
          double ratingSum = (userData['ratingSum'] ?? 0).toDouble();
          int ratingCount = userData['ratingCount'] ?? 0;
          bool isOpenForWork = userData['isOpenForWork'] ?? false;
          String name = userData['fullName'] ?? 'User';
          String phone = userData['phone'] ?? '';
          String? profilePhotoUrl = userData['profilePhotoUrl'];
          String idProofStatus = userData['idProofStatus'] ?? 'Unverified';

          double trustScore = ratingCount == 0 ? 5.0 : (ratingSum / ratingCount);

          return SafeArea(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.settings_outlined, color: AppColors.darkText),
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => SettingsScreen(userData: userData),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20.0),
                    child: Text(
                      'Profile',
                      style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: AppColors.darkText),
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  // Purple User Card
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20.0),
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Row(
                        children: [
                          Stack(
                            children: [
                              GestureDetector(
                                onTap: () async {
                                  final picker = ImagePicker();
                                  final pickedFile = await picker.pickImage(source: ImageSource.gallery);
                                  if (pickedFile != null && context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Uploading photo...')));
                                    await DatabaseService().uploadProfilePhoto(await PickedImage.fromXFile(pickedFile));
                                  }
                                },
                                child: CircleAvatar(
                                  radius: 32,
                                  backgroundColor: Colors.white.withOpacity(0.2),
                                  backgroundImage: profilePhotoUrl != null ? NetworkImage(profilePhotoUrl) : null,
                                  child: profilePhotoUrl == null
                                      ? Text(
                                          name.isNotEmpty ? name[0].toUpperCase() : 'U',
                                          style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                                        )
                                      : null,
                                ),
                              ),
                              Positioned(
                                right: 0,
                                bottom: 0,
                                child: Container(
                                  padding: const EdgeInsets.all(2),
                                  decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                                  child: const Icon(Icons.camera_alt, color: AppColors.primary, size: 16),
                                ),
                              )
                            ],
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name,
                                  style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  phone,
                                  style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 14),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 24),
                  
                  // Stats Row
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20.0),
                    child: Row(
                      children: [
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 20),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: Colors.grey.withOpacity(0.1)),
                              boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.05), blurRadius: 10, spreadRadius: 2)],
                            ),
                            child: Column(
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(trustScore.toStringAsFixed(1), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.darkText)),
                                    const SizedBox(width: 4),
                                    const Icon(Icons.star, color: Colors.orange, size: 20),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                const Text('Trust Score', style: TextStyle(color: AppColors.greyText, fontSize: 12)),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 20),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: Colors.grey.withOpacity(0.1)),
                              boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.05), blurRadius: 10, spreadRadius: 2)],
                            ),
                            child: Column(
                              children: [
                                Text('$tasksDone', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.darkText)),
                                const SizedBox(height: 4),
                                const Text('Tasks Done', style: TextStyle(color: AppColors.greyText, fontSize: 12)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 24),
                  
                  // Menu Items
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20.0),
                    child: Column(
                      children: [
                        GestureDetector(
                          onTap: idProofStatus == 'Verified' ? null : () async {
                            final picker = ImagePicker();
                            final pickedFile = await picker.pickImage(source: ImageSource.gallery);
                            if (pickedFile != null && context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Uploading ID Proof...')));
                              await DatabaseService().uploadIdProof(await PickedImage.fromXFile(pickedFile));
                            }
                          },
                          child: _buildMenuListItem(
                            icon: Icons.badge_outlined,
                            title: 'Govt ID',
                            trailingText: idProofStatus,
                            trailingColor: AppColors.primary,
                            trailingBgColor: AppColors.secondary,
                          ),
                        ),
                        const SizedBox(height: 12),
                        GestureDetector(
                          onTap: () {
                            Navigator.push(context, MaterialPageRoute(builder: (_) => const WalletScreen()));
                          },
                          child: _buildMenuListItem(
                            icon: Icons.account_balance_wallet_outlined,
                            title: 'My Wallet',
                            trailingText: '₹$wallet',
                            trailingColor: wallet < 0 ? AppColors.red : AppColors.success,
                            trailingBgColor: wallet < 0 ? AppColors.pastelRed : AppColors.pastelGreen,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.grey.withOpacity(0.1)),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(12)),
                                child: const Icon(Icons.work_outline, color: AppColors.darkText, size: 20),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('Open for Work', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.darkText)),
                                    const SizedBox(height: 2),
                                    Text('Let others find you', style: TextStyle(color: AppColors.greyText.withOpacity(0.7), fontSize: 12)),
                                  ],
                                ),
                              ),
                              Switch(
                                value: isOpenForWork,
                                activeColor: Colors.white,
                                activeTrackColor: AppColors.primary,
                                inactiveThumbColor: Colors.grey,
                                inactiveTrackColor: Colors.grey.withOpacity(0.2),
                                onChanged: (val) => DatabaseService().toggleOpenForWork(val),
                              ),
                            ],
                          ),
                        ),
                        
                        const SizedBox(height: 40),
                        
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton(
                            onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => SettingsScreen(userData: userData),
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(color: AppColors.primary.withOpacity(0.4)),
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            ),
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.settings_outlined, color: AppColors.primary),
                                SizedBox(width: 8),
                                Text('Settings', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 16)),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton(
                            onPressed: () => AuthService().signOut(),
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(color: AppColors.red.withOpacity(0.3)),
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            ),
                            child: const Text('Logout', style: TextStyle(color: AppColors.red, fontWeight: FontWeight.bold, fontSize: 16)),
                          ),
                        ),
                        const SizedBox(height: 32),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: AppColors.primary.withOpacity(0.2)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: const [
                              Text('Need Help? Contact Support', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.darkText)),
                              SizedBox(height: 12),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.email_outlined, size: 16, color: AppColors.primary),
                                  SizedBox(width: 8),
                                  Text('support@chalbro.com', style: TextStyle(color: AppColors.darkText)),
                                ],
                              ),
                              SizedBox(height: 8),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.phone_outlined, size: 16, color: AppColors.primary),
                                  SizedBox(width: 8),
                                  Text('+91 99999 99999', style: TextStyle(color: AppColors.darkText)),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 40),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildMenuListItem({
    required IconData icon,
    required String title,
    required String trailingText,
    required Color trailingColor,
    required Color trailingBgColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.withOpacity(0.1)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: AppColors.darkText, size: 20),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.darkText)),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: trailingBgColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              trailingText,
              style: TextStyle(color: trailingColor, fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
