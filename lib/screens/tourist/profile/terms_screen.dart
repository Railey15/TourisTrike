import 'package:flutter/material.dart';
import 'package:touristrike/core/policies/touristrike_notices.dart';

/// Existing booking and profile Terms route.
class TermsScreen extends StatelessWidget {
  const TermsScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF5F7FB),
    appBar: AppBar(title: const Text('Terms & Conditions')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'TOURISTRIKE BOOKING TERMS AND CONDITIONS',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          const Text(
            'Version $bookingTermsVersion • Effective $bookingTermsEffectiveDate',
          ),
          const SizedBox(height: 16),
          for (final section in bookingTermsSections) ...[
            Text(
              section.heading,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(section.body, style: const TextStyle(height: 1.5)),
            const SizedBox(height: 20),
          ],
          Text(
            'Cancellation Policy',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          const Text(cancellationPolicySummary, style: TextStyle(height: 1.5)),
        ],
      ),
    ),
  );
}
