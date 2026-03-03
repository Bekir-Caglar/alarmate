import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:vibration/vibration.dart';
import '../../../core/theme/app_colors.dart';

class BarcodeMissionScreen extends StatefulWidget {
  final String difficulty;

  const BarcodeMissionScreen({super.key, required this.difficulty});

  @override
  State<BarcodeMissionScreen> createState() => _BarcodeMissionScreenState();
}

class _BarcodeMissionScreenState extends State<BarcodeMissionScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late String _currentDifficulty;

  final MobileScannerController _scannerController = MobileScannerController(
    formats: [BarcodeFormat.all],
    detectionSpeed: DetectionSpeed.normal,
  );

  int _targetScanCount = 1;
  final Set<String> _scannedBarcodes = {};
  int _lastScanTime = 0;

  bool _missionComplete = false;
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
  }

  @override
  void dispose() {
    _scannerController.dispose();
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
      _targetScanCount = 1;
    } else if (_currentDifficulty == 'ORTA') {
      _targetScanCount =
          2; // Daha derine saklanmış 2 farklı ürün bulmak gerekecek
    } else if (_currentDifficulty == 'ZOR') {
      _targetScanCount = 3;
    } else if (_currentDifficulty == 'CEHENNEM') {
      _targetScanCount =
          5; // Evin içinde köşe bucak 5 farklı ürün barkodu arayacak!
    }
  }

  void _onDetect(BarcodeCapture capture) {
    if (_missionComplete) return;

    final int now = DateTime.now().millisecondsSinceEpoch;
    // Okumalar arasında en az 1.5 saniye bekle (Kamera aynı anda farklı formatlarda okumasın diye)
    if (now - _lastScanTime < 1500) return;

    final List<Barcode> barcodes = capture.barcodes;
    bool newBarcodeDetected = false;
    bool duplicateDetected = false;

    for (final barcode in barcodes) {
      if (barcode.rawValue != null && barcode.rawValue!.isNotEmpty) {
        // EAN-13 ve UPC-A aynı barkodu başına 0 ekleyerek farklı gibi gösterebiliyor. Normalized ediyoruz.
        String raw = barcode.rawValue!.trim();
        String normalized = raw.replaceFirst(RegExp(r'^0+'), '');
        if (normalized.isEmpty) normalized = raw;

        if (!_scannedBarcodes.contains(normalized)) {
          _scannedBarcodes.add(normalized);
          newBarcodeDetected = true;
          _lastScanTime = now;
          break; // O frame'de sadece 1 yeni barkod kabul etsin
        } else {
          duplicateDetected = true;
        }
      }
    }

    if (newBarcodeDetected) {
      if (_hasVibrator) {
        Vibration.vibrate(duration: 100, amplitude: 255);
      }

      setState(() {
        if (_scannedBarcodes.length >= _targetScanCount) {
          _missionComplete = true;
          _onMissionComplete();
        } else {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'YENİ BARKOD BULUNDU! SONRAKİNE GEÇİN.',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
              backgroundColor: Colors.deepPurpleAccent,
              duration: Duration(seconds: 1),
            ),
          );
        }
      });
    } else if (duplicateDetected && (now - _lastScanTime > 2000)) {
      // Kullanıcı inatla aynı barkodu okutuyorsa uyar (çok sık spam atmasın diye lastScanTime kullanıyoruz)
      _lastScanTime = now;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'BU ÜRÜN ZATEN OKUNDU! BAŞKA BARKOD BUL.',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          backgroundColor: Colors.redAccent,
          duration: Duration(seconds: 1),
        ),
      );
    }
  }

  void _onMissionComplete() {
    _scannerController.stop();
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'BARKODLAR BAŞARIYLA OKUNDU! ALARM KAPATILDI.',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        backgroundColor: Colors.green,
      ),
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    // Tarayıcı ekranına özel Brutalist mor/lacivert arka plan
    final bgColor = isDarkMode
        ? const Color(0xFF100826)
        : const Color(0xFFEDE7FF);

    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(isDarkMode),
              const SizedBox(height: 16),
              Expanded(child: _buildScannerArea(isDarkMode)),
              const SizedBox(height: 16),
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
            color: Colors.deepPurpleAccent,
            border: Border.all(color: Colors.black, width: 3),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Text(
            'BARKOD OKUT',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              letterSpacing: 2,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildScannerArea(bool isDarkMode) {
    final shadowColor = isDarkMode ? AppColors.shadowDark : AppColors.shadow;
    final borderColor = isDarkMode ? AppColors.borderDark : AppColors.border;
    final textColor = isDarkMode ? Colors.white : Colors.black;

    int scannedCount = _scannedBarcodes.length;
    bool needsMultiple = _targetScanCount > 1;

    return Column(
      children: [
        Text(
          needsMultiple
              ? 'ALARM SADECE $_targetScanCount FARKLI ÜRÜN BARKODU OKUTUNCA SUSACAK!'
              : 'ALARM SADECE BİR BARKOD OKUTUNCA SUSACAK!',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w900,
            color: textColor,
            letterSpacing: 1,
            height: 1.2,
          ),
        ),
        if (needsMultiple) ...[
          const SizedBox(height: 8),
          Text(
            'İlerleme: $scannedCount / $_targetScanCount',
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w900,
              color: Colors.deepPurpleAccent,
            ),
          ),
        ],
        const SizedBox(height: 24),
        Expanded(
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
                    border: Border.all(color: borderColor, width: 3),
                  ),
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: borderColor, width: 3),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(21),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      MobileScanner(
                        controller: _scannerController,
                        onDetect: _onDetect,
                        errorBuilder: (context, error) {
                          return Center(
                            child: Text(
                              'Kamera başlatılamadı.\nFiziksel cihaz kullanın veya izinleri kontrol edin.',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.redAccent,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          );
                        },
                      ),
                      // Scanner Overlay Effect
                      AnimatedBuilder(
                        animation: _pulseController,
                        builder: (context, child) {
                          return Positioned(
                            top:
                                (_pulseController.value * 200) +
                                MediaQuery.of(context).size.height * 0.1,
                            left: 0,
                            right: 0,
                            child: Container(
                              height: 3,
                              decoration: BoxDecoration(
                                color: Colors.redAccent.withValues(alpha: 0.8),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.redAccent.withValues(
                                      alpha: 0.5,
                                    ),
                                    blurRadius: 10,
                                    spreadRadius: 5,
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
