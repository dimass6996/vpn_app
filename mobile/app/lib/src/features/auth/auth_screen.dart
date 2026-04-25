import 'package:flutter/material.dart';

import '../../shared/app_button.dart';
import '../../shared/app_card.dart';
import '../../shared/app_input.dart';
import '../../shared/app_reveal.dart';
import '../../shared/app_theme.dart';
import '../../shared/atmospheric_background.dart';
import '../app_shell/app_controller.dart';
import '../../shared/status_banner.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _loginController = TextEditingController();
  final _codeController = TextEditingController();
  final _linkController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _codeController.addListener(_onCodeChanged);
  }

  @override
  void dispose() {
    _codeController.removeListener(_onCodeChanged);
    _loginController.dispose();
    _codeController.dispose();
    _linkController.dispose();
    super.dispose();
  }

  void _onCodeChanged() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final isVerification = widget.controller.authStage == AuthStage.codeVerification;
        final code = _codeController.text.trim();
        final incomingMagicLink = widget.controller.lastMagicLink;
        if (incomingMagicLink != null &&
            incomingMagicLink.isNotEmpty &&
            _linkController.text.isEmpty) {
          _linkController.text = incomingMagicLink;
        }
        return Scaffold(
          body: AtmosphericBackground(
            child: SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AppReveal(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Arbuz VPN',
                                style: Theme.of(context).textTheme.headlineMedium,
                              ),
                              const SizedBox(height: AppSpacing.xs),
                              Text(
                                isVerification ? 'Verify access code' : 'Request access code',
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                      color: AppColors.textSecondary,
                                    ),
                              ),
                              const SizedBox(height: AppSpacing.md),
                              const Wrap(
                                spacing: AppSpacing.xs,
                                runSpacing: AppSpacing.xs,
                                children: [
                                  _FeatureChip(label: 'OTP sign-in'),
                                  _FeatureChip(label: 'Session restore'),
                                  _FeatureChip(label: 'Config delivery'),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        AppReveal(
                          delay: const Duration(milliseconds: 70),
                          child: AppCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (!isVerification) ...[
                                AppInput(
                                  controller: _loginController,
                                  label: 'Telegram username',
                                  hint: '@username',
                                ),
                                const SizedBox(height: AppSpacing.md),
                                AppButton(
                                  label: 'Request OTP',
                                  onPressed: widget.controller.isLoading
                                      ? null
                                      : () => widget.controller.startAuth(_loginController.text),
                                  expanded: true,
                                ),
                                const SizedBox(height: AppSpacing.md),
                                AppInput(
                                  controller: _linkController,
                                  label: 'Telegram login link',
                                  hint: 'https://.../auth?challenge_id=...&code=...',
                                ),
                                const SizedBox(height: AppSpacing.sm),
                                AppButton(
                                  label: 'Sign in by link',
                                  variant: AppButtonVariant.ghost,
                                  onPressed: widget.controller.isLoading
                                      ? null
                                      : () => widget.controller.verifyAuthLink(_linkController.text),
                                  expanded: true,
                                ),
                              ] else ...[
                                if (widget.controller.login.isNotEmpty) ...[
                                  Text(
                                    'Login: ${widget.controller.login}',
                                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                          color: AppColors.textSecondary,
                                        ),
                                  ),
                                  const SizedBox(height: AppSpacing.md),
                                ],
                                _OtpCells(code: code),
                                const SizedBox(height: AppSpacing.sm),
                                AppInput(
                                  controller: _codeController,
                                  label: 'OTP code',
                                  keyboardType: TextInputType.number,
                                  hint: widget.controller.lastDeliveryHint ??
                                      (widget.controller.otpInputHint.isEmpty
                                          ? 'Enter the code from your delivery channel.'
                                          : widget.controller.otpInputHint),
                                ),
                                if (widget.controller.lastMagicLink != null &&
                                    widget.controller.lastMagicLink!.isNotEmpty) ...[
                                  const SizedBox(height: AppSpacing.md),
                                  AppInput(
                                    controller: _linkController,
                                    label: 'Telegram login link',
                                    hint: 'Paste or edit login link',
                                  ),
                                  const SizedBox(height: AppSpacing.sm),
                                  AppButton(
                                    label: 'Sign in by link',
                                    variant: AppButtonVariant.ghost,
                                    onPressed: widget.controller.isLoading
                                        ? null
                                        : () => widget.controller.verifyAuthLink(_linkController.text),
                                    expanded: true,
                                  ),
                                ],
                                const SizedBox(height: AppSpacing.md),
                                Row(
                                  children: [
                                    Expanded(
                                      child: AppButton(
                                        label: 'Back',
                                        variant: AppButtonVariant.secondary,
                                        onPressed: widget.controller.isLoading
                                            ? null
                                            : widget.controller.restartAuth,
                                      ),
                                    ),
                                    const SizedBox(width: AppSpacing.sm),
                                    Expanded(
                                      child: AppButton(
                                        label: 'Resend code',
                                        variant: AppButtonVariant.ghost,
                                        onPressed: widget.controller.isLoading
                                            ? null
                                            : widget.controller.resendAuthCode,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: AppSpacing.sm),
                                AppButton(
                                  label: 'Verify and continue',
                                  onPressed: widget.controller.isLoading
                                      ? null
                                      : () => widget.controller.verifyAuth(_codeController.text),
                                  expanded: true,
                                ),
                              ],
                              const SizedBox(height: AppSpacing.lg),
                              StatusBanner(
                                message: widget.controller.statusMessage,
                                tone: widget.controller.statusTone,
                              ),
                              if (widget.controller.isLoading) ...[
                                const SizedBox(height: AppSpacing.md),
                                const LinearProgressIndicator(minHeight: 2),
                              ],
                            ],
                          ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _FeatureChip extends StatelessWidget {
  const _FeatureChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.elevatedSurface,
        border: Border.all(color: AppColors.borderSubtle),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Text(
          label,
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}

class _OtpCells extends StatelessWidget {
  const _OtpCells({required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    final digits = code.padRight(6).substring(0, 6).split('');
    return Row(
      children: [
        for (var i = 0; i < digits.length; i++) ...[
          Expanded(
            child: Container(
              height: 54,
              margin: EdgeInsets.only(right: i == digits.length - 1 ? 0 : AppSpacing.xs),
              decoration: BoxDecoration(
                color: AppColors.elevatedSurface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.borderSubtle),
              ),
              child: Center(
                child: Text(
                  digits[i].trim().isEmpty ? '•' : digits[i],
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 20,
                    letterSpacing: 0.3,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
