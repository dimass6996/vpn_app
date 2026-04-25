import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../shared/app_button.dart';
import '../../shared/app_card.dart';
import '../../shared/app_reveal.dart';
import '../../shared/app_theme.dart';
import '../app_shell/app_controller.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final subscription = widget.controller.subscription;
    final me = widget.controller.me;
    final isConnected = widget.controller.vpnEnabled;
    final canToggle = widget.controller.canToggleVpn;
    final primaryConfig = widget.controller.primarySubscriptionLink;

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        AppReveal(
          child: AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _PulsingShield(
                      controller: _pulseController,
                      connected: isConnected,
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isConnected ? 'Connected' : 'Disconnected',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        Text(
                          canToggle ? 'Ready to connect' : 'Subscription inactive',
                          style: const TextStyle(color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                _MetaLine(label: 'Account', value: me?.username ?? 'unknown'),
                const SizedBox(height: AppSpacing.xs),
                _MetaLine(label: 'Protocol', value: widget.controller.activeProtocol),
                const SizedBox(height: AppSpacing.xs),
                _MetaLine(label: 'Location', value: widget.controller.activeLocation),
                const SizedBox(height: AppSpacing.xs),
                _MetaLine(label: 'Days left', value: '${subscription?.daysLeft ?? 0}'),
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
                Text('Connection', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: AppSpacing.md),
                _ConnectButton(
                  connected: isConnected,
                  enabled: canToggle,
                  onPressed: widget.controller.isLoading ? null : widget.controller.toggleVpn,
                ),
                const SizedBox(height: AppSpacing.sm),
                if (primaryConfig.isNotEmpty)
                  AppButton(
                    label: 'Copy personal VPN link',
                    icon: Icons.copy_all_outlined,
                    variant: AppButtonVariant.secondary,
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: primaryConfig));
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Personal VPN link copied')),
                        );
                      }
                    },
                    expanded: true,
                  ),
                if (primaryConfig.isNotEmpty)
                  const SizedBox(height: AppSpacing.sm),
                AppButton(
                  label: 'Refresh profile',
                  icon: Icons.sync,
                  variant: AppButtonVariant.ghost,
                  onPressed: widget.controller.isLoading ? null : widget.controller.refreshDashboard,
                  expanded: true,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        AppReveal(
          delay: const Duration(milliseconds: 150),
          child: AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Backend status', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: AppSpacing.sm),
                Text(widget.controller.statusMessage),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'VPN runtime: ${widget.controller.vpnRuntimeDetails}',
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Core: ${widget.controller.coreStatus.available ? 'available' : 'missing'}'
                  '${widget.controller.coreStatus.path == null ? '' : ' (${widget.controller.coreStatus.path})'}',
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Process alive: ${widget.controller.runtimeProcessAlive ? 'yes' : 'no'}',
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Heartbeat age: ${widget.controller.runtimeHeartbeatAgeSeconds == null ? 'n/a' : '${widget.controller.runtimeHeartbeatAgeSeconds}s'}',
                  style: TextStyle(
                    color: widget.controller.runtimeHeartbeatStale
                        ? const Color(0xFFFFBABA)
                        : AppColors.textSecondary,
                  ),
                ),
                if (widget.controller.runtimeHeartbeatStale) ...[
                  const SizedBox(height: AppSpacing.xs),
                  const Text(
                    'Warning: runtime heartbeat is stale. Core may be stuck.',
                    style: TextStyle(color: Color(0xFFFFBABA)),
                  ),
                ],
                if ((widget.controller.coreStatus.details ?? '').isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Core details: ${widget.controller.coreStatus.details}',
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                ],
                const SizedBox(height: AppSpacing.sm),
                AppButton(
                  label: 'Refresh VPN runtime',
                  icon: Icons.memory_outlined,
                  variant: AppButtonVariant.ghost,
                  onPressed: widget.controller.isLoading
                      ? null
                      : widget.controller.refreshVpnRuntimeStatus,
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

class _ConnectButton extends StatelessWidget {
  const _ConnectButton({
    required this.connected,
    required this.enabled,
    required this.onPressed,
  });

  final bool connected;
  final bool enabled;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onPressed : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        width: double.infinity,
        height: 112,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: enabled
              ? Colors.white.withValues(alpha: connected ? 0.11 : 0.06)
              : Colors.white.withValues(alpha: 0.03),
          border: Border.all(
            color: enabled ? AppColors.borderHighlight : AppColors.borderSubtle,
          ),
          boxShadow: enabled
              ? [
                  BoxShadow(
                    color: AppColors.glow.withValues(alpha: connected ? 0.18 : 0.1),
                    blurRadius: connected ? 30 : 18,
                    offset: const Offset(0, 6),
                  ),
                ]
              : const [],
        ),
        child: Center(
          child: Text(
            connected ? 'Disable VPN' : 'Enable VPN',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: enabled ? AppColors.textPrimary : AppColors.textTertiary,
                ),
          ),
        ),
      ),
    );
  }
}

class _PulsingShield extends StatelessWidget {
  const _PulsingShield({
    required this.controller,
    required this.connected,
  });

  final AnimationController controller;
  final bool connected;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final t = Curves.easeInOut.transform(controller.value);
        final glowAlpha = connected ? 0.06 + (0.1 * t) : 0.02 + (0.04 * t);
        return Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: 0.04),
            border: Border.all(color: AppColors.borderSubtle),
            boxShadow: [
              BoxShadow(
                color: AppColors.glow.withValues(alpha: glowAlpha),
                blurRadius: 18,
                spreadRadius: 2,
              ),
            ],
          ),
          child: const Icon(Icons.shield_outlined, size: 20),
        );
      },
    );
  }
}

class _MetaLine extends StatelessWidget {
  const _MetaLine({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 90,
          child: Text(
            label,
            style: const TextStyle(color: AppColors.textTertiary, fontSize: 12),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(color: AppColors.textPrimary),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
