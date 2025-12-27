import 'package:flutter/material.dart';
import 'package:client/theme/colors.dart';
import 'package:client/theme/spacing.dart';
import 'package:client/theme/typography.dart';

class UserProfileScreen extends StatelessWidget {
  const UserProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Profile',
          style: AppTypography.h3.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.account_circle,
              size: 100,
              color: AppColors.textTertiary,
            ),
            const SizedBox(height: Spacing.md),
            Text(
              'Profile',
              style: AppTypography.h2,
            ),
            const SizedBox(height: Spacing.xs),
            Text(
              'Coming soon...',
              style: AppTypography.body.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
