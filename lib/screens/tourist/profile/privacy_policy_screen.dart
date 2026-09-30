import 'package:flutter/material.dart';
import 'package:touristrike/core/policies/touristrike_notices.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF5F7FB),
    appBar: AppBar(title: const Text('Privacy Notice')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'TOURISTRIKE PRIVACY NOTICE',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          const Text(
            'Version $privacyNoticeVersion • Effective $privacyNoticeEffectiveDate',
          ),
          const SizedBox(height: 16),
          for (final section in privacyNoticeSections) ...[
            Text(
              section.heading,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(section.body, style: const TextStyle(height: 1.5)),
            const SizedBox(height: 20),
          ],
        ],
      ),
    ),
  );
}
