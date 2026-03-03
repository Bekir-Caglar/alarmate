import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import 'primary_button.dart';

class RetroMissionPickerBottomSheet extends StatefulWidget {
  final String initialMission;
  final String initialDifficulty;
  final Function(String mission, String difficulty) onMissionSelected;

  const RetroMissionPickerBottomSheet({
    super.key,
    required this.initialMission,
    required this.initialDifficulty,
    required this.onMissionSelected,
  });

  static Future<void> show(
    BuildContext context, {
    required String initialMission,
    required String initialDifficulty,
    required Function(String mission, String difficulty) onMissionSelected,
  }) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => RetroMissionPickerBottomSheet(
        initialMission: initialMission,
        initialDifficulty: initialDifficulty,
        onMissionSelected: onMissionSelected,
      ),
    );
  }

  @override
  State<RetroMissionPickerBottomSheet> createState() => _RetroMissionPickerBottomSheetState();
}

class _RetroMissionPickerBottomSheetState extends State<RetroMissionPickerBottomSheet> {
  int _step = 0;
  late String _selectedMission;
  late String _selectedDifficulty;

  final List<Map<String, dynamic>> _missions = [
    {
      'name': 'MATEMATİK SINAVI',
      'icon': Icons.calculate_rounded,
      'color': Colors.yellowAccent,
    },
    {
      'name': 'RENK TUZAĞI',
      'icon': Icons.palette_rounded,
      'color': Colors.pinkAccent,
    },
    {
      'name': 'TELEFONU SALLA',
      'icon': Icons.vibration_rounded,
      'color': Colors.greenAccent,
    },
    // {
    //   'name': 'ADIM SAYAR',
    //   'icon': Icons.directions_run_rounded,
    //   'color': Colors.cyanAccent,
    // },
    {
      'name': 'BARKOD OKUT',
      'icon': Icons.qr_code_scanner_rounded,
      'color': Colors.orangeAccent,
    },
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
    _selectedMission = widget.initialMission;
    _selectedDifficulty = widget.initialDifficulty;
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDarkMode ? AppColors.surfaceDark : Colors.white;
    final shadowColor = isDarkMode ? AppColors.shadowDark : AppColors.shadow;
    final borderColor = isDarkMode ? AppColors.borderDark : AppColors.border;
    final titleColor = isDarkMode ? AppColors.textDarkPrimary : AppColors.textPrimary;

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
              _step == 0 ? 'GÖREVİ SEÇ' : 'ZORLUĞU SEÇ',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w900,
                color: titleColor,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 32),
            if (_step == 0) ..._buildMissions(isDarkMode, shadowColor, borderColor) else ..._buildDifficulties(isDarkMode, shadowColor, borderColor),
            const SizedBox(height: 24),
            Row(
              children: [
                if (_step == 1) ...[
                  Expanded(
                    child: PrimaryButton(
                      text: '<- GERİ',
                      onPressed: () {
                        setState(() {
                          _step = 0;
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 16),
                ],
                Expanded(
                  child: PrimaryButton(
                    text: _step == 0 ? 'SIRADAKİ ->' : 'KAYDET',
                    onPressed: () {
                      if (_step == 0) {
                        setState(() {
                          _step = 1;
                        });
                      } else {
                        widget.onMissionSelected(_selectedMission, _selectedDifficulty);
                        Navigator.pop(context);
                      }
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildMissions(bool isDarkMode, Color shadowColor, Color borderColor) {
    final unselectedCardBg = isDarkMode ? AppColors.surfaceDark : Colors.white;

    return _missions.map((missionData) {
      final missionName = missionData['name'] as String;
      final icon = missionData['icon'] as IconData;
      final bgColor = missionData['color'] as Color;
      final isSelected = _selectedMission == missionName;
      
      return GestureDetector(
        onTap: () {
          setState(() {
            _selectedMission = missionName;
          });
        },
        child: Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isSelected ? bgColor : unselectedCardBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderColor, width: 3),
            boxShadow: isSelected ? [
              BoxShadow(
                color: shadowColor,
                offset: const Offset(4, 4),
              )
            ] : null,
          ),
          child: Row(
            children: [
              Icon(
                isSelected ? Icons.check_circle_rounded : Icons.circle_outlined,
                color: isSelected ? AppColors.textPrimary : (isDarkMode ? AppColors.textDarkPrimary : AppColors.textPrimary),
              ),
              const SizedBox(width: 16),
              Icon(icon, color: isSelected ? AppColors.textPrimary : (isDarkMode ? AppColors.textDarkPrimary : AppColors.textPrimary)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  missionName,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: isSelected ? AppColors.textPrimary : (isDarkMode ? AppColors.textDarkPrimary : AppColors.textPrimary),
                    decoration: isSelected ? null : TextDecoration.lineThrough,
                    decorationThickness: 2,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }).toList();
  }

  List<Widget> _buildDifficulties(bool isDarkMode, Color shadowColor, Color borderColor) {
    final unselectedCardBg = isDarkMode ? AppColors.surfaceDark : Colors.white;

    return _difficulties.map((diffData) {
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
            boxShadow: isSelected ? [
              BoxShadow(
                color: shadowColor,
                offset: const Offset(4, 4),
              )
            ] : null,
          ),
          child: Row(
            children: [
              Icon(
                isSelected ? Icons.check_circle_rounded : Icons.circle_outlined,
                color: isSelected ? AppColors.textPrimary : (isDarkMode ? AppColors.textDarkPrimary : AppColors.textPrimary),
              ),
              const SizedBox(width: 16),
              Text(
                diffName,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: isSelected ? AppColors.textPrimary : (isDarkMode ? AppColors.textDarkPrimary : AppColors.textPrimary),
                  decoration: isSelected ? null : TextDecoration.lineThrough,
                  decorationThickness: 2,
                ),
              ),
            ],
          ),
        ),
      );
    }).toList();
  }
}
