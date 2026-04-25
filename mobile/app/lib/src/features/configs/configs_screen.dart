import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/network/api_models.dart';
import '../../shared/app_button.dart';
import '../../shared/app_card.dart';
import '../../shared/app_reveal.dart';
import '../../shared/app_theme.dart';
import '../app_shell/app_controller.dart';

class ConfigsScreen extends StatelessWidget {
  const ConfigsScreen({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final items = controller.configs;
    if (items.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(AppSpacing.lg),
          child: Text(
            'No configs loaded yet. Pull data from the BFF after sign-in.',
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(AppSpacing.lg),
      itemBuilder: (context, index) {
        if (index == 0) {
          return AppReveal(
            child: _ImportGuideCard(item: items.first),
          );
        }
        return AppReveal(
          delay: Duration(milliseconds: 70 + ((index - 1) * 50)),
          child: _ConfigTile(item: items[index - 1]),
        );
      },
      separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
      itemCount: items.length + 1,
    );
  }
}

class _ImportGuideCard extends StatelessWidget {
  const _ImportGuideCard({required this.item});

  final ConfigItem item;

  @override
  Widget build(BuildContext context) {
    final steps = _platformSteps(Theme.of(context).platform);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Quick connect guide', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Primary payload: ${item.label}.',
            style: const TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.md),
          for (var i = 0; i < steps.length; i++) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.06),
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.borderSubtle),
                  ),
                  child: Center(
                    child: Text(
                      '${i + 1}',
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    steps[i],
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ],
      ),
    );
  }

  List<String> _platformSteps(TargetPlatform platform) {
    switch (platform) {
      case TargetPlatform.android:
        return const [
          'Copy the subscription link below.',
          'Open your Android VPN client and choose import from clipboard or URL.',
          'Paste the link and save the profile as your primary connection.',
        ];
      case TargetPlatform.iOS:
        return const [
          'Copy the subscription link below.',
          'Open your iOS VPN client and choose import from URL.',
          'Paste the link and confirm the profile appears before connecting.',
        ];
      case TargetPlatform.linux:
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
        return const [
          'Copy the subscription link below.',
          'Use a desktop-compatible client such as a Clash, Hiddify or sing-box based app.',
          'Import the URL and validate the profile list before the first connection.',
        ];
      case TargetPlatform.fuchsia:
        return const [
          'Copy the subscription link below.',
          'Import the URL into the target VPN client.',
          'Save the imported profile and test the first connection.',
        ];
    }
  }
}

class _ConfigTile extends StatelessWidget {
  const _ConfigTile({required this.item});

  final ConfigItem item;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(item.label, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(
            item.protocol.toUpperCase(),
            style: const TextStyle(color: AppColors.textTertiary, fontSize: 12),
          ),
          const SizedBox(height: AppSpacing.md),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.elevatedSurface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.borderSubtle),
            ),
            child: SelectableText(
              item.value,
              style: const TextStyle(
                fontFamily: 'monospace',
                color: AppColors.textPrimary,
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              AppButton(
                label: 'Copy link',
                icon: Icons.copy_all_outlined,
                variant: AppButtonVariant.secondary,
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: item.value));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Config copied to clipboard')),
                    );
                  }
                },
              ),
              AppButton(
                label: 'How to use',
                icon: Icons.info_outline,
                variant: AppButtonVariant.ghost,
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  backgroundColor: Colors.transparent,
                  builder: (context) => _ConfigUsageSheet(item: item),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ConfigUsageSheet extends StatelessWidget {
  const _ConfigUsageSheet({required this.item});

  final ConfigItem item;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: AppCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(item.label, style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Protocol: ${item.protocol.toUpperCase()}',
                style: const TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: AppSpacing.md),
              const Text(
                'Copy the value, open your VPN client, choose import from URL or clipboard, then verify profile list before connecting.',
                style: TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: AppSpacing.md),
              AppButton(
                label: 'Copy and close',
                icon: Icons.copy_all_outlined,
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: item.value));
                  if (context.mounted) {
                    Navigator.of(context).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Config copied to clipboard')),
                    );
                  }
                },
                expanded: true,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
