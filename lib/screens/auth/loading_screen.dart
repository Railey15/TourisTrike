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
  static const String logoUrl =
      'https://mvtqhsrdgtwdeootgjci.supabase.co/storage/v1/object/public/public-assets/Logo.png';

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
    final progressWidth =
        (trackWidth * (_progress / 100)).clamp(0.0, trackWidth);

    return Scaffold(
      body: Container(
        width: size.width,
        height: size.height,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFFEAF5FF),
              Color(0xFFF8FBFF),
              Color(0xFFEFFAF5),
            ],
          ),
        ),
        child: Stack(
          children: [
            _buildGlowCircle(
              top: -110,
              right: -70,
              size: 280,
              color: const Color(0xFF2A86FF).withValues(alpha: 0.13),
            ),
            _buildGlowCircle(
              left: -100,
              bottom: -105,
              size: 300,
              color: const Color(0xFF16A34A).withValues(alpha: 0.10),
            ),
            _buildGlowCircle(
              top: size.height * 0.36,
              right: -90,
              size: 180,
              color: const Color(0xFFA78BFA).withValues(alpha: 0.08),
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
                    const SizedBox(height: 28),
                    const Text(
                      'TourisTrike',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 42,
                        height: 1,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF0F172A),
                        letterSpacing: -1.2,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildLocationBadge(),
                    const SizedBox(height: 18),
                    Text(
                      kIsWeb
                          ? 'Manage destinations, packages, bookings, and city tourism operations in one secure portal.'
                          : 'Discover local destinations and book safe tricycle rides with ease.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 14.8,
                        height: 1.55,
                        color: Color(0xFF64748B),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(flex: 2),
                    _buildProgressCard(progressWidth),
                    const Spacer(),
                    const Padding(
                      padding: EdgeInsets.only(bottom: 12),
                      child: Text(
                        'Powered by TourisTrike',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: Color(0xFF94A3B8),
                          fontWeight: FontWeight.w800,
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
          width: 158,
          height: 158,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.96),
            borderRadius: BorderRadius.circular(38),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.9),
              width: 1.4,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF2A86FF).withValues(alpha: 0.18),
                blurRadius: 36,
                offset: const Offset(0, 20),
              ),
            ],
          ),
          child: Image.network(
            logoUrl,
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) {
              return Container(
                decoration: const BoxDecoration(
                  color: Color(0xFFEAF2FF),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.electric_rickshaw_rounded,
                  size: 56,
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.86),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFE2ECF8)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 14,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.travel_explore_rounded,
            size: 18,
            color: Color(0xFF2A86FF),
          ),
          const SizedBox(width: 8),
          Text(
            kIsWeb
                ? 'Tourism Management Portal'
                : 'Tourist Mobility Platform',
            style: const TextStyle(
              fontSize: 14.5,
              color: Color(0xFF475569),
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressCard(double progressWidth) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withValues(alpha: 0.92)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.065),
            blurRadius: 28,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF2FF),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: const Icon(
                  Icons.rocket_launch_rounded,
                  color: Color(0xFF2A86FF),
                  size: 21,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  kIsWeb ? 'PREPARING ADMIN PORTAL' : 'PREPARING YOUR APP',
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
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF2A86FF),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: Container(
              width: double.infinity,
              height: 13,
              color: const Color(0xFFE8EEF5),
              child: Align(
                alignment: Alignment.centerLeft,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  curve: Curves.easeOut,
                  width: progressWidth,
                  height: 13,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    gradient: const LinearGradient(
                      colors: [
                        Color(0xFF60A5FA),
                        Color(0xFF2A86FF),
                        Color(0xFF1D4ED8),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 15),
          Row(
            children: [
              const Icon(
                Icons.shield_rounded,
                size: 17,
                color: Color(0xFF16A34A),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  kIsWeb
                      ? 'Loading secure tourism tools and management access.'
                      : 'Loading destinations, routes, rides, and travel services.',
                  style: const TextStyle(
                    fontSize: 12.8,
                    color: Color(0xFF64748B),
                    fontWeight: FontWeight.w700,
                    height: 1.35,
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
      child: IgnorePointer(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        ),
      ),
    );
  }
}