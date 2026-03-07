import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/app_colors.dart';

class PrimaryButton extends StatefulWidget {
  final VoidCallback onPressed;
  final String text;
  final bool isLoading;
  final double? width;
  final IconData? icon;
  final String? imageIcon;
  final Color? color;

  const PrimaryButton({
    super.key,
    required this.text,
    required this.onPressed,
    this.isLoading = false,
    this.width = double.infinity,
    this.icon,
    this.imageIcon,
    this.color,
  });

  @override
  State<PrimaryButton> createState() => _PrimaryButtonState();
}

class _PrimaryButtonState extends State<PrimaryButton> {
  bool _isPressed = false;

  void _tapDown(TapDownDetails details) {
    if (!widget.isLoading) {
      setState(() {
        _isPressed = true;
      });
    }
  }

  void _tapUp(TapUpDetails details) {
    if (!widget.isLoading) {
      setState(() {
        _isPressed = false;
      });
      Future.delayed(const Duration(milliseconds: 50), widget.onPressed);
    }
  }

  void _tapCancel() {
    if (!widget.isLoading) {
      setState(() {
        _isPressed = false;
      });
    }
  }

  Color get _foregroundColor {
    final bgColor = widget.color ?? AppColors.primary;
    return bgColor.computeLuminance() > 0.5
        ? AppColors.textPrimary
        : Colors.white;
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final shadowColor = isDarkMode ? AppColors.shadowDark : AppColors.shadow;
    final borderColor = isDarkMode ? AppColors.borderDark : AppColors.border;
    const double shadowOffset = 6.0;

    return GestureDetector(
      onTapDown: _tapDown,
      onTapUp: _tapUp,
      onTapCancel: _tapCancel,
      child: SizedBox(
        width: widget.width,
        height: 60 + shadowOffset,
        child: Stack(
          children: [
            Positioned(
              left: shadowOffset,
              top: shadowOffset,
              right: 0,
              bottom: 0,
              child: Container(
                decoration: BoxDecoration(
                  color: shadowColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: borderColor, width: 2),
                ),
              ),
            ),
            AnimatedPositioned(
              duration: const Duration(milliseconds: 100),
              curve: Curves.fastOutSlowIn,
              left: _isPressed ? shadowOffset : 0,
              top: _isPressed ? shadowOffset : 0,
              right: _isPressed ? 0 : shadowOffset,
              bottom: _isPressed ? 0 : shadowOffset,
              child: Container(
                decoration: BoxDecoration(
                  color: widget.color ?? AppColors.primary,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: borderColor, width: 3),
                ),
                child: Center(
                  child: widget.isLoading
                      ? SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            color: _foregroundColor,
                            strokeWidth: 3,
                          ),
                        )
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (widget.imageIcon != null) ...[
                              Image.asset(
                                widget.imageIcon!,
                                width: 22,
                                height: 22,
                              ),
                              const SizedBox(width: 8),
                            ] else if (widget.icon != null) ...[
                              Icon(
                                widget.icon,
                                color: _foregroundColor,
                                size: 28,
                              ),
                              const SizedBox(width: 8),
                            ],
                            Text(
                              widget.text.toUpperCase(),
                              style: GoogleFonts.jersey10(
                                fontSize: 32,
                                fontWeight: FontWeight.w400,
                                color: _foregroundColor,
                                letterSpacing: 2.0,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
