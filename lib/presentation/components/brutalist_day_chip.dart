import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

class BrutalistDayChip extends StatelessWidget {
  final String text;
  final bool isSelected;
  final VoidCallback onTap;
  final bool isDarkMode;
  final bool isDisabled;

  const BrutalistDayChip({
    super.key,
    required this.text,
    required this.isSelected,
    required this.onTap,
    required this.isDarkMode,
    this.isDisabled = false,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor = isDarkMode ? AppColors.borderDark : AppColors.border;
    final selectedColor = AppColors.primary;
    final unselectedColor = isDarkMode ? AppColors.surfaceDark : Colors.white;

    final textColor = isSelected
        ? Colors.white
        : (isDarkMode ? AppColors.textDarkPrimary : AppColors.textPrimary);

    return GestureDetector(
      onTap: isDisabled ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 35,
        height: 35,
        transform: isSelected
            ? Matrix4.translationValues(1, 1, 0)
            : Matrix4.identity(),
        decoration: BoxDecoration(
          color: isSelected ? selectedColor : unselectedColor,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: borderColor, width: 2),
          boxShadow: !isSelected
              ? [
                  BoxShadow(
                    color: isDarkMode ? AppColors.shadowDark : AppColors.shadow,
                    offset: const Offset(2, 2),
                  ),
                ]
              : null,
        ),
        child: Center(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w900,
              color: textColor.withOpacity(isDisabled ? 0.5 : 1.0),
            ),
          ),
        ),
      ),
    );
  }
}
