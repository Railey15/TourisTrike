import 'package:flutter/material.dart';

import 'city_admin_signup_screen.dart';
import 'web_portal_login_screen.dart';

class WebPortalLandingScreen extends StatelessWidget {
  const WebPortalLandingScreen({super.key});

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
      backgroundColor: const Color(0xFFF6FAFF),
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
                        horizontal: wide ? 40 : 20,
                        vertical: wide ? 28 : 18,
                      ),
                      child: Column(
                        children: [
                          _TopBar(
                            onLogin: () => _openLogin(context),
                            onApply: () => _openCityAdminSignup(context),
                          ),
                          SizedBox(height: wide ? 56 : 28),
                          Expanded(
                            child: wide
                                ? Row(
                                    children: [
                                      Expanded(
                                        flex: 11,
                                        child: _IntroPanel(
                                          onLogin: () => _openLogin(context),
                                          onApply: () =>
                                              _openCityAdminSignup(context),
                                        ),
                                      ),
                                      const SizedBox(width: 34),
                                      const Expanded(
                                        flex: 9,
                                        child: _PortalPreview(),
                                      ),
                                    ],
                                  )
                                : ListView(
                                    physics: const BouncingScrollPhysics(),
                                    children: [
                                      _IntroPanel(
                                        onLogin: () => _openLogin(context),
                                        onApply: () =>
                                            _openCityAdminSignup(context),
                                      ),
                                      const SizedBox(height: 22),
                                      const _PortalPreview(),
                                    ],
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
  const _TopBar({required this.onLogin, required this.onApply});

  final VoidCallback onLogin;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 620;
        final brand = Row(
          children: [
            Container(
              width: 42,
              height: 42,
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFE2ECF8)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 14,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Image.asset(
                'assets/images/touristrike_logo.png',
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => const Icon(
                  Icons.electric_rickshaw_rounded,
                  color: Color(0xFF2A86FF),
                ),
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'TourisTrike Admin Portal',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Color(0xFF0F172A),
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
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
              icon: const Icon(Icons.how_to_reg_rounded, size: 18),
              label: const Text('Apply'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF0F766E),
                side: const BorderSide(color: Color(0xFFA7F3D0)),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 16,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
            OutlinedButton.icon(
              onPressed: onLogin,
              icon: const Icon(Icons.login_rounded, size: 18),
              label: const Text('Sign In'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF2A86FF),
                side: const BorderSide(color: Color(0xFFB9D7FF)),
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 16,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
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
              const SizedBox(height: 12),
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
  const _IntroPanel({required this.onLogin, required this.onApply});

  final VoidCallback onLogin;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: const Color(0xFFE2ECF8)),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.admin_panel_settings_rounded,
                  size: 18,
                  color: Color(0xFF2A86FF),
                ),
                SizedBox(width: 8),
                Text(
                  'Web access for tourism administrators',
                  style: TextStyle(
                    color: Color(0xFF475569),
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Manage Bulacan tourism operations from a dedicated web portal.',
            style: TextStyle(
              color: Color(0xFF0F172A),
              fontSize: 46,
              height: 1.05,
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            'Provincial and city tourism teams can review packages, manage destinations, monitor bookings, and coordinate local drivers from one desktop-friendly workspace.',
            style: TextStyle(
              color: Color(0xFF64748B),
              fontSize: 16,
              height: 1.55,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 28),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              ElevatedButton.icon(
                onPressed: onLogin,
                icon: const Icon(Icons.lock_open_rounded),
                label: const Text('Open Admin Login'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2A86FF),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 22,
                    vertical: 18,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  textStyle: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                  ),
                ),
              ),
              OutlinedButton.icon(
                onPressed: onApply,
                icon: const Icon(Icons.how_to_reg_rounded),
                label: const Text('Apply as City Admin'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF0F766E),
                  side: const BorderSide(color: Color(0xFFA7F3D0)),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 18,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  textStyle: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE2ECF8)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.phone_android_rounded,
                      color: Color(0xFF64748B),
                      size: 19,
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Tourist and driver access remains mobile-first',
                      style: TextStyle(
                        color: Color(0xFF475569),
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 30),
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
      width: 250,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2ECF8)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.045),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xFF2A86FF).withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: const Color(0xFF2A86FF), size: 22),
          ),
          const SizedBox(width: 12),
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
                const SizedBox(height: 3),
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
        constraints: const BoxConstraints(maxWidth: 470),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: Colors.white),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 32,
              offset: const Offset(0, 22),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: const Color(0xFF2A86FF),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(
                    Icons.dashboard_rounded,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Operations Snapshot',
                        style: TextStyle(
                          color: Color(0xFF0F172A),
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      SizedBox(height: 2),
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
            const SizedBox(height: 18),
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
            const SizedBox(height: 18),
            const _ProgressPreview(
              title: 'Published packages',
              value: '74%',
              progress: 0.74,
            ),
            const SizedBox(height: 12),
            const _ProgressPreview(
              title: 'Confirmed bookings',
              value: '61%',
              progress: 0.61,
            ),
            const SizedBox(height: 18),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF4F8FF),
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Row(
                children: [
                  Icon(Icons.shield_rounded, color: Color(0xFF16A34A)),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Role-based access for provincial and city tourism offices',
                      style: TextStyle(
                        color: Color(0xFF475569),
                        fontWeight: FontWeight.w800,
                        fontSize: 12.5,
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
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF6FAFF),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2ECF8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xFF2A86FF), size: 21),
          const SizedBox(height: 10),
          Text(
            value,
            style: const TextStyle(
              color: Color(0xFF0F172A),
              fontSize: 26,
              fontWeight: FontWeight.w900,
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
                  color: const Color(0xFF2A86FF),
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
            color: Color(0xFF2A86FF),
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
    return CustomPaint(
      painter: _PortalBackdropPainter(),
      child: const SizedBox.expand(),
    );
  }
}

class _PortalBackdropPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    paint.color = const Color(0xFFEAF5FF);
    canvas.drawRect(Offset.zero & size, paint);

    paint.color = const Color(0xFFDBECFF);
    canvas.drawCircle(
      Offset(size.width * 0.86, size.height * 0.18),
      260,
      paint,
    );

    paint.color = const Color(0xFFEFFFF7);
    canvas.drawCircle(
      Offset(size.width * 0.08, size.height * 0.82),
      240,
      paint,
    );

    final linePaint = Paint()
      ..color = const Color(0xFFCFE2F8).withValues(alpha: 0.55)
      ..strokeWidth = 1;
    for (var x = 0.0; x < size.width; x += 56) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), linePaint);
    }
    for (var y = 0.0; y < size.height; y += 56) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), linePaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
