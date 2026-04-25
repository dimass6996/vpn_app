import 'package:flutter/material.dart';

import '../features/app_shell/app_controller.dart';
import 'app_card.dart';
import 'app_theme.dart';

class StatusBanner extends StatelessWidget {
  const StatusBanner({
    super.key,
    required this.message,
    required this.tone,
  });

  final String message;
  final StatusTone tone;

  @override
  Widget build(BuildContext context) {
    final icon = switch (tone) {
      StatusTone.success => Icons.check_circle_outline,
      StatusTone.warning => Icons.warning_amber_rounded,
      StatusTone.error => Icons.error_outline,
      StatusTone.neutral => Icons.info_outline,
    };
    final opacity = switch (tone) {
      StatusTone.success => 0.3,
      StatusTone.warning => 0.22,
      StatusTone.error => 0.22,
      StatusTone.neutral => 0.14,
    };

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.white.withValues(alpha: 0.7)),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: AppColors.textPrimary.withValues(alpha: 0.88),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: opacity),
            ),
          ),
        ],
      ),
    );
  }
}
