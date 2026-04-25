import 'package:flutter/material.dart';

import 'app_theme.dart';

enum AppButtonVariant { primary, secondary, ghost }

class AppButton extends StatefulWidget {
  const AppButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.variant = AppButtonVariant.primary,
    this.expanded = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final AppButtonVariant variant;
  final bool expanded;

  @override
  State<AppButton> createState() => _AppButtonState();
}

class _AppButtonState extends State<AppButton> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) {
      return;
    }
    setState(() {
      _pressed = value;
    });
  }

  @override
  Widget build(BuildContext context) {
    final disabled = widget.onPressed == null;
    final background = switch (widget.variant) {
      AppButtonVariant.primary => AppColors.elevatedSurface,
      AppButtonVariant.secondary => Colors.white.withValues(alpha: 0.04),
      AppButtonVariant.ghost => Colors.transparent,
    };
    final borderColor = switch (widget.variant) {
      AppButtonVariant.primary => AppColors.borderHighlight,
      AppButtonVariant.secondary => AppColors.borderSubtle,
      AppButtonVariant.ghost => AppColors.borderSubtle,
    };
    final child = GestureDetector(
      onTap: widget.onPressed,
      onTapDown: disabled ? null : (_) => _setPressed(true),
      onTapCancel: disabled ? null : () => _setPressed(false),
      onTapUp: disabled
          ? null
          : (_) {
              _setPressed(false);
            },
      child: AnimatedScale(
        scale: _pressed && !disabled ? 0.985 : 1,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOutCubic,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          height: 52,
          decoration: BoxDecoration(
            color: disabled ? background.withValues(alpha: 0.4) : background,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderColor),
            boxShadow: disabled
                ? const []
                : [
                    BoxShadow(
                      color: const Color.fromRGBO(0, 0, 0, 0.35),
                      blurRadius: _pressed ? 9 : 16,
                      offset: Offset(0, _pressed ? 4 : 8),
                    ),
                    BoxShadow(
                      color: AppColors.glow.withValues(alpha: _pressed ? 0.08 : 0.14),
                      blurRadius: _pressed ? 8 : 14,
                      offset: const Offset(0, -1),
                    ),
                  ],
          ),
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.icon != null) ...[
                  Icon(widget.icon, size: 18, color: AppColors.textPrimary),
                  const SizedBox(width: AppSpacing.xs),
                ],
                Text(
                  widget.label,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return widget.expanded ? SizedBox(width: double.infinity, child: child) : child;
  }
}
