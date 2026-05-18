import 'package:flutter/material.dart';

/// Privacy Policy Screen (local text)
/// - Same UI language: blue, rounded cards, soft shadows
/// - Scrollable policy content
///
/// Navigate:
/// Navigator.push(context, MaterialPageRoute(builder: (_) => const PrivacyPolicyScreen()));
class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    const bg = Color(0xFFF5F7FB);
    const textDark = Color(0xFF0F172A);

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  _TopCircleButton(
                    icon: Icons.arrow_back_rounded,
                    onTap: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Privacy Policy',
                      style: TextStyle(
                        fontSize: 20.5,
                        fontWeight: FontWeight.w900,
                        color: textDark,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
                children: const [
                  _PolicyCard(
                    children: [
                      _PolicyTitle('Last updated'),
                      _PolicyText('February 21, 2026'),
                      SizedBox(height: 14),

                      _PolicyTitle('1. Overview'),
                      _PolicyText(
                        'This Privacy Policy explains how TouriStrike collects, uses, and protects '
                        'your information when you use the app for tricycle rides and tours.',
                      ),
                      SizedBox(height: 12),

                      _PolicyTitle('2. Information We Collect'),
                      _PolicyBullet(
                        'Account info (name, email, phone number if provided).',
                      ),
                      _PolicyBullet(
                        'Trip info (pickup, drop-off, date/time, fare, trip status).',
                      ),
                      _PolicyBullet(
                        'Saved Places (places you choose to save).',
                      ),
                      _PolicyBullet(
                        'Emergency Contacts (contacts you choose to add).',
                      ),
                      _PolicyBullet(
                        'Device info (basic diagnostics, app version).',
                      ),
                      SizedBox(height: 12),

                      _PolicyTitle('3. How We Use Your Information'),
                      _PolicyBullet(
                        'To provide ride and tour booking features.',
                      ),
                      _PolicyBullet('To show trip history and receipts.'),
                      _PolicyBullet('To improve app safety and reliability.'),
                      _PolicyBullet(
                        'To provide support and respond to issues.',
                      ),
                      SizedBox(height: 12),

                      _PolicyTitle('4. Location Data'),
                      _PolicyText(
                        'Location data may be used to support pickup and drop-off functionality. '
                        'If location permissions are denied, some features may not work properly.',
                      ),
                      SizedBox(height: 12),

                      _PolicyTitle('5. Sharing of Information'),
                      _PolicyText(
                        'We do not sell your personal information. We only share data when necessary '
                        'to provide services (e.g., trip details with the driver), comply with legal '
                        'requirements, or protect user safety.',
                      ),
                      SizedBox(height: 12),

                      _PolicyTitle('6. Data Retention'),
                      _PolicyText(
                        'We keep your data only as long as needed to provide the service, comply with '
                        'legal obligations, and maintain records for safety and support.',
                      ),
                      SizedBox(height: 12),

                      _PolicyTitle('7. Security'),
                      _PolicyText(
                        'We use reasonable security practices to protect your data. However, no method '
                        'of transmission or storage is 100% secure.',
                      ),
                      SizedBox(height: 12),

                      _PolicyTitle('8. Your Choices'),
                      _PolicyBullet('You can edit your profile information.'),
                      _PolicyBullet(
                        'You can remove Saved Places and Emergency Contacts.',
                      ),
                      _PolicyBullet('You can manage notification preferences.'),
                      SizedBox(height: 12),

                      _PolicyTitle('9. Contact Us'),
                      _PolicyText(
                        'If you have questions about this policy, contact support through the app.',
                      ),
                    ],
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

class _TopCircleButton extends StatelessWidget {
  const _TopCircleButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 18,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Icon(icon, color: const Color(0xFF0F172A)),
      ),
    );
  }
}

class _PolicyCard extends StatelessWidget {
  const _PolicyCard({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    const line = Color(0xFFE7EEF7);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: line),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 22,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}

class _PolicyTitle extends StatelessWidget {
  const _PolicyTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    const textDark = Color(0xFF0F172A);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: const TextStyle(
          fontWeight: FontWeight.w900,
          color: textDark,
          fontSize: 16,
        ),
      ),
    );
  }
}

class _PolicyText extends StatelessWidget {
  const _PolicyText(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    const textMid = Color(0xFF64748B);
    return Text(
      text,
      style: const TextStyle(
        fontWeight: FontWeight.w800,
        color: textMid,
        height: 1.35,
      ),
    );
  }
}

class _PolicyBullet extends StatelessWidget {
  const _PolicyBullet(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    const textMid = Color(0xFF64748B);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Text(
            'â€¢ ',
            style: TextStyle(fontWeight: FontWeight.w900, color: textMid),
          ),
          // NOTE: Expanded must not be const because it depends on text
        ],
      ),
    );
  }
}
