import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

class BrutalistIconButton extends StatefulWidget {
  final IconData? icon;
  final String? text;
  final Color? backgroundColor;
  final Color? contentColor;
  final VoidCallback onTap;
  final bool isToggled;
  final double? buttonSize;

  const BrutalistIconButton({
    super.key,
    this.icon,
    this.text,
    this.backgroundColor,
    this.contentColor,
    this.isToggled = false,
    this.buttonSize,
    required this.onTap,
  }) : assert(
         icon != null || text != null,
         'Either icon or text must be provided',
       );

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
    final bgColor =
        widget.backgroundColor ??
        (isDarkMode ? AppColors.surfaceDark : Colors.white);
    final fgColor =
        widget.contentColor ??
        (isDarkMode ? AppColors.textDarkPrimary : AppColors.textPrimary);

    const double shadowOffset = 4.0;
    final double buttonSize = widget.buttonSize ?? 44.0;

    final bool effectivePressed = _isPressed || widget.isToggled;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) async {
        widget.onTap();
        await Future.delayed(const Duration(milliseconds: 50));
        if (mounted) setState(() => _isPressed = false);
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
              top: effectivePressed ? shadowOffset : 0,
              left: effectivePressed ? shadowOffset : 0,
              right: effectivePressed ? 0 : shadowOffset,
              bottom: effectivePressed ? 0 : shadowOffset,
              child: Container(
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: borderColor, width: 3),
                ),
                child: Center(
                  child: widget.text != null
                      ? Text(
                          widget.text!,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            color: fgColor,
                          ),
                        )
                      : Icon(widget.icon, color: fgColor),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
