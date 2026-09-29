import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/app_colors.dart';
import '../services/database_service.dart';
import '../utils/picked_image.dart';
import 'package:image_picker/image_picker.dart';
import '../components/location_autocomplete.dart';

class PostTaskScreen extends StatefulWidget {
  final String? targetHelperUid;
  final String? targetHelperName;
  final String? initialCategory;

  const PostTaskScreen({
    super.key,
    this.targetHelperUid,
    this.targetHelperName,
    this.initialCategory,
  });

  @override
  State<PostTaskScreen> createState() => _PostTaskScreenState();
}

class _PostTaskScreenState extends State<PostTaskScreen> {
  final DatabaseService _dbService = DatabaseService();
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descController = TextEditingController();
  final _priceController = TextEditingController();
  final _startLocController = TextEditingController(); 
  final _destLocController = TextEditingController(); 
  final _customDurationController = TextEditingController(text: '24'); 
  PickedImage? _imageFile;
  bool _isUploading = false;

  late String selectedCategory; 
  bool isUrgent = false;

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    try {
      final pickedFile = await picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
      if (pickedFile != null) {
        final picked = await PickedImage.fromXFile(pickedFile);
        if (mounted) setState(() => _imageFile = picked);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error picking image: $e')));
      }
    }
  }

  final Map<String, Duration> _durationOptions = {
    '10 Minutes': const Duration(minutes: 10),
    '30 Minutes': const Duration(minutes: 30),
    '1 Hour': const Duration(hours: 1),
    '12 Hours': const Duration(hours: 12),
    '1 Day': const Duration(days: 1),
    '2 Days': const Duration(days: 2),
    '5 Days': const Duration(days: 5),
    '10 Days': const Duration(days: 10),
    'Custom': const Duration(),
  };
  String _selectedDurationKey = '2 Days';

  @override
  void initState() {
    super.initState();
    selectedCategory = widget.initialCategory ?? 'Assignment';
  }

  void _submitTask(String userProfileName, String userProfileCity) async {
    if (_formKey.currentState!.validate()) {
      setState(() => _isUploading = true);
      bool success = await _dbService.postTask(
        title: _titleController.text.trim(),
        description: _descController.text.trim(),
        price: int.parse(_priceController.text.trim()),
        category: selectedCategory,
        city: userProfileCity,
        postedByName: userProfileName,
        isUrgent: isUrgent,
        targetHelperUid: widget.targetHelperUid,
        startLocation: selectedCategory == 'Transport' ? _startLocController.text.trim() : null,
        destinationLocation: selectedCategory == 'Transport' ? _destLocController.text.trim() : null,
        endTime: _selectedDurationKey == 'Custom' 
            ? DateTime.now().add(Duration(hours: int.tryParse(_customDurationController.text.trim()) ?? 48))
            : DateTime.now().add(_durationOptions[_selectedDurationKey]!),
        image: _imageFile,
      );

      if (mounted) setState(() => _isUploading = false);

      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Task published'),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
          ),
        );

        _titleController.clear();
        _descController.clear();
        _priceController.clear();
        _startLocController.clear();
        _destLocController.clear();
        setState(() {
          isUrgent = false;
          _imageFile = null;
          selectedCategory = 'Transport';
        });

        if (Navigator.canPop(context)) {
          Navigator.pop(context);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
        stream: _dbService.streamUserData(),
        builder: (context, snapshot) {
          String profileName = "User";
          String profileCity = "Surat";

          if (snapshot.hasData && snapshot.data!.exists) {
            final data = snapshot.data!.data() as Map<String, dynamic>;
            profileName = data['fullName'] ?? 'User';
            profileCity = data['city'] ?? 'Surat';

            // --- RESTRICTION: Rejected ID prevents posting tasks ---
            final idStatus = data['idProofStatus'] ?? '';
            final rejectionReason = data['banReason'] as String?;

            if (idStatus == 'Rejected') {
              return Scaffold(
                backgroundColor: AppColors.surface,
                appBar: AppBar(
                  backgroundColor: AppColors.surface,
                  elevation: 0,
                  leading: IconButton(
                    icon: const Icon(Icons.arrow_back_ios_rounded, color: AppColors.darkText),
                    onPressed: () { if (Navigator.canPop(context)) Navigator.pop(context); },
                  ),
                  title: const Text('Post a Task',
                      style: TextStyle(color: AppColors.darkText, fontWeight: FontWeight.w900)),
                  centerTitle: true,
                ),
                body: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      const SizedBox(height: 16),

                      // Main alert card
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Colors.red.withOpacity(0.12), Colors.orange.withOpacity(0.06)],
                            begin: Alignment.topLeft, end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.redAccent.withOpacity(0.4)),
                        ),
                        child: Column(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.red.withOpacity(0.1),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.gpp_bad_rounded, color: Colors.redAccent, size: 48),
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'Proper Photo ID Required',
                              style: TextStyle(
                                  color: Colors.redAccent, fontSize: 20, fontWeight: FontWeight.bold),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 10),
                            const Text(
                              'Your ID photo was rejected by our team.\nYou must submit a valid ID to post tasks.',
                              style: TextStyle(color: Colors.black54, fontSize: 14, height: 1.5),
                              textAlign: TextAlign.center,
                            ),

                            // Show the specific rejection reason if available
                            if (rejectionReason != null && rejectionReason.isNotEmpty) ...[
                              const SizedBox(height: 16),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: Colors.red.withOpacity(0.07),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: Colors.redAccent.withOpacity(0.3)),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('REJECTION REASON:',
                                        style: TextStyle(
                                            color: Colors.redAccent,
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            letterSpacing: 1.0)),
                                    const SizedBox(height: 6),
                                    Text(rejectionReason,
                                        style: const TextStyle(
                                            color: Colors.black87, fontSize: 13, height: 1.4)),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Step guide
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: Colors.orange.withOpacity(0.06),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.orange.withOpacity(0.2)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('How to fix this:',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.orange)),
                            const SizedBox(height: 12),
                            const _StepRow(n: '1', text: 'Take a clear, well-lit photo of your ID'),
                            const SizedBox(height: 8),
                            const _StepRow(n: '2', text: 'Make sure all text & corners are visible'),
                            const SizedBox(height: 8),
                            const _StepRow(n: '3', text: 'Upload via your Profile → ID Proof'),
                            const SizedBox(height: 8),
                            const _StepRow(n: '4', text: 'Admin reviews within 24 hours'),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            padding: const EdgeInsets.symmetric(vertical: 15),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          icon: const Icon(Icons.upload_rounded, color: Colors.white),
                          label: const Text('Re-upload Photo ID',
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }
          }


          return Scaffold(
            backgroundColor: AppColors.surface,
            appBar: AppBar(
              backgroundColor: AppColors.surface,
              elevation: 0,
              leadingWidth: 80,
              leading: TextButton(
                onPressed: () {
                  if (Navigator.canPop(context)) Navigator.pop(context);
                },
                child: const Text('Cancel', style: TextStyle(color: AppColors.darkText, fontSize: 16)),
              ),
              title: Text(
                  widget.targetHelperName != null
                      ? 'Request ${widget.targetHelperName}'
                      : 'Post a Task',
                  style: const TextStyle(color: AppColors.darkText, fontWeight: FontWeight.w900, fontSize: 20)),
              centerTitle: true,
            ),
            body: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0),
              child: Form(
                key: _formKey,
                child: ListView(
                  children: [
                    const SizedBox(height: 16),
                    _buildTextField(
                      controller: _titleController,
                      label: 'Task Title',
                      validator: (val) => val!.isEmpty ? 'Enter a title' : null,
                    ),
                    const SizedBox(height: 16),
                    _buildTextField(
                      controller: _descController,
                      label: 'Description (Optional)',
                      maxLines: 3,
                    ),
                    const SizedBox(height: 16),
                    _buildTextField(
                      controller: _priceController,
                      label: 'Budget (₹)',
                      keyboardType: TextInputType.number,
                      validator: (val) => val!.isEmpty ? 'Enter your budget' : null,
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      value: selectedCategory,
                      decoration: InputDecoration(
                        labelText: 'Category',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      items: [
                        'Assignment',
                        'Transport',
                        'Home Svcs',
                        'Education',
                        'Events',
                        'Shopping',
                        'Repairs',
                        'Daily Help',
                        'Medicine Pickup',
                        'Document Delivery',
                        'Grocery Shopping',
                        'Furniture Moving',
                        'Other',
                      ]
                          .map((cat) => DropdownMenuItem(value: cat, child: Text(cat)))
                          .toList(),
                      onChanged: (val) => setState(() => selectedCategory = val!),
                    ),
                    const SizedBox(height: 16),
                    
                    if (selectedCategory == 'Transport') ...[
                      LocationAutocompleteField(
                        labelText: 'Start Location',
                        controller: _startLocController,
                        userCity: profileCity,
                        validator: (val) => val!.isEmpty ? 'Required for Transport' : null,
                      ),
                      const SizedBox(height: 16),
                      LocationAutocompleteField(
                        labelText: 'Destination Location',
                        controller: _destLocController,
                        userCity: profileCity,
                        validator: (val) => val!.isEmpty ? 'Required for Transport' : null,
                      ),
                      const SizedBox(height: 16),
                    ],
                    
                    DropdownButtonFormField<String>(
                      value: _selectedDurationKey,
                      decoration: InputDecoration(
                        labelText: 'Task Duration (Ends automatically)',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      items: _durationOptions.keys
                          .map((dur) => DropdownMenuItem(value: dur, child: Text(dur)))
                          .toList(),
                      onChanged: (val) => setState(() => _selectedDurationKey = val!),
                    ),
                    const SizedBox(height: 16),

                    if (_selectedDurationKey == 'Custom') ...[
                      _buildTextField(
                        controller: _customDurationController,
                        label: 'Custom Duration (Hours)',
                        keyboardType: TextInputType.number,
                        validator: (val) => val!.isEmpty ? 'Enter hours' : null,
                      ),
                      const SizedBox(height: 16),
                    ],
                    
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.grey.withOpacity(0.2)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Mark as Urgent', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                const SizedBox(height: 2),
                                Text('Needs immediate attention', style: TextStyle(color: AppColors.greyText.withOpacity(0.7), fontSize: 12)),
                              ],
                            ),
                          ),
                          Switch(
                            value: isUrgent,
                            activeColor: Colors.white,
                            activeTrackColor: AppColors.primary,
                            inactiveThumbColor: Colors.grey,
                            inactiveTrackColor: Colors.grey.withOpacity(0.2),
                            onChanged: (val) => setState(() => isUrgent = val),
                          ),
                        ],
                      ),
                    ),
                    
                    const SizedBox(height: 24),
                    
                    InkWell(
                      onTap: _pickImage,
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        height: 160,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: AppColors.background,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.grey.withOpacity(0.3), style: BorderStyle.solid),
                        ),
                        child: _imageFile != null
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(16),
                                child: Image.memory(_imageFile!.bytes, fit: BoxFit.cover),
                              )
                            : Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.add_photo_alternate_outlined, color: Colors.grey.shade400, size: 48),
                                  const SizedBox(height: 8),
                                  const Text('Add Photo (Optional)', style: TextStyle(color: AppColors.greyText, fontWeight: FontWeight.bold)),
                                ],
                              ),
                      ),
                    ),
                    if (_imageFile != null)
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: () => setState(() => _imageFile = null),
                          child: const Text('Remove Photo', style: TextStyle(color: AppColors.red)),
                        ),
                      ),
                      
                    const SizedBox(height: 32),
                    
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isUploading ? null : () => _submitTask(profileName, profileCity),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          elevation: 0,
                        ),
                        child: _isUploading 
                            ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                            : const Text('Post Task live', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                      ),
                    ),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
          );
        });
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    int maxLines = 1,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
    );
  }
}

/// A numbered step row used in the ID rejection guidance card.
class _StepRow extends StatelessWidget {
  final String n;
  final String text;
  const _StepRow({required this.n, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: Colors.orange.withOpacity(0.2),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.orange.withOpacity(0.5)),
          ),
          child: Center(
            child: Text(n,
                style: const TextStyle(
                    color: Colors.orange,
                    fontSize: 11,
                    fontWeight: FontWeight.bold)),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(text,
              style: const TextStyle(fontSize: 13, color: Colors.black87, height: 1.4)),
        ),
      ],
    );
  }
}
