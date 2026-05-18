import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'login_screen.dart';
import 'web_portal_landing_screen.dart';

class TourisTrikeLoadingScreen extends StatefulWidget {
  const TourisTrikeLoadingScreen({super.key});

  @override
  State<TourisTrikeLoadingScreen> createState() =>
      _TourisTrikeLoadingScreenState();
}

class _TourisTrikeLoadingScreenState extends State<TourisTrikeLoadingScreen>
    with SingleTickerProviderStateMixin {
  int _progress = 0;
  Timer? _timer;
  late final AnimationController _floatController;

  @override
  void initState() {
    super.initState();

    _floatController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);

    _startLoading();
  }

  void _startLoading() {
    _timer = Timer.periodic(const Duration(milliseconds: 28), (timer) {
      if (!mounted) return;

      setState(() {
        if (_progress < 100) {
          _progress++;
        } else {
          timer.cancel();
          _onLoadingComplete();
        }
      });
    });
  }

  void _onLoadingComplete() {
    if (!mounted) return;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) =>
            kIsWeb ? const WebPortalLandingScreen() : const LoginScreen(),
      ),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _floatController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    const horizontalPadding = 28.0;
    final trackWidth = math.max(0.0, size.width - (horizontalPadding * 2));
    final progressWidth = (trackWidth * (_progress / 100)).clamp(
      0.0,
      trackWidth,
    );

    return Scaffold(
      body: Container(
        width: size.width,
        height: size.height,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFEAF5FF), Color(0xFFD8ECFF), Color(0xFFFFFFFF)],
            stops: [0.0, 0.45, 1.0],
          ),
        ),
        child: Stack(
          children: [
            _buildGlowCircle(
              top: -90,
              right: -55,
              size: 230,
              color: const Color(0xFF2A86FF).withValues(alpha: 0.10),
            ),
            _buildGlowCircle(
              left: -85,
              bottom: -95,
              size: 250,
              color: const Color(0xFF38BDF8).withValues(alpha: 0.10),
            ),
            _buildGlowCircle(
              top: size.height * 0.35,
              right: -80,
              size: 160,
              color: const Color(0xFF16A34A).withValues(alpha: 0.06),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: horizontalPadding,
                ),
                child: Column(
                  children: [
                    const Spacer(flex: 2),
                    _buildLogo(),
                    const SizedBox(height: 30),
                    const Text(
                      'TourisTrike',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 40,
                        height: 1,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF0F172A),
                        letterSpacing: -1,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildLocationBadge(),
                    const SizedBox(height: 18),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 10),
                      child: Text(
                        kIsWeb
                            ? 'Manage destinations, packages, bookings, and city tourism operations.'
                            : 'Discover Bustos with fast, safe, and convenient tricycle booking.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 14.5,
                          height: 1.5,
                          color: Color(0xFF64748B),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const Spacer(flex: 2),
                    _buildProgressCard(progressWidth),
                    const Spacer(),
                    const Padding(
                      padding: EdgeInsets.only(bottom: 10),
                      child: Text(
                        'Powered by TourisTrike',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: Color(0xFF94A3B8),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
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

  Widget _buildLogo() {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.92, end: 1).animate(
        CurvedAnimation(parent: _floatController, curve: Curves.easeInOut),
      ),
      child: AnimatedBuilder(
        animation: _floatController,
        builder: (context, child) {
          final dy = (_floatController.value - 0.5) * 12;
          return Transform.translate(offset: Offset(0, dy), child: child);
        },
        child: Container(
          width: 152,
          height: 152,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.95),
            borderRadius: BorderRadius.circular(34),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.9),
              width: 1.4,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF2A86FF).withValues(alpha: 0.20),
                blurRadius: 32,
                offset: const Offset(0, 18),
              ),
            ],
          ),
          child: Image.asset(
            'assets/images/touristrike_logo.png',
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) {
              return Container(
                decoration: const BoxDecoration(
                  color: Color(0xFFEAF2FF),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.electric_rickshaw_rounded,
                  size: 54,
                  color: Color(0xFF2A86FF),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildLocationBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFE5EEF9)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.035),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.location_on_rounded,
            size: 18,
            color: Color(0xFF2A86FF),
          ),
          const SizedBox(width: 8),
          Text(
            kIsWeb
                ? 'Tourism Management Portal'
                : 'Tourist Mobility for Bustos',
            style: const TextStyle(
              fontSize: 14.5,
              color: Color(0xFF475569),
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressCard(double progressWidth) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: Colors.white.withValues(alpha: 0.9)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 24,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 11,
                height: 11,
                decoration: BoxDecoration(
                  color: const Color(0xFF2A86FF),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF2A86FF).withValues(alpha: 0.35),
                      blurRadius: 10,
                      spreadRadius: 1,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  kIsWeb ? 'PREPARING ADMIN PORTAL' : 'PREPARING YOUR RIDE',
                  style: TextStyle(
                    fontSize: 12.5,
                    letterSpacing: 1.1,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF0F172A),
                  ),
                ),
              ),
              Text(
                '$_progress%',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF2A86FF),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: Container(
              width: double.infinity,
              height: 12,
              color: const Color(0xFFE8EEF5),
              child: Align(
                alignment: Alignment.centerLeft,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  curve: Curves.easeOut,
                  width: progressWidth,
                  height: 12,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    gradient: const LinearGradient(
                      colors: [
                        Color(0xFF5BB2FF),
                        Color(0xFF2A86FF),
                        Color(0xFF1D4ED8),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          const Row(
            children: [
              Icon(Icons.shield_rounded, size: 16, color: Color(0xFF16A34A)),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  kIsWeb
                      ? 'Loading tourism management tools and secure access.'
                      : 'Securing routes, drivers, and tourist transport services.',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: Color(0xFF64748B),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGlowCircle({
    double? top,
    double? right,
    double? bottom,
    double? left,
    required double size,
    required Color color,
  }) {
    return Positioned(
      top: top,
      right: right,
      bottom: bottom,
      left: left,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color),
      ),
    );
  }
}
