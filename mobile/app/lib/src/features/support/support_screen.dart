import 'package:flutter/material.dart';

import '../../shared/app_button.dart';
import '../../shared/app_card.dart';
import '../../shared/app_input.dart';
import '../../shared/app_reveal.dart';
import '../../shared/app_theme.dart';
import '../app_shell/app_controller.dart';

class SupportScreen extends StatefulWidget {
  const SupportScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends State<SupportScreen> {
  final _subjectController = TextEditingController(text: 'Need help with setup');
  final _messageController = TextEditingController(
    text: 'The app can sign in, but I need a clearer import path for configs.',
  );

  @override
  void dispose() {
    _subjectController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        AppReveal(
          child: AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Support', style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: AppSpacing.md),
                AppInput(
                  controller: _subjectController,
                  label: 'Subject',
                ),
                const SizedBox(height: AppSpacing.sm),
                AppInput(
                  controller: _messageController,
                  label: 'Message',
                  maxLines: 6,
                ),
                const SizedBox(height: AppSpacing.md),
                AppButton(
                  label: 'Send request',
                  icon: Icons.send_outlined,
                  onPressed: widget.controller.isLoading
                      ? null
                      : () async {
                          await widget.controller.sendSupportRequest(
                            subject: _subjectController.text,
                            message: _messageController.text,
                          );
                          if (!context.mounted) {
                            return;
                          }
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Support request sent')),
                          );
                        },
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
