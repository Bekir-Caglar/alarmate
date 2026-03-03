import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

class RetroProgressBar extends StatelessWidget {
  final int totalSteps;
  final int currentStep;
  final Function(int)? onStepTapped;

  const RetroProgressBar({
    super.key,
    required this.totalSteps,
    required this.currentStep,
    this.onStepTapped,
  });

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDarkMode ? AppColors.surfaceDark : Colors.white;
    final shadowColor = isDarkMode ? AppColors.shadowDark : AppColors.shadow;
    final borderColor = isDarkMode ? AppColors.borderDark : AppColors.border;

    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: bgColor,
        border: Border.all(color: borderColor, width: 3),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: shadowColor,
            offset: const Offset(4, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: List.generate(totalSteps, (index) {
          final isCompleted = index <= currentStep;
          return Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onStepTapped != null ? () => onStepTapped!(index) : null,
              child: Container(
                margin: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: isCompleted ? AppColors.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                  border: isCompleted 
                      ? Border.all(color: borderColor, width: 2)
                      : Border.all(
                          color: borderColor.withValues(alpha: isDarkMode ? 0.35 : 0.2), 
                          width: 2
                        ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}
