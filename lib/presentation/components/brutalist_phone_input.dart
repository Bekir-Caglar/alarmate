import 'package:flutter/material.dart';
import 'package:flutter_multi_formatter/flutter_multi_formatter.dart';
import '../../core/theme/app_colors.dart';

class BrutalistPhoneInput extends StatelessWidget {
  final TextEditingController controller;
  final bool isDarkMode;
  final bool isSmsMode;
  final String flagEmoji;
  final String dialCode;
  final VoidCallback onCountryTap;
  final String? hintText;

  const BrutalistPhoneInput({
    super.key,
    required this.controller,
    required this.isDarkMode,
    required this.isSmsMode,
    required this.flagEmoji,
    required this.dialCode,
    required this.onCountryTap,
    this.hintText,
  });

  @override
  Widget build(BuildContext context) {
    final border = isDarkMode ? AppColors.borderDark : AppColors.border;
    final shadow = isDarkMode ? AppColors.shadowDark : AppColors.shadow;
    final bg = isDarkMode ? AppColors.surfaceDark : Colors.white;
    final text = isDarkMode ? AppColors.textDarkPrimary : AppColors.textPrimary;

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border, width: 3),
        boxShadow: [
          BoxShadow(color: shadow, offset: const Offset(6, 6), blurRadius: 0),
        ],
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Mavi ülke kodu prefix
            GestureDetector(
              onTap: isSmsMode ? null : onCountryTap,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 18,
                ),
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  border: Border(right: BorderSide(color: border, width: 3)),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(9),
                    bottomLeft: Radius.circular(9),
                  ),
                ),
                child: isSmsMode
                    ? const Icon(
                        Icons.sms_rounded,
                        color: Colors.white,
                        size: 22,
                      )
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(flagEmoji, style: const TextStyle(fontSize: 20)),
                          const SizedBox(width: 6),
                          Text(
                            dialCode,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
              ),
            ),

            // Text field
            Expanded(
              child: TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                textAlignVertical: TextAlignVertical.center,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: text,
                  letterSpacing: 2,
                ),
                decoration: InputDecoration(
                  border: InputBorder.none,
                  hintText:
                      hintText ?? (isSmsMode ? 'X X X X X X' : '5XX XXX XX XX'),
                  hintStyle: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: text.withValues(alpha: 0.3),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 18,
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

class CountrySelectorSheet extends StatefulWidget {
  final List<PhoneCountryData> countries;
  final String selectedCode;
  final bool isDarkMode;
  final String Function(String) flagBuilder;
  final ValueChanged<PhoneCountryData> onSelect;

  const CountrySelectorSheet({
    super.key,
    required this.countries,
    required this.selectedCode,
    required this.isDarkMode,
    required this.flagBuilder,
    required this.onSelect,
  });

  @override
  State<CountrySelectorSheet> createState() => _CountrySelectorSheetState();
}

class _CountrySelectorSheetState extends State<CountrySelectorSheet> {
  final _searchCtrl = TextEditingController();
  List<PhoneCountryData> _filtered = [];

  @override
  void initState() {
    super.initState();
    _filtered = widget.countries;
    _searchCtrl.addListener(_onSearch);
  }

  void _onSearch() {
    final q = _searchCtrl.text.toLowerCase().trim();
    setState(() {
      _filtered = q.isEmpty
          ? widget.countries
          : widget.countries.where((c) {
              final name = (c.country ?? '').toLowerCase();
              final code = (c.phoneCode ?? '').toLowerCase();
              final iso = (c.countryCode ?? '').toLowerCase();
              return name.contains(q) || code.contains(q) || iso.contains(q);
            }).toList();
    });
  }

  @override
  void dispose() {
    _searchCtrl.removeListener(_onSearch);
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = widget.isDarkMode;
    final shadow = dark ? AppColors.shadowDark : AppColors.shadow;
    final border = dark ? AppColors.borderDark : AppColors.border;
    final bg = dark ? AppColors.surfaceDark : Colors.white;
    final titleC = dark ? AppColors.textDarkPrimary : AppColors.textPrimary;
    final inputBg = dark ? AppColors.backgroundDark : const Color(0xFFF5F5F5);

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(color: border, width: 3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: shadow.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Başlık
          Text(
            'Ülke Kodu',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w900,
              color: titleC,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 16),

          // Arama kutusu
          Container(
            decoration: BoxDecoration(
              color: inputBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: border, width: 2),
            ),
            child: TextField(
              controller: _searchCtrl,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: titleC,
              ),
              decoration: InputDecoration(
                hintText: 'Ülke adı veya kod ara...',
                hintStyle: TextStyle(
                  color: titleC.withValues(alpha: 0.4),
                  fontWeight: FontWeight.w600,
                ),
                prefixIcon: Icon(
                  Icons.search_rounded,
                  color: titleC.withValues(alpha: 0.5),
                ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Liste
          Expanded(
            child: _filtered.isEmpty
                ? Center(
                    child: Text(
                      'Sonuç bulunamadı',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: titleC.withValues(alpha: 0.4),
                      ),
                    ),
                  )
                : ListView.separated(
                    itemCount: _filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final c = _filtered[i];
                      final selected =
                          (c.countryCode ?? '') == widget.selectedCode;

                      return GestureDetector(
                        onTap: () {
                          widget.onSelect(c);
                          Navigator.pop(context);
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                          decoration: BoxDecoration(
                            color: selected ? AppColors.primary : bg,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: border, width: 2),
                            boxShadow: selected
                                ? [
                                    BoxShadow(
                                      color: shadow,
                                      offset: const Offset(4, 4),
                                    ),
                                  ]
                                : null,
                          ),
                          child: Row(
                            children: [
                              Text(
                                widget.flagBuilder(c.countryCode ?? ''),
                                style: const TextStyle(fontSize: 22),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  c.country ?? '',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w900,
                                    color: selected ? Colors.white : titleC,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Text(
                                '+${c.phoneCode ?? ''}',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w900,
                                  color: selected
                                      ? Colors.white
                                      : AppColors.primary,
                                ),
                              ),
                              if (selected) ...[
                                const SizedBox(width: 8),
                                const Icon(
                                  Icons.check_circle_rounded,
                                  color: Colors.white,
                                  size: 18,
                                ),
                              ],
                            ],
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
}
