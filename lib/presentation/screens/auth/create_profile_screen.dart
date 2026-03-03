import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../../../core/theme/app_colors.dart';
import '../../components/primary_button.dart';

class CreateProfileScreen extends StatefulWidget {
  const CreateProfileScreen({super.key});

  @override
  State<CreateProfileScreen> createState() => _CreateProfileScreenState();
}

class _CreateProfileScreenState extends State<CreateProfileScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();

  bool _isLoading = false;

  Future<void> _saveProfile() async {
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'BİR KULLANICI ADI GİRMELİSİN!',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final bool needsPhone =
            user.phoneNumber == null || user.phoneNumber!.isEmpty;
        if (needsPhone && _phoneController.text.trim().isEmpty) {
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'LÜTFEN BİR TELEFON NUMARASI GİRİN!',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          );
          return;
        }

        final String finalUsername = _nameController.text.trim().toUpperCase();
        String finalPhone = needsPhone
            ? _phoneController.text.trim()
            : user.phoneNumber!;

        // +90 ön ekini ekle (kullanıcı yazmadıysa)
        if (needsPhone && !finalPhone.startsWith('+')) {
          finalPhone = '+90$finalPhone';
        }

        final DatabaseReference dbRef = FirebaseDatabase.instance.ref();

        // === Nick benzersizlik kontrolü ===
        final usernameEvent = await dbRef
            .child('users')
            .orderByChild('username')
            .equalTo(finalUsername)
            .once();

        if (usernameEvent.snapshot.exists) {
          final otherUsers = usernameEvent.snapshot.children.where(
            (child) => child.key != user.uid,
          );
          if (otherUsers.isNotEmpty) {
            setState(() => _isLoading = false);
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'BU KULLANICI ADI ZATEN ALINMIŞ!',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
                backgroundColor: Colors.red,
              ),
            );
            return;
          }
        }

        // === Telefon benzersizlik kontrolü ===
        final phoneEvent = await dbRef
            .child('users')
            .orderByChild('phone')
            .equalTo(finalPhone)
            .once();

        if (phoneEvent.snapshot.exists) {
          final otherUsers = phoneEvent.snapshot.children.where(
            (child) => child.key != user.uid,
          );
          if (otherUsers.isNotEmpty) {
            setState(() => _isLoading = false);
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'BU TELEFON NUMARASI ZATEN KAYITLI!',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
                backgroundColor: Colors.red,
              ),
            );
            return;
          }
        }

        // === Kaydet ===
        await dbRef.child('users').child(user.uid).set({
          'username': finalUsername,
          'phone': finalPhone,
          'createdAt': ServerValue.timestamp,
        });
      }

      if (!mounted) return;

      // Navigate to Home by popping back to AuthWrapper
      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (e, stackTrace) {
      debugPrint('=== KAYIT HATASI ===');
      debugPrint('Error: $e');
      debugPrint('StackTrace: $stackTrace');
      setState(() => _isLoading = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Kayıt Başarısız: $e',
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              color: Colors.white,
            ),
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _signOutAndGoBack() async {
    await GoogleSignIn().signOut();
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  void dispose() {
    _nameController.dispose();
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

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _signOutAndGoBack();
      },
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _ProfileGridBackgroundPainter(
                  color: isDarkMode
                      ? Colors.white.withValues(alpha: 0.05)
                      : AppColors.textPrimary.withValues(alpha: 0.05),
                ),
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Spacer(),

                    // Avatar Pick (Placeholder)
                    Center(
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Container(
                            width: 120,
                            height: 120,
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              shape: BoxShape.circle,
                              border: Border.all(color: borderColor, width: 4),
                              boxShadow: [
                                BoxShadow(
                                  color: shadowColor,
                                  offset: const Offset(6, 6),
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.person,
                              size: 64,
                              color: Colors.white,
                            ),
                          ),
                          Positioned(
                            bottom: 0,
                            right: -10,
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.yellowAccent,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: borderColor,
                                  width: 3,
                                ),
                              ),
                              child: const Icon(
                                Icons.camera_alt_rounded,
                                color: AppColors.textPrimary,
                                size: 24,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 48),

                    // Title
                    Text(
                      'KİMLİĞİNİ\nOLUŞTUR',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 40,
                        fontWeight: FontWeight.w900,
                        color: titleColor,
                        height: 1.0,
                        letterSpacing: -2,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'ARKADAŞLARIN SENİ BURADAN TANIYACAK.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        color: subTitleColor,
                      ),
                    ),
                    const SizedBox(height: 48),

                    // Brutalist TextField (Username)
                    _buildBrutalistTextField(
                      controller: _nameController,
                      hintText: 'KULLANICI ADI',
                      icon: Icons.badge_rounded,
                      isDarkMode: isDarkMode,
                    ),

                    if (FirebaseAuth.instance.currentUser?.phoneNumber ==
                            null ||
                        FirebaseAuth
                            .instance
                            .currentUser!
                            .phoneNumber!
                            .isEmpty) ...[
                      const SizedBox(height: 24),
                      _buildBrutalistTextField(
                        controller: _phoneController,
                        hintText: 'TELEFON (ÖR: +90532...)',
                        icon: Icons.phone_rounded,
                        isDarkMode: isDarkMode,
                        keyboardType: TextInputType.phone,
                      ),
                    ],

                    const Spacer(),

                    PrimaryButton(
                      text: _isLoading
                          ? 'KAYDEDİLİYOR...'
                          : 'PROFİLİ KAYDET VE BAŞLA',
                      onPressed: _isLoading ? () {} : _saveProfile,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBrutalistTextField({
    required TextEditingController controller,
    required String hintText,
    required IconData icon,
    required bool isDarkMode,
    TextInputType keyboardType = TextInputType.name,
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
                  textCapitalization: TextCapitalization.characters,
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

class _ProfileGridBackgroundPainter extends CustomPainter {
  final Color color;
  _ProfileGridBackgroundPainter({required this.color});

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
