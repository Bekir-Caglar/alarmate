import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/services.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import '../../../core/theme/app_colors.dart';
import '../../components/brutalist_icon_button.dart';
import '../alarm_detail/alarm_detail_screen.dart';
import '../create_alarm/create_alarm_screen.dart';
import '../settings/settings_screen.dart';
import '../invitation/invitation_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import '../../../core/services/alarm_sync_service.dart';
import '../../../core/services/local_alarm_service.dart';
import '../../../core/database/local_db.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io';
import '../../../main.dart';
import '../../../data/repositories/data_repository.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // RTDB Veri Durumları
  List<Map<String, dynamic>> _invitations = [];
  List<Map<String, dynamic>> _alarms = [];
  bool _isLoadingAlarms = true;
  bool _isAnonymous = false;
  bool _overlayPermissionMissing = false;

  StreamSubscription<DatabaseEvent>? _pendingUpdatesSubscription;
  StreamSubscription<List<Map<String, dynamic>>>? _localAlarmsSub;
  StreamSubscription<List<Map<String, dynamic>>>? _localInvitationsSub;
  StreamSubscription<Map<String, dynamic>?>? _userSub;

  List<Map<String, dynamic>> _pendingUpdates = [];

  int _currentInvitationIndex = 0;

  String? _username;
  bool _isOnline = true; // Connection state for Firebase
  bool _isFirstConnectivityCheck = true;
  Timer? _connectivityTimer;

  @override
  void initState() {
    super.initState();
    _loadUserInfo();
    _setupLocalStreams();
    _setupDatabaseListeners();
  }

  void _setupLocalStreams() {
    DataRepository.instance.startFirebaseSync();

    _localAlarmsSub = DataRepository.instance.alarmsStream.listen((alarms) {
      if (mounted) {
        // Alarmları zaman (saat) sırasına göre dizeceğiz ki sıralamalar rastgele atlamasın
        alarms.sort((a, b) {
          int minA = _timeToMinutes(a['time'] ?? '00:00', a['ampm'] ?? 'AM');
          int minB = _timeToMinutes(b['time'] ?? '00:00', b['ampm'] ?? 'AM');
          return minA.compareTo(minB);
        });

        setState(() {
          _alarms = alarms;
          _isLoadingAlarms = false;
        });
      }
    });

    _localInvitationsSub = DataRepository.instance.invitationsStream.listen((
      invites,
    ) {
      if (mounted) {
        setState(() {
          _invitations = invites;
        });
      }
    });

    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    if (currentUid != null) {
      _userSub = DataRepository.instance.watchUser(currentUid).listen((data) {
        if (mounted && data != null && data['username'] != null) {
          setState(() {
            _username = data['username'];
          });
        }
      });
    }
  }

  void _setupDatabaseListeners() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) {
      if (mounted) setState(() => _isLoadingAlarms = false);
      return;
    }

    final db = FirebaseDatabase.instance.ref();

    // Bekleyen güncellemeleri dinle (Firebase UI spesifik)
    _pendingUpdatesSubscription = db
        .child('pendingUpdates')
        .child(user.uid)
        .onValue
        .listen(
          (event) {
            if (event.snapshot.exists && event.snapshot.value is Map) {
              final data = Map<String, dynamic>.from(
                event.snapshot.value as Map,
              );
              final list = data.entries.map((e) {
                final val = Map<String, dynamic>.from(e.value as Map);
                val['alarmId'] = e.key;
                return val;
              }).toList();
              if (mounted) setState(() => _pendingUpdates = list);
            } else {
              if (mounted) setState(() => _pendingUpdates = []);
            }
          },
          onError: (error) {
            debugPrint('PendingUpdates error: $error');
            if (mounted) setState(() => _pendingUpdates = []);
          },
        );

    // Bağlantı durumunu dinle (Offline banner için)
    FirebaseDatabase.instance.ref('.info/connected').onValue.listen((event) {
      final connected = event.snapshot.value as bool? ?? false;
      _connectivityTimer?.cancel();

      if (connected) {
        if (mounted) {
          if (!_isFirstConnectivityCheck && !_isOnline && !_isAnonymous) {
            // İnternet sonradan geri geldi! Senkronizasyonu başlat
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'İnternet bağlantısı sağlandı, veriler güncelleniyor...',
                ),
                backgroundColor: Colors.green,
                duration: Duration(seconds: 2),
              ),
            );
            DataRepository.instance.forceSync();
          }
          setState(() {
            _isOnline = true;
            _isFirstConnectivityCheck = false;
          });
        }
      } else {
        // Saniyelik gidip gelmeleri engellemek için Timer (Debounce)
        _connectivityTimer = Timer(const Duration(milliseconds: 2500), () {
          if (mounted) {
            setState(() {
              _isOnline = false;
              _isFirstConnectivityCheck = false;
            });
          }
        });
      }
    });
  }

  Future<void> _loadUserInfo() async {
    final user = FirebaseAuth.instance.currentUser;
    final prefs = await SharedPreferences.getInstance();
    final isOfflineGuest = prefs.getBool('isOfflineGuest') ?? false;

    if (mounted) {
      setState(() {
        _isAnonymous = (user?.isAnonymous ?? false) || isOfflineGuest;
      });
    }

    if (user != null) {
      // Handle pending activation after login
      final prefs = await SharedPreferences.getInstance();
      final pendingActivation =
          prefs.getBool('pending_alarm_activation') ?? false;
      if (pendingActivation) {
        await AlarmSyncService.toggleAllAlarms(true);
        await prefs.setBool('pending_alarm_activation', false);
      }

      // Always sync with device on startup to ensure local schedules match DB
      await AlarmSyncService.syncAlarmsWithDevice();

      if (!user.isAnonymous) {
        // FCM token'ını kaydet
        try {
          final fcmToken = await FirebaseMessaging.instance.getToken();
          if (fcmToken != null) {
            await FirebaseDatabase.instance
                .ref()
                .child('users')
                .child(user.uid)
                .child('fcmToken')
                .set(fcmToken);
          }
        } catch (e) {
          debugPrint('FCM token kaydedilemedi: $e');
        }
      }
    }

    // Check for overlay permission on Android
    if (Platform.isAndroid) {
      _checkOverlayPermission();
    }
  }

  Future<void> _checkOverlayPermission() async {
    final status = await Permission.systemAlertWindow.status;
    if (mounted) {
      setState(() {
        _overlayPermissionMissing = !status.isGranted;
      });
    }
  }

  Future<void> _loadLocalAlarms() async {
    // Left empty since StreamBuilder handles everything seamlessly now
  }

  int _timeToMinutes(String timeStr, String ampm) {
    try {
      final parts = timeStr.trim().split(':');
      int h = int.parse(parts[0].trim());
      int m = int.parse(parts[1].trim());
      if (h <= 12) {
        if (ampm == 'PM' && h != 12) h += 12;
        if (ampm == 'AM' && h == 12) h = 0;
      }
      return h * 60 + m;
    } catch (_) {
      return 0;
    }
  }

  @override
  void dispose() {
    _connectivityTimer?.cancel();
    _pendingUpdatesSubscription?.cancel();
    _localAlarmsSub?.cancel();
    _localInvitationsSub?.cancel();
    _userSub?.cancel();
    super.dispose();
  }

  Widget _buildOverlayPermissionWarning(bool isDarkMode) {
    final borderColor = isDarkMode ? AppColors.borderDark : AppColors.border;
    final bgColor = isDarkMode ? AppColors.surfaceDark : Colors.white;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          top: 8,
          left: 8,
          right: -8,
          bottom: -8,
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.error.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: borderColor, width: 3),
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderColor, width: 3),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.error,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: borderColor, width: 2),
                    ),
                    child: const Icon(
                      Icons.warning_amber_rounded,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'KRİTİK İZİN EKSİK!',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Text(
                'Alarmların diğer uygulamaların üstünde açılabilmesi için "Üstte Gösterme" izni vermelisin.',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.error,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide(color: borderColor, width: 2),
                  ),
                ),
                onPressed: () async {
                  await Permission.systemAlertWindow.request();
                  _checkOverlayPermission();
                },
                child: const Text(
                  'İZİN VER',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildOfflineBanner(bool isDarkMode) {
    if (_isOnline || _isAnonymous) return const SizedBox.shrink();

    final borderColor = isDarkMode ? AppColors.borderDark : AppColors.border;

    return Container(
      margin: const EdgeInsets.only(bottom: 16.0),
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      decoration: BoxDecoration(
        color: AppColors.error,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor, width: 2),
      ),
      child: Row(
        children: const [
          Icon(Icons.wifi_off_rounded, color: Colors.white),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'İNTERNET BAĞLANTISI YOK\nDeğişikliklerin tekrar çevrimiçi olduğunda senkronize edilecek.',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final shadowColor = isDarkMode ? AppColors.shadowDark : AppColors.shadow;
    final borderColor = isDarkMode ? AppColors.borderDark : AppColors.border;
    final statusBarColor = isDarkMode ? AppColors.surfaceDark : Colors.white;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Stack(
        children: [
          // Grid Background
          Positioned.fill(
            child: CustomPaint(
              painter: _HomeGridBackgroundPainter(
                color: isDarkMode
                    ? Colors.white.withOpacity(0.05)
                    : AppColors.textPrimary.withOpacity(0.05),
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
                _buildAppBar(isDarkMode),
                Expanded(
                  child: _isLoadingAlarms
                      ? const Center(child: CircularProgressIndicator())
                      : RefreshIndicator(
                          onRefresh: () async {
                            if (!_isAnonymous) {
                              await DataRepository.instance.forceSync();
                            }
                          },
                          color: AppColors.primary,
                          child:
                              (_alarms.isNotEmpty ||
                                  _invitations.isNotEmpty ||
                                  _pendingUpdates.isNotEmpty)
                              ? ListView(
                                  physics:
                                      const AlwaysScrollableScrollPhysics(),
                                  padding: const EdgeInsets.all(24),
                                  children: [
                                    if (_pendingUpdates.isNotEmpty) ...[
                                      ..._pendingUpdates.map(
                                        (update) => Padding(
                                          padding: const EdgeInsets.only(
                                            bottom: 12.0,
                                          ),
                                          child: _buildPendingUpdateBanner(
                                            context,
                                            isDarkMode,
                                            update,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                    ],

                                    if (_invitations.isNotEmpty) ...[
                                      _buildInvitationBanner(
                                        context,
                                        isDarkMode,
                                      ),
                                      const SizedBox(height: 16),
                                    ],

                                    if (Platform.isAndroid &&
                                        _overlayPermissionMissing) ...[
                                      _buildOverlayPermissionWarning(
                                        isDarkMode,
                                      ),
                                      const SizedBox(height: 32),
                                    ],

                                    _buildOfflineBanner(isDarkMode),

                                    if (_alarms.isNotEmpty) ...[
                                      _buildSectionTitle(
                                        'AKTİF ALARMLAR',
                                        isDarkMode,
                                      ),
                                      const SizedBox(height: 16),
                                      ..._alarms.map(
                                        (alarm) => Padding(
                                          padding: const EdgeInsets.only(
                                            bottom: 16.0,
                                          ),
                                          child: _buildAlarmCard(
                                            context: context,
                                            alarmId: alarm['id'],
                                            time: alarm['time'] ?? '00:00',
                                            ampm: alarm['ampm'] ?? 'AM',
                                            groupName:
                                                alarm['groupName'] ??
                                                'BİR GRUP',
                                            membersAwake:
                                                (alarm['membersAwake'] as List?)
                                                    ?.length ??
                                                0,
                                            totalMembers:
                                                (alarm['members'] as Map?)
                                                    ?.length ??
                                                1,
                                            color: alarm['color'] != null
                                                ? Color(
                                                    int.parse(alarm['color']),
                                                  )
                                                : AppColors.primaryLight,
                                            isAdmin:
                                                alarm['creatorId'] ==
                                                FirebaseAuth
                                                    .instance
                                                    .currentUser
                                                    ?.uid,
                                            isActive: alarm['isActive'] ?? true,
                                            isDarkMode: isDarkMode,
                                            isAnonymous: _isAnonymous,
                                            days: List<int>.from(
                                              alarm['days'] ?? [],
                                            ),
                                            onToggle: () async {
                                              final bool newActive =
                                                  !(alarm['isActive'] ?? true);

                                              await LocalAlarmService.updateAlarm(
                                                alarm['id'],
                                                {'isActive': newActive},
                                              );
                                              // Update UI locally first for instant feedback
                                              setState(() {
                                                final index = _alarms
                                                    .indexWhere(
                                                      (a) =>
                                                          a['id'] ==
                                                          alarm['id'],
                                                    );
                                                if (index != -1) {
                                                  _alarms[index]['isActive'] =
                                                      newActive;
                                                }
                                              });

                                              // Update local cache immediately for offline reliability
                                              final current = await LocalDb
                                                  .instance
                                                  .getById(
                                                    'alarms',
                                                    alarm['id'],
                                                  );
                                              if (current != null) {
                                                await LocalDb.instance.save(
                                                  'alarms',
                                                  alarm['id'],
                                                  {
                                                    ...current,
                                                    'isActive': newActive,
                                                  },
                                                );
                                              }

                                              // Report individual status to Firebase for others to see in team status
                                              final user = FirebaseAuth
                                                  .instance
                                                  .currentUser;
                                              if (user != null &&
                                                  !user.isAnonymous) {
                                                await FirebaseDatabase.instance
                                                    .ref()
                                                    .child('alarms')
                                                    .child(alarm['id'])
                                                    .child(
                                                      'memberActiveStatuses',
                                                    )
                                                    .child(user.uid)
                                                    .set(newActive);
                                              }

                                              // Sync with hardware alarm package
                                              await AlarmSyncService.syncAlarmsWithDevice();
                                            },
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                )
                              : ListView(
                                  physics:
                                      const AlwaysScrollableScrollPhysics(),
                                  children: [
                                    SizedBox(
                                      height:
                                          MediaQuery.of(context).size.height *
                                          0.6,
                                      child: _buildEmptyState(isDarkMode),
                                    ),
                                  ],
                                ),
                        ),
                ),

                // Bottom Action
                Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: _buildBrutalistFab(isDarkMode),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppBar(bool isDarkMode) {
    final appBarBg = isDarkMode ? AppColors.surfaceDark : Colors.white;
    final shadowColor = isDarkMode ? AppColors.shadowDark : AppColors.shadow;
    final borderColor = isDarkMode ? AppColors.borderDark : AppColors.border;
    final titleColor = isDarkMode
        ? AppColors.textDarkPrimary
        : AppColors.textPrimary;
    final subTitleColor = isDarkMode
        ? AppColors.textDarkSecondary
        : AppColors.textSecondary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        color: appBarBg,
        border: Border(bottom: BorderSide(color: borderColor, width: 3)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              if (_isAnonymous) ...[
                // Anonim: Logo + Alarmate
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    border: Border.all(color: borderColor, width: 3),
                    shape: BoxShape.circle,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: ClipOval(
                      child: Image.asset('assets/logo.png', fit: BoxFit.cover),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'Alarmate',
                  style: GoogleFonts.jersey10(
                    fontSize: 36,
                    fontWeight: FontWeight.w400,
                    color: titleColor,
                    letterSpacing: 1.0,
                  ),
                ),
              ] else ...[
                // Giriş yapmış: Avatar + Merhaba
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    border: Border.all(color: borderColor, width: 3),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      (_username ?? '?')[0],
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'MERHABA,',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        color: subTitleColor,
                        letterSpacing: 1,
                      ),
                    ),
                    Text(
                      _username ?? 'OYUNCU',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: titleColor,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
          Row(
            children: [
              BrutalistIconButton(
                icon: Icons.settings,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const SettingsScreen(),
                    ),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  /*
  final List<Map<String, String>> _mockInvitations = [
    {
      'inviterName': 'OYUNCU 2',
      'groupName': 'SABAH SAVAŞÇILARI',
      'time': '07:30',
      'ampm': 'AM',
      'mission': 'MATEMATİK SINAVI',
      'difficulty': 'CEHENNEM',
    },
    {
      'inviterName': 'OYUNCU 3',
      'groupName': 'TEMBEL TENEKELER',
      'time': '09:00',
      'ampm': 'AM',
      'mission': 'ADIM SAYAR',
      'difficulty': 'KOLAY',
    },
    {
      'inviterName': 'OYUNCU 1',
      'groupName': 'GECE KUŞLARI',
      'time': '12:00',
      'ampm': 'PM',
      'mission': 'BARKOD OKUT',
      'difficulty': 'NORMAL',
    },
    {
      'inviterName': 'OYUNCU 4',
      'groupName': 'TEST GRUBU',
      'time': '11:00',
      'ampm': 'AM',
      'mission': 'TELEFONU SALLA',
      'difficulty': 'ZOR',
    },
  ];
  */

  Widget _buildInvitationBanner(BuildContext context, bool isDarkMode) {
    if (_invitations.isEmpty) return const SizedBox.shrink();

    final int totalInvitations = _invitations.length;
    final int indicatorCount = totalInvitations > 3 ? 3 : totalInvitations;

    int startIndex = 0;
    if (totalInvitations > 3) {
      if (_currentInvitationIndex == 0) {
        startIndex = 0;
      } else if (_currentInvitationIndex == totalInvitations - 1) {
        startIndex = totalInvitations - 3;
      } else {
        startIndex = _currentInvitationIndex - 1;
      }
    }

    final borderColor = isDarkMode ? AppColors.borderDark : AppColors.border;

    return Padding(
      padding: const EdgeInsets.only(bottom: 24.0),
      child: SizedBox(
        height: 104, // Slightly increased height for vertical swiping room
        child: Row(
          children: [
            // Dikey Indicator Alanı (Kaydırılabilir, animasyonlu)
            if (indicatorCount > 1)
              SizedBox(
                width: 32,
                height: 84, // 3 dot height (28 * 3)
                child: ClipRect(
                  child: Stack(
                    children: [
                      AnimatedPositioned(
                        duration: const Duration(milliseconds: 350),
                        curve: Curves.easeOutCubic,
                        top: -(startIndex * 28.0),
                        left: 0,
                        right: 0,
                        child: Column(
                          children: List.generate(totalInvitations, (
                            actualIndex,
                          ) {
                            final isSelected =
                                _currentInvitationIndex == actualIndex;
                            return SizedBox(
                              height: 28,
                              child: Center(
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 350),
                                  curve: Curves.easeOutBack,
                                  width: isSelected ? 24 : 10,
                                  height: isSelected ? 24 : 10,
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? AppColors.primary
                                        : (isDarkMode
                                              ? Colors.white24
                                              : Colors.black12),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: borderColor,
                                      width: isSelected ? 2 : 1,
                                    ),
                                  ),
                                  child: Center(
                                    child: isSelected
                                        ? Text(
                                            '${actualIndex + 1}',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w900,
                                            ),
                                          )
                                        : const SizedBox.shrink(),
                                  ),
                                ),
                              ),
                            );
                          }),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (indicatorCount > 1) const SizedBox(width: 8),

            // Kartların Kaydırılabilir Alanı (PageView)
            Expanded(
              child: PageView.builder(
                scrollDirection: Axis.vertical,
                clipBehavior: Clip.hardEdge,
                physics: const BouncingScrollPhysics(),
                controller: PageController(viewportFraction: 1.0),
                onPageChanged: (index) {
                  setState(() {
                    _currentInvitationIndex = index;
                  });
                },
                itemCount: totalInvitations,
                itemBuilder: (context, index) {
                  final inv = _invitations[index];
                  // Yalnızca sağa ve alta gölge bırakacak pay veriliyor. Yatayda tam genişliyor.
                  return Padding(
                    padding: const EdgeInsets.only(right: 8.0, bottom: 8.0),
                    child: _buildSingleInvitationCard(context, isDarkMode, inv),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSingleInvitationCard(
    BuildContext context,
    bool isDarkMode,
    Map<String, dynamic> inv,
  ) {
    final shadowColor = isDarkMode ? AppColors.shadowDark : AppColors.shadow;
    final borderColor = isDarkMode ? AppColors.borderDark : AppColors.border;

    // Arkasına solid arka plan rengini ekleyip, üstüne saydam yeşili bindiriyoruz.
    final baseBgColor = isDarkMode ? AppColors.surfaceDark : Colors.white;
    final greenOverlay = Colors.greenAccent.withValues(alpha: 0.45);
    final cardBg = Color.alphaBlend(greenOverlay, baseBgColor);

    final titleColor = isDarkMode
        ? AppColors.textDarkPrimary
        : AppColors.textPrimary;

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => InvitationScreen(
              alarmId: inv['id']!,
              inviterName: inv['inviterName']!,
              groupName: inv['groupName']!,
              time: inv['time']!,
              ampm: inv['ampm']!,
              mission: inv['mission']!,
              difficulty: inv['difficulty']!,
              days: List<int>.from(inv['days'] ?? []),
            ),
          ),
        );
      },
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            top: 6,
            left: 6,
            right: -6,
            bottom: -6,
            child: Container(
              decoration: BoxDecoration(
                color: shadowColor,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: borderColor, width: 3),
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: borderColor, width: 3),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(color: borderColor, width: 2),
                  ),
                  child: const Icon(
                    Icons.mail_rounded,
                    color: AppColors.primary,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'YENİ DAVET',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          color: titleColor,
                          letterSpacing: 1.5,
                        ),
                      ),
                      Text(
                        inv['groupName']!,
                        style: GoogleFonts.jersey10(
                          fontSize: 24,
                          fontWeight: FontWeight.w400,
                          color: titleColor,
                          height: 1.1,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.arrow_forward_ios_rounded,
                  color: AppColors.textPrimary,
                  size: 20,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPendingUpdateBanner(
    BuildContext context,
    bool isDarkMode,
    Map<String, dynamic> update,
  ) {
    final borderColor = isDarkMode ? AppColors.borderDark : AppColors.border;
    final shadowColor = isDarkMode ? AppColors.shadowDark : AppColors.shadow;

    final baseBgColor = isDarkMode ? AppColors.surfaceDark : Colors.white;
    final orangeOverlay = Colors.orangeAccent.withValues(alpha: 0.35);
    final cardBg = Color.alphaBlend(orangeOverlay, baseBgColor);

    final titleColor = isDarkMode
        ? AppColors.textDarkPrimary
        : AppColors.textPrimary;
    final subColor = isDarkMode
        ? AppColors.textDarkSecondary
        : AppColors.textSecondary;

    final updatedBy = update['updatedBy'] ?? 'BİRİ';
    final groupName = update['groupName'] ?? 'BİR GRUP';
    final oldTime = update['oldTime'] ?? '??:??';
    final newTime = update['newTime'] ?? '??:??';
    final alarmId = update['alarmId'] ?? '';

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          top: 6,
          left: 6,
          right: -6,
          bottom: -6,
          child: Container(
            decoration: BoxDecoration(
              color: shadowColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: borderColor, width: 3),
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderColor, width: 3),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.orangeAccent,
                      shape: BoxShape.circle,
                      border: Border.all(color: borderColor, width: 2),
                    ),
                    child: const Icon(
                      Icons.update_rounded,
                      color: AppColors.textPrimary,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'ALARM GÜNCELLENDİ!',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                            color: titleColor,
                            letterSpacing: 1.2,
                          ),
                        ),
                        Text(
                          '$updatedBy, $groupName alarmını değiştirdi',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: subColor,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Eski → Yeni saat gösterimi
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: isDarkMode
                      ? Colors.black26
                      : Colors.white.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: borderColor, width: 2),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      oldTime,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: subColor,
                        decoration: TextDecoration.lineThrough,
                        decorationColor: AppColors.error,
                        decorationThickness: 2.5,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Icon(
                        Icons.arrow_forward_rounded,
                        color: titleColor,
                        size: 20,
                      ),
                    ),
                    Text(
                      newTime,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: Colors.green.shade700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // Butonlar
              Row(
                children: [
                  // ONAYLA butonu
                  Expanded(
                    child: GestureDetector(
                      onTap: () async {
                        // Güncellemeyi onayla ve alarm detayına git
                        await AlarmSyncService.confirmUpdate(alarmId);
                        if (context.mounted) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) =>
                                  AlarmDetailScreen(alarmId: alarmId),
                            ),
                          );
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.green,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: borderColor, width: 2),
                          boxShadow: [
                            BoxShadow(
                              color: shadowColor,
                              offset: const Offset(3, 3),
                            ),
                          ],
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.check_rounded,
                              color: Colors.white,
                              size: 18,
                            ),
                            SizedBox(width: 4),
                            Text(
                              'ONAYLA',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                                letterSpacing: 1,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // REDDET butonu
                  Expanded(
                    child: GestureDetector(
                      onTap: () async {
                        // Güncellemeyi sadece kaldır (cihaz alarmını güncelleme)
                        final user = FirebaseAuth.instance.currentUser;
                        if (user != null) {
                          await FirebaseDatabase.instance
                              .ref()
                              .child('pendingUpdates')
                              .child(user.uid)
                              .child(alarmId)
                              .remove();
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: isDarkMode
                              ? AppColors.surfaceDark
                              : Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: borderColor, width: 2),
                          boxShadow: [
                            BoxShadow(
                              color: shadowColor,
                              offset: const Offset(3, 3),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.close_rounded,
                              color: titleColor,
                              size: 18,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'KAPAT',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w900,
                                color: titleColor,
                                letterSpacing: 1,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState(bool isDarkMode) {
    final titleColor = isDarkMode
        ? AppColors.textDarkPrimary
        : AppColors.textPrimary;
    final subTitleColor = isDarkMode
        ? AppColors.textDarkSecondary
        : AppColors.textSecondary;
    final borderColor = isDarkMode ? AppColors.borderDark : AppColors.border;
    final shadowColor = isDarkMode ? AppColors.shadowDark : AppColors.shadow;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: isDarkMode ? AppColors.surfaceDark : Colors.white,
                shape: BoxShape.circle,
                border: Border.all(color: borderColor, width: 3),
                boxShadow: [
                  BoxShadow(color: shadowColor, offset: const Offset(6, 6)),
                ],
              ),
              child: const Icon(
                Icons.alarm_add_rounded,
                size: 80,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 48),
            Text(
              'HİÇ ALARMIN YOK',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w900,
                color: titleColor,
                letterSpacing: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Text(
              'Güne başlamak ve ekibini\nuyandırmak için yeni bir alarm kur!',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: subTitleColor,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(
              height: 48,
            ), // Padding equivalent for bottom nav space
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title, bool isDarkMode) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w900,
        color: isDarkMode ? AppColors.textDarkPrimary : AppColors.textPrimary,
        letterSpacing: 1.5,
      ),
    );
  }

  Widget _buildAlarmCard({
    required BuildContext context,
    required String alarmId,
    required String time,
    required String ampm,
    required String groupName,
    required int membersAwake,
    required int totalMembers,
    required Color color,
    required bool isAdmin,
    required bool isActive,
    required bool isDarkMode,
    required bool isAnonymous,
    required List<int> days,
    required VoidCallback onToggle,
  }) {
    final shadowColor = isDarkMode ? AppColors.shadowDark : AppColors.shadow;
    final borderColor = isDarkMode ? AppColors.borderDark : AppColors.border;
    final titleColor = isDarkMode
        ? AppColors.textDarkPrimary
        : AppColors.textPrimary;
    final subTitleColor = isDarkMode
        ? AppColors.textDarkSecondary
        : AppColors.textSecondary;

    // In dark mode, an inactive card should be slightly darker than the surface
    final activeCardBg = isDarkMode ? AppColors.surfaceDark : Colors.white;
    final inactiveCardBg = isDarkMode
        ? const Color(0xFF111721)
        : const Color(0xFFE0E0E0);

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) =>
                AlarmDetailScreen(alarmId: alarmId, isAnonymous: _isAnonymous),
          ),
        ).then((_) {
          if (_isAnonymous) {
            _loadLocalAlarms();
          } else {
            //authenticated users too
            _setupDatabaseListeners();
          }
        });
      },
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Hard Shadow
          Positioned(
            top: 8,
            left: 8,
            right: -8,
            bottom: -8,
            child: Container(
              decoration: BoxDecoration(
                color: shadowColor,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: borderColor, width: 3),
              ),
            ),
          ),
          // Main Card
          Container(
            padding: const EdgeInsets.all(16), // Reduced from 24
            decoration: BoxDecoration(
              color: isActive ? activeCardBg : inactiveCardBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: borderColor, width: 3),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    ValueListenableBuilder<bool>(
                      valueListenable: timeFormatNotifier,
                      builder: (context, is24h, _) {
                        String displayTime = time;
                        String? displayAmPm = ampm;

                        if (is24h) {
                          final parts = time.split(':');
                          int h = int.parse(parts[0]);
                          if (ampm == 'PM' && h < 12) h += 12;
                          if (ampm == 'AM' && h == 12) h = 0;
                          displayTime =
                              '${h.toString().padLeft(2, '0')}:${parts[1]}';
                          displayAmPm = null;
                        }

                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              displayTime,
                              style: GoogleFonts.jersey10(
                                fontSize: 44, // Reduced from 64
                                fontWeight: FontWeight.w400,
                                color: titleColor,
                                height: 1.0,
                              ),
                            ),
                            if (displayAmPm != null) ...[
                              const SizedBox(width: 4),
                              Padding(
                                padding: const EdgeInsets.only(bottom: 6.0),
                                child: Text(
                                  displayAmPm,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w900,
                                    color: titleColor,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        );
                      },
                    ),
                    // Retro Toggle Button
                    GestureDetector(
                      onTap: onToggle,
                      child: Container(
                        width: 48, // Reduced from 56
                        height: 28, // Reduced from 32
                        decoration: BoxDecoration(
                          color: isActive
                              ? AppColors.primary
                              : (isDarkMode
                                    ? AppColors.surfaceDark
                                    : Colors.white),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: borderColor, width: 2),
                          boxShadow: [
                            BoxShadow(
                              color: shadowColor,
                              offset: const Offset(2, 2),
                            ),
                          ],
                        ),
                        alignment: isActive
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        padding: const EdgeInsets.all(2),
                        child: Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            color: isActive ? Colors.white : shadowColor,
                            shape: BoxShape.circle,
                            border: Border.all(color: borderColor, width: 2),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12), // Reduced from 20
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: borderColor, width: 2),
                        boxShadow: [
                          BoxShadow(
                            color: shadowColor,
                            offset: const Offset(1, 1),
                          ),
                        ],
                      ),
                      child: Text(
                        groupName,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                          color: AppColors.textPrimary,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                    if (!isAnonymous) ...[
                      const SizedBox(width: 12),
                      Icon(
                        Icons.people_alt_rounded,
                        size: 16,
                        color: subTitleColor,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '$membersAwake / $totalMembers',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          color: subTitleColor,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 12),
                // Days row
                // Days row or One-time label
                if (days.isEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    decoration: BoxDecoration(
                      color: isDarkMode
                          ? AppColors.primary.withOpacity(0.1)
                          : AppColors.primaryLight.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: AppColors.primary.withOpacity(0.5),
                        width: 2,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        'TEK SEFERLİK ALARM',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                          color: isDarkMode ? Colors.white : AppColors.primary,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ),
                  )
                else
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: List.generate(7, (index) {
                      final dayNamesArr = [
                        'Pt',
                        'Sa',
                        'Ça',
                        'Pe',
                        'Cu',
                        'Ct',
                        'Pz',
                      ];
                      final dayIndex = index + 1;
                      final isHighlighted = days.contains(dayIndex);

                      return Container(
                        width: 36, // Slightly wider for 2 letters
                        height: 28,
                        decoration: BoxDecoration(
                          color: isHighlighted
                              ? AppColors.primary.withOpacity(
                                  isDarkMode ? 0.3 : 0.1,
                                )
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: isHighlighted
                                ? AppColors.primary
                                : borderColor.withOpacity(0.3),
                            width: 2,
                          ),
                        ),
                        child: Center(
                          child: Text(
                            dayNamesArr[index],
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              color: isHighlighted
                                  ? (isDarkMode
                                        ? Colors.white
                                        : AppColors.primary)
                                  : titleColor.withOpacity(0.3),
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBrutalistFab(bool isDarkMode) {
    return _BrutalistFab(
      isDarkMode: isDarkMode,
      isAnonymous: _isAnonymous,
      onRefresh: () {
        if (_isAnonymous) _loadLocalAlarms();
      },
    );
  }
}

class _BrutalistFab extends StatefulWidget {
  final bool isDarkMode;
  final bool isAnonymous;
  final VoidCallback onRefresh;
  const _BrutalistFab({
    required this.isDarkMode,
    required this.isAnonymous,
    required this.onRefresh,
  });

  @override
  State<_BrutalistFab> createState() => _BrutalistFabState();
}

class _BrutalistFabState extends State<_BrutalistFab> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final shadowColor = widget.isDarkMode
        ? AppColors.shadowDark
        : AppColors.shadow;
    final borderColor = widget.isDarkMode
        ? AppColors.borderDark
        : AppColors.border;
    const double shadowOffset = 8.0;

    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) {
        setState(() => _isPressed = false);
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) =>
                CreateAlarmScreen(isAnonymous: widget.isAnonymous),
          ),
        ).then((_) => widget.onRefresh());
      },
      onTapCancel: () => setState(() => _isPressed = false),
      child: SizedBox(
        height: 64 + shadowOffset,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // Solid background shadow
            Positioned(
              top: shadowOffset,
              left: shadowOffset,
              right: 0,
              bottom: 0,
              child: Container(
                decoration: BoxDecoration(
                  color: shadowColor,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: borderColor, width: 3),
                ),
              ),
            ),
            // Animated foreground
            AnimatedPositioned(
              duration: const Duration(milliseconds: 100),
              curve: Curves.fastOutSlowIn,
              top: _isPressed ? shadowOffset : 0,
              left: _isPressed ? shadowOffset : 0,
              right: _isPressed ? 0 : shadowOffset,
              bottom: _isPressed ? 0 : shadowOffset,
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: borderColor, width: 3),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.add_box_rounded,
                      color: Colors.white,
                      size: 28,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'YENİ ALARM KUR',
                      style: GoogleFonts.jersey10(
                        fontSize: 32,
                        color: Colors.white,
                        letterSpacing: 2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeGridBackgroundPainter extends CustomPainter {
  final Color color;
  _HomeGridBackgroundPainter({required this.color});

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
