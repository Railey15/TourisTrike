import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:touristrike/screens/driver/profile/driver_identity_status.dart';
import 'package:touristrike/screens/driver/profile/services/driver_profile_service.dart';
import 'package:touristrike/screens/driver/profile/widgets/driver_profile_components.dart';
import 'package:touristrike/screens/tourist/profile/privacy_policy_screen.dart';

class DriverIdentityVerificationCard extends StatefulWidget {
  const DriverIdentityVerificationCard({
    super.key,
    this.service,
    this.openUrl,
    this.mtoApprovalStatus,
  });

  final DriverProfileService? service;
  final Future<bool> Function(Uri)? openUrl;
  final String? mtoApprovalStatus;

  @override
  State<DriverIdentityVerificationCard> createState() =>
      _DriverIdentityVerificationCardState();
}

class _DriverIdentityVerificationCardState
    extends State<DriverIdentityVerificationCard>
    with WidgetsBindingObserver {
  late final DriverProfileService _service;
  DriverIdentityStatus? _status;
  bool _busy = false;
  String? _error;
  bool _launched = false;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? DriverProfileService();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final status = await _service.fetchIdentityVerificationStatus();
      if (!mounted) return;
      setState(() {
        _status = status;
        _error = null;
        if (status.value == 'approved' ||
            status.value == 'declined' ||
            status.value == 'expired') {
          _launched = false;
        }
      });
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not load verification status.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _start() async {
    if (_busy || _status?.value == 'approved') return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await _service.startIdentityVerification();
      if (!mounted) return;
      setState(() => _status = result.status);
      if (result.url != null) {
        final opened =
            await (widget.openUrl?.call(result.url!) ??
                launchUrl(result.url!, mode: LaunchMode.externalApplication));
        if (!opened) {
          throw StateError('Could not open identity verification.');
        }
        if (mounted) setState(() => _launched = true);
      }
      await _refreshAfterLaunch();
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Could not open identity verification. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _refreshAfterLaunch() async {
    try {
      final status = await _service.fetchIdentityVerificationStatus();
      if (mounted) setState(() => _status = status);
    } catch (_) {
      // The resume hook and manual refresh remain available.
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    if (status?.value == 'approved') {
      final verifiedAt = status!.verifiedAt;
      final mtoLabel = switch (widget.mtoApprovalStatus?.toLowerCase()) {
        'approved' => 'Approved',
        'pending' => 'Pending',
        'rejected' => 'Rejected',
        'suspended' => 'Suspended',
        _ => 'Status unavailable',
      };
      return DriverProfileCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.verified_rounded,
                  color: Color(0xFF168356),
                  size: 24,
                ),
                const SizedBox(width: 9),
                const Expanded(child: DriverSectionTitle('Identity Verified')),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F7EF),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'Verified ✓',
                    style: TextStyle(
                      color: Color(0xFF146C49),
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const Text('Government-issued identity successfully verified.'),
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF5FAF7),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFDDEFE4)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Verified ID',
                    style: TextStyle(color: Color(0xFF527263), fontSize: 12),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    status.verifiedIdLabel,
                    style: const TextStyle(
                      color: Color(0xFF183A2A),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Verified via Didit',
              style: TextStyle(color: Color(0xFF52657A), fontSize: 12),
            ),
            if (verifiedAt != null) ...[
              const SizedBox(height: 2),
              Text(
                'Verified on ${DateFormat('MMM d, yyyy').format(verifiedAt.toLocal())}',
                style: const TextStyle(color: Color(0xFF52657A), fontSize: 12),
              ),
            ],
            const Divider(height: 24, color: Color(0xFFE7EEF7)),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Driver-Tour Guide Approval',
                    style: TextStyle(color: Color(0xFF52657A), fontSize: 12),
                  ),
                ),
                Text(
                  mtoLabel,
                  style: const TextStyle(
                    color: Color(0xFF334155),
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const Text(
              'Reviewed separately by your MTO.',
              style: TextStyle(color: Color(0xFF64748B), fontSize: 11),
            ),
            TextButton.icon(
              onPressed: _busy ? null : _refresh,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Refresh status'),
            ),
          ],
        ),
      );
    }
    return DriverProfileCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const DriverSectionTitle('Identity Verification'),
          const SizedBox(height: 8),
          Text(
            status?.label ?? 'Loading verification status...',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            status?.description ??
                'Checking your identity verification record.',
          ),
          if (_launched && status?.value != 'approved') ...[
            const SizedBox(height: 8),
            const Text('Verification submitted. We’re checking your result.'),
          ],
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: Colors.red)),
          ],
          const SizedBox(height: 12),
          const Text(
            'Didit processes your government ID, selfie/liveness, and facial comparison. '
            'TourisTrike receives the verification status for MTO review.',
          ),
          TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const PrivacyPolicyScreen()),
            ),
            child: const Text('Read Privacy Notice'),
          ),
          if (status?.canStart == true)
            DriverPrimaryButton(
              label:
                  status!.value == 'not_started' ||
                      status.value == 'in_progress'
                  ? 'Continue Verification'
                  : 'Verify Identity',
              onPressed: _busy ? null : _start,
              loading: _busy,
              icon: Icons.verified_user_outlined,
            ),
          TextButton.icon(
            onPressed: _busy ? null : _refresh,
            icon: const Icon(Icons.refresh),
            label: const Text('Refresh status'),
          ),
        ],
      ),
    );
  }
}
