import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Step wizard progress bar widget for multi-step flows (e.g. Plan creation).
class StepWizardProgress extends StatelessWidget {
  const StepWizardProgress({
    super.key,
    required this.currentStep,
    this.steps = const [
      'Xác nhận đơn',
      'Sửa thuốc',
      'Đặt lịch',
    ],
  });

  /// Current active step (1-indexed: 1, 2, or 3).
  final int currentStep;

  /// Labels for each step.
  final List<String> steps;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceSoft,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: List.generate(steps.length * 2 - 1, (index) {
          if (index.isOdd) {
            final stepBefore = (index ~/ 2) + 1;
            final isCompleted = currentStep > stepBefore;
            return Expanded(
              child: Container(
                height: 3,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  color: isCompleted
                      ? AppColors.primary
                      : AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            );
          }

          final stepIndex = (index ~/ 2) + 1;
          final isCurrent = currentStep == stepIndex;
          final isCompleted = currentStep > stepIndex;
          final label = steps[stepIndex - 1];

          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isCompleted
                      ? AppColors.primary
                      : isCurrent
                          ? AppColors.primaryDark
                          : AppColors.surface,
                  border: Border.all(
                    color: (isCompleted || isCurrent)
                        ? AppColors.primaryDark
                        : AppColors.border,
                    width: 2,
                  ),
                ),
                child: Center(
                  child: isCompleted
                      ? const Icon(Icons.check, size: 16, color: Colors.white)
                      : Text(
                          '$stepIndex',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: isCurrent
                                ? Colors.white
                                : AppColors.textSecondary,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isCurrent ? FontWeight.w800 : FontWeight.w600,
                  color: isCurrent
                      ? AppColors.textPrimary
                      : AppColors.textMuted,
                ),
              ),
            ],
          );
        }),
      ),
    );
  }
}
