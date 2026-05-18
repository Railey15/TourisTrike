import 'package:flutter/material.dart';

/// Terms & Conditions Screen (local text)
///
/// Navigate:
/// Navigator.push(context, MaterialPageRoute(builder: (_) => const TermsScreen()));
class TermsScreen extends StatelessWidget {
  const TermsScreen({super.key});

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
                      'Terms & Conditions',
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

                      _PolicyTitle('1. Using the App'),
                      _PolicyText(
                        'By using TouriStrike, you agree to follow these terms. '
                        'If you do not agree, please stop using the app.',
                      ),
                      SizedBox(height: 12),

                      _PolicyTitle('2. Bookings'),
                      _PolicyBullet(
                        'Ride and tour availability may vary depending on drivers and conditions.',
                      ),
                      _PolicyBullet(
                        'Fares shown may be estimates unless stated as final.',
                      ),
                      _PolicyBullet(
                        'You are responsible for providing correct pickup and drop-off details.',
                      ),
                      SizedBox(height: 12),

                      _PolicyTitle('3. Cancellations'),
                      _PolicyText(
                        'Cancellations may occur due to driver availability, safety concerns, or incorrect details. '
                        'Some trips may not be eligible for refunds depending on the situation.',
                      ),
                      SizedBox(height: 12),

                      _PolicyTitle('4. User Conduct'),
                      _PolicyBullet(
                        'Respect drivers, guides, and other users.',
                      ),
                      _PolicyBullet(
                        'Do not misuse the app for illegal or harmful activities.',
                      ),
                      _PolicyBullet(
                        'Do not provide false booking information.',
                      ),
                      SizedBox(height: 12),

                      _PolicyTitle('5. Safety'),
                      _PolicyText(
                        'Use the appâ€™s safety features responsibly. In emergencies, contact local authorities.',
                      ),
                      SizedBox(height: 12),

                      _PolicyTitle('6. Limitation of Liability'),
                      _PolicyText(
                        'TouriStrike is a platform that helps connect users with transportation and tour services. '
                        'We are not liable for delays, cancellations, or damages beyond what is required by law.',
                      ),
                      SizedBox(height: 12),

                      _PolicyTitle('7. Changes to Terms'),
                      _PolicyText(
                        'We may update these terms from time to time. Continued use of the app means you accept the updated terms.',
                      ),
                      SizedBox(height: 12),

                      _PolicyTitle('8. Contact'),
                      _PolicyText(
                        'For concerns about these terms, contact support through the app.',
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
        children: [
          const Text(
            'â€¢ ',
            style: TextStyle(fontWeight: FontWeight.w900, color: textMid),
          ),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                color: textMid,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
