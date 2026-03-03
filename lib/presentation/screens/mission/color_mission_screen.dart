import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_colors.dart';

class ColorMissionScreen extends StatefulWidget {
  final String difficulty;

  const ColorMissionScreen({super.key, required this.difficulty});

  @override
  State<ColorMissionScreen> createState() => _ColorMissionScreenState();
}

class _ColorMissionScreenState extends State<ColorMissionScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late String _currentDifficulty;

  // Renk Tuzağı (Stroop Effect) State
  int _targetScore = 3;
  int _currentScore = 0;

  // O an sorulan kelime metni örn: "MAVİ"
  String _wordText = "";
  // O an ekranda yazının boyandığı renk örn: Mavi Renk Modeli (Colors.blue)
  Color _wordColor = Colors.black;
  // O anki kelimenin ait olduğu doğru renk referansı (karşılaştırma için)
  String _correctColorName = "";

  bool _askForTextColor = true;
  String _targetAnswerName = "";
  List<Map<String, dynamic>> _shuffledButtons = [];

  final List<Map<String, dynamic>> _gameColors = [
    {'name': 'KIRMIZI', 'color': Colors.redAccent},
    {'name': 'MAVİ', 'color': Colors.blueAccent},
    {'name': 'SARI', 'color': Colors.yellowAccent},
    {'name': 'YEŞİL', 'color': Colors.greenAccent},
  ];

  @override
  void initState() {
    super.initState();
    _currentDifficulty = widget.difficulty;
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);

    _applyDifficulty();
    _generateNextColorTrap();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  void _applyDifficulty() {
    // Zorluklara göre kaç kez doğru bilinmesi ve sınır şartları belirlenir
    if (_currentDifficulty == 'KOLAY') {
      _targetScore = 3;
    } else if (_currentDifficulty == 'ORTA') {
      _targetScore = 5;
    } else if (_currentDifficulty == 'ZOR') {
      _targetScore = 10;
    } else if (_currentDifficulty == 'CEHENNEM') {
      _targetScore = 20;
    }
    _currentScore = 0; // Başa dön
  }

  void _generateNextColorTrap() {
    final random = Random();

    // Rastgele yazılacak kelimeyi seç (örn: "YEŞİL")
    final textMap = _gameColors[random.nextInt(_gameColors.length)];
    _wordText = textMap['name'];

    // Rastgele rengi seç
    final colorMap = _gameColors[random.nextInt(_gameColors.length)];
    _wordColor = colorMap['color'];
    _correctColorName = colorMap['name'];

    // Zorluklara göre rastgele tuzaklar
    if (_currentDifficulty == 'KOLAY') {
      _askForTextColor = true;
    } else {
      _askForTextColor = random.nextBool(); // Bazen Metni sor, Bazen Rengi
    }

    _targetAnswerName = _askForTextColor ? _correctColorName : _wordText;

    // Butonları karıştırarak oluştur
    final List<Map<String, dynamic>> shuffledTexts = List.from(_gameColors);
    shuffledTexts.shuffle(random);

    final List<Color> shuffledColors = _gameColors
        .map((e) => e['color'] as Color)
        .toList();
    if (_currentDifficulty == 'ZOR' || _currentDifficulty == 'CEHENNEM') {
      shuffledColors.shuffle(
        random,
      ); // Renkler kelimelerden tamamen koparılıp beyni yakar!
    }

    _shuffledButtons = [];
    for (int i = 0; i < 4; i++) {
      _shuffledButtons.add({
        'name': shuffledTexts[i]['name'],
        'color':
            (_currentDifficulty == 'ZOR' || _currentDifficulty == 'CEHENNEM')
            ? shuffledColors[i]
            : shuffledTexts[i]['color'], // Kolay ve Orta'da uyumlu
      });
    }

    setState(() {});
  }

  void _onColorTapped(String selectedColorName) {
    if (selectedColorName == _targetAnswerName) {
      // Doğru!
      setState(() {
        _currentScore++;
      });
      if (_currentScore >= _targetScore) {
        // Oyun bitti, alarm kapandı.
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'DOĞRU! ALARM KAPATILDI.',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      } else {
        // Sıradaki
        _generateNextColorTrap();
      }
    } else {
      // Yanlış cevap! Başa sar. (Acımasız ama etkili)
      setState(() {
        _currentScore = 0;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'YANLIŞ RENK! EN BAŞA DÖNDÜN.',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          backgroundColor: Colors.red,
          duration: Duration(milliseconds: 1500),
        ),
      );
      _generateNextColorTrap();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    // Alarm Ekranına Özel Çok Dikkat Çekici Bir Arka Plan
    final bgColor = isDarkMode
        ? const Color(0xFF1a0000)
        : const Color(0xFFFFEBEE);

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
              _buildGameContent(isDarkMode),
              const Spacer(),
              _buildColorButtons(isDarkMode),
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
            color: Colors.pinkAccent,
            border: Border.all(color: Colors.black, width: 3),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Text(
            'RENK TUZAĞI',
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

  Widget _buildGameContent(bool isDarkMode) {
    final textColor = isDarkMode ? Colors.white : Colors.black;
    final shadowColor = isDarkMode ? AppColors.shadowDark : AppColors.shadow;
    final borderColor = isDarkMode ? AppColors.borderDark : AppColors.border;

    String instructionMsg = _askForTextColor
        ? 'YAZININ RENGİNİ BUL!'
        : 'YAZAN KELİMEYİ BUL!';

    return Column(
      children: [
        Text(
          instructionMsg,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w900,
            color: _askForTextColor ? Colors.redAccent : Colors.lightBlueAccent,
            letterSpacing: 1,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'DİKKAT: Her zaman sadece butonun içindeki YAZIYI seçeceksin!',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w900,
            color: textColor.withValues(alpha: 0.5),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'İlerleme: $_currentScore / $_targetScore',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w900,
            color: textColor.withValues(alpha: 0.7),
          ),
        ),
        const SizedBox(height: 48),
        // Ana Odak (Focus)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
          decoration: BoxDecoration(
            color: isDarkMode ? AppColors.surfaceDark : Colors.white,
            border: Border.all(color: borderColor, width: 4),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(color: shadowColor, offset: const Offset(6, 6)),
            ],
          ),
          child: Text(
            _wordText,
            textAlign: TextAlign.center,
            style: GoogleFonts.jersey10(
              fontSize: 80,
              fontWeight: FontWeight.w400,
              color: _wordColor, // KELİMENİN YAZILDIĞI GERÇEK RENK
              height: 1.0,
              letterSpacing: 4,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildColorButtons(bool isDarkMode) {
    if (_shuffledButtons.isEmpty) return const SizedBox.shrink();

    final shadowColor = isDarkMode ? AppColors.shadowDark : AppColors.shadow;
    final borderColor = isDarkMode ? AppColors.borderDark : AppColors.border;

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _ColorButton(
                colorData: _shuffledButtons[0],
                borderColor: borderColor,
                shadowColor: shadowColor,
                onTap: () => _onColorTapped(_shuffledButtons[0]['name']),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _ColorButton(
                colorData: _shuffledButtons[1],
                borderColor: borderColor,
                shadowColor: shadowColor,
                onTap: () => _onColorTapped(_shuffledButtons[1]['name']),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _ColorButton(
                colorData: _shuffledButtons[2],
                borderColor: borderColor,
                shadowColor: shadowColor,
                onTap: () => _onColorTapped(_shuffledButtons[2]['name']),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _ColorButton(
                colorData: _shuffledButtons[3],
                borderColor: borderColor,
                shadowColor: shadowColor,
                onTap: () => _onColorTapped(_shuffledButtons[3]['name']),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ColorButton extends StatefulWidget {
  final Map<String, dynamic> colorData;
  final Color borderColor;
  final Color shadowColor;
  final VoidCallback onTap;

  const _ColorButton({
    required this.colorData,
    required this.borderColor,
    required this.shadowColor,
    required this.onTap,
  });

  @override
  State<_ColorButton> createState() => _ColorButtonState();
}

class _ColorButtonState extends State<_ColorButton> {
  bool _isPressed = false;

  void _handleTapDown(TapDownDetails details) {
    setState(() {
      _isPressed = true;
    });
  }

  void _handleTapUp(TapUpDetails details) {
    setState(() {
      _isPressed = false;
    });
    Future.delayed(const Duration(milliseconds: 50), widget.onTap);
  }

  void _handleTapCancel() {
    setState(() {
      _isPressed = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    const double shadowOffset = 6.0;

    return GestureDetector(
      onTapDown: _handleTapDown,
      onTapUp: _handleTapUp,
      onTapCancel: _handleTapCancel,
      child: SizedBox(
        height: 84 + shadowOffset,
        child: Stack(
          children: [
            Positioned(
              left: shadowOffset,
              top: shadowOffset,
              right: 0,
              bottom: 0,
              child: Container(
                decoration: BoxDecoration(
                  color: widget.shadowColor,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: widget.borderColor, width: 3),
                ),
              ),
            ),
            AnimatedPositioned(
              duration: const Duration(milliseconds: 100),
              curve: Curves.fastOutSlowIn,
              left: _isPressed ? shadowOffset : 0,
              top: _isPressed ? shadowOffset : 0,
              right: _isPressed ? 0 : shadowOffset,
              bottom: _isPressed ? 0 : shadowOffset,
              child: Container(
                decoration: BoxDecoration(
                  color: widget.colorData['color'],
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: widget.borderColor, width: 3),
                ),
                child: Center(
                  child: Text(
                    widget.colorData['name'],
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: Colors.black, // Zıtlık için hep siyah
                      letterSpacing: 1.5,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
