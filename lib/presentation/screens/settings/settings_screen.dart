import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../../../core/theme/app_colors.dart';
import '../../components/brutalist_icon_button.dart';
import '../../components/primary_button.dart';
import '../../../main.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:alarm/alarm.dart';
import '../../../core/services/alarm_sync_service.dart';
import 'dart:io';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _notificationsEnabled = false;
  bool _overlayEnabled = false;
  late TextEditingController _nicknameController;
  late TextEditingController _phoneController;

  @override
  void initState() {
    super.initState();
    _nicknameController = TextEditingController();
    _phoneController = TextEditingController();
    _loadNotificationSettings();
    _loadProfileData();
    _loadOverlayPermission();
  }

  Future<void> _loadProfileData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) return;
    final snapshot = await FirebaseDatabase.instance
        .ref()
        .child('users')
        .child(user.uid)
        .get();
    if (snapshot.exists && snapshot.value is Map) {
      final data = snapshot.value as Map;
      if (!mounted) return;
      _nicknameController.text = data['username'] ?? '';
      _phoneController.text = data['phone'] ?? '';
    }
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _loadNotificationSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _notificationsEnabled = prefs.getBool('notifications_enabled') ?? false;
    });

    // Also check actual system permission status to keep in sync
    final status = await Permission.notification.status;
    if (status.isGranted != _notificationsEnabled) {
      setState(() {
        _notificationsEnabled = status.isGranted;
      });
      await prefs.setBool('notifications_enabled', status.isGranted);
    }
  }

  Future<void> _toggleNotifications(bool value) async {
    if (value) {
      final status = await Permission.notification.request();
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _notificationsEnabled = status.isGranted;
      });
      await prefs.setBool('notifications_enabled', status.isGranted);

      if (status.isPermanentlyDenied) {
        if (mounted) {
          _showPermissionDeniedDialog();
        }
      }
    } else {
      // We can't actually "revoke" permission programmatically on most platforms,
      // but we can store the user's preference to disable notifications.
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _notificationsEnabled = false;
      });
      await prefs.setBool('notifications_enabled', false);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'BİLDİRİMLER UYGULAMA İÇİNDEN DEVRE DIŞI BIRAKILDI. TAMAMEN KAPATMAK İÇİN SİSTEM AYARLARINA GİDİN.',
            ),
          ),
        );
      }
    }
  }

  Future<void> _loadOverlayPermission() async {
    if (!Platform.isAndroid) return;
    final status = await Permission.systemAlertWindow.status;
    setState(() {
      _overlayEnabled = status.isGranted;
    });
  }

  Future<void> _toggleOverlayPermission(bool value) async {
    if (!Platform.isAndroid) return;

    if (value) {
      final status = await Permission.systemAlertWindow.request();
      setState(() {
        _overlayEnabled = status.isGranted;
      });

      if (status.isPermanentlyDenied || status.isDenied) {
        if (mounted) {
          _showOverlayPermissionDialog();
        }
      }
    } else {
      // Cannot revoke programmatically easily, guide user
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'BU İZNİ KAPATMAK İÇİN SİSTEM AYARLARINA GİTMELİSİNİZ.',
            ),
          ),
        );
      }
      // Re-check status to sync UI if they didn't actually change anything
      _loadOverlayPermission();
    }
  }

  void _showOverlayPermissionDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(
          'DİĞER UYGULAMALARIN ÜZERİNDE GÖSTERME',
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
        ),
        content: const Text(
          'ALARM ÇALDIĞINDA GÖREV EKRANININ GÖZÜKMESİ İÇİN BU İZİN GEREKLİDİR. LÜTFEN LİSTEDEN ALARMATE\'İ BULUP İZİN VERİN.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'İPTAL',
              style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w900),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              openAppSettings();
            },
            child: const Text(
              'AYARLARA GİT',
              style: TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showPermissionDeniedDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(
          'BİLDİRİM İZNİ GEREKLİ',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        content: const Text(
          'BİLDİRİMLERİ AÇMAK İÇİN SİSTEM AYARLARINA GİDİP İZİN VERMELİSİNİZ.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'İPTAL',
              style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w900),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              openAppSettings();
            },
            child: const Text(
              'AYARLARA GİT',
              style: TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    bool isDarkMode = themeNotifier.value == ThemeMode.dark;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _SettingsGridBackgroundPainter(
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
                _StatusBarCover(
                  color: isDarkMode ? AppColors.surfaceDark : Colors.white,
                ),
                _buildAppBar(context, isDarkMode),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 16,
                    ),
                    children: [
                      _buildSettingsTitle('GENEL BİLGİLER', isDarkMode),
                      const SizedBox(height: 12),
                      if (!(FirebaseAuth.instance.currentUser?.isAnonymous ??
                          true)) ...[
                        _buildSettingsCard(
                          context: context,
                          title: 'PROFİLİ DÜZENLE',
                          icon: Icons.person_outline_rounded,
                          color: Colors.yellowAccent,
                          isDarkMode: isDarkMode,
                          onTap: () =>
                              _showEditProfileBottomSheet(context, isDarkMode),
                        ),
                        const SizedBox(height: 12),
                      ],
                      const SizedBox(height: 12),
                      _buildNotificationToggleCard(isDarkMode),
                      if (Platform.isAndroid && !_overlayEnabled) ...[
                        const SizedBox(height: 12),
                        _buildOverlayToggleCard(isDarkMode),
                      ],
                      const SizedBox(height: 24),
                      _buildSettingsTitle('GÖRÜNÜM', isDarkMode),
                      const SizedBox(height: 12),
                      _buildThemeToggleCard(context, isDarkMode),
                      const SizedBox(height: 12),
                      _buildSettingsCard(
                        context: context,
                        title: 'SAAT FORMATI',
                        icon: Icons.access_time_filled_rounded,
                        color: Colors.purpleAccent,
                        isDarkMode: isDarkMode,
                        onTap: () =>
                            _showTimeFormatBottomSheet(context, isDarkMode),
                      ),
                      const SizedBox(height: 12),
                      _buildSettingsCard(
                        context: context,
                        title: 'DİL SEÇİMİ',
                        icon: Icons.language_rounded,
                        color: Colors.cyanAccent,
                        isDarkMode: isDarkMode,
                        onTap: () =>
                            _showLanguageBottomSheet(context, isDarkMode),
                      ),
                      const SizedBox(height: 24),
                      _buildSettingsTitle('DESTEK', isDarkMode),
                      const SizedBox(height: 12),
                      _buildSettingsCard(
                        context: context,
                        title: 'SÜRÜM BİLGİSİ',
                        icon: Icons.info_outline_rounded,
                        color: Colors.orangeAccent,
                        isDarkMode: isDarkMode,
                        onTap: () {},
                      ),
                      const SizedBox(height: 12),
                      _buildSettingsCard(
                        context: context,
                        title: 'ÇIKIŞ YAP',
                        icon: Icons.logout_rounded,
                        color: AppColors.error,
                        isDestructive: true,
                        isDarkMode: isDarkMode,
                        onTap: () async {
                          // Deactivate and sync alarms before logout
                          await AlarmSyncService.toggleAllAlarms(false);
                          await AlarmSyncService.syncAlarmsWithDevice();
                          await Alarm.stopAll();

                          // Mark that we need to activate alarms on next login
                          final prefs = await SharedPreferences.getInstance();
                          await prefs.setBool('pending_alarm_activation', true);

                          await GoogleSignIn().signOut();
                          await FirebaseAuth.instance.signOut();

                          if (!context.mounted) return;
                          Navigator.pushAndRemoveUntil(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const AuthWrapper(),
                            ),
                            (route) => false,
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsTitle(String title, bool isDarkMode) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w900,
        color: isDarkMode
            ? AppColors.textDarkSecondary
            : AppColors.textSecondary,
        letterSpacing: 1.5,
      ),
    );
  }

  Widget _buildAppBar(BuildContext context, bool isDarkMode) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: BoxDecoration(
        color: isDarkMode ? AppColors.surfaceDark : Colors.white,
        border: Border(
          bottom: BorderSide(
            color: isDarkMode ? AppColors.borderDark : AppColors.border,
            width: 3,
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          BrutalistIconButton(
            icon: Icons.arrow_back_rounded,
            onTap: () => Navigator.pop(context),
          ),
          Text(
            'SİSTEM AYARLARI',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: isDarkMode
                  ? AppColors.textDarkPrimary
                  : AppColors.textPrimary,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(width: 44),
        ],
      ),
    );
  }

  Widget _buildSettingsCard({
    required BuildContext context,
    required String title,
    required IconData icon,
    required Color color,
    required bool isDarkMode,
    bool isDestructive = false,
    required VoidCallback onTap,
  }) {
    final shadowColor = isDarkMode ? AppColors.shadowDark : AppColors.shadow;
    final borderColor = isDarkMode ? AppColors.borderDark : AppColors.border;
    final cardBgColor = isDarkMode ? AppColors.surfaceDark : Colors.white;

    return GestureDetector(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            top: 4,
            left: 4,
            right: -4,
            bottom: -4,
            child: Container(
              decoration: BoxDecoration(
                color: shadowColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: borderColor, width: 2),
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: cardBgColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: borderColor, width: 2),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: Border.all(color: borderColor, width: 2),
                  ),
                  child: Icon(
                    icon,
                    size: 20,
                    color: isDestructive ? Colors.white : AppColors.textPrimary,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: isDestructive
                          ? AppColors.error
                          : (isDarkMode
                                ? AppColors.textDarkPrimary
                                : AppColors.textPrimary),
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  color: isDarkMode
                      ? AppColors.textDarkPrimary
                      : AppColors.textPrimary,
                  size: 14,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOverlayToggleCard(bool isDarkMode) {
    final shadowColor = isDarkMode ? AppColors.shadowDark : AppColors.shadow;
    final borderColor = isDarkMode ? AppColors.borderDark : AppColors.border;
    final cardBgColor = isDarkMode ? AppColors.surfaceDark : Colors.white;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          top: 4,
          left: 4,
          right: -4,
          bottom: -4,
          child: Container(
            decoration: BoxDecoration(
              color: shadowColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: borderColor, width: 2),
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: cardBgColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderColor, width: 2),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.pinkAccent,
                  shape: BoxShape.circle,
                  border: Border.all(color: borderColor, width: 2),
                ),
                child: const Icon(
                  Icons.layers_rounded,
                  size: 20,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ÜSTTE GÖSTERME',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      'ALARM DİĞER APPLERİN ÜSTÜNDE AÇILIR',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: _overlayEnabled,
                onChanged: _toggleOverlayPermission,
                activeColor: AppColors.primary,
                activeTrackColor: AppColors.primary.withValues(alpha: 0.3),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildNotificationToggleCard(bool isDarkMode) {
    final shadowColor = isDarkMode ? AppColors.shadowDark : AppColors.shadow;
    final borderColor = isDarkMode ? AppColors.borderDark : AppColors.border;
    final cardBgColor = isDarkMode ? AppColors.surfaceDark : Colors.white;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          top: 4,
          left: 4,
          right: -4,
          bottom: -4,
          child: Container(
            decoration: BoxDecoration(
              color: shadowColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: borderColor, width: 2),
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: cardBgColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderColor, width: 2),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.greenAccent,
                  shape: BoxShape.circle,
                  border: Border.all(color: borderColor, width: 2),
                ),
                child: const Icon(
                  Icons.notifications_active_outlined,
                  size: 20,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  _notificationsEnabled
                      ? 'BİLDİRİMLER: AÇIK'
                      : 'BİLDİRİMLER: KAPALI',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: isDarkMode
                        ? AppColors.textDarkPrimary
                        : AppColors.textPrimary,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              Switch(
                value: _notificationsEnabled,
                activeColor: AppColors.primary,
                activeTrackColor: AppColors.primary.withValues(alpha: 0.5),
                inactiveThumbColor: AppColors.textPrimary,
                inactiveTrackColor: Colors.grey[300],
                onChanged: _toggleNotifications,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildThemeToggleCard(BuildContext context, bool isDarkMode) {
    final shadowColor = isDarkMode ? AppColors.shadowDark : AppColors.shadow;
    final borderColor = isDarkMode ? AppColors.borderDark : AppColors.border;
    final cardBgColor = isDarkMode ? AppColors.surfaceDark : Colors.white;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          top: 4,
          left: 4,
          right: -4,
          bottom: -4,
          child: Container(
            decoration: BoxDecoration(
              color: shadowColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: borderColor, width: 2),
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: cardBgColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderColor, width: 2),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blueAccent,
                  shape: BoxShape.circle,
                  border: Border.all(color: borderColor, width: 2),
                ),
                child: Icon(
                  isDarkMode
                      ? Icons.dark_mode_rounded
                      : Icons.light_mode_rounded,
                  size: 20,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  isDarkMode ? 'GECE MODU: AÇIK' : 'GECE MODU: KAPALI',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: isDarkMode
                        ? AppColors.textDarkPrimary
                        : AppColors.textPrimary,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              Switch(
                value: isDarkMode,
                activeColor: AppColors.primary,
                activeTrackColor: AppColors.primary.withValues(alpha: 0.5),
                inactiveThumbColor: AppColors.textPrimary,
                inactiveTrackColor: Colors.grey[300],
                onChanged: (value) {
                  themeNotifier.value = value
                      ? ThemeMode.dark
                      : ThemeMode.light;
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _showTimeFormatBottomSheet(BuildContext context, bool isDarkMode) {
    final shadowColor = isDarkMode ? AppColors.shadowDark : AppColors.shadow;
    final borderColor = isDarkMode ? AppColors.borderDark : AppColors.border;
    final bgColor = isDarkMode ? AppColors.surfaceDark : Colors.white;
    final titleColor = isDarkMode
        ? AppColors.textDarkPrimary
        : AppColors.textPrimary;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return ValueListenableBuilder<bool>(
          valueListenable: timeFormatNotifier,
          builder: (context, use24h, _) {
            return Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
                border: Border.all(color: borderColor, width: 3),
              ),
              child: SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.symmetric(horizontal: 100),
                      decoration: BoxDecoration(
                        color: shadowColor.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'SAAT FORMATI',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        color: titleColor,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(height: 24),
                    _buildSelectionOption(
                      context: context,
                      title: '24 SAAT FORMATI',
                      isSelected: use24h,
                      isDarkMode: isDarkMode,
                      onTap: () {
                        timeFormatNotifier.value = true;
                        Navigator.pop(context);
                      },
                    ),
                    const SizedBox(height: 16),
                    _buildSelectionOption(
                      context: context,
                      title: '12 SAAT FORMATI (AM/PM)',
                      isSelected: !use24h,
                      isDarkMode: isDarkMode,
                      onTap: () {
                        timeFormatNotifier.value = false;
                        Navigator.pop(context);
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildSelectionOption({
    required BuildContext context,
    required String title,
    required bool isSelected,
    required bool isDarkMode,
    required VoidCallback onTap,
  }) {
    final borderColor = isDarkMode ? AppColors.borderDark : AppColors.border;
    final bgColor = isSelected
        ? AppColors.primary
        : (isDarkMode ? AppColors.surfaceDark : Colors.white);
    final textColor = isSelected
        ? Colors.white
        : (isDarkMode ? AppColors.textDarkPrimary : AppColors.textPrimary);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor, width: 2),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: isDarkMode ? AppColors.shadowDark : AppColors.shadow,
                    offset: const Offset(4, 4),
                  ),
                ]
              : null,
        ),
        child: Row(
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: textColor,
                letterSpacing: 1,
              ),
            ),
            const Spacer(),
            if (isSelected)
              const Icon(Icons.check_circle_rounded, color: Colors.white),
          ],
        ),
      ),
    );
  }

  void _showLanguageBottomSheet(BuildContext context, bool isDarkMode) {
    final shadowColor = isDarkMode ? AppColors.shadowDark : AppColors.shadow;
    final borderColor = isDarkMode ? AppColors.borderDark : AppColors.border;
    final bgColor = isDarkMode ? AppColors.surfaceDark : Colors.white;
    final titleColor = isDarkMode
        ? AppColors.textDarkPrimary
        : AppColors.textPrimary;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border.all(color: borderColor, width: 3),
          ),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.symmetric(horizontal: 100),
                  decoration: BoxDecoration(
                    color: shadowColor.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'DİL SEÇİMİ',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    color: titleColor,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 24),
                _buildLanguageOption(
                  context: context,
                  title: 'TÜRKÇE',
                  isSelected: true,
                  isDarkMode: isDarkMode,
                  onTap: () => Navigator.pop(context),
                ),
                const SizedBox(height: 16),
                _buildLanguageOption(
                  context: context,
                  title: 'ENGLISH (YAKINDA)',
                  isSelected: false,
                  isDarkMode: isDarkMode,
                  onTap: () {},
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildLanguageOption({
    required BuildContext context,
    required String title,
    required bool isSelected,
    required bool isDarkMode,
    required VoidCallback onTap,
  }) {
    final borderColor = isDarkMode ? AppColors.borderDark : AppColors.border;
    final bgColor = isSelected
        ? AppColors.primary
        : (isDarkMode ? AppColors.surfaceDark : Colors.white);
    final textColor = isSelected
        ? Colors.white
        : (isDarkMode ? AppColors.textDarkPrimary : AppColors.textPrimary);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor, width: 2),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: isDarkMode ? AppColors.shadowDark : AppColors.shadow,
                    offset: const Offset(4, 4),
                  ),
                ]
              : null,
        ),
        child: Row(
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: textColor,
                letterSpacing: 1,
              ),
            ),
            const Spacer(),
            if (isSelected)
              const Icon(Icons.check_circle_rounded, color: Colors.white),
          ],
        ),
      ),
    );
  }

  void _showEditProfileBottomSheet(BuildContext context, bool isDarkMode) {
    final borderColor = isDarkMode ? AppColors.borderDark : AppColors.border;
    final bgColor = isDarkMode ? AppColors.surfaceDark : Colors.white;
    final titleColor = isDarkMode
        ? AppColors.textDarkPrimary
        : AppColors.textPrimary;
    final shadowColor = isDarkMode ? AppColors.shadowDark : AppColors.shadow;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
              border: Border.all(color: borderColor, width: 3),
            ),
            child: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: shadowColor.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'PROFİLİ DÜZENLE',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      color: titleColor,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 32),
                  // Profile Photo
                  Center(
                    child: Stack(
                      children: [
                        Container(
                          width: 100,
                          height: 100,
                          decoration: BoxDecoration(
                            color: Colors.yellowAccent,
                            shape: BoxShape.circle,
                            border: Border.all(color: borderColor, width: 3),
                            boxShadow: [
                              BoxShadow(
                                color: shadowColor,
                                offset: const Offset(4, 4),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.person_rounded,
                            size: 50,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              shape: BoxShape.circle,
                              border: Border.all(color: borderColor, width: 2),
                            ),
                            child: const Icon(
                              Icons.camera_alt_rounded,
                              size: 16,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),
                  _buildEditField(
                    label: 'TAKMA AD',
                    controller: _nicknameController,
                    isDarkMode: isDarkMode,
                  ),
                  const SizedBox(height: 32),
                  PrimaryButton(
                    text: 'GÜNCELLE',
                    onPressed: () async {
                      final user = FirebaseAuth.instance.currentUser;
                      if (user == null) return;
                      final newUsername = _nicknameController.text
                          .trim()
                          .toUpperCase();
                      if (newUsername.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('KULLANICI ADI BOŞ OLAMAZ!'),
                          ),
                        );
                        return;
                      }

                      final dbRef = FirebaseDatabase.instance.ref();

                      // Nick benzersizlik kontrolü
                      final usernameEvent = await dbRef
                          .child('users')
                          .orderByChild('username')
                          .equalTo(newUsername)
                          .once();
                      if (usernameEvent.snapshot.exists) {
                        final others = usernameEvent.snapshot.children.where(
                          (c) => c.key != user.uid,
                        );
                        if (others.isNotEmpty) {
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'BU KULLANICI ADI ZATEN ALINMIŞ!',
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
                      }

                      // Güncelle
                      await dbRef.child('users').child(user.uid).update({
                        'username': newUsername,
                      });

                      if (!context.mounted) return;
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('PROFİL GÜNCELLENDİ!')),
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildEditField({
    required String label,
    required TextEditingController controller,
    required bool isDarkMode,
    TextInputType keyboardType = TextInputType.text,
  }) {
    final borderColor = isDarkMode ? AppColors.borderDark : AppColors.border;
    final titleColor = isDarkMode
        ? AppColors.textDarkPrimary
        : AppColors.textPrimary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w900,
            color: isDarkMode
                ? AppColors.textDarkSecondary
                : AppColors.textSecondary,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: isDarkMode ? AppColors.surfaceDark : Colors.grey[100],
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderColor, width: 2),
          ),
          child: TextField(
            controller: controller,
            keyboardType: keyboardType,
            style: TextStyle(fontWeight: FontWeight.w900, color: titleColor),
            decoration: const InputDecoration(
              contentPadding: EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
              border: InputBorder.none,
            ),
          ),
        ),
      ],
    );
  }
}

class _SettingsGridBackgroundPainter extends CustomPainter {
  final Color color;
  _SettingsGridBackgroundPainter({required this.color});

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
