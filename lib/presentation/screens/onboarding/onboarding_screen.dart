import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../components/primary_button.dart';
import '../../components/retro_progress_bar.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import '../../../main.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with SingleTickerProviderStateMixin {
  int _currentIndex = 0;
  late AnimationController _slideController;
  late Animation<Offset> _slideAnimation;

  final List<Map<String, dynamic>> _pages = [
    {
      'title': 'GÜNE BİRLİKTE\nBAŞLA',
      'description':
          'Arkadaşlarınla ortak gruplar kur. Herkes uyanmadan o alarm susmaz. Sorumluluk büyük!',
      'icon': Icons.group_add_rounded,
    },
    {
      'title': 'KİMSE KAÇAMAZ',
      'description':
          'Sadece butona basmak yetmez. Uyanmak için görevleri ve mini oyunları tamamlamak zorundasın.',
      'icon': Icons.gamepad_rounded,
    },
    {
      'title': 'ANINDA\nTAKİP ET',
      'description':
          'Uyuyanları gör, uyananları tebrik et. Kim uyuyakaldıysa bildirimle darlamaya başla.',
      'icon': Icons.rocket_launch_rounded,
    },
    {
      'title': 'HABERDAR\nKAL',
      'description':
          'Arkadaşların uyandığında veya seni darladıklarında bildirim almak için izin vermelisin.',
      'icon': Icons.notifications_active_rounded,
    },
  ];

  @override
  void initState() {
    super.initState();
    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _slideAnimation =
        Tween<Offset>(begin: Offset.zero, end: const Offset(-1.5, 0)).animate(
          CurvedAnimation(parent: _slideController, curve: Curves.easeInBack),
        );
  }

  @override
  void dispose() {
    _slideController.dispose();
    super.dispose();
  }

  bool _notificationPermissionRequested = false;

  void _nextStep() async {
    if (_currentIndex == 3) {
      if (!_notificationPermissionRequested) {
        // First click: Request Permission

        // FCM permission request
        await FirebaseMessaging.instance.requestPermission(
          alert: true,
          badge: true,
          sound: true,
        );

        // Local notification and other permissions via permission_handler
        final status = await Permission.notification.request();

        // Android specific: Request exact alarm permission if needed
        if (await Permission.scheduleExactAlarm.isDenied) {
          await Permission.scheduleExactAlarm.request();
        }

        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('notifications_enabled', status.isGranted);
        setState(() {
          _notificationPermissionRequested = true;
        });
        return; // Don't move to next step yet
      }
    }

    if (_currentIndex < _pages.length - 1) {
      await _slideController.forward();
      setState(() {
        _currentIndex++;
      });
      _slideController.reset();
    } else {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('has_seen_onboarding', true);

      if (!mounted) return;
      // Reload everything by going back to AuthWrapper
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const AuthWrapper()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final shadowColor = isDarkMode ? AppColors.shadowDark : AppColors.shadow;
    final borderColor = isDarkMode ? AppColors.borderDark : AppColors.border;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Stack(
        children: [
          // Grid Background
          Positioned.fill(
            child: CustomPaint(
              painter: GridBackgroundPainter(
                color: isDarkMode
                    ? Colors.white.withValues(alpha: 0.05)
                    : AppColors.textPrimary.withValues(alpha: 0.05),
              ),
            ),
          ),

          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 24.0,
                vertical: 24.0,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildRetroProgressBar(isDarkMode),

                  const Spacer(),
                  // Animated Card with Stickers
                  SlideTransition(
                    position: _slideAnimation,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        _buildBrutalistCard(_pages[_currentIndex], isDarkMode),
                        // Brutalist/Retro Stickers
                        if (_currentIndex == 0) ...[
                          _buildSticker(
                            'BİRLİKTE!',
                            AppColors.error,
                            -0.2,
                            shadowColor,
                            isDarkMode,
                            top: -15,
                            left: -15,
                          ),
                          _buildSticker(
                            'ORTAK',
                            AppColors.primaryLight,
                            0.15,
                            shadowColor,
                            isDarkMode,
                            bottom: -10,
                            right: -20,
                          ),
                        ],
                        if (_currentIndex == 1) ...[
                          _buildSticker(
                            'ZORLU',
                            Colors.yellowAccent,
                            0.2,
                            shadowColor,
                            isDarkMode,
                            top: -20,
                            right: -10,
                          ),
                          _buildSticker(
                            'KAÇIŞ YOK',
                            const Color(0xFFE81CFF),
                            -0.15,
                            shadowColor,
                            isDarkMode,
                            bottom: -15,
                            left: -15,
                          ),
                        ],
                        if (_currentIndex == 2) ...[
                          _buildSticker(
                            'RADAR',
                            Colors.greenAccent,
                            0.25,
                            shadowColor,
                            isDarkMode,
                            bottom: -20,
                            left: -20,
                          ),
                          _buildSticker(
                            'YAKALANDIN!',
                            Colors.yellowAccent,
                            0.15,
                            shadowColor,
                            isDarkMode,
                            top: -15,
                            right: -20,
                          ),
                        ],
                        if (_currentIndex == 3) ...[
                          _buildSticker(
                            'ÖNEMLİ!',
                            Colors.orangeAccent,
                            0.2,
                            shadowColor,
                            isDarkMode,
                            bottom: -10,
                            right: -15,
                          ),
                        ],
                      ],
                    ),
                  ),

                  const Spacer(),

                  PrimaryButton(
                    text: _currentIndex == _pages.length - 1
                        ? (_notificationPermissionRequested
                              ? 'HADİ BAŞLAYALIM!'
                              : 'İZİN VER')
                        : 'SIRADAKİ ->',
                    onPressed: _nextStep,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSticker(
    String text,
    Color color,
    double angle,
    Color shadowColor,
    bool isDarkMode, {
    double? top,
    double? bottom,
    double? left,
    double? right,
  }) {
    final borderColor = isDarkMode ? AppColors.borderDark : AppColors.border;
    return Positioned(
      top: top,
      bottom: bottom,
      left: left,
      right: right,
      child: Transform.rotate(
        angle: angle,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          decoration: BoxDecoration(
            color: color,
            border: Border.all(color: borderColor, width: 3),
            boxShadow: [
              BoxShadow(color: shadowColor, offset: const Offset(4, 4)),
            ],
          ),
          child: Text(
            text,
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 16,
              color: AppColors.textPrimary,
              letterSpacing: 1.5,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRetroProgressBar(bool isDarkMode) {
    return RetroProgressBar(
      totalSteps: _pages.length,
      currentStep: _currentIndex,
    );
  }

  Widget _buildBrutalistCard(Map<String, dynamic> page, bool isDarkMode) {
    final shadowColor = isDarkMode ? AppColors.shadowDark : AppColors.shadow;
    final borderColor = isDarkMode ? AppColors.borderDark : AppColors.border;
    final cardBg = isDarkMode ? AppColors.surfaceDark : Colors.white;
    final titleColor = isDarkMode
        ? AppColors.textDarkPrimary
        : AppColors.textPrimary;
    final subTitleColor = isDarkMode
        ? AppColors.textDarkSecondary
        : AppColors.textSecondary;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          top: 12,
          left: 12,
          right: -12,
          bottom: -12,
          child: Container(
            decoration: BoxDecoration(
              color: shadowColor,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: borderColor, width: 3),
            ),
          ),
        ),

        Container(
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: borderColor, width: 3),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: borderColor, width: 3),
                  boxShadow: [
                    BoxShadow(color: shadowColor, offset: const Offset(4, 4)),
                  ],
                ),
                child: Icon(
                  page['icon'],
                  size: 50,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 48),
              Text(
                page['title'],
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w900,
                  color: titleColor,
                  height: 1.1,
                  letterSpacing: -1,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                page['description'],
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: subTitleColor,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class GridBackgroundPainter extends CustomPainter {
  final Color color;
  GridBackgroundPainter({required this.color});

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
