import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

class BrutalistIconButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback onTap;

  const BrutalistIconButton({
    super.key,
    required this.icon,
    required this.onTap,
  });

  @override
  State<BrutalistIconButton> createState() => _BrutalistIconButtonState();
}

class _BrutalistIconButtonState extends State<BrutalistIconButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    bool isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final shadowColor = isDarkMode ? AppColors.shadowDark : AppColors.shadow;
    final borderColor = isDarkMode ? AppColors.borderDark : AppColors.border;
    final bgColor = isDarkMode ? AppColors.surfaceDark : Colors.white;
    final iconColor = isDarkMode ? AppColors.textDarkPrimary : AppColors.textPrimary;

    const double shadowOffset = 4.0;
    const double buttonSize = 44.0;

    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) {
        setState(() => _isPressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _isPressed = false),
      child: SizedBox(
        width: buttonSize + shadowOffset,
        height: buttonSize + shadowOffset,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              top: shadowOffset,
              left: shadowOffset,
              right: 0,
              bottom: 0,
              child: Container(
                decoration: BoxDecoration(
                  color: shadowColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: borderColor, width: 3),
                ),
              ),
            ),
            AnimatedPositioned(
              duration: const Duration(milliseconds: 100),
              curve: Curves.fastOutSlowIn,
              top: _isPressed ? shadowOffset : 0,
              left: _isPressed ? shadowOffset : 0,
              right: _isPressed ? 0 : shadowOffset,
              bottom: _isPressed ? 0 : shadowOffset,
              child: Container(
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: borderColor, width: 3),
                ),
                child: Center(
                  child: Icon(widget.icon, color: iconColor),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
