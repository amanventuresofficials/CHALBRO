// lib/widgets/language_picker_dialog.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../utils/app_colors.dart';
import '../utils/language_provider.dart';

/// A premium bottom-sheet language picker.
/// [isFirstRun] = true  → shown on first launch; cannot be dismissed without picking.
/// [isFirstRun] = false → shown from Settings; can be dismissed.
class LanguagePickerDialog extends StatefulWidget {
  final bool isFirstRun;
  const LanguagePickerDialog({super.key, this.isFirstRun = false});

  /// Convenience: shows the sheet and returns when dismissed.
  static Future<void> show(BuildContext context, {bool isFirstRun = false}) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: !isFirstRun,
      enableDrag: !isFirstRun,
      backgroundColor: Colors.transparent,
      builder: (_) => LanguagePickerDialog(isFirstRun: isFirstRun),
    );
  }

  @override
  State<LanguagePickerDialog> createState() => _LanguagePickerDialogState();
}

class _LanguagePickerDialogState extends State<LanguagePickerDialog> {
  late String _selected;

  @override
  void initState() {
    super.initState();
    _selected = context.read<LanguageProvider>().currentLang;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 24),

          // Gradient header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Column(
              children: [
                Text(
                  'Choose Language',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'भाषा चुनें',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Language options
          Row(
            children: [
              Expanded(child: _LanguageCard(
                symbol: 'A',
                nativeName: 'English',
                localName: 'अंग्रेज़ी',
                langCode: 'en',
                isSelected: _selected == 'en',
                onTap: () => setState(() => _selected = 'en'),
              )),
              const SizedBox(width: 16),
              Expanded(child: _LanguageCard(
                symbol: 'अ',
                nativeName: 'हिंदी',
                localName: 'Hindi',
                langCode: 'hi',
                isSelected: _selected == 'hi',
                onTap: () => setState(() => _selected = 'hi'),
              )),
            ],
          ),
          const SizedBox(height: 28),

          // Continue/Save button
          SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton(
              onPressed: () async {
                final provider = context.read<LanguageProvider>();
                if (widget.isFirstRun) {
                  await provider.completeFirstRun(_selected);
                } else {
                  await provider.setLanguage(_selected);
                }
                if (context.mounted) Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 0,
              ),
              child: Text(
                _selected == 'hi' ? 'जारी रखें' : 'Continue',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LanguageCard extends StatelessWidget {
  final String symbol;
  final String nativeName;
  final String localName;
  final String langCode;
  final bool isSelected;
  final VoidCallback onTap;

  const _LanguageCard({
    required this.symbol,
    required this.nativeName,
    required this.localName,
    required this.langCode,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.tertiary : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? AppColors.primary : Colors.grey.shade200,
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppColors.primary.withOpacity(0.15),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  )
                ]
              : [],
        ),
        child: Column(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: isSelected ? AppColors.primary.withOpacity(0.12) : AppColors.surface,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Text(
                symbol,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: isSelected ? AppColors.primary : AppColors.darkText,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              nativeName,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: isSelected ? AppColors.primary : AppColors.darkText,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              localName,
              style: const TextStyle(fontSize: 12, color: AppColors.greyText),
            ),
            const SizedBox(height: 10),
            AnimatedOpacity(
              opacity: isSelected ? 1 : 0,
              duration: const Duration(milliseconds: 200),
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check, color: Colors.white, size: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
