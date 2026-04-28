import 'package:flutter/material.dart';

import '../../config/app_config.dart';
import '../../models/app_branding.dart';

class RRHHSedeOption {
  const RRHHSedeOption({
    required this.sedeId,
    required this.icon,
  });

  final String sedeId;
  final IconData icon;

  AppBranding get branding => AppBranding.fromSedeId(sedeId);
  String get title => sedeId == SedeAccess.matrizId
      ? 'Sede Matriz'
      : SedeAccess.displayNameForId(sedeId);
}

const List<RRHHSedeOption> rrhhSedeOptions = [
  RRHHSedeOption(
    sedeId: SedeAccess.matrizId,
    icon: Icons.account_balance_outlined,
  ),
  RRHHSedeOption(
    sedeId: SedeAccess.sedeNorteId,
    icon: Icons.spa_outlined,
  ),
  RRHHSedeOption(
    sedeId: SedeAccess.sedeCentroId,
    icon: Icons.location_city_outlined,
  ),
  RRHHSedeOption(
    sedeId: SedeAccess.sedeCreSerId,
    icon: Icons.school_outlined,
  ),
];

class RRHHSedeSelectorPage extends StatelessWidget {
  const RRHHSedeSelectorPage({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onSelected,
    this.allowedSedeIds = const [],
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final ValueChanged<RRHHSedeOption> onSelected;
  final List<String> allowedSedeIds;

  @override
  Widget build(BuildContext context) {
    final branding = AppBranding.matriz;
    final opcionesVisibles = allowedSedeIds.isEmpty
        ? rrhhSedeOptions
        : rrhhSedeOptions
            .where((option) => allowedSedeIds.contains(option.sedeId))
            .toList();
    return Scaffold(
      backgroundColor: branding.background,
      body: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    branding.background,
                    branding.surface,
                    branding.softAccent.withOpacity(0.7),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  const spacing = 92.0;
                  final cols = (constraints.maxWidth / spacing).ceil() + 1;
                  final rows = (constraints.maxHeight / spacing).ceil() + 1;

                  return Opacity(
                    opacity: 0.08,
                    child: Stack(
                      children: List.generate(rows * cols, (index) {
                        final row = index ~/ cols;
                        final col = index % cols;
                        final offsetX = row.isEven ? 0.0 : spacing / 2;

                        return Positioned(
                          left: col * spacing + offsetX,
                          top: row * spacing,
                          child: Image.asset(
                            branding.logoSmall,
                            width: 42,
                            height: 42,
                            fit: BoxFit.contain,
                          ),
                        );
                      }),
                    ),
                  );
                },
              ),
            ),
          ),
          Positioned(
            right: -40,
            top: 150,
            child: IgnorePointer(
              child: Opacity(
                opacity: 0.11,
                child: Image.asset(
                  branding.logoWatermark,
                  width: 260,
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 26),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Align(
                    alignment: Alignment.topRight,
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () {
                          Navigator.pushReplacementNamed(context, '/login');
                        },
                        child: Ink(
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.18),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.35),
                            ),
                          ),
                          child: const Icon(
                            Icons.logout_rounded,
                            color: Colors.white,
                            size: 22,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildHero(),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.72),
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(color: Colors.white.withOpacity(0.85)),
                      boxShadow: [
                        BoxShadow(
                          color: branding.primary.withOpacity(0.08),
                          blurRadius: 18,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Selecciona una sede',
                          style: TextStyle(
                            fontSize: 21,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF22343D),
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Cada mosaico abre una vista separada solo para esa sede. El fondo y los bloques ahora priorizan mejor la lectura del nombre.',
                          style: TextStyle(
                            color: Color(0xFF5D6D76),
                            height: 1.45,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: opcionesVisibles.length,
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 14,
                      crossAxisSpacing: 14,
                      childAspectRatio: 0.72,
                    ),
                    itemBuilder: (context, index) {
                      final option = opcionesVisibles[index];
                      return _SedeCard(
                        option: option,
                        onTap: () => onSelected(option),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHero() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF426A6C), Color(0xFF5E8B8C)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF426A6C).withOpacity(0.18),
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.14),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(icon, color: Colors.white, size: 30),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.14),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    'Panel RRHH',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    height: 1.05,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.92),
                    height: 1.42,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SedeCard extends StatelessWidget {
  const _SedeCard({
    required this.option,
    required this.onTap,
  });

  final RRHHSedeOption option;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final branding = option.branding;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(26),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                branding.primaryDark,
                branding.primary,
                branding.primary.withOpacity(0.9),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(26),
            boxShadow: [
              BoxShadow(
                color: branding.primary.withOpacity(0.18),
                blurRadius: 18,
                offset: const Offset(0, 12),
              ),
            ],
          ),
            child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.14),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(
                        option.icon,
                        color: Colors.white,
                      ),
                    ),
                    const Spacer(),
                    const Icon(
                      Icons.arrow_forward_ios_rounded,
                      size: 18,
                      color: Colors.white70,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: Center(
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Container(
                          width: 92,
                          height: 92,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(28),
                          ),
                        ),
                        Opacity(
                          opacity: 0.26,
                          child: Image.asset(
                            branding.logoWatermark,
                            width: 86,
                            height: 86,
                            fit: BoxFit.contain,
                            errorBuilder: (context, error, stackTrace) =>
                                const SizedBox.shrink(),
                          ),
                        ),
                        Container(
                          width: 72,
                          height: 72,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(22),
                          ),
                          child: Image.asset(
                            branding.logoSmall,
                            fit: BoxFit.contain,
                            errorBuilder: (context, error, stackTrace) => Icon(
                              option.icon,
                              color: Colors.white,
                              size: 34,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: Colors.white.withOpacity(0.08)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        option.title,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          height: 1.15,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        branding.subtitle,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.82),
                          fontSize: 12,
                          height: 1.3,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
