import 'package:flutter/material.dart';

import '../../shared/app_button.dart';
import '../../shared/app_card.dart';
import '../../shared/app_reveal.dart';
import '../../shared/app_theme.dart';
import '../app_shell/app_controller.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final me = controller.me;
    final subscription = controller.subscription;
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        AppReveal(
          child: AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Account', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Username: ${me?.username ?? 'unknown'}',
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Provider: ${me?.authProvider ?? 'n/a'}',
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Subscription: ${subscription?.isActive == true ? 'active' : 'inactive'}',
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        AppReveal(
          delay: const Duration(milliseconds: 90),
          child: AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Security', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: AppSpacing.md),
                AppButton(
                  label: 'Sign out',
                  icon: Icons.logout,
                  variant: AppButtonVariant.secondary,
                  onPressed: controller.isLoading ? null : controller.logout,
                  expanded: true,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
