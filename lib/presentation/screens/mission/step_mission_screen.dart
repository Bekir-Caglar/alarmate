import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:pedometer/pedometer.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../core/theme/app_colors.dart';

class StepMissionScreen extends StatefulWidget {
  final String difficulty;

  const StepMissionScreen({
    super.key,
    required this.difficulty,
  });

  @override
  State<StepMissionScreen> createState() => _StepMissionScreenState();
}

class _StepMissionScreenState extends State<StepMissionScreen> with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late String _currentDifficulty;

  StreamSubscription<StepCount>? _stepCountSubscription;
  
  int _targetSteps = 20;
  int _currentSteps = 0;
  int? _initialStepCount;
  
  bool _missionComplete = false;
  String _statusMessage = 'SENSÖR BEKLENIYOR...';

  @override
  void initState() {
    super.initState();
    _currentDifficulty = widget.difficulty;
    _pulseController = AnimationController(
       vsync: this, 
       duration: const Duration(seconds: 1)
    )..repeat(reverse: true);
    
    _applyDifficulty();
    _initPedometer();
  }

  @override
  void dispose() {
    _stepCountSubscription?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  void _applyDifficulty() {
    if (_currentDifficulty == 'KOLAY') {
      _targetSteps = 15;
    } else if (_currentDifficulty == 'ORTA') {
      _targetSteps = 30;
    } else if (_currentDifficulty == 'ZOR') {
      _targetSteps = 50;
    } else if (_currentDifficulty == 'CEHENNEM') {
      _targetSteps = 100; // Kalkıp evi turlamanız gerekecek
    }
  }

  Future<void> _initPedometer() async {
    // Android 10+ için Activity Recognition, iOS için Motion sensör iznini isteyelim
    if (Platform.isAndroid || Platform.isIOS) {
      final status = await Permission.activityRecognition.request();
      if (status.isDenied || status.isPermanentlyDenied) {
        setState(() {
          _statusMessage = 'İzin Reddedildi! Ayarlara giderek "Fiziksel Aktivite" iznini açın.';
        });
        return;
      }
    }

    setState(() {
      _statusMessage = 'HAREKETE GEÇ!';
    });

    _stepCountSubscription = Pedometer.stepCountStream.listen(
      _onStepCount,
      onError: _onStepCountError,
    );
  }

  void _onStepCount(StepCount event) {
    if (_missionComplete) return;

    setState(() {
      // Pedometer cihaz açık kaldığı sürece atılan TOPLAM adımı verir, bu yüzden başlangıç adımımızı kaydetmeliyiz.
      _initialStepCount ??= event.steps;

      // O anki toplamdan oyuna başladığımız anki toplamı çıkarırsak bu oyunda atılan limiti buluruz.
      _currentSteps = event.steps - _initialStepCount!;
      
      // Çok minik negatif hatalara karşı koruma
      if (_currentSteps < 0) _currentSteps = 0;

      if (_currentSteps >= _targetSteps) {
        _missionComplete = true;
        _onMissionComplete();
      }
    });
  }

  void _onStepCountError(error) {
    setState(() {
      _statusMessage = 'Adım Sayacı Başlatılamadı.\nEğer Simülatör kullanıyorsanız çalışmaz. Gerçek cihazda deneyin!';
    });
  }

  void _onMissionComplete() {
    _stepCountSubscription?.cancel();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('YÜRÜYÜŞ BAŞARILI! ALARM KAPATILDI.', style: TextStyle(fontWeight: FontWeight.w900)),
        backgroundColor: Colors.green,
      ),
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    
    // Yürüme ekranına özel Turuncu sıcak tonlu bir Brutalist arka plan
    final bgColor = isDarkMode ? const Color(0xFF261000) : const Color(0xFFFFF3E0);

    double progress = _targetSteps > 0 ? (_currentSteps / _targetSteps) : 0;
    if (progress > 1.0) progress = 1.0;

    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(isDarkMode),
              const Spacer(),
              _buildStepMeter(isDarkMode, progress),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(bool isDarkMode) {
    return Column(
      children: [
        AnimatedBuilder(
          animation: _pulseController,
          builder: (context, child) {
            return Transform.scale(
              scale: 1.0 + (_pulseController.value * 0.05),
              child: Text(
                'UYANMA VAKTİ!',
                style: GoogleFonts.jersey10(
                  fontSize: 64,
                  fontWeight: FontWeight.w400,
                  color: AppColors.error,
                  height: 1.0,
                  letterSpacing: 2,
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.orangeAccent,
            border: Border.all(color: Colors.black, width: 3),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Text(
            'ADIM SAYAR',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: Colors.black,
              letterSpacing: 2,
            ),
          ),
        ),
        const SizedBox(height: 16),
        // DEBUG: Zamanla zorluğu değiştirebilme
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: ['KOLAY', 'ORTA', 'ZOR', 'CEHENNEM'].map((diff) {
              final isSelected = _currentDifficulty == diff;
              return GestureDetector(
                onTap: () {
                  if (diff != _currentDifficulty) {
                    setState(() {
                      _currentDifficulty = diff;
                      _currentSteps = 0; // Başa dönmeli
                      _initialStepCount = null; // Sensördeki referansı sıfırla ki adım saymaya baştan başlasın
                    });
                    _applyDifficulty();
                  }
                },
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: isSelected ? Colors.black : Colors.white,
                    border: Border.all(color: Colors.black, width: 3),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    diff,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      color: isSelected ? Colors.white : Colors.black,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildStepMeter(bool isDarkMode, double progress) {
    final shadowColor = isDarkMode ? AppColors.shadowDark : AppColors.shadow;
    final borderColor = isDarkMode ? AppColors.borderDark : AppColors.border;
    final textColor = isDarkMode ? Colors.white : Colors.black;

    return Column(
      children: [
        Text(
          _statusMessage,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w900,
            color: _statusMessage.contains('HAREKETE GEÇ') ? textColor : Colors.redAccent,
            letterSpacing: 1,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 24),
        AnimatedBuilder(
          animation: _pulseController,
          builder: (context, child) {
            // İlerleme arttıkça ikon yukarı aşağı zıplama efekti yapsın
            double translateY = sin(_pulseController.value * pi * 2) * 20; 
            
            return Transform.translate(
              offset: Offset(0, -translateY),
              child: Icon(
                Icons.directions_walk_rounded,
                size: 160,
                color: _currentSteps > 0 ? Colors.orangeAccent : (isDarkMode ? Colors.white : Colors.black),
              ),
            );
          },
        ),
        const SizedBox(height: 48),
        // Brutalist Progress Bar (Güç Barı)
        Stack(
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
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: borderColor, width: 3),
                ),
              ),
            ),
            Container(
              height: 48,
              width: double.infinity, // Maksimum yayılma
              decoration: BoxDecoration(
                color: isDarkMode ? AppColors.surfaceDark : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: borderColor, width: 3),
              ),
              child: Stack(
                children: [
                  if (progress > 0)
                    FractionallySizedBox(
                      widthFactor: progress,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.orangeAccent,
                          borderRadius: BorderRadius.circular(13),
                          border: Border(
                            right: BorderSide(color: borderColor, width: 3),
                          ),
                        ),
                      ),
                    ),
                  Center(
                    child: Text(
                      '$_currentSteps / $_targetSteps',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        color: Colors.black, // Zıtlık
                        letterSpacing: 2,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}
