import 'package:flutter/material.dart';

class AppColors {
  // Backgrounds (layered depth)
  static const background = Color(0xFF000000);      // Pure black
  static const surface = Color(0xFF121212);         // Elevated surfaces
  static const surfaceVariant = Color(0xFF1C1C1E);  // Cards, inputs

  // Accents (Instagram-inspired gradient blues)
  static const primary = Color(0xFF0095F6);         // Instagram blue
  static const primaryLight = Color(0xFF3897F0);
  static const primaryDark = Color(0xFF005EBF);

  // Status colors
  static const online = Color(0xFF00D856);          // WhatsApp green
  static const typing = Color(0xFF0095F6);
  static const sent = Color(0xFF8E8E93);
  static const delivered = Color(0xFF0095F6);
  static const read = Color(0xFF0095F6);

  // Text (improved hierarchy)
  static const textPrimary = Color(0xFFFFFFFF);
  static const textSecondary = Color(0xFFB0B0B0);   // Softer gray
  static const textTertiary = Color(0xFF8E8E93);
  static const textDisabled = Color(0xFF6E6E73);

  // Interactive
  static const buttonPrimary = Color(0xFF0095F6);
  static const buttonSecondary = Color(0xFF1C1C1E);
  static const ripple = Color(0x1AFFFFFF);

  // Semantic
  static const error = Color(0xFFED4956);           // Instagram red
  static const success = Color(0xFF00D856);
  static const warning = Color(0xFFFBBD08);
}
