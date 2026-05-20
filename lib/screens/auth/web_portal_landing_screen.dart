import 'package:flutter/material.dart';

import 'city_admin_signup_screen.dart';
import 'web_portal_login_screen.dart';

class WebPortalLandingScreen extends StatelessWidget {
  const WebPortalLandingScreen({super.key});

  static const String logoUrl =
      'https://mvtqhsrdgtwdeootgjci.supabase.co/storage/v1/object/public/public-assets/Logo.png';

  void _openLogin(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const WebPortalLoginScreen()),
    );
  }

  void _openCityAdminSignup(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CityAdminSignupScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F9FF),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 920;

          return Stack(
            children: [
              const Positioned.fill(child: _PortalBackdrop()),
              SafeArea(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1180),
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: wide ? 42 : 20,
                        vertical: wide ? 28 : 18,
                      ),
                      child: Column(
                        children: [
                          _TopBar(
                            onLogin: () => _openLogin(context),
                            onApply: () => _openCityAdminSignup(context),
                          ),
                          Expanded(
                            child: Center(
                              child: SingleChildScrollView(
                                physics: const BouncingScrollPhysics(),
                                child: wide
                                    ? Row(
                                        children: [
                                          Expanded(
                                            flex: 11,
                                            child: _IntroPanel(
                                              onLogin: () =>
                                                  _openLogin(context),
                                            ),
                                          ),
                                          const SizedBox(width: 36),
                                          const Expanded(
                                            flex: 9,
                                            child: _PortalPreview(),
                                          ),
                                        ],
                                      )
                                    : Column(
                                        children: [
                                          _IntroPanel(
                                            onLogin: () => _openLogin(context),
                                            compact: true,
                                          ),
                                          const SizedBox(height: 24),
                                          const _PortalPreview(),
                                        ],
                                      ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.onLogin,
    required this.onApply,
  });

  final VoidCallback onLogin;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 640;

        final brand = Row(
          children: [
            Container(
              width: 48,
              height: 48,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.95),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFDCEBFF)),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF0F172A).withOpacity(0.06),
                    blurRadius: 18,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Image.network(
                WebPortalLandingScreen.logoUrl,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => const Icon(
                  Icons.electric_rickshaw_rounded,
                  color: Color(0xFF2563EB),
                ),
              ),
            ),
            const SizedBox(width: 13),
            const Expanded(
              child: Text(
                'TourisTrike Admin Portal',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Color(0xFF0F172A),
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.2,
                ),
              ),
            ),
          ],
        );

        final actions = Wrap(
          spacing: 10,
          runSpacing: 10,
          alignment: WrapAlignment.end,
          children: [
            OutlinedButton.icon(
              onPressed: onApply,
              icon: const Icon(Icons.location_city_rounded, size: 18),
              label: const Text('Apply as City Admin'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF0F766E),
                side: const BorderSide(color: Color(0xFFA7F3D0)),
                backgroundColor: Colors.white.withOpacity(0.86),
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 16,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
                textStyle: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 13,
                ),
              ),
            ),
            ElevatedButton.icon(
              onPressed: onLogin,
              icon: const Icon(Icons.login_rounded, size: 18),
              label: const Text('Sign In'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2563EB),
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 16,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
                textStyle: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        );

        if (compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              brand,
              const SizedBox(height: 14),
              Align(alignment: Alignment.centerRight, child: actions),
            ],
          );
        }

        return Row(
          children: [
            Expanded(child: brand),
            actions,
          ],
        );
      },
    );
  }
}

class _IntroPanel extends StatelessWidget {
  const _IntroPanel({
    required this.onLogin,
    this.compact = false,
  });

  final VoidCallback onLogin;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: compact ? Alignment.center : Alignment.centerLeft,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment:
            compact ? CrossAxisAlignment.center : CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.9),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: const Color(0xFFE2ECF8)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(width: 9),
                const Text(
                  'Web access for tourism administrators',
                  style: TextStyle(
                    color: Color(0xFF475569),
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 26),
          Text(
            'Manage Bulacan tourism operations from one secure portal.',
            textAlign: compact ? TextAlign.center : TextAlign.start,
            style: TextStyle(
              color: const Color(0xFF0F172A),
              fontSize: compact ? 36 : 52,
              height: 1.04,
              fontWeight: FontWeight.w900,
              letterSpacing: -1.4,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'Provincial and city tourism teams can review packages, manage destinations, monitor bookings, and coordinate local drivers from a clean desktop workspace.',
            textAlign: compact ? TextAlign.center : TextAlign.start,
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontSize: 16,
              height: 1.6,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 28),
          const Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _RoleTile(
                icon: Icons.account_balance_rounded,
                title: 'Main Tenant',
                body: 'Bulacan Provincial Tourism Office',
              ),
              _RoleTile(
                icon: Icons.location_city_rounded,
                title: 'Sub-Tenant',
                body: 'Approved city and municipal tourism offices',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RoleTile extends StatelessWidget {
  const _RoleTile({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 255,
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.92),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2ECF8)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withOpacity(0.045),
            blurRadius: 20,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFF2563EB).withOpacity(0.10),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(icon, color: const Color(0xFF2563EB), size: 23),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF0F172A),
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 12,
                    height: 1.3,
                    fontWeight: FontWeight.w600,
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

class _PortalPreview extends StatelessWidget {
  const _PortalPreview();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 480),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.94),
          borderRadius: BorderRadius.circular(32),
          border: Border.all(color: Colors.white),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF0F172A).withOpacity(0.08),
              blurRadius: 34,
              offset: const Offset(0, 24),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(17),
                    border: Border.all(color: const Color(0xFFDCEBFF)),
                  ),
                  child: Image.network(
                    WebPortalLandingScreen.logoUrl,
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) => const Icon(
                      Icons.dashboard_rounded,
                      color: Color(0xFF2563EB),
                    ),
                  ),
                ),
                const SizedBox(width: 13),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Operations Snapshot',
                        style: TextStyle(
                          color: Color(0xFF0F172A),
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      SizedBox(height: 3),
                      Text(
                        'Web dashboard preview',
                        style: TextStyle(
                          color: Color(0xFF64748B),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            const Row(
              children: [
                Expanded(
                  child: _MetricPreview(
                    label: 'Spots',
                    value: '128',
                    icon: Icons.place_rounded,
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: _MetricPreview(
                    label: 'Packages',
                    value: '42',
                    icon: Icons.inventory_2_rounded,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Row(
              children: [
                Expanded(
                  child: _MetricPreview(
                    label: 'Bookings',
                    value: '316',
                    icon: Icons.receipt_long_rounded,
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: _MetricPreview(
                    label: 'Drivers',
                    value: '89',
                    icon: Icons.badge_rounded,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            const _ProgressPreview(
              title: 'Published packages',
              value: '74%',
              progress: 0.74,
            ),
            const SizedBox(height: 13),
            const _ProgressPreview(
              title: 'Confirmed bookings',
              value: '61%',
              progress: 0.61,
            ),
            const SizedBox(height: 20),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: const Color(0xFFF4F8FF),
                borderRadius: BorderRadius.circular(19),
                border: Border.all(color: const Color(0xFFE2ECF8)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.shield_rounded, color: Color(0xFF16A34A)),
                  SizedBox(width: 11),
                  Expanded(
                    child: Text(
                      'Role-based access for provincial and city tourism offices',
                      style: TextStyle(
                        color: Color(0xFF475569),
                        fontWeight: FontWeight.w800,
                        fontSize: 12.5,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricPreview extends StatelessWidget {
  const _MetricPreview({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FBFF),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2ECF8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xFF2563EB), size: 22),
          const SizedBox(height: 11),
          Text(
            value,
            style: const TextStyle(
              color: Color(0xFF0F172A),
              fontSize: 27,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.5,
            ),
          ),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgressPreview extends StatelessWidget {
  const _ProgressPreview({
    required this.title,
    required this.value,
    required this.progress,
  });

  final String title;
  final String value;
  final double progress;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Color(0xFF0F172A),
                  fontWeight: FontWeight.w900,
                  fontSize: 12.5,
                ),
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 9,
                  color: const Color(0xFF2563EB),
                  backgroundColor: const Color(0xFFE2ECF8),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Text(
          value,
          style: const TextStyle(
            color: Color(0xFF2563EB),
            fontWeight: FontWeight.w900,
            fontSize: 13,
          ),
        ),
      ],
    );
  }
}

class _PortalBackdrop extends StatelessWidget {
  const _PortalBackdrop();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        CustomPaint(
          painter: _PortalBackdropPainter(),
          child: const SizedBox.expand(),
        ),
        const Positioned(
          top: -120,
          right: -100,
          child: _GlowCircle(size: 320, color: Color(0xFF60A5FA)),
        ),
        const Positioned(
          bottom: -120,
          left: -110,
          child: _GlowCircle(size: 300, color: Color(0xFF34D399)),
        ),
      ],
    );
  }
}

class _GlowCircle extends StatelessWidget {
  const _GlowCircle({
    required this.size,
    required this.color,
  });

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withOpacity(0.13),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.18),
              blurRadius: 90,
              spreadRadius: 28,
            ),
          ],
        ),
      ),
    );
  }
}

class _PortalBackdropPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;

    paint.color = const Color(0xFFEAF5FF);
    canvas.drawRect(Offset.zero & size, paint);

    final linePaint = Paint()
      ..color = const Color(0xFFCFE2F8).withOpacity(0.42)
      ..strokeWidth = 1;

    for (var x = 0.0; x < size.width; x += 58) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), linePaint);
    }

    for (var y = 0.0; y < size.height; y += 58) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), linePaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}