import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/theme/app_colors.dart';
import '../../components/primary_button.dart';
import '../home/home_screen.dart';
import 'auth_screen.dart';

class ModeSelectionScreen extends StatefulWidget {
  const ModeSelectionScreen({super.key});

  @override
  State<ModeSelectionScreen> createState() => _ModeSelectionScreenState();
}

class _ModeSelectionScreenState extends State<ModeSelectionScreen>
    with SingleTickerProviderStateMixin {
  bool _isLoading = false;
  int? _selectedIndex;

  late AnimationController _animController;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Future<bool> _hasInternet() async {
    try {
      final result = await InternetAddress.lookup('google.com');
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<void> _enterGuestMode() async {
    setState(() => _isLoading = true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isOfflineGuest', true);

    // Generate a local ID if it doesn't exist
    if (!prefs.containsKey('local_guest_id')) {
      final localId = 'local_${DateTime.now().millisecondsSinceEpoch}';
      await prefs.setString('local_guest_id', localId);
    }

    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => const HomeScreen()),
      (route) => false,
    );
  }

  void _onContinue() async {
    if (_selectedIndex == null || _isLoading) return;

    if (_selectedIndex == 0) {
      setState(() => _isLoading = true);
      final isOnline = await _hasInternet();
      setState(() => _isLoading = false);

      if (!isOnline) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'BU MOD İÇİN İNTERNET BAĞLANTISI GEREKLİDİR.',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                color: Colors.white,
              ),
            ),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const AuthScreen()),
      );
    } else {
      _enterGuestMode();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final titleColor = isDarkMode
        ? AppColors.textDarkPrimary
        : AppColors.textPrimary;
    final subTitleColor = isDarkMode
        ? AppColors.textDarkSecondary
        : AppColors.textSecondary;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _ModeSelectionGridBackgroundPainter(
                color: isDarkMode
                    ? Colors.white.withValues(alpha: 0.05)
                    : AppColors.textPrimary.withValues(alpha: 0.05),
              ),
            ),
          ),
          SafeArea(
            child: FadeTransition(
              opacity: _fadeAnim,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return SingleChildScrollView(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.only(
                          left: 24.0,
                          right: 24.0,
                          top: 48.0,
                          bottom: 24.0,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            // === ÜST: Başlık ===
                            Column(
                              children: [
                                const SizedBox(height: 16),

                                Text(
                                  'NASIL UYANMAK\nİSTERSİN?',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 44,
                                    fontWeight: FontWeight.w900,
                                    color: titleColor,
                                    height: 1.0,
                                    letterSpacing: -2,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'KENDİNE UYGUN MODU SEÇ.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w900,
                                    color: subTitleColor,
                                    letterSpacing: 1,
                                  ),
                                ),
                              ],
                            ),

                            // === ALT: Kartlar ===
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                const SizedBox(height: 32),
                                _buildModeCard(
                                  index: 0,
                                  title: 'ARKADAŞLARIMLA',
                                  description:
                                      'Ortak alarmlar kur, birbirini uyanmaya zorla!',
                                  icon: Icons.group_rounded,
                                  accentColor: AppColors.primary,
                                  isDarkMode: isDarkMode,
                                  onTap: () {
                                    if (_isLoading) return;
                                    setState(() => _selectedIndex = 0);
                                  },
                                ),
                                const SizedBox(height: 16),
                                _buildModeCard(
                                  index: 1,
                                  title: 'TEK BAŞIMA',
                                  description:
                                      'Kendi alarmını kur, sessiz sakin uyan.',
                                  icon: Icons.person_rounded,
                                  accentColor: Colors.cyanAccent,
                                  isDarkMode: isDarkMode,
                                  onTap: () {
                                    if (_isLoading) return;
                                    setState(() => _selectedIndex = 1);
                                  },
                                ),
                                const SizedBox(height: 24),
                                AnimatedOpacity(
                                  opacity: _selectedIndex != null ? 1.0 : 0.3,
                                  duration: const Duration(milliseconds: 200),
                                  child: PrimaryButton(
                                    text: _isLoading
                                        ? 'BEKLEYIN...'
                                        : 'DEVAM ET',
                                    onPressed:
                                        _selectedIndex == null || _isLoading
                                        ? () {}
                                        : _onContinue,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModeCard({
    required int index,
    required String title,
    required String description,
    required IconData icon,
    required Color accentColor,
    required bool isDarkMode,
    required VoidCallback onTap,
  }) {
    final shadowColor = isDarkMode ? AppColors.shadowDark : AppColors.shadow;
    final borderColor = isDarkMode ? AppColors.borderDark : AppColors.border;
    final cardBg = isDarkMode ? AppColors.surfaceDark : Colors.white;
    final titleColor = isDarkMode
        ? AppColors.textDarkPrimary
        : AppColors.textPrimary;
    final subColor = isDarkMode
        ? AppColors.textDarkSecondary
        : AppColors.textSecondary;
    final isSelected = _selectedIndex == index;
    const double shadowOffset = 6.0;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        transform: isSelected
            ? Matrix4.translationValues(shadowOffset, shadowOffset, 0.0)
            : Matrix4.identity(),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // Shadow
            Positioned(
              top: shadowOffset,
              left: shadowOffset,
              right: -shadowOffset,
              bottom: -shadowOffset,
              child: Container(
                decoration: BoxDecoration(
                  color: shadowColor,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: borderColor, width: 3),
                ),
              ),
            ),
            // Card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isSelected ? accentColor : borderColor,
                  width: 3,
                ),
              ),
              child: Row(
                children: [
                  // Icon badge
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: accentColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: borderColor, width: 3),
                    ),
                    child: Center(
                      child: Icon(icon, size: 30, color: titleColor),
                    ),
                  ),
                  const SizedBox(width: 16),
                  // Info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: GoogleFonts.jersey10(
                            fontSize: 28,
                            fontWeight: FontWeight.w400,
                            color: titleColor,
                            letterSpacing: 1.0,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          description.toUpperCase(),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: subColor,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Arrow
                  Icon(
                    Icons.arrow_forward_rounded,
                    color: titleColor,
                    size: 28,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModeSelectionGridBackgroundPainter extends CustomPainter {
  final Color color;
  _ModeSelectionGridBackgroundPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    var paint = Paint()
      ..color = color
      ..strokeWidth = 2.0;

    double gridSpace = 32.0;

    for (double i = 0; i < size.width; i += gridSpace) {
      canvas.drawLine(Offset(i, 0), Offset(i, size.height), paint);
    }

    for (double i = 0; i < size.height; i += gridSpace) {
      canvas.drawLine(Offset(0, i), Offset(size.width, i), paint);
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => true;
}
