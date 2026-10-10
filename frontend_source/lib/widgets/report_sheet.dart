import 'package:flutter/material.dart';
import '../services/database_service.dart';
import '../utils/app_colors.dart';

/// "Report" bottom sheet: lets someone flag a task or a person for the admin team.
/// One report per person per target (a second attempt is told it was already sent).
Future<void> showReportSheet(
  BuildContext context, {
  required String targetType, // 'task' | 'user'
  required String targetId,
  required String targetOwnerUid,
  String targetTitle = '',
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (_) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: _ReportSheet(targetType: targetType, targetId: targetId, targetOwnerUid: targetOwnerUid, targetTitle: targetTitle),
    ),
  );
}

const List<(String, String)> _reasons = [
  ('spam', 'Spam or advertising'),
  ('fraud', 'Fraud or a scam'),
  ('abuse', 'Abuse or harassment'),
  ('fake', 'Fake or misleading'),
  ('inappropriate', 'Inappropriate content'),
  ('other', 'Something else'),
];

class _ReportSheet extends StatefulWidget {
  final String targetType;
  final String targetId;
  final String targetOwnerUid;
  final String targetTitle;
  const _ReportSheet({required this.targetType, required this.targetId, required this.targetOwnerUid, required this.targetTitle});

  @override
  State<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<_ReportSheet> {
  final TextEditingController _details = TextEditingController();
  String? _reason;
  bool _sending = false;

  @override
  void dispose() {
    _details.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_reason == null) return;
    setState(() => _sending = true);
    final result = await DatabaseService().submitReport(
      targetType: widget.targetType,
      targetId: widget.targetId,
      targetOwnerUid: widget.targetOwnerUid,
      targetTitle: widget.targetTitle,
      reason: _reason!,
      details: _details.text.trim(),
    );
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    switch (result) {
      case ReportResult.sent:
        messenger.showSnackBar(const SnackBar(content: Text('Thank you. Our team will review your report.'), backgroundColor: AppColors.success));
        break;
      case ReportResult.alreadyReported:
        messenger.showSnackBar(const SnackBar(content: Text('Thank you, we already have your report and are looking into it.')));
        break;
      case ReportResult.failed:
        messenger.showSnackBar(const SnackBar(content: Text('Could not send the report. Please try again.'), backgroundColor: AppColors.red));
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isTask = widget.targetType == 'task';
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 16),
              Text(isTask ? 'Report this task' : 'Report this person', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.darkText)),
              const SizedBox(height: 4),
              const Text('Tell us what is wrong. Your report is private; the other person is not told who sent it.', style: TextStyle(color: AppColors.greyText, fontSize: 13, height: 1.4)),
              const SizedBox(height: 14),
              for (final r in _reasons)
                RadioListTile<String>(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  value: r.$1,
                  groupValue: _reason,
                  activeColor: AppColors.primary,
                  title: Text(r.$2),
                  onChanged: _sending ? null : (v) => setState(() => _reason = v),
                ),
              const SizedBox(height: 8),
              TextField(
                controller: _details,
                maxLines: 3,
                maxLength: 500,
                enabled: !_sending,
                decoration: InputDecoration(
                  hintText: 'Anything else we should know? (optional)',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                  onPressed: _reason == null || _sending ? null : _send,
                  child: _sending
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Send report'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
