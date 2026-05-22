import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:touristrike/core/supabase/touristrike_repository.dart';
import 'package:touristrike/screens/guest/guest_trip_tracking_screen.dart';

/// Entry point for unauthenticated guests who open a shared trip link.
/// Accepts a [publicToken] from the URL path and prompts for an access code.
class GuestTripAccessScreen extends StatefulWidget {
  const GuestTripAccessScreen({super.key, required this.publicToken});

  final String publicToken;

  @override
  State<GuestTripAccessScreen> createState() => _GuestTripAccessScreenState();
}

class _GuestTripAccessScreenState extends State<GuestTripAccessScreen> {
  final _repo = TourisTrikeRepository();
  final _codeCtrl = TextEditingController();
  final _focusNode = FocusNode();

  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _codeCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _validate() async {
    final code = _codeCtrl.text.trim();
    if (code.length != 6) {
      setState(() => _error = 'Please enter the 6-digit access code.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final details = await _repo.validateGuestTripLink(
        publicToken: widget.publicToken,
        accessCode: code,
        deviceInfo: _resolveDeviceInfo(),
        userAgent: 'TourisTrike Flutter App',
      );

      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => GuestTripTrackingScreen(
            publicToken: widget.publicToken,
            accessCode: code,
            initialDetails: details!,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString().replaceFirst('Exception: ', '');
      setState(() {
        _error = msg.isNotEmpty
            ? msg
            : 'Trip link is invalid, expired, or disabled.';
        _loading = false;
      });
    }
  }

  String _resolveDeviceInfo() {
    // Returns a simple device description usable in notifications
    return 'Flutter App';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 32),

              // Logo / brand
              Center(
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: const Color(0xFF2A86FF),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF2A86FF).withValues(alpha: 0.3),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.share_location_rounded,
                    color: Colors.white,
                    size: 36,
                  ),
                ),
              ),
              const SizedBox(height: 24),

              const Text(
                'TourisTrike',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 26,
                  color: Color(0xFF1E293B),
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Trip Link Access',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  color: Color(0xFF64748B),
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 40),

              // Card
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 20,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Enter Trip Access Code',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'The trip organizer shared a 6-digit code with you. Enter it below to view the trip.',
                      style: TextStyle(
                        fontSize: 13.5,
                        color: Color(0xFF64748B),
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Code input
                    TextField(
                      controller: _codeCtrl,
                      focusNode: _focusNode,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      textAlign: TextAlign.center,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      style: const TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 8,
                        color: Color(0xFF1E293B),
                      ),
                      decoration: InputDecoration(
                        hintText: '------',
                        hintStyle: const TextStyle(
                          letterSpacing: 8,
                          color: Color(0xFFCBD5E1),
                          fontWeight: FontWeight.w900,
                          fontSize: 30,
                        ),
                        counterText: '',
                        filled: true,
                        fillColor: const Color(0xFFF8FAFC),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(
                            color: Color(0xFF2A86FF),
                            width: 2,
                          ),
                        ),
                        errorText: _error,
                        errorMaxLines: 3,
                      ),
                      onSubmitted: (_) => _validate(),
                    ),
                    const SizedBox(height: 20),

                    FilledButton(
                      onPressed: _loading ? null : _validate,
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF2A86FF),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: _loading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2.5,
                              ),
                            )
                          : const Text(
                              'View Trip',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Security note
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0F9FF),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFBAE6FD)),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      size: 16,
                      color: Color(0xFF0284C7),
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'You will only see limited trip information: itinerary stops, trip status, tricycle number, and live map during the active tour. No personal or payment details are shown.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF0369A1),
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 32),
              const Text(
                'Powered by TourisTrike',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: Color(0xFFCBD5E1)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
