// lib/utils/app_colors.dart
import 'package:flutter/material.dart';

class AppColors {
  // Light Mode Surface & Chrome Tokens
  static const Color surface = Color(0xFFFFFFFF);
  static const Color onSurface = Color(0xFF000000);
  static const Color background = Color(0xFFF9F9FB); 
  static const Color darkText = Color(0xFF1C1C1E);
  static const Color greyText = Color(0xFF6B6B70);

  // Primary Theme Colors
  static const Color primary = Color(0xFF6347EA);
  static const Color secondary = Color(0xFFEFE8FF);
  static const Color tertiary = Color(0xFFF6F3FF);

  // Categories Pastel Colors
  static const Color pastelRed = Color(0xFFFFEBEB);
  static const Color pastelRedIcon = Color(0xFFF06565);
  
  static const Color pastelPurple = Color(0xFFF1EFFF);
  static const Color pastelPurpleIcon = Color(0xFF7E64FF);
  
  static const Color pastelGreen = Color(0xFFE8FAF0);
  static const Color pastelGreenIcon = Color(0xFF4AC27E);
  
  static const Color pastelOrange = Color(0xFFFFF0E5);
  static const Color pastelOrangeIcon = Color(0xFFF79F39);

  static const Color pastelPink = Color(0xFFFCEBFF);
  static const Color pastelPinkIcon = Color(0xFFE253A4);

  static const Color pastelBlue = Color(0xFFEAF5FF);
  static const Color pastelBlueIcon = Color(0xFF4CB3D4);

  // Semantic Status Tokens
  static const Color success = Color(0xFF34C759);
  static const Color warning = Color(0xFFFF9500);
  static const Color red = Color(0xFFFF3B30);

  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFF6347EA), Color(0xFF886DF2)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}
