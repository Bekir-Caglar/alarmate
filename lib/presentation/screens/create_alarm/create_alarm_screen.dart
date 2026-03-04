import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_database/firebase_database.dart';
import '../../../core/services/local_alarm_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/database/local_db.dart';
import '../../components/primary_button.dart';
import '../../components/retro_progress_bar.dart';
import '../../components/retro_time_picker.dart';
import '../../components/brutalist_icon_button.dart';
import '../../../core/services/alarm_sync_service.dart';
import '../../../main.dart';
import '../../../data/repositories/data_repository.dart';

class CreateAlarmScreen extends StatefulWidget {
  final bool isAnonymous;
  const CreateAlarmScreen({super.key, this.isAnonymous = false});

  @override
  State<CreateAlarmScreen> createState() => _CreateAlarmScreenState();
}

class _CreateAlarmScreenState extends State<CreateAlarmScreen>
    with SingleTickerProviderStateMixin {
  int _currentIndex = 0;

  late AnimationController _slideController;
  late Animation<Offset> _slideAnimation;

  // State data for new alarm
  String _selectedTime = '07:30';
  String _selectedAmPm = 'AM';
  String _selectedMission = 'MATEMATİK SINAVI';
  String _selectedDifficulty = 'CEHENNEM';
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _memberPhoneController = TextEditingController();

  List<Map<String, dynamic>> _invitedMembers = [];
  bool _isSearching = false;
  late bool _isAnonymous;

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

  final List<String> _missions = [
    'MATEMATİK SINAVI',
    'RENK TUZAĞI',
    'TELEFONU SALLA',
    // 'ADIM SAYAR',
    'BARKOD OKUT',
  ];

  final List<Map<String, dynamic>> _difficulties = [
    {'name': 'KOLAY', 'color': Colors.greenAccent},
    {'name': 'ORTA', 'color': Colors.yellowAccent},
    {'name': 'ZOR', 'color': Colors.orangeAccent},
    {'name': 'CEHENNEM', 'color': Colors.redAccent},
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
    _isAnonymous = widget.isAnonymous;
  }

  @override
  void dispose() {
    _slideController.dispose();
    _nameController.dispose();
    _memberPhoneController.dispose();
    super.dispose();
  }

  void _nextStep() async {
    // Basic validation
    if (_currentIndex == 3 && _nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'BİR İSİM GİRMELİSİN!',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
        ),
      );
      return;
    }

    final maxIndex = _isAnonymous ? 3 : 4;

    if (_currentIndex < maxIndex) {
      await _slideController.forward();
      setState(() {
        _currentIndex++;
      });
      _slideController.reset();
    } else {
      // Bitti - create alarm
      _showLoadingAndSave();
    }
  }

  void _showLoadingAndSave() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );
    try {
      await _saveAlarm();
      if (mounted) Navigator.pop(context); // Close loading
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Close loading
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('HATA: $e')));
      }
    }
  }

  Future<void> _searchUserByPhone() async {
    final phone = _memberPhoneController.text.trim();
    if (phone.isEmpty) return;

    // Google style prefixing (+90) if not present
    String rawPhone = phone.replaceAll(RegExp(r'\s+'), '');
    String searchPhone = rawPhone.startsWith('+') ? rawPhone : '+90$rawPhone';

    setState(() => _isSearching = true);

    try {
      final db = FirebaseDatabase.instance.ref();
      final snapshot = await db
          .child('users')
          .orderByChild('phone')
          .equalTo(searchPhone)
          .once();

      if (snapshot.snapshot.exists) {
        final userData = (snapshot.snapshot.value as Map).entries.first;
        final uid = userData.key;
        final info = Map<String, dynamic>.from(userData.value as Map);

        // Already added?
        if (_invitedMembers.any((m) => m['uid'] == uid)) {
          if (mounted)
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('BU KULLANICI ZATEN EKLENMİŞ!')),
            );
        } else {
          setState(() {
            _invitedMembers.add({
              'uid': uid,
              'username': info['username'] ?? 'BİLİNMEYEN',
              'phone': info['phone'] ?? '',
            });
            _memberPhoneController.clear();
          });
        }
      } else {
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('KULLANICI BULUNAMADI!')),
          );
      }
    } finally {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  Future<void> _saveAlarm() async {
    final uid = await LocalDb.instance.getActiveUid();
    // if (user == null) return; // Removed because we have Local UID now

    final parts = _selectedTime.split(':');
    int hour = int.parse(parts[0]);

    if (_selectedAmPm == 'PM' && hour < 12) hour += 12;
    if (_selectedAmPm == 'AM' && hour == 12) hour = 0;

    if (_isAnonymous) {
      // Misafir için yerel DB'ye kaydet (SharedPrefs ile JSON listesi)
      await LocalAlarmService.saveAlarm({
        'groupName': _nameController.text.toUpperCase(),
        'time': _selectedTime,
        'ampm': _selectedAmPm,
        'mission': _selectedMission,
        'difficulty': _selectedDifficulty,
        'days': _selectedDays,
        'isActive': true,
        'creatorId': uid,
      });
    } else {
      // Kayıtlı kullanıcı için RTDB'de ID oluştur
      final db = FirebaseDatabase.instance.ref();
      final newAlarmRef = db.child('alarms').push();
      final String alarmId = newAlarmRef.key!;

      final alarmData = {
        'groupName': _nameController.text.toUpperCase(),
        'time': _selectedTime,
        'ampm': _selectedAmPm,
        'mission': _selectedMission,
        'difficulty': _selectedDifficulty,
        'creatorId': uid,
        'isActive': true,
        'days': _selectedDays,
        'createdAt': ServerValue.timestamp,
        'members': {uid: true},
        'memberActiveStatuses': {uid: true},
        'invitedMembers': {
          for (var m in _invitedMembers) m['uid']: m['username'],
        },
      };

      // Alarmlar node'una ekle (await YOK, offline first için asenkron çalışır)
      newAlarmRef.set(alarmData);

      // Yerel önbelleğe anında kaydet
      await LocalDb.instance.save('alarms', alarmId, alarmData);

      // Kendi membership'ine ekle (await YOK)
      db.child('memberships').child(uid).child(alarmId).set(true);

      // Davetler gönder
      // Offline iken takılmaması için timeout ekliyor veya cache bekliyoruz.
      String inviterName = 'BİR ARKADAŞIN';
      try {
        final userData = await DataRepository.instance.getUserOnce(uid);
        if (userData != null && userData['username'] != null) {
          inviterName = userData['username'];
        }
      } catch (e) {
        debugPrint(
          'Kullanıcı adı alınamadı, offline olabilir (veya cache boş): $e',
        );
      }

      for (var member in _invitedMembers) {
        db.child('invitations').child(member['uid']).child(alarmId).set({
          'groupName': _nameController.text.toUpperCase(),
          'inviterName': inviterName,
          'time': _selectedTime,
          'ampm': _selectedAmPm,
          'mission': _selectedMission,
          'difficulty': _selectedDifficulty,
          'days': _selectedDays,
          'timestamp': ServerValue.timestamp,
        });
      }
    }

    // Ortak Alan: Alarmları cihazla senkronize et
    await AlarmSyncService.syncAlarmsWithDevice();

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isAnonymous
                ? 'ALARM BAŞARIYLA KURULDU!'
                : 'ALARM KURULDU VE DAVETLER GÖNDERİLDİ!',
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final statusBarColor = isDarkMode ? AppColors.surfaceDark : Colors.white;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _CreateGridBackgroundPainter(
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
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return SingleChildScrollView(
                        clipBehavior: Clip.none,
                        physics: const BouncingScrollPhysics(),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minHeight: constraints.maxHeight,
                          ),
                          child: IntrinsicHeight(
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
                                  SlideTransition(
                                    position: _slideAnimation,
                                    child: _buildCurrentStepView(isDarkMode),
                                  ),
                                  const Spacer(),
                                  const SizedBox(height: 24),
                                  PrimaryButton(
                                    text:
                                        (_isAnonymous
                                            ? _currentIndex == 3
                                            : _currentIndex == 4)
                                        ? 'BİTİR VE OLUŞTUR!'
                                        : 'SIRADAKİ ->',
                                    onPressed: _nextStep,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
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
            icon: Icons.close_rounded,
            onTap: () => Navigator.pop(context),
          ),
          Text(
            'YENİ ODA KUR',
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

  Widget _buildRetroProgressBar(bool isDarkMode) {
    final totalSteps = _isAnonymous ? 4 : 5;
    return RetroProgressBar(
      totalSteps: totalSteps,
      currentStep: _currentIndex,
      onStepTapped: (index) {
        if (index != _currentIndex) {
          final maxAllowedIndex = _isAnonymous ? 3 : 4;
          if (index >= maxAllowedIndex && _nameController.text.trim().isEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'BİR İSİM GİRMELİSİN!',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            );
            return;
          }
          setState(() {
            _currentIndex = index;
          });
          _slideController.reset();
        }
      },
    );
  }

  Widget _buildCurrentStepView(bool isDarkMode) {
    switch (_currentIndex) {
      case 0:
        return _buildStep1Time(isDarkMode);
      case 1:
        return _buildStep2Mission(isDarkMode);
      case 2:
        return _buildStep3Difficulty(isDarkMode);
      case 3:
        return _buildStep4Name(isDarkMode);
      case 4:
        return _buildStep5Invite(isDarkMode);
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildStep1Time(bool isDarkMode) {
    final shadowColor = isDarkMode ? AppColors.shadowDark : AppColors.shadow;
    final borderColor = isDarkMode ? AppColors.borderDark : AppColors.border;

    return _buildBrutalistCard(
      title: 'HEDEFİNİ SEÇ',
      description: 'Takımın ne zaman uyanacak? Zamanı iyi belirle.',
      isDarkMode: isDarkMode,
      child: Column(
        children: [
          GestureDetector(
            onTap: () {
              RetroTimePickerBottomSheet.show(
                context,
                initialTime: _selectedTime,
                initialAmPm: _selectedAmPm,
                onTimeSelected: (time, ampm) {
                  setState(() {
                    _selectedTime = time;
                    _selectedAmPm = ampm;
                  });
                },
              );
            },
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: borderColor, width: 3),
                boxShadow: [
                  BoxShadow(color: shadowColor, offset: const Offset(4, 4)),
                ],
              ),
              child: ValueListenableBuilder<bool>(
                valueListenable: timeFormatNotifier,
                builder: (context, is24h, _) {
                  String displayTime = _selectedTime;
                  String? displayAmPm = _selectedAmPm;

                  if (is24h) {
                    final parts = _selectedTime.split(':');
                    int h = int.parse(parts[0]);
                    if (_selectedAmPm == 'PM' && h < 12) h += 12;
                    if (_selectedAmPm == 'AM' && h == 12) h = 0;
                    displayTime = '${h.toString().padLeft(2, '0')}:${parts[1]}';
                    displayAmPm = null;
                  }

                  return Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        displayTime,
                        style: GoogleFonts.jersey10(
                          fontSize: 72,
                          fontWeight: FontWeight.w400,
                          color: AppColors.textPrimary,
                          height: 1.0,
                        ),
                      ),
                      if (displayAmPm != null) ...[
                        const SizedBox(width: 8),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12.0),
                          child: Text(
                            displayAmPm,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(width: 16),
                      const Padding(
                        padding: EdgeInsets.only(bottom: 12.0),
                        child: Icon(
                          Icons.edit_rounded,
                          color: AppColors.textPrimary,
                          size: 32,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 32),
          _buildDaysPicker(isDarkMode),
        ],
      ),
    );
  }

  Widget _buildDaysPicker(bool isDarkMode) {
    final titleColor = isDarkMode
        ? AppColors.textDarkPrimary
        : AppColors.textPrimary;
    final borderColor = isDarkMode ? AppColors.borderDark : AppColors.border;
    final shadowColor = isDarkMode ? AppColors.shadowDark : AppColors.shadow;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'TEKRAR GÜNLERİ',
          style: TextStyle(
            fontSize: 18,
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
              onTap: () {
                setState(() {
                  if (isSelected) {
                    _selectedDays.remove(dayIndex);
                  } else {
                    _selectedDays.add(dayIndex);
                    _selectedDays.sort();
                  }
                });
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppColors.primary
                      : (isDarkMode ? AppColors.surfaceDark : Colors.white),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: borderColor,
                    width: isSelected ? 3 : 2,
                  ),
                  boxShadow: isSelected
                      ? null
                      : [
                          BoxShadow(
                            color: (index == 5 || index == 6)
                                ? Colors.pinkAccent
                                : shadowColor,
                            offset: const Offset(2, 2),
                          ),
                        ],
                ),
                child: Center(
                  child: Text(
                    _dayNames[index],
                    style: TextStyle(
                      fontSize: 10,
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

  Widget _buildStep2Mission(bool isDarkMode) {
    final shadowColor = isDarkMode ? AppColors.shadowDark : AppColors.shadow;
    final borderColor = isDarkMode ? AppColors.borderDark : AppColors.border;
    final unselectedCardBg = isDarkMode ? AppColors.surfaceDark : Colors.white;

    return _buildBrutalistCard(
      title: 'CEZA NE OLACAK?',
      description:
          'Uyanmak için gruptaki herkesin bu görevi geçmesi gerekecek.',
      isDarkMode: isDarkMode,
      child: Column(
        children: _missions.map((mission) {
          final isSelected = _selectedMission == mission;
          return GestureDetector(
            onTap: () {
              setState(() {
                _selectedMission = mission;
              });
            },
            child: Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isSelected ? Colors.yellowAccent : unselectedCardBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: borderColor, width: 3),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: shadowColor,
                          offset: const Offset(4, 4),
                        ),
                      ]
                    : null,
              ),
              child: Row(
                children: [
                  Icon(
                    isSelected
                        ? Icons.check_circle_rounded
                        : Icons.circle_outlined,
                    color: isSelected
                        ? AppColors.textPrimary
                        : (isDarkMode
                              ? AppColors.textDarkPrimary
                              : AppColors.textPrimary),
                  ),
                  const SizedBox(width: 16),
                  Text(
                    mission,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: isSelected
                          ? AppColors.textPrimary
                          : (isDarkMode
                                ? AppColors.textDarkPrimary
                                : AppColors.textPrimary),
                      decoration: isSelected
                          ? null
                          : TextDecoration.lineThrough,
                      decorationThickness: 2,
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildStep3Difficulty(bool isDarkMode) {
    final shadowColor = isDarkMode ? AppColors.shadowDark : AppColors.shadow;
    final borderColor = isDarkMode ? AppColors.borderDark : AppColors.border;
    final unselectedCardBg = isDarkMode ? AppColors.surfaceDark : Colors.white;

    return _buildBrutalistCard(
      title: 'ZORLUĞU SEÇ',
      description: 'Zorluk seviyesi, görevin ne kadar süreceğini belirler.',
      isDarkMode: isDarkMode,
      child: Column(
        children: _difficulties.map((diffData) {
          final diffName = diffData['name'] as String;
          final bgColor = diffData['color'] as Color;
          final isSelected = _selectedDifficulty == diffName;

          return GestureDetector(
            onTap: () {
              setState(() {
                _selectedDifficulty = diffName;
              });
            },
            child: Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isSelected ? bgColor : unselectedCardBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: borderColor, width: 3),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: shadowColor,
                          offset: const Offset(4, 4),
                        ),
                      ]
                    : null,
              ),
              child: Row(
                children: [
                  Icon(
                    isSelected
                        ? Icons.check_circle_rounded
                        : Icons.circle_outlined,
                    color: isSelected
                        ? AppColors.textPrimary
                        : (isDarkMode
                              ? AppColors.textDarkPrimary
                              : AppColors.textPrimary),
                  ),
                  const SizedBox(width: 16),
                  Text(
                    diffName,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: isSelected
                          ? AppColors.textPrimary
                          : (isDarkMode
                                ? AppColors.textDarkPrimary
                                : AppColors.textPrimary),
                      decoration: isSelected
                          ? null
                          : TextDecoration.lineThrough,
                      decorationThickness: 2,
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildStep4Name(bool isDarkMode) {
    final borderColor = isDarkMode ? AppColors.borderDark : AppColors.border;
    final inputBg = isDarkMode ? AppColors.surfaceDark : Colors.white;
    final textColor = isDarkMode
        ? AppColors.textDarkPrimary
        : AppColors.textPrimary;

    return _buildBrutalistCard(
      title: 'ODANI İSİMLENDİR',
      description: 'Grubuna efsanevi bir isim ver.',
      isDarkMode: isDarkMode,
      child: Column(
        children: [
          Container(
            decoration: BoxDecoration(
              color: inputBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: borderColor, width: 3),
            ),
            child: TextField(
              controller: _nameController,
              textAlign: TextAlign.center,
              textCapitalization: TextCapitalization.characters,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w900,
                color: textColor,
                letterSpacing: 2,
              ),
              decoration: InputDecoration(
                hintText: 'ÖR: SABAH SAVAŞÇILARI',
                hintStyle: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: textColor.withValues(alpha: 0.3),
                  letterSpacing: 1,
                ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 24,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStep5Invite(bool isDarkMode) {
    final shadowColor = isDarkMode ? AppColors.shadowDark : AppColors.shadow;
    final borderColor = isDarkMode ? AppColors.borderDark : AppColors.border;

    return _buildBrutalistCard(
      title: 'TAKIMINI KUR',
      description: 'Arkadaşlarını telefon numarasıyla ara ve ekle.',
      isDarkMode: isDarkMode,
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: isDarkMode ? AppColors.surfaceDark : Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: borderColor, width: 3),
                  ),
                  child: TextField(
                    controller: _memberPhoneController,
                    keyboardType: TextInputType.phone,
                    style: TextStyle(
                      height: 1.0,
                      color: isDarkMode ? Colors.white : Colors.black,
                    ),
                    decoration: const InputDecoration(
                      hintText: '5XX XXX XX XX',
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(horizontal: 16),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _isSearching ? null : _searchUserByPhone,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: borderColor, width: 3),
                  ),
                  child: _isSearching
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
          const SizedBox(height: 16),
          if (_invitedMembers.isNotEmpty) ...[
            const Divider(thickness: 2),
            const SizedBox(height: 8),
            ..._invitedMembers.map(
              (member) => Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDarkMode
                      ? Colors.white10
                      : Colors.black.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: AppColors.primary,
                      radius: 14,
                      child: Text(
                        member['username'][0],
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        member['username'],
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 20),
                      onPressed: () {
                        setState(() {
                          _invitedMembers.remove(member);
                        });
                      },
                    ),
                  ],
                ),
              ),
            ),
          ] else
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Opacity(
                opacity: 0.5,
                child: Text(
                  'HENÜZ KİMSE EKLENMEDİ',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBrutalistCard({
    required String title,
    required String description,
    required Widget child,
    required bool isDarkMode,
  }) {
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
          top: 8,
          left: 8,
          right: -8,
          bottom: -8,
          child: Container(
            decoration: BoxDecoration(
              color: shadowColor,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: borderColor, width: 3),
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: borderColor, width: 3),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  color: titleColor,
                  height: 1.1,
                  letterSpacing: -1,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                description,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: subTitleColor,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 32),
              child,
            ],
          ),
        ),
      ],
    );
  }
}

class _CreateGridBackgroundPainter extends CustomPainter {
  final Color color;
  _CreateGridBackgroundPainter({required this.color});

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
