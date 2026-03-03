import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_colors.dart';
import '../../components/primary_button.dart';

class MathMissionScreen extends StatefulWidget {
  final String difficulty;

  const MathMissionScreen({super.key, required this.difficulty});

  @override
  State<MathMissionScreen> createState() => _MathMissionScreenState();
}

class _MathMissionScreenState extends State<MathMissionScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;

  // Math Mission specific state
  int _num1 = 0;
  int _num2 = 0;
  String _operator = '+';
  String _userInput = '';
  int _correctAnswer = 0;

  // Debug toggle for demo purposes
  late String _currentDifficulty;

  @override
  void initState() {
    super.initState();
    _currentDifficulty = widget.difficulty;
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);

    _generateMathQuestion();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  void _generateMathQuestion() {
    final random = Random();

    // Zorluklara göre işlem limitleri ve formatı
    if (_currentDifficulty == 'KOLAY') {
      _operator = random.nextBool() ? '+' : '-';
      _num1 = random.nextInt(20) + 10;
      _num2 = random.nextInt(20) + 10;
    } else if (_currentDifficulty == 'ORTA') {
      _operator = random.nextBool() ? '+' : '-';
      _num1 = random.nextInt(80) + 20; // 20 ile 100 arası
      _num2 = random.nextInt(80) + 20;
    } else if (_currentDifficulty == 'ZOR') {
      // Zor seviyede rastgele olarak küçük çarpmalar veya zor 3 haneli toplama/çıkarmalar gelebilir
      int opChoice = random.nextInt(3);
      if (opChoice == 0) {
        _operator = 'x';
        _num1 = random.nextInt(10) + 6; // 6 ile 15 arası çarpma (örn: 14x12)
        _num2 = random.nextInt(10) + 6;
      } else {
        _operator = opChoice == 1 ? '+' : '-';
        _num1 = random.nextInt(500) + 100; // 100 ile 600 arası
        _num2 = random.nextInt(400) + 50;
      }
    } else if (_currentDifficulty == 'CEHENNEM') {
      // Cehennem: Acımasızca Büyük x Orta çarpımlar veya devasa üç haneli çıkarma/toplama
      int opChoice = random.nextInt(3);
      if (opChoice == 0) {
        _operator = 'x';
        _num1 =
            random.nextInt(20) +
            15; // 15 ile 35 arası çarpım (34x19 gibi eziyet)
        _num2 = random.nextInt(15) + 5;
      } else {
        _operator = opChoice == 1 ? '+' : '-';
        _num1 = random.nextInt(900) + 100; // 100 ile 1000 arası eziyet
        _num2 = random.nextInt(900) + 100;
      }
    }

    // Çıkarmaysa eksi sonuç çıkmasını engellemek için büyüğü başa al
    if (_operator == '-') {
      if (_num1 < _num2) {
        final temp = _num1;
        _num1 = _num2;
        _num2 = temp;
      }
    }

    // Cevabı set et
    if (_operator == '+') _correctAnswer = _num1 + _num2;
    if (_operator == '-') _correctAnswer = _num1 - _num2;
    if (_operator == 'x') _correctAnswer = _num1 * _num2;

    setState(() {
      _userInput = '';
    });
  }

  void _onKeypadTap(String value) {
    setState(() {
      if (value == 'C') {
        if (_userInput.isNotEmpty) {
          _userInput = _userInput.substring(0, _userInput.length - 1);
        }
      } else {
        // En fazla 4 basamaklı olabilir
        if (_userInput.length < 4) {
          _userInput += value;
        }
      }
    });
  }

  void _checkAnswer() {
    if (_userInput.isEmpty) return;

    if (int.tryParse(_userInput) == _correctAnswer) {
      // Doğru cevap! Alarmı kapat
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'DOĞRU! ALARM KAPATILDI.',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pop(context); // Home'a dön
    } else {
      // Yanlış cevap! Temizle ve kızart
      setState(() {
        _userInput = '';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'YANLIŞ CEVAP! TEKRAR DENE.',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    // Alarm Ekranına Özel Çok Dikkat Çekici Bir Arka Plan (Solid Colors for true contrast)
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
              _buildMathContent(isDarkMode),
              // Diğer modlar buraya eklenecek (Renk, Salla vb.)
              const Spacer(),
              _buildKeypad(isDarkMode),
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
            color: Colors.yellowAccent,
            border: Border.all(color: Colors.black, width: 3),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Text(
            'MATEMATİK SINAVI',
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

  Widget _buildMathContent(bool isDarkMode) {
    final shadowColor = isDarkMode ? AppColors.shadowDark : AppColors.shadow;
    final borderColor = isDarkMode ? AppColors.borderDark : AppColors.border;
    final textColor = isDarkMode
        ? Colors.white
        : Colors.black; // Ensure high contrast over tinted background

    return Column(
      children: [
        Text(
          'Aşağıdaki işlemi çözmeden alarm susmayacak.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w900,
            color: textColor.withValues(alpha: 0.7),
          ),
        ),
        const SizedBox(height: 32),
        // İşlem Göstergesi
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '$_num1 $_operator $_num2 = ',
              style: GoogleFonts.jersey10(
                fontSize: 64,
                fontWeight: FontWeight.w400,
                color: textColor,
              ),
            ),
            Container(
              constraints: const BoxConstraints(minWidth: 80),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: isDarkMode ? AppColors.surfaceDark : Colors.white,
                border: Border.all(color: borderColor, width: 3),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(color: shadowColor, offset: const Offset(4, 4)),
                ],
              ),
              child: Text(
                _userInput.isEmpty ? '?' : _userInput,
                textAlign: TextAlign.center,
                style: GoogleFonts.jersey10(
                  fontSize: 64,
                  fontWeight: FontWeight.w400,
                  color: _userInput.isEmpty ? Colors.grey : AppColors.primary,
                  height: 1.1,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildKeypad(bool isDarkMode) {
    final buttons = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['C', '0', 'GO'],
    ];

    return Column(
      children: buttons.map((row) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 12.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: row.map((btn) {
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6.0),
                  child: _buildKeypadButton(btn, isDarkMode),
                ),
              );
            }).toList(),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildKeypadButton(String text, bool isDarkMode) {
    return _MathKeypadButton(
      text: text,
      isDarkMode: isDarkMode,
      onTap: () {
        if (text == 'GO') {
          _checkAnswer();
        } else {
          _onKeypadTap(text);
        }
      },
    );
  }
}

class _MathKeypadButton extends StatefulWidget {
  final String text;
  final bool isDarkMode;
  final VoidCallback onTap;

  const _MathKeypadButton({
    required this.text,
    required this.isDarkMode,
    required this.onTap,
  });

  @override
  State<_MathKeypadButton> createState() => _MathKeypadButtonState();
}

class _MathKeypadButtonState extends State<_MathKeypadButton> {
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
    // Ufak bir gecikme ekleyerek animasyon hissini hissettir
    Future.delayed(const Duration(milliseconds: 50), widget.onTap);
  }

  void _handleTapCancel() {
    setState(() {
      _isPressed = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isAction = widget.text == 'C' || widget.text == 'GO';
    Color bgColor = widget.isDarkMode ? AppColors.surfaceDark : Colors.white;
    Color textColor = widget.isDarkMode
        ? AppColors.textDarkPrimary
        : AppColors.textPrimary;

    if (widget.text == 'C') {
      bgColor = Colors.redAccent;
      textColor = Colors.white;
    } else if (widget.text == 'GO') {
      bgColor = Colors.greenAccent;
      textColor = Colors.black;
    }

    final shadowColor = widget.isDarkMode
        ? AppColors.shadowDark
        : AppColors.shadow;
    final borderColor = widget.isDarkMode
        ? AppColors.borderDark
        : AppColors.border;
    const double shadowOffset = 6.0;

    return GestureDetector(
      onTapDown: _handleTapDown,
      onTapUp: _handleTapUp,
      onTapCancel: _handleTapCancel,
      child: SizedBox(
        height: 72 + shadowOffset,
        child: Stack(
          children: [
            Positioned(
              left: shadowOffset,
              top: shadowOffset,
              right: 0,
              bottom: 0,
              child: Container(
                decoration: BoxDecoration(
                  color: shadowColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: borderColor, width: 3),
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
                  color: bgColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: borderColor, width: 3),
                ),
                child: Center(
                  child: widget.text == 'C'
                      ? Icon(
                          Icons.backspace_rounded,
                          color: textColor,
                          size: 24,
                        )
                      : Text(
                          widget.text,
                          style: TextStyle(
                            fontSize: isAction ? 20 : 28,
                            fontWeight: FontWeight.w900,
                            color: textColor,
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
