import 'package:flutter/material.dart';

import '../models/app_branding.dart';

class BootstrapAdminUi {
  static const Color pageBackground = Color(0xFFF5F7FB);
  static const Color panelBackground = Colors.white;
  static const Color panelBorder = Color(0xFFC1D0DB);
  static const Color ink = Color(0xFF22303A);
  static const Color muted = Color(0xFF6B7B8C);

  static ThemeData buildTheme(
    ThemeData base, {
    required Color accentColor,
  }) {
    final outline = panelBorder;

    return base.copyWith(
      scaffoldBackgroundColor: pageBackground,
      dividerColor: outline,
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        labelStyle: const TextStyle(
          color: muted,
          fontWeight: FontWeight.w600,
        ),
        hintStyle: TextStyle(
          color: muted.withValues(alpha: 0.88),
          fontWeight: FontWeight.w500,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: accentColor, width: 1.4),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: accentColor,
          side: BorderSide(color: accentColor.withValues(alpha: 0.28)),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accentColor,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accentColor,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: accentColor,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  static BoxDecoration surfaceCard({
    Color? borderColor,
    Color? shadowColor,
    Color backgroundColor = panelBackground,
    double radius = 24,
  }) {
    return BoxDecoration(
      color: backgroundColor,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: borderColor ?? panelBorder),
      boxShadow: [
        BoxShadow(
          color: (shadowColor ?? Colors.black).withValues(alpha: 0.08),
          blurRadius: 24,
          offset: const Offset(0, 12),
        ),
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.03),
          blurRadius: 6,
          offset: const Offset(0, 2),
        ),
      ],
    );
  }

  static BoxDecoration softAccentCard(
    Color accentColor, {
    double radius = 18,
  }) {
    return BoxDecoration(
      color: accentColor.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: accentColor.withValues(alpha: 0.24)),
    );
  }
}

class BootstrapAdminHero extends StatelessWidget {
  const BootstrapAdminHero({
    super.key,
    required this.branding,
    required this.icon,
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    this.trailing,
    this.footer,
  });

  final AppBranding branding;
  final IconData icon;
  final String eyebrow;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 980;
        final iconSize = compact ? 60.0 : 72.0;
        final heroCopy = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: Colors.white38),
              ),
              child: Text(
                eyebrow,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ),
            const SizedBox(height: 18),
            if (compact) ...[
              Container(
                width: iconSize,
                height: iconSize,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: Colors.white38),
                ),
                child: Icon(
                  icon,
                  color: Colors.white,
                  size: 30,
                ),
              ),
              const SizedBox(height: 16),
              _HeroCopyBlock(
                title: title,
                subtitle: subtitle,
                footer: footer,
                compact: compact,
              ),
            ] else
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: iconSize,
                    height: iconSize,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: Colors.white38),
                    ),
                    child: Icon(
                      icon,
                      color: Colors.white,
                      size: 34,
                    ),
                  ),
                  const SizedBox(width: 18),
                  Expanded(
                    child: _HeroCopyBlock(
                      title: title,
                      subtitle: subtitle,
                      footer: footer,
                      compact: compact,
                    ),
                  ),
                ],
              ),
          ],
        );

        return Container(
          width: double.infinity,
          padding: EdgeInsets.all(compact ? 22 : 28),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                branding.primaryDark,
                branding.primary,
                branding.primary.withValues(alpha: 0.84),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: branding.primary.withValues(alpha: 0.18),
                blurRadius: 26,
                offset: const Offset(0, 14),
              ),
            ],
          ),
          child: compact
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    heroCopy,
                    if (trailing != null) ...[
                      const SizedBox(height: 18),
                      trailing!,
                    ],
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 3, child: heroCopy),
                    if (trailing != null) ...[
                      const SizedBox(width: 20),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 320),
                        child: trailing!,
                      ),
                    ],
                  ],
                ),
        );
      },
    );
  }
}

class _HeroCopyBlock extends StatelessWidget {
  const _HeroCopyBlock({
    required this.title,
    required this.subtitle,
    required this.footer,
    required this.compact,
  });

  final String title;
  final String subtitle;
  final Widget? footer;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: Colors.white,
            fontSize: compact ? 28 : 36,
            fontWeight: FontWeight.w800,
            height: 1.05,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          subtitle,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.92),
            fontSize: 14,
            height: 1.55,
            fontWeight: FontWeight.w500,
          ),
        ),
        if (footer != null) ...[
          const SizedBox(height: 16),
          footer!,
        ],
      ],
    );
  }
}

class BootstrapAdminSectionHeading extends StatelessWidget {
  const BootstrapAdminSectionHeading({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    required this.accentColor,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BootstrapAdminUi.softAccentCard(accentColor),
              child: Icon(icon, color: accentColor, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  color: BootstrapAdminUi.ink,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 8),
          Text(
            subtitle!,
            style: const TextStyle(
              color: BootstrapAdminUi.muted,
              fontSize: 13,
              height: 1.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ],
    );
  }
}

class BootstrapAdminAlertBar extends StatelessWidget {
  const BootstrapAdminAlertBar({
    super.key,
    required this.icon,
    required this.message,
    required this.accentColor,
    this.backgroundColor,
  });

  final IconData icon;
  final String message;
  final Color accentColor;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: backgroundColor ?? accentColor.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accentColor.withValues(alpha: 0.40)),
      ),
      child: Row(
        children: [
          Icon(icon, color: accentColor, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: accentColor,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
