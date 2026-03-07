import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter_multi_formatter/flutter_multi_formatter.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../../../core/theme/app_colors.dart';
import '../../components/primary_button.dart';
import '../../components/brutalist_phone_input.dart';
import 'create_profile_screen.dart';

// ─── Ana ekran ────────────────────────────────────────────────────────────────

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _phoneCtrl = TextEditingController();

  final _auth = FirebaseAuth.instance;
  final _db = FirebaseDatabase.instance.ref();

  bool _isCodeSent = false;
  bool _isLoading = false;
  String? _verificationId;

  // Başlangıç ülkesi: Türkiye, bulunamazsa ilk ülke
  PhoneCountryData _country =
      PhoneCodes.getPhoneCountryDataByCountryCode('TR') ??
      PhoneCodes.getAllCountryDatas().first;

  // ── Yardımcı ──────────────────────────────────────────────────────────────

  static String _flag(String iso) {
    if (iso.length != 2) return '🏳️';
    final base = 0x1F1E6 - 0x41;
    return String.fromCharCodes(
      iso.toUpperCase().codeUnits.map((c) => c + base),
    );
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          msg,
          style: const TextStyle(
            fontWeight: FontWeight.w900,
            color: Colors.white,
          ),
        ),
        backgroundColor: Colors.red,
      ),
    );
  }

  // ── Login akışı ───────────────────────────────────────────────────────────

  Future<void> _login() async {
    final text = _phoneCtrl.text.trim();
    if (text.isEmpty) return;
    _isCodeSent ? await _verifySms() : await _sendSms();
  }

  Future<void> _sendSms() async {
    final phone = '+${_country.phoneCode}${_phoneCtrl.text.trim()}';
    setState(() => _isLoading = true);
    try {
      await _auth.verifyPhoneNumber(
        phoneNumber: phone,
        verificationCompleted: (c) => _signIn(c),
        verificationFailed: (e) {
          setState(() => _isLoading = false);
          _showError(e.message ?? 'Doğrulama başarısız.');
        },
        codeSent: (id, _) => setState(() {
          _verificationId = id;
          _isCodeSent = true;
          _isLoading = false;
          _phoneCtrl.clear();
        }),
        codeAutoRetrievalTimeout: (id) => _verificationId = id,
      );
    } catch (e) {
      setState(() => _isLoading = false);
      _showError(e.toString());
    }
  }

  Future<void> _verifySms() async {
    if (_verificationId == null) return;
    setState(() => _isLoading = true);
    try {
      final cred = PhoneAuthProvider.credential(
        verificationId: _verificationId!,
        smsCode: _phoneCtrl.text.trim(),
      );
      await _signIn(cred);
    } on FirebaseAuthException {
      setState(() => _isLoading = false);
      _showError('Hatalı SMS kodu.');
    } catch (e) {
      setState(() => _isLoading = false);
      _showError(e.toString());
    }
  }

  Future<void> _signIn(AuthCredential cred) async {
    try {
      final result = await _auth.signInWithCredential(cred);
      await _route(result.user);
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
      _showError('Giriş başarısız.');
    }
  }

  Future<void> _route(User? user) async {
    if (user == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }
    final snap = await _db.child('users').child(user.uid).get();
    if (!mounted) return;
    if (snap.exists) {
      Navigator.of(context).popUntil((r) => r.isFirst);
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const CreateProfileScreen()),
      );
    }
  }

  Future<void> _googleSignIn() async {
    setState(() => _isLoading = true);
    try {
      final g = await GoogleSignIn().signIn();
      if (g == null) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }
      final ga = await g.authentication;
      final cred = GoogleAuthProvider.credential(
        accessToken: ga.accessToken,
        idToken: ga.idToken,
      );
      await _signIn(cred);
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
      _showError('Google ile giriş başarısız.');
    }
  }

  Future<void> _appleSignIn() async {
    setState(() => _isLoading = true);
    try {
      final r = await _auth.signInWithProvider(AppleAuthProvider());
      await _route(r.user);
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
      _showError('Apple ile giriş başarısız.');
    }
  }

  // ── Ülke seçici sheet ─────────────────────────────────────────────────────

  void _openCountrySheet(bool dark) {
    final all = PhoneCodes.getAllCountryDatas();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => CountrySelectorSheet(
        countries: all,
        selectedCode: _country.countryCode ?? '',
        isDarkMode: dark,
        flagBuilder: _flag,
        onSelect: (c) {
          setState(() {
            _country = c;
            _phoneCtrl.clear();
          });
        },
      ),
    );
  }

  // ── Dispose ───────────────────────────────────────────────────────────────

  @override
  void dispose() {
    _phoneCtrl.dispose();
    super.dispose();
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final shadowColor = dark ? AppColors.shadowDark : AppColors.shadow;
    final titleColor = dark ? AppColors.textDarkPrimary : AppColors.textPrimary;
    final subColor = dark
        ? AppColors.textDarkSecondary
        : AppColors.textSecondary;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Stack(
        children: [
          // Grid arka plan
          Positioned.fill(
            child: CustomPaint(
              painter: _GridPainter(
                color: dark
                    ? Colors.white.withValues(alpha: 0.05)
                    : AppColors.textPrimary.withValues(alpha: 0.05),
              ),
            ),
          ),

          SafeArea(
            child: LayoutBuilder(
              builder: (ctx, constraints) => SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 48, 24, 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // ── ÜST: Başlık + input ──────────────────────────
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
                                  ? 'TELEFONUNUZA GELEN 6 HANELİ KODU GİRİN.'
                                  : 'ARKADAŞLARININ SENİ UYANDIRABİLMESİ İÇİN NUMARANI GİRMELİSİN.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w900,
                                color: subColor,
                              ),
                            ),
                            const SizedBox(height: 48),

                            // ──── Telefon input alanı ────
                            BrutalistPhoneInput(
                              controller: _phoneCtrl,
                              isDarkMode: dark,
                              isSmsMode: _isCodeSent,
                              flagEmoji: _flag(_country.countryCode ?? ''),
                              dialCode: '+${_country.phoneCode ?? ''}',
                              onCountryTap: () => _openCountrySheet(dark),
                            ),

                            const SizedBox(height: 20),
                            _BlinkingText(
                              text: _isCodeSent
                                  ? 'KODU GİRİN_'
                                  : 'SMS KODU GÖNDERİLECEK_',
                              color: titleColor,
                            ),
                          ],
                        ),

                        // ── ALT: Butonlar ─────────────────────────────────
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const SizedBox(height: 32),
                            PrimaryButton(
                              text: _isLoading
                                  ? 'BEKLEYİN...'
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
                                    horizontal: 16,
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
                                    imageIcon: 'assets/google_logo.png',
                                    color: Colors.white,
                                    onPressed: _isLoading
                                        ? () {}
                                        : _googleSignIn,
                                  ),
                                ),
                                if (Platform.isIOS) ...[
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: PrimaryButton(
                                      text: 'APPLE',
                                      icon: Icons.apple_rounded,
                                      color: dark
                                          ? Colors.white24
                                          : Colors.black,
                                      onPressed: _isLoading
                                          ? () {}
                                          : _appleSignIn,
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
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Yanıp sönen metin ────────────────────────────────────────────────────────

class _BlinkingText extends StatefulWidget {
  final String text;
  final Color color;
  const _BlinkingText({required this.text, required this.color});

  @override
  State<_BlinkingText> createState() => _BlinkingTextState();
}

class _BlinkingTextState extends State<_BlinkingText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: _ctrl,
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

// ─── Grid arka plan ───────────────────────────────────────────────────────────

class _GridPainter extends CustomPainter {
  final Color color;
  const _GridPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 1.5;
    const s = 32.0;
    for (double x = 0; x < size.width; x += s)
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
    for (double y = 0; y < size.height; y += s)
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
  }

  @override
  bool shouldRepaint(_GridPainter old) => old.color != color;
}
