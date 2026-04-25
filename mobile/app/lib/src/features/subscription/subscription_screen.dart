import 'package:flutter/material.dart';

import '../../shared/app_button.dart';
import '../../shared/app_card.dart';
import '../../shared/app_reveal.dart';
import '../../shared/app_theme.dart';
import '../app_shell/app_controller.dart';

class SubscriptionScreen extends StatelessWidget {
  const SubscriptionScreen({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final subscription = controller.subscription;
    final expiryLabel = _formatExpiry(subscription?.expireAtUnix);
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        AppReveal(
          child: AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Plan status', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    _Tag(value: subscription?.isActive == true ? 'Active' : 'Inactive'),
                    const SizedBox(width: AppSpacing.sm),
                    _Tag(value: '${subscription?.daysLeft ?? 0} days left'),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                Text('Expires: $expiryLabel', style: const TextStyle(color: AppColors.textSecondary)),
                const SizedBox(height: AppSpacing.lg),
                AppButton(
                  label: 'Refresh status',
                  icon: Icons.sync,
                  variant: AppButtonVariant.secondary,
                  onPressed: controller.isLoading ? null : controller.refreshDashboard,
                  expanded: true,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        const AppReveal(
          delay: Duration(milliseconds: 90),
          child: AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Billing roadmap', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                SizedBox(height: AppSpacing.sm),
                Text(
                  'Payment hooks are not wired yet. Extend can be handled through internal admin endpoint.',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _formatExpiry(int? expireAtUnix) {
    if (expireAtUnix == null) {
      return 'not set';
    }
    final date = DateTime.fromMillisecondsSinceEpoch(expireAtUnix * 1000);
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.value});

  final String value;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.elevatedSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(
          value,
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
      ),
    );
  }
}
