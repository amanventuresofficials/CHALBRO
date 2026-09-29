import 'package:flutter/material.dart';
import '../utils/app_colors.dart';

class Avatar extends StatelessWidget {
  final String? uri;
  final String? name;
  final double size;

  const Avatar({
    super.key,
    this.uri,
    this.name,
    this.size = 44, // Minimum accessible touch target size
  });

  String get initials {
    final n = (name == null || name!.isEmpty) ? "?" : name!;
    final parts = n.trim().split(RegExp(r'\s+'));
    return parts.take(2).map((s) => s.isNotEmpty ? s[0].toUpperCase() : '').join('');
  }

  @override
  Widget build(BuildContext context) {
    // If a valid image URL is provided
    if (uri != null && uri!.isNotEmpty) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: AppColors.tertiary, // Updated fallback color
          shape: BoxShape.circle,
          image: DecorationImage(
            image: NetworkImage(uri!),
            fit: BoxFit.cover,
          ),
        ),
      );
    }

    // Design System Fallback: Initials with brandTertiary background
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        color: AppColors.tertiary, // System aligned background
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        initials.isEmpty ? "U" : initials,
        style: TextStyle(
          color: AppColors.primary, // System aligned text color
          fontWeight: FontWeight.w700,
          fontSize: size * 0.42,
        ),
      ),
    );
  }
}
