import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_database/firebase_database.dart';
import 'dart:async';
import '../../../core/services/alarm_sync_service.dart';
import '../../../core/services/local_alarm_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../components/primary_button.dart';
import '../../components/brutalist_icon_button.dart';
import '../../components/retro_mission_picker.dart';
import '../../../data/repositories/data_repository.dart';
import '../../../core/database/local_db.dart';
import '../../../main.dart';

class AlarmDetailScreen extends StatefulWidget {
  final String alarmId;
  final bool isAnonymous;

  const AlarmDetailScreen({
    super.key,
    required this.alarmId,
    this.isAnonymous = false,
  });

  @override
  State<AlarmDetailScreen> createState() => _AlarmDetailScreenState();
}

class _AlarmDetailScreenState extends State<AlarmDetailScreen> {
  String _currentTime = '00:00';
  String _currentAmPm = 'AM';
  String _currentMission = 'YÜKLENİYOR...';
  String _currentDifficulty = '...';
  String _groupName = 'YÜKLENİYOR...';
  Color _groupColor = AppColors.primaryLight;
  bool _isAdmin = false;
  bool _isLoading = true;
  bool _isModified = false;
  late bool _isAnonymous;
  String? _activeUid;

  List<Map<String, dynamic>> _members = [];
  StreamSubscription<List<Map<String, dynamic>>>? _alarmSub;
  StreamSubscription? _pendingSub;
  bool _hasPendingUpdate = false;
  Map<String, dynamic>? _pendingUpdateData;
  List<int> _selectedDays = [];

  final List<String> _dayNames = [
    'PZT',
    'SAL',
    'ÇAR',
    'PER',
    'CUM',
    'CMT',
    'PAZ',
  ];

  FixedExtentScrollController? _hourController;
  FixedExtentScrollController? _minuteController;
  FixedExtentScrollController? _amPmController;
  Timer? _debounceTimer;
  final TextEditingController _memberPhoneController = TextEditingController();
  bool _isSearchingMember = false;

  @override
  void initState() {
    super.initState();
    _isAnonymous = widget.isAnonymous;
    _initActiveUid();
    _setupAlarmListener();
    _setupPendingUpdateListener();
  }

  Future<void> _initActiveUid() async {
    final uid = await LocalDb.instance.getActiveUid();
    if (mounted) {
      setState(() {
        _activeUid = uid;
      });
    }
  }

  void _setupAlarmListener() async {
    final currentUid = await LocalDb.instance.getActiveUid();
    // if (currentUid == null) return; // Local UID is always present now

    _alarmSub = DataRepository.instance.alarmsStream.listen((alarms) async {
      // Bulamazsa null döner
      final data = alarms.where((e) => e['id'] == widget.alarmId).firstOrNull;

      if (data != null) {
        // Üyeleri çek
        final membersMap = Map<String, dynamic>.from(data['members'] ?? {});
        final membersAwakeList = (data['membersAwake'] as List?) ?? [];

        List<Map<String, dynamic>> memberInfoList = [];

        // Kabul edenleri ekle
        for (var uid in membersMap.keys) {
          String username = uid == currentUid ? 'SEN' : 'OYUNCU';

          if (uid != currentUid) {
            final userData = await DataRepository.instance.getUserOnce(uid);
            if (userData != null && userData['username'] != null) {
              username = userData['username'];
            }
          }

          memberInfoList.add({
            'uid': uid,
            'username': username,
            'isAwake': membersAwakeList.contains(uid),
            'isMe': uid == currentUid,
            'status': 'JOINED',
          });
        }

        // Davet edilenleri ekle (henüz kabul etmeyenler)
        if (data['invitedMembers'] != null) {
          final invitedMap = Map<String, dynamic>.from(
            data['invitedMembers'] as Map,
          );
          for (var entry in invitedMap.entries) {
            memberInfoList.add({
              'uid': entry.key,
              'username': entry.value.toString(),
              'isAwake': false,
              'isMe': false,
              'status': 'PENDING',
            });
          }
        }

        if (mounted) {
          setState(() {
            _currentTime = data['time'] ?? '00:00';
            _currentAmPm = data['ampm'] ?? 'AM';
            _currentMission = data['mission'] ?? 'BİLİNMİYOR';
            _currentDifficulty = data['difficulty'] ?? 'ORTA';
            _groupName = data['groupName'] ?? 'BİR GRUP';
            _groupColor = data['color'] != null
                ? Color(int.parse(data['color'].toString()))
                : AppColors.primaryLight;
            _isAdmin =
                data['creatorId'] == currentUid ||
                widget.alarmId.startsWith('local_');
            _members = memberInfoList;
            _selectedDays = List<int>.from(data['days'] ?? []);
            _isLoading = false;

            if (_isAdmin) {
              _initWheelControllers();
            }
          });
        }
      } else {
        if (mounted && !_isLoading && Navigator.canPop(context)) {
          // if initially missing, it might just need sync, but we let it be
          // If we previously loaded but now missing, it got deleted
          Navigator.of(context).pop();
        } else if (mounted) {
          // Not loaded yet, but if no alarms at all it might just be the first tick of the stream, do nothing yet
        }
      }
    });
  }

  @override
  void dispose() {
    _alarmSub?.cancel();
    _pendingSub?.cancel();
    _debounceTimer?.cancel();
    _hourController?.dispose();
    _minuteController?.dispose();
    _amPmController?.dispose();
    _memberPhoneController.dispose();
    super.dispose();
  }

  void _setupPendingUpdateListener() async {
    final currentUid = await LocalDb.instance.getActiveUid();
    if (widget.alarmId.startsWith('local_')) return;

    final db = FirebaseDatabase.instance.ref();
    _pendingSub = db
        .child('pendingUpdates')
        .child(currentUid)
        .child(widget.alarmId)
        .onValue
        .listen((event) {
          if (event.snapshot.exists && event.snapshot.value is Map) {
            if (mounted) {
              setState(() {
                _hasPendingUpdate = true;
                _pendingUpdateData = Map<String, dynamic>.from(
                  event.snapshot.value as Map,
                );
              });
            }
          } else {
            if (mounted) {
              setState(() {
                _hasPendingUpdate = false;
                _pendingUpdateData = null;
              });
            }
          }
        });
  }

  void _initWheelControllers() {
    if (_hourController != null) return;

    final parts = _currentTime.split(':');
    int hour = int.tryParse(parts[0]) ?? 7;
    int minute = int.tryParse(parts.length > 1 ? parts[1] : '30') ?? 30;

    final is24h = timeFormatNotifier.value;

    if (is24h) {
      // Convert to 24h if it was 12h
      if (_currentAmPm == 'PM' && hour < 12) hour += 12;
      if (_currentAmPm == 'AM' && hour == 12) hour = 0;
      _hourController = FixedExtentScrollController(initialItem: hour);
    } else {
      // Convert to 12h if it was 24h
      bool isPm = hour >= 12;
      int displayHour = hour % 12;
      if (displayHour == 0) displayHour = 12;
      _hourController = FixedExtentScrollController(
        initialItem: displayHour - 1,
      );
      _amPmController = FixedExtentScrollController(initialItem: isPm ? 1 : 0);
    }
    _minuteController = FixedExtentScrollController(initialItem: minute);
  }

  Future<void> _updateAlarmData() async {
    if (widget.alarmId.startsWith('local_')) {
      await LocalAlarmService.updateAlarm(widget.alarmId, {
        'time': _currentTime,
        'ampm': _currentAmPm,
        'mission': _currentMission,
        'difficulty': _currentDifficulty,
        'days': _selectedDays,
      });

      // Sync with hardware alarm package
      await AlarmSyncService.syncAlarmsWithDevice();
      return;
    }

    // Eski değerleri sakla (değişiklik kontrolü için)
    final db = FirebaseDatabase.instance.ref();
    DataSnapshot? oldSnap;
    try {
      oldSnap = await db
          .child('alarms')
          .child(widget.alarmId)
          .get()
          .timeout(const Duration(seconds: 2));
    } catch (e) {
      debugPrint('Old alarm fetch timeout: $e');
    }

    bool hasFunctionalChange = false;
    String oldTimeFormatted = '';

    if (oldSnap != null && oldSnap.exists && oldSnap.value is Map) {
      final oldData = Map<String, dynamic>.from(oldSnap.value as Map);

      // Zaman kontrolü
      if (oldData['time'] != _currentTime || oldData['ampm'] != _currentAmPm) {
        hasFunctionalChange = true;
      }
      // Görev kontrolü
      if (oldData['mission'] != _currentMission ||
          oldData['difficulty'] != _currentDifficulty) {
        hasFunctionalChange = true;
      }
      // Günler kontrolü
      final oldDays = List<int>.from(oldData['days'] ?? []);
      if (oldDays.length != _selectedDays.length ||
          !oldDays.every((day) => _selectedDays.contains(day))) {
        hasFunctionalChange = true;
      }

      oldTimeFormatted = '${oldData['time'] ?? ''} ${oldData['ampm'] ?? ''}';
    } else {
      // Eğer eski data yoksa (yeni oda vs) her türlü true
      hasFunctionalChange = true;
    }

    await db.child('alarms').child(widget.alarmId).update({
      'time': _currentTime,
      'ampm': _currentAmPm,
      'mission': _currentMission,
      'difficulty': _currentDifficulty,
      'days': _selectedDays,
    });

    // Diğer grup üyelerine sadece değişiklik varsa bildirim gönder
    final currentUid = await LocalDb.instance.getActiveUid();
    if (_isAdmin &&
        hasFunctionalChange &&
        !widget.alarmId.startsWith('local_')) {
      // Güncelleme yapan kişinin adını al
      String updaterName = 'BİR ARKADAŞIN';
      try {
        final userData = await DataRepository.instance.getUserOnce(currentUid);
        if (userData != null && userData['username'] != null) {
          updaterName = userData['username'];
        }
      } catch (_) {}

      final newTime = '$_currentTime $_currentAmPm';

      for (var member in _members) {
        final memberUid = member['uid'] as String;
        // Kendine bildirim gönderme
        if (memberUid == currentUid) continue;
        // Sadece JOINED olan üyelere gönder
        if (member['status'] != 'JOINED') continue;

        await db
            .child('pendingUpdates')
            .child(memberUid)
            .child(widget.alarmId)
            .set({
              'updatedBy': updaterName,
              'groupName': _groupName,
              'oldTime': oldTimeFormatted,
              'newTime': newTime,
              'mission': _currentMission,
              'difficulty': _currentDifficulty,
              'timestamp': ServerValue.timestamp,
            });
      }
    }

    // Sync with hardware alarm package
    await AlarmSyncService.syncAlarmsWithDevice();
  }

  Future<void> _closeRoom() async {
    // Önce bottom sheet'i kapat
    if (Navigator.canPop(context)) {
      Navigator.of(context).pop();
    }

    if (widget.alarmId.startsWith('local_')) {
      await LocalAlarmService.deleteAlarm(widget.alarmId);
      // Listener will handle popping the DetailScreen
      return;
    }
    final db = FirebaseDatabase.instance.ref();
    // 1. Önce üyelerin membership'lerini temizle
    for (var member in _members) {
      await db
          .child('memberships')
          .child(member['uid'])
          .child(widget.alarmId)
          .remove();
    }
    // 2. Alarma ait davetleri temizle (opsiyonel ama iyi olur)
    // 3. Alarmı sil - Bu işlem _alarmSub listener'ını tetikleyecektir
    await db.child('alarms').child(widget.alarmId).remove();
    // Listener zaten pop yapacağı için burada tekrar yapmıyoruz (Remote için)
  }

  Future<void> _leaveGroup() async {
    final uid = await LocalDb.instance.getActiveUid();
    // if (user == null) return;

    if (!widget.alarmId.startsWith('local_')) {
      final db = FirebaseDatabase.instance.ref();
      await db
          .child('alarms')
          .child(widget.alarmId)
          .child('members')
          .child(uid)
          .remove();
      await db.child('memberships').child(uid).child(widget.alarmId).remove();
    }

    // Listener will handle popping the screen when membership is removed
  }

  Future<void> _removeMember(String memberUid, String username) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        final isDarkMode = Theme.of(context).brightness == Brightness.dark;
        final titleColor = isDarkMode
            ? AppColors.textDarkPrimary
            : AppColors.textPrimary;
        final bgColor = isDarkMode ? AppColors.surfaceDark : Colors.white;
        final borderColor = isDarkMode
            ? AppColors.borderDark
            : AppColors.border;
        final shadowColor = isDarkMode
            ? AppColors.shadowDark
            : AppColors.shadow;

        return Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: borderColor, width: 3),
              boxShadow: [
                BoxShadow(color: shadowColor, offset: const Offset(6, 6)),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.person_remove_rounded,
                  color: AppColors.error,
                  size: 48,
                ),
                const SizedBox(height: 16),
                Text(
                  'Üyeyi Çıkar',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: titleColor,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  '$username isimli kullanıcıyı gruptan çıkarmak istediğine emin misin?',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: titleColor.withOpacity(0.7),
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => Navigator.pop(context, false),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: Colors.grey.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: borderColor, width: 2),
                          ),
                          child: Center(
                            child: Text(
                              'Vazgeç',
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                color: titleColor,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => Navigator.pop(context, true),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: AppColors.error,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: borderColor, width: 2),
                          ),
                          child: const Center(
                            child: Text(
                              'Çıkar',
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );

    if (confirm != true) return;

    try {
      final db = FirebaseDatabase.instance.ref();
      // Remove from members
      await db
          .child('alarms')
          .child(widget.alarmId)
          .child('members')
          .child(memberUid)
          .remove();
      // Remove from invitedMembers
      await db
          .child('alarms')
          .child(widget.alarmId)
          .child('invitedMembers')
          .child(memberUid)
          .remove();
      // Remove membership record
      await db
          .child('memberships')
          .child(memberUid)
          .child(widget.alarmId)
          .remove();
      // Remove invitation record
      await db
          .child('invitations')
          .child(memberUid)
          .child(widget.alarmId)
          .remove();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$username gruptan çıkarıldı.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('İşlem sırasında bir hata oluştu.'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _searchUserByPhone(StateSetter setModalState) async {
    String phone = _memberPhoneController.text.trim().replaceAll(
      RegExp(r'\s+'),
      '',
    );
    if (phone.isEmpty) return;

    String searchPhone = phone.startsWith('+') ? phone : '+90$phone';

    setModalState(() => _isSearchingMember = true);

    try {
      final db = FirebaseDatabase.instance.ref();
      final snapshot = await db
          .child('users')
          .orderByChild('phone')
          .equalTo(searchPhone)
          .once();

      if (snapshot.snapshot.exists) {
        final userData = (snapshot.snapshot.value as Map).entries.first;
        final invitedUid = userData.key;
        final info = Map<String, dynamic>.from(userData.value as Map);
        final username = info['username'] ?? 'BİLİNMEYEN';

        // Check if already a member or already invited
        bool alreadyIn = _members.any((m) => m['uid'] == invitedUid);

        if (alreadyIn) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('BU KULLANICI ZATEN GRUPTA VEYA DAVET EDİLMİŞ!'),
              ),
            );
          }
        } else {
          // Send Invitation
          String inviterName = 'BİR ARKADAŞIN';
          final currentUserData = await DataRepository.instance.getUserOnce(
            _activeUid!,
          );
          if (currentUserData != null && currentUserData['username'] != null) {
            inviterName = currentUserData['username'];
          }

          final inviteData = {
            'groupName': _groupName,
            'inviterName': inviterName,
            'time': _currentTime,
            'ampm': _currentAmPm,
            'mission': _currentMission,
            'difficulty': _currentDifficulty,
            'days': _selectedDays,
            'timestamp': ServerValue.timestamp,
          };

          // 1. Send invite to user's invitations node
          await db
              .child('invitations')
              .child(invitedUid)
              .child(widget.alarmId)
              .set(inviteData);

          // 2. Add to alarm's invitedMembers list
          await db
              .child('alarms')
              .child(widget.alarmId)
              .child('invitedMembers')
              .child(invitedUid)
              .set(username);

          _memberPhoneController.clear();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('DAVET GÖNDERİLDİ!'),
                backgroundColor: Colors.green,
              ),
            );
            Navigator.pop(
              context,
            ); // Close bottom sheet after successful invite
          }
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('KULLANICI BULUNAMADI!')),
          );
        }
      }
    } finally {
      if (mounted) setModalState(() => _isSearchingMember = false);
    }
  }

  Future<bool> _showExitConfirmation() async {
    if (!_isModified) return true;

    final bool? result = await showDialog<bool>(
      context: context,
      builder: (context) {
        final isDarkMode = Theme.of(context).brightness == Brightness.dark;
        final titleColor = isDarkMode
            ? AppColors.textDarkPrimary
            : AppColors.textPrimary;
        final bgColor = isDarkMode ? AppColors.surfaceDark : Colors.white;
        final borderColor = isDarkMode
            ? AppColors.borderDark
            : AppColors.border;
        final shadowColor = isDarkMode
            ? AppColors.shadowDark
            : AppColors.shadow;

        return Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: borderColor, width: 3),
              boxShadow: [
                BoxShadow(color: shadowColor, offset: const Offset(6, 6)),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.warning_amber_rounded,
                  color: Colors.orange,
                  size: 48,
                ),
                const SizedBox(height: 16),
                Text(
                  'Değişiklikleri Kaydetme',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: titleColor,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Yaptığın değişiklikler kaydedilmedi. Çıkmak istediğine emin misin?',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: titleColor.withOpacity(0.7),
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => Navigator.pop(context, false),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: Colors.grey.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: borderColor, width: 2),
                          ),
                          child: Center(
                            child: Text(
                              'Vazgeç',
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                color: titleColor,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => Navigator.pop(context, true),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: AppColors.error,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: borderColor, width: 2),
                          ),
                          child: const Center(
                            child: Text(
                              'Çık',
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final statusBarColor = isDarkMode ? AppColors.surfaceDark : Colors.white;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final shouldPop = await _showExitConfirmation();
        if (shouldPop && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Stack(
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _DetailGridBackgroundPainter(
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
                        _buildAppBar(context, isDarkMode),
                        Expanded(
                          child: ListView(
                            padding: const EdgeInsets.all(24),
                            children: [
                              if (_hasPendingUpdate && !_isAdmin) ...[
                                _buildPendingUpdateBanner(isDarkMode),
                                const SizedBox(height: 24),
                              ],
                              _buildTimeHeader(context, isDarkMode),
                              const SizedBox(height: 32),
                              _buildMissionSection(isDarkMode),
                              const SizedBox(height: 32),
                              _buildDaysSection(isDarkMode),
                              if (!_isAnonymous) ...[
                                const SizedBox(height: 32),
                                _buildTeamSection(isDarkMode),
                              ],
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(24.0),
                          child: _buildLeaveButton(context, isDarkMode),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildAppBar(BuildContext context, bool isDarkMode) {
    final bgColor = isDarkMode ? AppColors.surfaceDark : Colors.white;
    final shadowColor = isDarkMode ? AppColors.shadowDark : AppColors.shadow;
    final borderColor = isDarkMode ? AppColors.borderDark : AppColors.border;

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
            onTap: () => Navigator.maybePop(context),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: _groupColor,
              border: Border.all(color: borderColor, width: 3),
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(color: shadowColor, offset: const Offset(2, 2)),
              ],
            ),
            child: Text(
              _groupName,
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                color: AppColors.textPrimary,
                letterSpacing: 1.5,
              ),
            ),
          ),
          if (_isModified)
            BrutalistIconButton(
              icon: Icons.check_rounded,
              onTap: () async {
                await _updateAlarmData();
                setState(() {
                  _isModified = false;
                });
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Değişiklikler kaydedildi!'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              },
            )
          else if (_isAdmin)
            BrutalistIconButton(
              icon: Icons.settings,
              onTap: () {
                _showSettingsBottomSheet(context, isDarkMode);
              },
            )
          else
            const SizedBox(width: 44),
        ],
      ),
    );
  }

  void _showSettingsBottomSheet(BuildContext context, bool isDarkMode) {
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
                    color: shadowColor.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Oda Ayarları',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    color: titleColor,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 24),
                if (_isAdmin) ...[
                  _buildBottomSheetButton(
                    title: 'Odayı Kapat',
                    icon: Icons.close_rounded,
                    color: AppColors.error,
                    textColor: Colors.white,
                    onTap: () {
                      _closeRoom();
                    },
                    isDarkMode: isDarkMode,
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildBottomSheetButton({
    required String title,
    required IconData icon,
    required Color color,
    Color textColor = AppColors.textPrimary,
    required VoidCallback onTap,
    required bool isDarkMode,
  }) {
    final shadowColor = isDarkMode ? AppColors.shadowDark : AppColors.shadow;
    final borderColor = isDarkMode ? AppColors.borderDark : AppColors.border;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 56,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor, width: 3),
          boxShadow: [
            BoxShadow(color: shadowColor, offset: const Offset(4, 4)),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: textColor),
            const SizedBox(width: 8),
            Text(
              title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: textColor,
                letterSpacing: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimeHeader(BuildContext context, bool isDarkMode) {
    return ValueListenableBuilder<bool>(
      valueListenable: timeFormatNotifier,
      builder: (context, is24h, _) {
        if (_isAdmin && _hourController != null) {
          return _buildWheelTimePicker(isDarkMode, is24h);
        }

        final titleColor = isDarkMode
            ? AppColors.textDarkPrimary
            : AppColors.textPrimary;

        String displayTime = _currentTime;
        String? displayAmPm = _currentAmPm;

        if (is24h) {
          final parts = _currentTime.split(':');
          int h = int.parse(parts[0]);
          if (_currentAmPm == 'PM' && h < 12) h += 12;
          if (_currentAmPm == 'AM' && h == 12) h = 0;
          displayTime = '${h.toString().padLeft(2, '0')}:${parts[1]}';
          displayAmPm = null;
        }

        return Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                displayTime,
                style: GoogleFonts.jersey10(
                  fontSize: 100,
                  fontWeight: FontWeight.w400,
                  color: titleColor,
                  height: 1.0,
                ),
              ),
              if (displayAmPm != null) ...[
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(bottom: 16.0),
                  child: Text(
                    displayAmPm,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      color: titleColor,
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildWheelTimePicker(bool isDarkMode, bool is24h) {
    final wheelItemColor = isDarkMode
        ? AppColors.textDarkPrimary
        : AppColors.textPrimary;
    final borderColor = isDarkMode ? AppColors.borderDark : AppColors.border;

    return Center(
      child: Container(
        height: 150,
        constraints: const BoxConstraints(maxWidth: 300),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              height: 50,
              decoration: BoxDecoration(
                color: AppColors.primaryLight.withValues(alpha: 0.15),
                border: Border.symmetric(
                  horizontal: BorderSide(color: borderColor, width: 2),
                ),
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: _buildWheel(
                    controller: _hourController!,
                    itemCount: is24h ? 24 : 12,
                    onSelectedItemChanged: (_) => _onWheelChanged(is24h),
                    itemBuilder: (context, index) {
                      final val = is24h ? index : (index + 1);
                      return _buildWheelItem(
                        val.toString().padLeft(2, '0'),
                        wheelItemColor,
                      );
                    },
                  ),
                ),
                Text(
                  ':',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w900,
                    color: wheelItemColor,
                  ),
                ),
                Expanded(
                  child: _buildWheel(
                    controller: _minuteController!,
                    itemCount: 60,
                    onSelectedItemChanged: (_) => _onWheelChanged(is24h),
                    itemBuilder: (context, index) {
                      return _buildWheelItem(
                        index.toString().padLeft(2, '0'),
                        wheelItemColor,
                      );
                    },
                  ),
                ),
                if (!is24h) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildWheel(
                      controller: _amPmController!,
                      itemCount: 2,
                      onSelectedItemChanged: (_) => _onWheelChanged(is24h),
                      itemBuilder: (context, index) {
                        final options = ['AM', 'PM'];
                        return _buildWheelItem(
                          options[index],
                          wheelItemColor,
                          isSmall: true,
                        );
                      },
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _onWheelChanged(bool is24h) {
    int hour;
    int minute = _minuteController?.selectedItem ?? 0;
    String amPm;

    if (is24h) {
      hour = _hourController?.selectedItem ?? 0;
      // Convert to 12h for internal DB storage (we store 12h + AM/PM)
      bool isPm = hour >= 12;
      amPm = isPm ? 'PM' : 'AM';
      hour = hour % 12;
      if (hour == 0) hour = 12;
    } else {
      hour = (_hourController?.selectedItem ?? 0) + 1;
      int amPmIndex = _amPmController?.selectedItem ?? 0;
      amPm = amPmIndex == 0 ? 'AM' : 'PM';
    }

    setState(() {
      _currentTime =
          '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
      _currentAmPm = amPm;
      _isModified = true;
    });
  }

  Widget _buildWheel({
    required FixedExtentScrollController controller,
    required int itemCount,
    required Function(int) onSelectedItemChanged,
    required Widget Function(BuildContext, int) itemBuilder,
  }) {
    return ListWheelScrollView.useDelegate(
      controller: controller,
      itemExtent: 50,
      physics: const FixedExtentScrollPhysics(),
      overAndUnderCenterOpacity: 0.3,
      onSelectedItemChanged: onSelectedItemChanged,
      childDelegate: ListWheelChildBuilderDelegate(
        builder: itemBuilder,
        childCount: itemCount,
      ),
    );
  }

  Widget _buildWheelItem(String text, Color color, {bool isSmall = false}) {
    return Center(
      child: Text(
        text,
        style: GoogleFonts.jersey10(
          fontSize: isSmall ? 32 : 44,
          fontWeight: FontWeight.w400,
          color: color,
          height: 1.0,
        ),
      ),
    );
  }

  Widget _buildDaysSection(bool isDarkMode) {
    final titleColor = isDarkMode
        ? AppColors.textDarkPrimary
        : AppColors.textPrimary;
    final borderColor = isDarkMode ? AppColors.borderDark : AppColors.border;
    final shadowColor = isDarkMode ? AppColors.shadowDark : AppColors.shadow;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _selectedDays.isEmpty ? 'Tek Seferlik Alarm' : 'Tekrar Günleri',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w900,
            color: titleColor,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(7, (index) {
            final dayIndex = index + 1;
            final isSelected = _selectedDays.contains(dayIndex);

            return GestureDetector(
              onTap: _isAdmin
                  ? () {
                      setState(() {
                        if (isSelected) {
                          _selectedDays.remove(dayIndex);
                        } else {
                          _selectedDays.add(dayIndex);
                          _selectedDays.sort();
                        }
                        _isModified = true;
                      });
                    }
                  : null,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppColors.primary
                      : (isDarkMode ? AppColors.surfaceDark : Colors.white),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: borderColor, width: 3),
                  boxShadow: isSelected
                      ? null
                      : [
                          BoxShadow(
                            color: (index == 5 || index == 6)
                                ? Colors.pinkAccent
                                : shadowColor,
                            offset: const Offset(3, 3),
                          ),
                        ],
                ),
                child: Center(
                  child: Text(
                    _dayNames[index],
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      color: isSelected
                          ? Colors.white
                          : (isDarkMode
                                ? AppColors.textDarkPrimary
                                : AppColors.textPrimary),
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
      ],
    );
  }

  Widget _buildMissionSection(bool isDarkMode) {
    final shadowColor = isDarkMode ? AppColors.shadowDark : AppColors.shadow;
    final borderColor = isDarkMode ? AppColors.borderDark : AppColors.border;
    final cardBg = isDarkMode ? AppColors.surfaceDark : Colors.white;
    final titleColor = isDarkMode
        ? AppColors.textDarkPrimary
        : AppColors.textPrimary;

    IconData missionIcon = Icons.calculate_rounded;
    Color missionColor = Colors.yellowAccent;

    if (_currentMission == 'TELEFONU SALLA') {
      missionIcon = Icons.vibration_rounded;
      missionColor = Colors.greenAccent;
    } else if (_currentMission == 'BARKOD OKUT') {
      missionIcon = Icons.qr_code_scanner_rounded;
      missionColor = Colors.orangeAccent;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Uyanma Görevi',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w900,
            color: titleColor,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 16),
        GestureDetector(
          onTap: _isAdmin
              ? () {
                  RetroMissionPickerBottomSheet.show(
                    context,
                    initialMission: _currentMission,
                    initialDifficulty: _currentDifficulty,
                    onMissionSelected: (mission, difficulty) {
                      setState(() {
                        _currentMission = mission;
                        _currentDifficulty = difficulty;
                        _isModified = true;
                      });
                    },
                  );
                }
              : null,
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: borderColor, width: 3),
              boxShadow: [
                BoxShadow(color: shadowColor, offset: const Offset(6, 6)),
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: missionColor,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: borderColor, width: 3),
                  ),
                  child: Icon(
                    missionIcon,
                    size: 32,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _currentMission,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: titleColor,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Zorluk: $_currentDifficulty',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          color: isDarkMode
                              ? AppColors.textDarkSecondary
                              : AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_isAdmin)
                  Icon(
                    Icons.edit_rounded,
                    color: isDarkMode
                        ? AppColors.textDarkSecondary
                        : AppColors.textSecondary,
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTeamSection(bool isDarkMode) {
    final shadowColor = isDarkMode ? AppColors.shadowDark : AppColors.shadow;
    final borderColor = isDarkMode ? AppColors.borderDark : AppColors.border;
    final cardBg = isDarkMode ? AppColors.surfaceDark : Colors.white;
    final titleColor = isDarkMode
        ? AppColors.textDarkPrimary
        : AppColors.textPrimary;
    final subTitleColor = isDarkMode
        ? AppColors.textDarkSecondary
        : AppColors.textSecondary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Ekip Durumu',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: titleColor,
                letterSpacing: 1.5,
              ),
            ),
            if (_isAdmin)
              GestureDetector(
                onTap: () {
                  _showAddMemberBottomSheet(context, isDarkMode);
                },
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: borderColor, width: 2),
                    boxShadow: [
                      BoxShadow(color: shadowColor, offset: const Offset(2, 2)),
                    ],
                  ),
                  child: const Icon(
                    Icons.person_add_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderColor, width: 3),
            boxShadow: [
              BoxShadow(color: shadowColor, offset: const Offset(6, 6)),
            ],
          ),
          child: Column(
            children: [
              ..._members.map(
                (member) => Column(
                  children: [
                    _buildTeamMemberRow(
                      member['isMe'] ? 'SEN' : member['username'],
                      member['isAwake'],
                      isDarkMode,
                      isAdminRow:
                          member['uid'] == _activeUid, // Simplify for UI
                      status: member['status'],
                      onKick: (_isAdmin && !member['isMe'])
                          ? () =>
                                _removeMember(member['uid'], member['username'])
                          : null,
                    ),
                    if (member != _members.last)
                      Divider(color: shadowColor, thickness: 3, height: 32),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                '${_members.where((m) => m['isAwake'] && m['status'] == 'JOINED').length}/${_members.where((m) => m['status'] == 'JOINED').length} UYANDI',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: subTitleColor,
                  letterSpacing: 1.5,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPendingUpdateBanner(bool isDarkMode) {
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

    final updatedBy = _pendingUpdateData?['updatedBy'] ?? 'BİR ARKADAŞIN';
    final oldTime = _pendingUpdateData?['oldTime'] ?? '??:??';
    final newTime = _pendingUpdateData?['newTime'] ?? '??:??';

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
                          'SİSTEM GÜNCELLEMESİ',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                            color: titleColor,
                            letterSpacing: 1.2,
                          ),
                        ),
                        Text(
                          '$updatedBy saati değiştirdi',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: subColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
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
              const SizedBox(height: 12),
              GestureDetector(
                onTap: () async {
                  await AlarmSyncService.confirmUpdate(widget.alarmId);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('ALARM BAŞARIYLA GÜNCELLENDİ!'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.green,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: borderColor, width: 2),
                    boxShadow: [
                      BoxShadow(color: shadowColor, offset: const Offset(4, 4)),
                    ],
                  ),
                  child: const Center(
                    child: Text(
                      'ŞİMDİ ONAYLA',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _showAddMemberBottomSheet(BuildContext context, bool isDarkMode) {
    final shadowColor = isDarkMode ? AppColors.shadowDark : AppColors.shadow;
    final borderColor = isDarkMode ? AppColors.borderDark : AppColors.border;
    final bgColor = isDarkMode ? AppColors.surfaceDark : Colors.white;
    final titleColor = isDarkMode
        ? AppColors.textDarkPrimary
        : AppColors.textPrimary;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
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
                  Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.symmetric(horizontal: 100),
                    decoration: BoxDecoration(
                      color: shadowColor.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Yeni Üye Ekle',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      color: titleColor,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 24),
                  StatefulBuilder(
                    builder: (context, setModalState) {
                      return Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: isDarkMode
                                        ? AppColors.surfaceDark
                                        : Colors.white,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: borderColor,
                                      width: 3,
                                    ),
                                  ),
                                  child: TextField(
                                    controller: _memberPhoneController,
                                    keyboardType: TextInputType.phone,
                                    style: TextStyle(
                                      height: 1.0,
                                      color: isDarkMode
                                          ? Colors.white
                                          : Colors.black,
                                    ),
                                    decoration: const InputDecoration(
                                      hintText: '5XX XXX XX XX',
                                      border: InputBorder.none,
                                      contentPadding: EdgeInsets.symmetric(
                                        horizontal: 16,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              GestureDetector(
                                onTap: _isSearchingMember
                                    ? null
                                    : () => _searchUserByPhone(setModalState),
                                child: Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: AppColors.primary,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: borderColor,
                                      width: 3,
                                    ),
                                  ),
                                  child: _isSearchingMember
                                      ? const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        )
                                      : const Icon(
                                          Icons.person_add_rounded,
                                          color: Colors.white,
                                        ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          const Opacity(
                            opacity: 0.6,
                            child: Text(
                              'Arkadaşını telefon numarasıyla ara ve davet et.',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildTeamMemberRow(
    String name,
    bool isAwake,
    bool isDarkMode, {
    bool isAdminRow = false,
    String status = 'JOINED',
    VoidCallback? onKick,
  }) {
    final shadowColor = isDarkMode ? AppColors.shadowDark : AppColors.shadow;
    final borderColor = isDarkMode ? AppColors.borderDark : AppColors.border;
    final titleColor = isDarkMode
        ? AppColors.textDarkPrimary
        : AppColors.textPrimary;

    return GestureDetector(
      onTap: onKick,
      behavior: HitTestBehavior.opaque,
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: status == 'PENDING'
                  ? Colors.grey
                  : (isAwake ? Colors.greenAccent : AppColors.error),
              shape: BoxShape.circle,
              border: Border.all(color: borderColor, width: 2),
              boxShadow: [
                BoxShadow(color: shadowColor, offset: const Offset(2, 2)),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Row(
              children: [
                Text(
                  name,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: titleColor,
                  ),
                ),
                if (isAdminRow) ...[
                  const SizedBox(width: 8),
                  const Icon(
                    Icons.workspace_premium_rounded,
                    color: Colors.orange,
                    size: 20,
                  ),
                ],
              ],
            ),
          ),
          Text(
            status == 'PENDING'
                ? 'Bekleniyor'
                : (isAwake ? 'Ayakta' : 'Uyuyor'),
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w900,
              color: status == 'PENDING'
                  ? Colors.grey
                  : (isAwake ? Colors.green : AppColors.error),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLeaveButton(BuildContext context, bool isDarkMode) {
    if (_isAdmin)
      return const SizedBox.shrink(); // Admin cannot leave, must close the room
    return PrimaryButton(
      text: 'Gruptan Çık',
      color: AppColors.error,
      onPressed: _leaveGroup,
    );
  }
}

class _DetailGridBackgroundPainter extends CustomPainter {
  final Color color;
  _DetailGridBackgroundPainter({required this.color});

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
