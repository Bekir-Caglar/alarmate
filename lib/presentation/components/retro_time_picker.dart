import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/app_colors.dart';
import 'primary_button.dart';
import '../../main.dart';

class RetroTimePickerBottomSheet extends StatefulWidget {
  final String initialTime;
  final String initialAmPm;
  final Function(String time, String amPm) onTimeSelected;

  const RetroTimePickerBottomSheet({
    super.key,
    required this.initialTime,
    required this.initialAmPm,
    required this.onTimeSelected,
  });

  static Future<void> show(
    BuildContext context, {
    required String initialTime,
    required String initialAmPm,
    required Function(String time, String amPm) onTimeSelected,
  }) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => RetroTimePickerBottomSheet(
        initialTime: initialTime,
        initialAmPm: initialAmPm,
        onTimeSelected: onTimeSelected,
      ),
    );
  }

  @override
  State<RetroTimePickerBottomSheet> createState() =>
      _RetroTimePickerBottomSheetState();
}

class _RetroTimePickerBottomSheetState
    extends State<RetroTimePickerBottomSheet> {
  late FixedExtentScrollController _hourController;
  late FixedExtentScrollController _minuteController;
  late FixedExtentScrollController _amPmController;

  int _selectedHour = 7;
  int _selectedMinute = 30;
  String _selectedAmPm = 'AM';

  final List<String> _amPmOptions = ['AM', 'PM'];

  @override
  void initState() {
    super.initState();
    final parts = widget.initialTime.split(':');
    int hour = int.tryParse(parts[0]) ?? 7;
    _selectedMinute = int.tryParse(parts.length > 1 ? parts[1] : '30') ?? 30;
    _selectedAmPm = widget.initialAmPm;

    final is24h = timeFormatNotifier.value;

    if (is24h) {
      if (_selectedAmPm == 'PM' && hour < 12) hour += 12;
      if (_selectedAmPm == 'AM' && hour == 12) hour = 0;
      _selectedHour = hour;
      _hourController = FixedExtentScrollController(initialItem: _selectedHour);
    } else {
      _selectedHour = hour; // already 1-12
      _hourController = FixedExtentScrollController(
        initialItem: _selectedHour - 1,
      );
    }

    _minuteController = FixedExtentScrollController(
      initialItem: _selectedMinute,
    );
    _amPmController = FixedExtentScrollController(
      initialItem: _amPmOptions.indexOf(_selectedAmPm) != -1
          ? _amPmOptions.indexOf(_selectedAmPm)
          : 0,
    );
  }

  @override
  void dispose() {
    _hourController.dispose();
    _minuteController.dispose();
    _amPmController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDarkMode ? AppColors.surfaceDark : Colors.white;
    final shadowColor = isDarkMode ? AppColors.shadowDark : AppColors.shadow;
    final borderColor = isDarkMode ? AppColors.borderDark : AppColors.border;
    final titleColor = isDarkMode
        ? AppColors.textDarkPrimary
        : AppColors.textPrimary;
    final wheelItemColor = isDarkMode
        ? AppColors.textDarkPrimary
        : AppColors.textPrimary;

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
              'ZAMANI BELİRLE',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w900,
                color: titleColor,
                letterSpacing: 1.5,
              ),
            ),
            ValueListenableBuilder<bool>(
              valueListenable: timeFormatNotifier,
              builder: (context, is24h, _) {
                return SizedBox(
                  height: 200,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        height: 60,
                        decoration: BoxDecoration(
                          color: AppColors.primaryLight.withValues(alpha: 0.15),
                          border: Border.symmetric(
                            horizontal: BorderSide(
                              color: borderColor,
                              width: 3,
                            ),
                          ),
                        ),
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: _buildWheel(
                              controller: _hourController,
                              itemCount: is24h ? 24 : 12,
                              onSelectedItemChanged: (index) {
                                setState(
                                  () => _selectedHour = is24h
                                      ? index
                                      : (index + 1),
                                );
                              },
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
                              fontSize: 40,
                              fontWeight: FontWeight.w900,
                              color: wheelItemColor,
                            ),
                          ),
                          Expanded(
                            child: _buildWheel(
                              controller: _minuteController,
                              itemCount: 60,
                              onSelectedItemChanged: (index) {
                                setState(() => _selectedMinute = index);
                              },
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
                                controller: _amPmController,
                                itemCount: 2,
                                onSelectedItemChanged: (index) {
                                  setState(
                                    () => _selectedAmPm = _amPmOptions[index],
                                  );
                                },
                                itemBuilder: (context, index) {
                                  return _buildWheelItem(
                                    _amPmOptions[index],
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
                );
              },
            ),
            const SizedBox(height: 48),
            PrimaryButton(
              text: 'KAYDET',
              onPressed: () {
                int hour = _selectedHour;
                String amPm = _selectedAmPm;

                if (timeFormatNotifier.value) {
                  // If picked in 24h, convert to 12h + AM/PM for internal storage consistency
                  bool isPm = hour >= 12;
                  amPm = isPm ? 'PM' : 'AM';
                  hour = hour % 12;
                  if (hour == 0) hour = 12;
                }

                final time =
                    '${hour.toString().padLeft(2, '0')}:${_selectedMinute.toString().padLeft(2, '0')}';
                widget.onTimeSelected(time, amPm);
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWheel({
    required FixedExtentScrollController controller,
    required int itemCount,
    required Function(int) onSelectedItemChanged,
    required Widget Function(BuildContext, int) itemBuilder,
  }) {
    return ListWheelScrollView.useDelegate(
      controller: controller,
      itemExtent: 60,
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
          fontSize: isSmall ? 40 : 60,
          fontWeight: FontWeight.w400,
          color: color,
          height: 1.0,
        ),
      ),
    );
  }
}
