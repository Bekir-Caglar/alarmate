import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:vibration/vibration.dart';
import '../../../core/theme/app_colors.dart';

class ShakeMissionScreen extends StatefulWidget {
  final String difficulty;

  const ShakeMissionScreen({super.key, required this.difficulty});

  @override
  State<ShakeMissionScreen> createState() => _ShakeMissionScreenState();
}

class _ShakeMissionScreenState extends State<ShakeMissionScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late String _currentDifficulty;

  StreamSubscription<AccelerometerEvent>? _accelerometerSubscription;
  Timer? _drainTimer;

  double _targetShakes = 100.0;
  double _currentShakes = 0.0;

  // Salla testi threshold ayarları
  static const double _shakeThresholdGravity =
      2.5; // G-Force çarpanı (2.5G oldukça serttir)
  int _lastShakeTime = 0;
  static const int _minTimeBetweenShakes = 150; // Milisaniye

  bool _hasVibrator = false;

  @override
  void initState() {
    super.initState();
    _currentDifficulty = widget.difficulty;
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);

    _applyDifficulty();
    _checkVibrator();
    _startShakeListener();
    _startDrainTimer();
  }

  @override
  void dispose() {
    _drainTimer?.cancel();
    _accelerometerSubscription?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _checkVibrator() async {
    bool? hasVib = await Vibration.hasVibrator();
    setState(() {
      _hasVibrator = hasVib ?? false;
    });
  }

  void _applyDifficulty() {
    if (_currentDifficulty == 'KOLAY') {
      _targetShakes = 30.0;
    } else if (_currentDifficulty == 'ORTA') {
      _targetShakes = 50.0;
    } else if (_currentDifficulty == 'ZOR') {
      _targetShakes = 100.0;
    } else if (_currentDifficulty == 'CEHENNEM') {
      _targetShakes = 200.0; // Tam bir uyku açıcı işkence
    }
  }

  void _startDrainTimer() {
    _drainTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (_currentShakes > 0 && mounted) {
        setState(() {
          // Zorluğa göre inme hızı da artabilir ama basitçe sabit tutalım
          _currentShakes -= 1.0;
          if (_currentShakes < 0) _currentShakes = 0;
        });
      }
    });
  }

  void _startShakeListener() {
    // Tüm cihazlarda en kararlı ivme ölçümü accelerometer Event ile yapılır
    // değerler m/s^2 cinsindendir.
    _accelerometerSubscription = accelerometerEventStream().listen((event) {
      // 1. Cihazın her bir eksendeki ivmesini Yer Çekimi İvmesine (G = 9.80665) bölerek G-Kuvvetini (G-Force) buluyoruz.
      final double gX = event.x / 9.80665;
      final double gY = event.y / 9.80665;
      final double gZ = event.z / 9.80665;

      // 2. 3 Boyutlu Uzayda Vektörün Büyüklüğünü (Bileşkesini) hesaplıyoruz.
      // Cihaz masada sabit dururken yer çekiminden dolayı bu değer her zaman ~1.0 G olacaktır.
      final double gForce = sqrt(gX * gX + gY * gY + gZ * gZ);

      // 3. Eğer G-Kuvveti bizim 2.5G threshold'umuzu aşarsa (yani cihaz şiddetli bir şoka / sarsıntıya maruz kaldıysa)
      if (gForce > _shakeThresholdGravity) {
        final int now = DateTime.now().millisecondsSinceEpoch;

        // 4. Çift sayımları ve noise/gürültüleri engellemek için iki sallama arasında en az ufak bir süre geçmesini zorunlu kılıyoruz.
        if (now - _lastShakeTime > _minTimeBetweenShakes) {
          _lastShakeTime = now;
          _onShakeDetected();
        }
      }
    });
  }

  Future<void> _onShakeDetected() async {
    if (!mounted) return;

    // Titreşim hissi (Cihaz destekliyorsa)
    if (_hasVibrator) {
      Vibration.vibrate(duration: 50, amplitude: 255);
    }

    setState(() {
      _currentShakes += 4.0; // Her başarlı sallama barı 4 birim doldurur
      if (_currentShakes > _targetShakes) _currentShakes = _targetShakes;
    });

    // Görev bitti mi?
    if (_currentShakes >= _targetShakes) {
      _drainTimer?.cancel();
      _accelerometerSubscription?.cancel(); // Durdurki daha fazla yormasın

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'SALLAMA BAŞARILI! ALARM KAPATILDI.',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pop(context); // Görevi tamamla ve çık
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    // Alarm Ekranına Özel Brutalist Arka Plan
    final bgColor = isDarkMode
        ? const Color(0xFF1a0000)
        : const Color(0xFFFFEBEE);

    // Kalan yüzde
    double progress = _targetShakes > 0 ? (_currentShakes / _targetShakes) : 0;
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
              _buildShakeMeter(isDarkMode, progress),
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
            color: Colors.greenAccent,
            border: Border.all(color: Colors.black, width: 3),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Text(
            'TELEFONU SALLA',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: Colors.black,
              letterSpacing: 2,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildShakeMeter(bool isDarkMode, double progress) {
    final shadowColor = isDarkMode ? AppColors.shadowDark : AppColors.shadow;
    final borderColor = isDarkMode ? AppColors.borderDark : AppColors.border;
    final textColor = isDarkMode ? Colors.white : Colors.black;

    return Column(
      children: [
        Text(
          'ALARM SADECE SALLAYINCA SUSACAK!',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w900,
            color: textColor,
            letterSpacing: 1,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 24),
        AnimatedBuilder(
          animation: _pulseController,
          builder: (context, child) {
            // İlerleme arttıkça ikon daha şiddetli titreyecek!
            double maxShakeAngle = progress > 0
                ? (pi / 12) + (progress * pi / 6)
                : pi / 24;
            double currentAngle =
                sin(_pulseController.value * pi * 4) * maxShakeAngle;

            return Transform.rotate(
              angle: currentAngle,
              child: Icon(
                Icons.vibration_rounded,
                size: 160,
                color: _currentShakes > 0
                    ? Colors.greenAccent
                    : (isDarkMode ? Colors.white : Colors.black),
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
                          color: Colors.greenAccent,
                          borderRadius: BorderRadius.circular(13),
                          border: Border(
                            right: BorderSide(color: borderColor, width: 3),
                          ),
                        ),
                      ),
                    ),
                  Center(
                    child: Text(
                      '%${(progress * 100).toInt()}',
                      style: const TextStyle(
                        fontSize: 32,
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
