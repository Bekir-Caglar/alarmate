import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:alarm/alarm.dart';
import 'package:alarm/utils/alarm_set.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'firebase_options.dart';
import 'core/theme/app_theme.dart';
import 'core/services/alarm_sync_service.dart';
import 'core/services/notification_service.dart';
import 'presentation/screens/onboarding/onboarding_screen.dart';
import 'presentation/screens/auth/mode_selection_screen.dart';
import 'presentation/screens/home/home_screen.dart';
import 'presentation/screens/mission/mission_screen.dart';
import 'presentation/screens/alarm_detail/alarm_detail_screen.dart';

/// Global navigator key — tüm uygulamadan erişilebilir.
/// Alarm çaldığında hangi ekranda olursak olalım MissionScreen açmak için kullanılır.
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// Global ring stream subscription — uygulama yaşadığı sürece aktif kalır.
StreamSubscription<AlarmSet>? _globalRingSubscription;

/// Zaten MissionScreen açık mı kontrol flag'i — çift açılmayı önler.
bool _isMissionScreenOpen = false;

/// Native tarafta uygulamayı ön plana çıkarmak için method channel.
const _appRetainChannel = MethodChannel('com.bekircaglar.alarmate/app_retain');

/// FCM arka plan mesaj handler'ı — top-level function olmalı
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  debugPrint('[FCM-BG] Arka plan mesajı alındı: ${message.data}');

  // Arka planda notification service'i ilklendir
  await NotificationService.init();

  if (message.data['type'] == 'alarm_update') {
    // Arka planda alarm senkronizasyonu yap
    await AlarmSyncService.syncAlarmsWithDevice();

    // Bildirim göster
    final updatedBy = message.data['updatedBy'] ?? 'Biri';
    final groupName = message.data['groupName'] ?? 'Alarm';
    final newTime = message.data['newTime'] ?? '';

    await NotificationService.showNotification(
      id: message.hashCode,
      title: 'Alarm Güncellendi 🔔',
      body: '$updatedBy, "$groupName" alarmını $newTime olarak güncelledi.',
      payload: message.data['alarmId'],
    );
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  FirebaseDatabase.instance.setPersistenceEnabled(true);
  await Alarm.init();

  // FCM arka plan handler'ını kaydet
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // Yerel bildirimleri ilklendir
  await NotificationService.init();

  final prefs = await SharedPreferences.getInstance();
  final isDarkMode = prefs.getBool('isDarkMode') ?? false;

  runApp(AlarmateApp(initialDarkMode: isDarkMode));

  // App tamamen ayağa kalktıktan sonra global alarm listener'ı başlat
  _setupGlobalAlarmListener();

  // FCM kurulumu
  _setupFCM();

  // Uygulama terminated iken alarm çaldıysa ve full-screen intent ile açıldıysa
  // bu noktada zaten çalmakta olan bir alarm olabilir — kontrol et
  _checkForRingingAlarmOnStartup();
}

/// FCM kurulumu: izin iste, token kaydet, foreground mesajları dinle
void _setupFCM() async {
  final messaging = FirebaseMessaging.instance;

  // Bildirim izni iste
  await messaging.requestPermission(alert: true, badge: true, sound: true);

  // FCM token'ını al ve Firebase'e kaydet
  await _saveFCMToken();

  // Token yenilendiğinde tekrar kaydet
  messaging.onTokenRefresh.listen((newToken) {
    _saveFCMTokenWithValue(newToken);
  });

  // Uygulama ön plandayken gelen mesajları dinle
  FirebaseMessaging.onMessage.listen((RemoteMessage message) {
    debugPrint('[FCM-FG] Ön plan mesajı: ${message.data}');
    if (message.data['type'] == 'alarm_update') {
      // Cihaz alarmlarını güncelle
      AlarmSyncService.syncAlarmsWithDevice();

      // Bildirim göster
      final updatedBy = message.data['updatedBy'] ?? 'Biri';
      final groupName = message.data['groupName'] ?? 'Alarm';
      final newTime = message.data['newTime'] ?? '';

      NotificationService.showNotification(
        id: message.hashCode,
        title: 'Alarm Güncellendi 🔔',
        body: '$updatedBy, "$groupName" alarmını $newTime olarak güncelledi.',
        payload: message.data['alarmId'],
      );
    }
  });

  // Kullanıcı bildirime tıkladığında (uygulama arka plandayken)
  FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
    debugPrint('[FCM-TAP] Bildirime tıklandı: ${message.data}');
    if (message.data['type'] == 'alarm_update') {
      final alarmId = message.data['alarmId'];
      if (alarmId != null) {
        // Sadece navigasyon yap, otomatik onaylama
        navigatorKey.currentState?.push(
          MaterialPageRoute(
            builder: (context) => AlarmDetailScreen(alarmId: alarmId),
          ),
        );
      }
    }
  });

  // Uygulama terminate iken bildirime tıklanarak açılmışsa
  final initialMessage = await messaging.getInitialMessage();
  if (initialMessage != null && initialMessage.data['type'] == 'alarm_update') {
    final alarmId = initialMessage.data['alarmId'];
    if (alarmId != null) {
      // Navigator hazır olana kadar bekle
      await Future.delayed(const Duration(milliseconds: 2500));
      navigatorKey.currentState?.push(
        MaterialPageRoute(
          builder: (context) => AlarmDetailScreen(alarmId: alarmId),
        ),
      );
    }
  }
}

/// FCM token'ını alıp Firebase'e kaydeder
Future<void> _saveFCMToken() async {
  try {
    final token = await FirebaseMessaging.instance.getToken();
    if (token != null) {
      await _saveFCMTokenWithValue(token);
    }
  } catch (e) {
    debugPrint('[FCM] Token alınamadı: $e');
  }
}

/// Verilen token'ı Firebase'e kaydeder
Future<void> _saveFCMTokenWithValue(String token) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null || user.isAnonymous) return;
  try {
    await FirebaseDatabase.instance
        .ref()
        .child('users')
        .child(user.uid)
        .child('fcmToken')
        .set(token);
    debugPrint('[FCM] Token kaydedildi');
  } catch (e) {
    debugPrint('[FCM] Token kaydedilemedi: $e');
  }
}

/// Global ringing listener — HomeScreen'e bağımlı değil.
/// Uygulama hangi ekranda olursa olsun alarm çaldığında MissionScreen açar.
void _setupGlobalAlarmListener() {
  _globalRingSubscription?.cancel();
  _globalRingSubscription = Alarm.ringing.listen((alarmSet) async {
    // AlarmSet içindeki ilk çalan alarmı al
    if (alarmSet.alarms.isEmpty) return;
    final ringingAlarm = alarmSet.alarms.first;
    debugPrint(
      '[GLOBAL] Alarm ringing: ${ringingAlarm.id} — navigating to mission',
    );
    await _navigateToMissionScreen(ringingAlarm.id);
  });
}

/// Uygulama başlarken zaten çalmakta olan bir alarm var mı kontrol eder.
/// Bu, telefon kapalı/terminated iken alarm çalıp full-screen intent ile
/// uygulamanın açılması durumunu yakalar.
void _checkForRingingAlarmOnStartup() async {
  // Navigator hazır olana kadar kısa bir bekleme
  await Future.delayed(const Duration(milliseconds: 1500));

  try {
    final alarms = await Alarm.getAlarms();
    for (final alarm in alarms) {
      final isRinging = await Alarm.isRinging(alarm.id);
      if (isRinging) {
        debugPrint(
          '[STARTUP] Found ringing alarm: ${alarm.id} — navigating to mission',
        );
        await _navigateToMissionScreen(alarm.id);
        return; // Sadece ilk çalan alarmı yakala
      }
    }
  } catch (e) {
    debugPrint('[STARTUP] Error checking ringing alarms: $e');
  }
}

/// Merkezi navigasyon fonksiyonu — alarm çaldığında MissionScreen açar.
/// Global navigator key kullanır, hiçbir widget context'ine bağımlı değildir.
Future<void> _navigateToMissionScreen(int alarmId) async {
  // Zaten MissionScreen açıksa tekrar açma
  if (_isMissionScreenOpen) {
    debugPrint('[NAV] MissionScreen already open, skipping');
    return;
  }

  // Android'de uygulamayı ön plana çıkar (kilit ekranı üzerinde göster)
  if (Platform.isAndroid) {
    try {
      await _appRetainChannel.invokeMethod('bringToFront');
      debugPrint('[NAV] bringToFront called successfully');
    } catch (e) {
      debugPrint('[NAV] bringToFront error: $e');
    }
  }

  // SharedPreferences'tan görev bilgilerini oku
  final prefs = await SharedPreferences.getInstance();
  final missionType =
      prefs.getString('alarm_${alarmId}_mission') ?? 'MATEMATİK SINAVI';
  final difficulty = prefs.getString('alarm_${alarmId}_difficulty') ?? 'ORTA';

  final navigator = navigatorKey.currentState;
  if (navigator == null) {
    debugPrint('[NAV] Navigator not ready yet');
    return;
  }

  _isMissionScreenOpen = true;

  await navigator.push(
    MaterialPageRoute(
      builder: (context) =>
          MissionScreen(missionType: missionType, difficulty: difficulty),
    ),
  );

  // MissionScreen kapandı — alarm'ı durdur ve sonraki günü planla
  _isMissionScreenOpen = false;
  await Alarm.stop(alarmId);

  // Tekrar eden alarmlar için bir sonraki günü planla
  try {
    await AlarmSyncService.syncAlarmsWithDevice();
  } catch (e) {
    debugPrint('[NAV] Error syncing alarms after mission: $e');
  }
}

final themeNotifier = ValueNotifier<ThemeMode>(ThemeMode.light);
final timeFormatNotifier = ValueNotifier<bool>(true); // true = 24h, false = 12h

class AlarmateApp extends StatefulWidget {
  final bool initialDarkMode;
  const AlarmateApp({super.key, required this.initialDarkMode});

  @override
  State<AlarmateApp> createState() => _AlarmateAppState();
}

class _AlarmateAppState extends State<AlarmateApp> {
  void _onThemeChanged() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isDarkMode', themeNotifier.value == ThemeMode.dark);
  }

  void _onTimeFormatChanged() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('use24HourFormat', timeFormatNotifier.value);
  }

  @override
  void initState() {
    super.initState();
    themeNotifier.value = widget.initialDarkMode
        ? ThemeMode.dark
        : ThemeMode.light;

    // Load initial time format from prefs or locale
    _loadInitialTimeFormat();

    // Listen for changes and save to prefs
    themeNotifier.addListener(_onThemeChanged);
    timeFormatNotifier.addListener(_onTimeFormatChanged);
  }

  Future<void> _loadInitialTimeFormat() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.containsKey('use24HourFormat')) {
      timeFormatNotifier.value = prefs.getBool('use24HourFormat')!;
    }
  }

  @override
  void dispose() {
    themeNotifier.removeListener(_onThemeChanged);
    timeFormatNotifier.removeListener(_onTimeFormatChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (context, currentMode, _) {
        return MaterialApp(
          navigatorKey: navigatorKey, // ← Global navigator key
          title: 'Alarmate',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: currentMode,
          home: const AuthWrapper(),
        );
      },
    );
  }
}

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  bool _isLoading = true;
  bool _hasSeenOnboarding = false;
  bool _isOfflineGuest = false;

  @override
  void initState() {
    super.initState();
    _checkOnboarding();
  }

  Future<void> _checkOnboarding() async {
    final prefs = await SharedPreferences.getInstance();

    // Set default time format from system if not already saved
    if (!prefs.containsKey('use24HourFormat')) {
      if (mounted) {
        timeFormatNotifier.value = MediaQuery.of(context).alwaysUse24HourFormat;
      }
    }

    final hasSeenOnboarding = prefs.getBool('has_seen_onboarding') ?? false;
    final isOfflineGuest = prefs.getBool('isOfflineGuest') ?? false;

    // Profili tamamlanmamış kullanıcıları temizle
    final user = FirebaseAuth.instance.currentUser;
    if (user != null && !user.isAnonymous) {
      // Arka planda kontrol et, UI'ı (Splash Screen) bloklama
      Future.microtask(() async {
        try {
          final snapshot = await FirebaseDatabase.instance
              .ref()
              .child('users')
              .child(user.uid)
              .child('username')
              .get()
              .timeout(const Duration(seconds: 2));
          if (!snapshot.exists) {
            // Auth olmuş ama profil oluşturmamış → çıkış yap
            await FirebaseAuth.instance.signOut();
          }
        } catch (e) {
          debugPrint('Kullanıcı kontrolü zaman aşımına uğradı veya hata: $e');
        }
      });
    }

    if (!mounted) return;
    setState(() {
      _hasSeenOnboarding = hasSeenOnboarding;
      _isOfflineGuest = isOfflineGuest;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasData && snapshot.data != null) {
          return const HomeScreen();
        }

        if (_isOfflineGuest) {
          return const HomeScreen();
        }

        if (_hasSeenOnboarding) {
          return const ModeSelectionScreen();
        }

        return const OnboardingScreen();
      },
    );
  }
}
