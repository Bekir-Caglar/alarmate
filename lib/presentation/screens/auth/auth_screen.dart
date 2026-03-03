import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../../../core/theme/app_colors.dart';
import '../../components/primary_button.dart';
import 'create_profile_screen.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final TextEditingController _phoneController = TextEditingController();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final DatabaseReference _db = FirebaseDatabase.instance.ref();

  bool _isCodeSent = false;
  bool _isLoading = false;
  String? _verificationId;

  Future<void> _login() async {
    if (_phoneController.text.trim().isEmpty) return;

    if (!_isCodeSent) {
      await _sendSmsCode();
    } else {
      await _verifySmsCode();
    }
  }

  Future<void> _sendSmsCode() async {
    setState(() => _isLoading = true);

    // Turkish phone format assumption (requires +90)
    String phone = _phoneController.text.trim();
    if (!phone.startsWith('+')) {
      if (phone.startsWith('0')) {
        phone = '+90${phone.substring(1)}';
      } else {
        phone = '+90$phone';
      }
    }

    try {
      await _auth.verifyPhoneNumber(
        phoneNumber: phone,
        verificationCompleted: (PhoneAuthCredential credential) async {
          // Auto-resolution (rarely triggers on iOS, but good for Android)
          await _signInWithCredential(credential);
        },
        verificationFailed: (FirebaseAuthException e) {
          setState(() => _isLoading = false);
          _showError(e.message ?? 'Doğrulama başarısız oldu.');
        },
        codeSent: (String verificationId, int? resendToken) {
          setState(() {
            _verificationId = verificationId;
            _isCodeSent = true;
            _isLoading = false;
            _phoneController.clear(); // Clear for SMS code
          });
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          _verificationId = verificationId;
        },
      );
    } catch (e) {
      setState(() => _isLoading = false);
      _showError(e.toString());
    }
  }

  Future<void> _verifySmsCode() async {
    final smsCode = _phoneController.text.trim();
    if (smsCode.isEmpty || _verificationId == null) return;

    setState(() => _isLoading = true);

    try {
      PhoneAuthCredential credential = PhoneAuthProvider.credential(
        verificationId: _verificationId!,
        smsCode: smsCode,
      );
      await _signInWithCredential(credential);
    } on FirebaseAuthException catch (e) {
      setState(() => _isLoading = false);
      _showError('Hatalı SMS kodu veya süre doldu.');
    } catch (e) {
      setState(() => _isLoading = false);
      _showError(e.toString());
    }
  }

  Future<void> _signInWithCredential(AuthCredential credential) async {
    try {
      UserCredential userCredential = await _auth.signInWithCredential(
        credential,
      );
      await _checkAndRouteUser(userCredential.user);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showError('Giriş başarısız oldu.');
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() => _isLoading = true);
    try {
      final GoogleSignInAccount? googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) {
        if (!mounted) return;
        setState(() => _isLoading = false);
        return;
      }
      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      await _signInWithCredential(credential);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showError('Google ile giriş başarısız oldu.');
    }
  }

  Future<void> _signInWithApple() async {
    setState(() => _isLoading = true);
    try {
      final appleProvider = AppleAuthProvider();
      final userCredential = await _auth.signInWithProvider(appleProvider);
      await _checkAndRouteUser(userCredential.user);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showError(
        'Apple ile giriş başarısız oldu. Cihazınız desteklemiyor olabilir.',
      );
    }
  }

  Future<void> _checkAndRouteUser(User? user) async {
    if (user != null) {
      final snapshot = await _db.child('users').child(user.uid).get();

      if (!mounted) return;

      if (snapshot.exists) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      } else {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const CreateProfileScreen()),
        );
      }
    } else {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(
            fontWeight: FontWeight.w900,
            color: Colors.white,
          ),
        ),
        backgroundColor: Colors.red,
      ),
    );
  }

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final shadowColor = isDarkMode ? AppColors.shadowDark : AppColors.shadow;
    final borderColor = isDarkMode ? AppColors.borderDark : AppColors.border;
    final titleColor = isDarkMode
        ? AppColors.textDarkPrimary
        : AppColors.textPrimary;
    final subTitleColor = isDarkMode
        ? AppColors.textDarkSecondary
        : AppColors.textSecondary;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _AuthGridBackgroundPainter(
                color: isDarkMode
                    ? Colors.white.withValues(alpha: 0.05)
                    : AppColors.textPrimary.withValues(alpha: 0.05),
              ),
            ),
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.only(
                        left: 24.0,
                        right: 24.0,
                        top: 48.0,
                        bottom: 24.0,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          // === ÜST KISIM: Başlık + Input ===
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const SizedBox(height: 16),
                              Text(
                                'OYUNCU\nGİRİŞİ',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 48,
                                  fontWeight: FontWeight.w900,
                                  color: titleColor,
                                  height: 1.0,
                                  letterSpacing: -2,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                _isCodeSent
                                    ? 'TELEFONUNUZA GELEN 6 HANELI KODU GİRİN.'
                                    : 'ARKADAŞLARININ SENİ UYANDIRABİLMESİ İÇİN NUMARANI GİRMELİSİN.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w900,
                                  color: subTitleColor,
                                ),
                              ),
                              const SizedBox(height: 48),
                              _buildBrutalistTextField(
                                controller: _phoneController,
                                hintText: _isCodeSent
                                    ? '123456'
                                    : '5XX XXX XX XX',
                                icon: _isCodeSent
                                    ? Icons.sms_rounded
                                    : Icons.phone_android_rounded,
                                isDarkMode: isDarkMode,
                                keyboardType: _isCodeSent
                                    ? TextInputType.number
                                    : TextInputType.phone,
                              ),
                              const SizedBox(height: 24),
                              BlinkingAuthText(
                                text: 'SMS KODU GÖNDERİLECEK_',
                                color: titleColor,
                              ),
                            ],
                          ),

                          // === ALT KISIM: Butonlar ===
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const SizedBox(height: 32),
                              PrimaryButton(
                                text: _isLoading
                                    ? 'BEKLEYIN...'
                                    : (_isCodeSent
                                          ? 'DOĞRULA VE GİRİŞ YAP'
                                          : 'BAĞLAN'),
                                onPressed: _isLoading ? () {} : _login,
                              ),
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  Expanded(
                                    child: Divider(
                                      color: shadowColor,
                                      thickness: 3,
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16.0,
                                    ),
                                    child: Text(
                                      'VEYA',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w900,
                                        color: titleColor,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: Divider(
                                      color: shadowColor,
                                      thickness: 3,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  Expanded(
                                    child: PrimaryButton(
                                      text: 'GOOGLE',
                                      icon: Icons.g_mobiledata_rounded,
                                      color: Colors.white,
                                      onPressed: _isLoading
                                          ? () {}
                                          : _signInWithGoogle,
                                    ),
                                  ),
                                  if (Platform.isIOS) ...[
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: PrimaryButton(
                                        text: 'APPLE',
                                        icon: Icons.apple_rounded,
                                        color: isDarkMode
                                            ? Colors.white24
                                            : Colors.black,
                                        onPressed: _isLoading
                                            ? () {}
                                            : _signInWithApple,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBrutalistTextField({
    required TextEditingController controller,
    required String hintText,
    required IconData icon,
    required bool isDarkMode,
    TextInputType keyboardType = TextInputType.text,
  }) {
    final shadowColor = isDarkMode ? AppColors.shadowDark : AppColors.shadow;
    final borderColor = isDarkMode ? AppColors.borderDark : AppColors.border;
    final inputBg = isDarkMode ? AppColors.surfaceDark : Colors.white;
    final textColor = isDarkMode
        ? AppColors.textDarkPrimary
        : AppColors.textPrimary;
    const double shadowOffset = 6.0;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          top: shadowOffset,
          left: shadowOffset,
          right: -shadowOffset,
          bottom: -shadowOffset,
          child: Container(
            decoration: BoxDecoration(
              color: shadowColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: borderColor, width: 3),
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: inputBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderColor, width: 3),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border(
                    right: BorderSide(color: borderColor, width: 3),
                  ),
                  color: AppColors.primaryLight,
                ),
                child: Icon(icon, color: AppColors.textPrimary),
              ),
              Expanded(
                child: TextField(
                  controller: controller,
                  keyboardType: keyboardType,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: textColor,
                    letterSpacing: 2,
                  ),
                  decoration: InputDecoration(
                    hintText: hintText,
                    hintStyle: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: textColor.withValues(alpha: 0.3),
                      letterSpacing: 2,
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 20,
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
}

class BlinkingAuthText extends StatefulWidget {
  final String text;
  final Color color;
  const BlinkingAuthText({super.key, required this.text, required this.color});

  @override
  State<BlinkingAuthText> createState() => _BlinkingAuthTextState();
}

class _BlinkingAuthTextState extends State<BlinkingAuthText>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _controller,
      child: Text(
        widget.text,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w900,
          color: widget.color,
          letterSpacing: 1.5,
        ),
      ),
    );
  }
}

class _AuthGridBackgroundPainter extends CustomPainter {
  final Color color;
  _AuthGridBackgroundPainter({required this.color});

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
