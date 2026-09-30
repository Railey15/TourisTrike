import 'package:flutter/material.dart';

import 'maintenance_settings.dart';

class MaintenanceScreen extends StatelessWidget {
  const MaintenanceScreen({
    super.key,
    required this.settings,
    required this.onTryAgain,
    this.checking = false,
    this.onAdministratorAccess,
  });

  static const _logoUrl =
      'https://mvtqhsrdgtwdeootgjci.supabase.co/storage/v1/object/public/public-assets/maintenance_logo.png';

  final MaintenanceSettings settings;

  // Retained as part of the screen contract so maintenance polling and gate
  // integration remain backward compatible. The redesigned screen is static.
  final Future<void> Function() onTryAgain;
  final bool checking;
  final Future<void> Function()? onAdministratorAccess;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFF4F8FF),
      child: Stack(
        fit: StackFit.expand,
        children: [
          const _MaintenanceBackground(),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 520;
                final horizontalPadding = compact ? 18.0 : 32.0;
                final verticalPadding = compact ? 20.0 : 32.0;

                return SingleChildScrollView(
                  padding: EdgeInsets.symmetric(
                    horizontal: horizontalPadding,
                    vertical: verticalPadding,
                  ),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: (constraints.maxHeight - verticalPadding * 2)
                          .clamp(0, double.infinity),
                    ),
                    child: Center(
                      child: Semantics(
                        container: true,
                        label: 'TourisTrike is temporarily under maintenance',
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 680),
                          child: _MaintenanceCard(
                            settings: settings,
                            compact: compact,
                          ),
                        ),
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
}

class _MaintenanceCard extends StatelessWidget {
  const _MaintenanceCard({required this.settings, required this.compact});

  final MaintenanceSettings settings;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        compact ? 24 : 48,
        compact ? 30 : 44,
        compact ? 24 : 48,
        compact ? 32 : 46,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.97),
        borderRadius: BorderRadius.circular(compact ? 26 : 32),
        border: Border.all(color: const Color(0xFFDCE8F8)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x17102A56),
            blurRadius: 44,
            offset: Offset(0, 20),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _TourisTrikeLogo(compact: compact),
          SizedBox(height: compact ? 28 : 34),
          const _MaintenanceMark(),
          SizedBox(height: compact ? 22 : 26),
          Text(
            settings.title,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: const Color(0xFF102A56),
              fontSize: compact ? 29 : 38,
              height: 1.15,
              letterSpacing: compact ? -0.5 : -0.8,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 14),
          Container(
            width: 48,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFF2A86FF),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          SizedBox(height: compact ? 18 : 22),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Text(
              settings.message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: const Color(0xFF5E6F89),
                fontSize: compact ? 14.5 : 16,
                height: 1.65,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          SizedBox(height: compact ? 24 : 30),
          const _PatienceNote(),
        ],
      ),
    );
  }
}

class _TourisTrikeLogo extends StatelessWidget {
  const _TourisTrikeLogo({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final size = compact ? 126.0 : 148.0;
    return Semantics(
      image: true,
      label: 'TourisTrike logo',
      excludeSemantics: true,
      child: Container(
        width: size,
        height: size,
        padding: EdgeInsets.all(compact ? 13 : 15),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(compact ? 30 : 36),
          border: Border.all(color: const Color(0xFFE1ECFA)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x162A86FF),
              blurRadius: 28,
              offset: Offset(0, 12),
            ),
          ],
        ),
        child: Image.network(
          MaintenanceScreen._logoUrl,
          fit: BoxFit.contain,
          loadingBuilder: (context, child, progress) {
            if (progress == null) return child;
            return const Center(
              child: SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  color: Color(0xFF2A86FF),
                ),
              ),
            );
          },
          errorBuilder: (_, _, _) => const DecoratedBox(
            decoration: BoxDecoration(
              color: Color(0xFFEAF3FF),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Icon(
                Icons.electric_rickshaw_rounded,
                size: 58,
                color: Color(0xFF2A86FF),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MaintenanceMark extends StatelessWidget {
  const _MaintenanceMark();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFEAF4FF), Color(0xFFDCEBFF)],
        ),
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0xFFC9DEFA)),
      ),
      child: const Icon(
        Icons.construction_rounded,
        size: 34,
        color: Color(0xFF1769D2),
      ),
    );
  }
}

class _PatienceNote extends StatelessWidget {
  const _PatienceNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F6FD),
        borderRadius: BorderRadius.circular(999),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.favorite_outline_rounded,
            size: 17,
            color: Color(0xFF2A86FF),
          ),
          SizedBox(width: 8),
          Flexible(
            child: Text(
              'Thank you for your patience.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF315B8A),
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MaintenanceBackground extends StatelessWidget {
  const _MaintenanceBackground();

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFEAF3FF), Color(0xFFF7FAFF), Color(0xFFEDF7FF)],
          ),
        ),
        child: Stack(
          children: const [
            _GlowCircle(
              alignment: Alignment(-1.16, -1.08),
              size: 340,
              color: Color(0x182A86FF),
            ),
            _GlowCircle(
              alignment: Alignment(1.18, 1.06),
              size: 380,
              color: Color(0x1238BDF8),
            ),
            _GlowCircle(
              alignment: Alignment(1.12, -0.45),
              size: 190,
              color: Color(0x0D155EEF),
            ),
          ],
        ),
      ),
    );
  }
}

class _GlowCircle extends StatelessWidget {
  const _GlowCircle({
    required this.alignment,
    required this.size,
    required this.color,
  });

  final Alignment alignment;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
    );
  }
}
