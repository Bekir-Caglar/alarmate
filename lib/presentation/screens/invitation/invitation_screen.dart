import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_colors.dart';
import '../../components/primary_button.dart';
import '../../components/brutalist_icon_button.dart';
import '../../../core/services/alarm_sync_service.dart';

class InvitationScreen extends StatefulWidget {
  final String alarmId;
  final String inviterName;
  final String groupName;
  final String time;
  final String ampm;
  final String mission;
  final String difficulty;
  final Color groupColor;
  final List<int> days;

  const InvitationScreen({
    super.key,
    required this.alarmId,
    required this.inviterName,
    required this.groupName,
    required this.time,
    required this.ampm,
    required this.mission,
    required this.difficulty,
    this.days = const [],
    this.groupColor = AppColors.primaryLight,
  });

  @override
  State<InvitationScreen> createState() => _InvitationScreenState();
}

class _InvitationScreenState extends State<InvitationScreen> {
  bool _isLoading = false;

  Future<void> _acceptInvitation() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _isLoading = true);

    try {
      final db = FirebaseDatabase.instance.ref();

      // 1. Alarma kendini ekle
      await db
          .child('alarms')
          .child(widget.alarmId)
          .child('members')
          .child(user.uid)
          .set(true);

      // 1b. Davet listesinden sil (alarm altındaki)
      await db
          .child('alarms')
          .child(widget.alarmId)
          .child('invitedMembers')
          .child(user.uid)
          .remove();

      // 2. Kendi membership'ine ekle
      await db
          .child('memberships')
          .child(user.uid)
          .child(widget.alarmId)
          .set(true);

      // 3. Daveti sil
      await db
          .child('invitations')
          .child(user.uid)
          .child(widget.alarmId)
          .remove();

      // 4. Yerel alarmı kur
      await AlarmSyncService.syncAlarmsWithDevice();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'DAVET KABUL EDİLDİ!',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('HATA: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _rejectInvitation() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _isLoading = true);

    try {
      final db = FirebaseDatabase.instance.ref();
      await db
          .child('invitations')
          .child(user.uid)
          .child(widget.alarmId)
          .remove();
      // Alarm içindeki davetli listesinden de sil
      await db
          .child('alarms')
          .child(widget.alarmId)
          .child('invitedMembers')
          .child(user.uid)
          .remove();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('DAVET REDDEDİLDİ!'),
            backgroundColor: Colors.orange,
          ),
        );
        Navigator.pop(context);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final statusBarColor = isDarkMode ? AppColors.surfaceDark : Colors.white;
    final shadowColor = isDarkMode ? AppColors.shadowDark : AppColors.shadow;
    final borderColor = isDarkMode ? AppColors.borderDark : AppColors.border;
    final titleColor = isDarkMode
        ? AppColors.textDarkPrimary
        : AppColors.textPrimary;
    final subTitleColor = isDarkMode
        ? AppColors.textDarkSecondary
        : AppColors.textSecondary;
    final cardBg = isDarkMode ? AppColors.surfaceDark : Colors.white;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _GridBackgroundPainter(
                color: isDarkMode
                    ? Colors.white.withValues(alpha: 0.05)
                    : AppColors.textPrimary.withValues(alpha: 0.05),
              ),
            ),
          ),
          SafeArea(
            top: false,
            bottom: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _StatusBarCover(color: statusBarColor),
                _buildAppBar(context, isDarkMode),
                Expanded(
                  child: Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Positioned(
                            top: 8,
                            left: 8,
                            right: -8,
                            bottom: -8,
                            child: Container(
                              decoration: BoxDecoration(
                                color: shadowColor,
                                borderRadius: BorderRadius.circular(24),
                                border: Border.all(
                                  color: borderColor,
                                  width: 3,
                                ),
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 40,
                            ),
                            decoration: BoxDecoration(
                              color: cardBg,
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(color: borderColor, width: 3),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(20),
                                  decoration: BoxDecoration(
                                    color: Colors.yellowAccent,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: borderColor,
                                      width: 3,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: shadowColor,
                                        offset: const Offset(4, 4),
                                      ),
                                    ],
                                  ),
                                  child: const Icon(
                                    Icons.mail_outline_rounded,
                                    size: 48,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 32),
                                Text(
                                  'YENİ BİR DAVETİN VAR!',
                                  style: TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.w900,
                                    color: titleColor,
                                    letterSpacing: 1.5,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 16),
                                RichText(
                                  textAlign: TextAlign.center,
                                  text: TextSpan(
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: subTitleColor,
                                      height: 1.5,
                                    ),
                                    children: [
                                      TextSpan(
                                        text: widget.inviterName,
                                        style: TextStyle(
                                          fontWeight: FontWeight.w900,
                                          color: titleColor,
                                        ),
                                      ),
                                      const TextSpan(text: ' seni '),
                                      TextSpan(
                                        text: widget.groupName,
                                        style: TextStyle(
                                          fontWeight: FontWeight.w900,
                                          color: titleColor,
                                        ),
                                      ),
                                      const TextSpan(
                                        text: ' odasına davet etti.',
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 32),
                                Container(
                                  padding: const EdgeInsets.all(20),
                                  decoration: BoxDecoration(
                                    color: isDarkMode
                                        ? const Color(0xFF161E2E)
                                        : Colors.grey[100],
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: borderColor,
                                      width: 2,
                                    ),
                                  ),
                                  child: Column(
                                    children: [
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.end,
                                        children: [
                                          Text(
                                            widget.time,
                                            style: GoogleFonts.jersey10(
                                              fontSize: 64,
                                              fontWeight: FontWeight.w400,
                                              color: titleColor,
                                              height: 1.0,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              bottom: 12.0,
                                            ),
                                            child: Text(
                                              widget.ampm,
                                              style: TextStyle(
                                                fontSize: 20,
                                                fontWeight: FontWeight.w900,
                                                color: titleColor,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      if (widget.days.isNotEmpty) ...[
                                        const SizedBox(height: 12),
                                        Text(
                                          widget.days
                                              .map((d) {
                                                const days = [
                                                  'PZT',
                                                  'SAL',
                                                  'ÇAR',
                                                  'PER',
                                                  'CUM',
                                                  'CMT',
                                                  'PAZ',
                                                ];
                                                return days[d - 1];
                                              })
                                              .join(', '),
                                          style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w900,
                                            color: AppColors.primary,
                                            letterSpacing: 1.2,
                                          ),
                                        ),
                                      ],
                                      const SizedBox(height: 16),
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.center,
                                            children: [
                                              Text(
                                                widget.mission,
                                                style: TextStyle(
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w900,
                                                  color: titleColor,
                                                ),
                                              ),
                                              Text(
                                                'Zorluk: ${widget.difficulty}',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w900,
                                                  color: subTitleColor,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 48),
                                if (_isLoading)
                                  const CircularProgressIndicator()
                                else ...[
                                  PrimaryButton(
                                    text: 'KABUL ET VE KATIL',
                                    color: AppColors.success,
                                    icon: Icons.check_circle_rounded,
                                    onPressed: _acceptInvitation,
                                  ),
                                  const SizedBox(height: 16),
                                  PrimaryButton(
                                    text: 'DAVETİ REDDET',
                                    color: AppColors.error,
                                    icon: Icons.cancel_rounded,
                                    onPressed: _rejectInvitation,
                                  ),
                                ],
                              ],
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
        ],
      ),
    );
  }

  Widget _buildAppBar(BuildContext context, bool isDarkMode) {
    final bgColor = isDarkMode ? AppColors.surfaceDark : Colors.white;
    final borderColor = isDarkMode ? AppColors.borderDark : AppColors.border;
    final titleColor = isDarkMode
        ? AppColors.textDarkPrimary
        : AppColors.textPrimary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        color: bgColor,
        border: Border(bottom: BorderSide(color: borderColor, width: 3)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          BrutalistIconButton(
            icon: Icons.arrow_back_rounded,
            onTap: () => Navigator.pop(context),
          ),
          Text(
            'DAVET',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: titleColor,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(width: 44),
        ],
      ),
    );
  }
}

class _GridBackgroundPainter extends CustomPainter {
  final Color color;
  _GridBackgroundPainter({required this.color});

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

class _StatusBarCover extends StatelessWidget {
  final Color color;
  const _StatusBarCover({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(height: MediaQuery.of(context).padding.top, color: color);
  }
}
