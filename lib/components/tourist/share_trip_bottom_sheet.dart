import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:touristrike/core/supabase/touristrike_models.dart';
import 'package:touristrike/core/supabase/touristrike_repository.dart';

class ShareTripBottomSheet extends StatefulWidget {
  const ShareTripBottomSheet({
    super.key,
    required this.bookingId,
    required this.travelDate,
  });

  final String bookingId;
  final DateTime? travelDate;

  static Future<void> show(
    BuildContext context, {
    required String bookingId,
    required DateTime? travelDate,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black54,
      builder: (_) => ShareTripBottomSheet(
        bookingId: bookingId,
        travelDate: travelDate,
      ),
    );
  }

  @override
  State<ShareTripBottomSheet> createState() => _ShareTripBottomSheetState();
}

class _ShareTripBottomSheetState extends State<ShareTripBottomSheet> {
  final _repo = TourisTrikeRepository();

  SharedTripLink? _link;
  bool _loading = true;
  bool _actionLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadOrCreate();
  }

  Future<void> _loadOrCreate() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      var link = await _repo.getActiveShareTripLink(widget.bookingId);
      link ??= await _repo.generateShareTripLink(
        bookingId: widget.bookingId,
        travelDate: widget.travelDate,
      );
      if (!mounted) return;
      setState(() {
        _link = link;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _disableLink() async {
    final link = _link;
    if (link == null) return;
    final confirm = await _showConfirmDialog(
      title: 'Disable Shared Link',
      body: 'Guests will no longer be able to access this trip link. Are you sure?',
      confirmLabel: 'Disable',
      destructive: true,
    );
    if (!confirm || !mounted) return;

    setState(() => _actionLoading = true);
    try {
      await _repo.disableShareTripLink(link.id);
      if (!mounted) return;
      Navigator.of(context).pop();
      _showSnack('Shared link disabled. Guests can no longer access it.');
    } catch (e) {
      if (mounted) _showSnack('Failed to disable link. Please try again.');
    } finally {
      if (mounted) setState(() => _actionLoading = false);
    }
  }

  Future<void> _regenerateLink() async {
    final link = _link;
    if (link == null) return;
    final confirm = await _showConfirmDialog(
      title: 'Generate New Link',
      body: 'The current link and access code will be permanently invalidated. Anyone using the old link will be denied. Continue?',
      confirmLabel: 'Generate New',
      destructive: true,
    );
    if (!confirm || !mounted) return;

    setState(() => _actionLoading = true);
    try {
      final newLink = await _repo.regenerateShareTripLink(
        oldLinkId: link.id,
        bookingId: widget.bookingId,
        travelDate: widget.travelDate,
      );
      if (!mounted) return;
      setState(() {
        _link = newLink;
        _actionLoading = false;
      });
      _showSnack('New link and access code generated.');
    } catch (e) {
      if (mounted) {
        setState(() => _actionLoading = false);
        _showSnack('Failed to generate new link. Please try again.');
      }
    }
  }

  void _copyToClipboard(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    _showSnack('$label copied to clipboard.');
  }

  Future<void> _shareLink() async {
    final link = _link;
    if (link == null) return;
    await Share.share(
      'Track my TourisTrike trip in real time!\n\n'
      'Trip Link: ${link.shareUrl}\n'
      'Access Code: ${link.accessCode}\n\n'
      'Open the link and enter the access code to view my trip status.',
      subject: 'TourisTrike Trip Share',
    );
  }

  Future<bool> _showConfirmDialog({
    required String title,
    required String body,
    required String confirmLabel,
    bool destructive = false,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: destructive
                ? TextButton.styleFrom(foregroundColor: Colors.red)
                : null,
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return result == true;
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(24, 20, 24, 24 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Header
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFF2A86FF).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.share_location_rounded,
                  color: Color(0xFF2A86FF),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Share Trip',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 17,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                    Text(
                      'Let companions follow your trip safely',
                      style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: CircularProgressIndicator(color: Color(0xFF2A86FF)),
              ),
            )
          else if (_error != null)
            _ErrorState(message: _error!, onRetry: _loadOrCreate)
          else if (_link != null)
            _buildLinkContent(),

          if (_actionLoading && !_loading)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: LinearProgressIndicator(color: Color(0xFF2A86FF)),
            ),
        ],
      ),
    );
  }

  Widget _buildLinkContent() {
    final link = _link!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Trip Link field
        _InfoCard(
          label: 'Trip Link',
          value: link.shareUrl,
          icon: Icons.link_rounded,
          onCopy: () => _copyToClipboard(link.shareUrl, 'Trip link'),
        ),
        const SizedBox(height: 12),

        // Access Code field
        _InfoCard(
          label: 'Access Code',
          value: link.accessCode,
          icon: Icons.lock_rounded,
          isCode: true,
          onCopy: () => _copyToClipboard(link.accessCode, 'Access code'),
        ),
        const SizedBox(height: 8),

        // Expiry notice
        if (link.expiresAt != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                const Icon(
                  Icons.access_time_rounded,
                  size: 13,
                  color: Color(0xFF94A3B8),
                ),
                const SizedBox(width: 4),
                Text(
                  'Link expires ${_formatExpiry(link.expiresAt!)}',
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: Color(0xFF94A3B8),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 16),

        // Share button (primary)
        FilledButton.icon(
          onPressed: _actionLoading ? null : _shareLink,
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF2A86FF),
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          icon: const Icon(Icons.share_rounded, size: 18),
          label: const Text(
            'Share with Companions',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
          ),
        ),
        const SizedBox(height: 10),

        // Danger row
        Row(
          children: [
            Expanded(
              child: _OutlineButton(
                icon: Icons.block_rounded,
                label: 'Disable Link',
                color: Colors.red,
                onTap: _actionLoading ? null : _disableLink,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _OutlineButton(
                icon: Icons.refresh_rounded,
                label: 'New Link',
                color: const Color(0xFF2A86FF),
                onTap: _actionLoading ? null : _regenerateLink,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Security note
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFF0FDF4),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFBBF7D0)),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.security_rounded,
                size: 16,
                color: Color(0xFF16A34A),
              ),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Guests only see limited trip info: itinerary, tricycle number, and live location during the tour. Personal and payment details are never shown.',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: Color(0xFF166534),
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _formatExpiry(DateTime expires) {
    final now = DateTime.now();
    final diff = expires.difference(now);
    if (diff.isNegative) return 'soon';
    if (diff.inHours < 24) return 'in ${diff.inHours}h ${diff.inMinutes % 60}m';
    return 'on ${expires.day}/${expires.month}/${expires.year}';
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.onCopy,
    this.isCode = false,
  });

  final String label;
  final String value;
  final IconData icon;
  final VoidCallback onCopy;
  final bool isCode;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: const Color(0xFF2A86FF)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF94A3B8),
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: isCode ? 22 : 13,
                    fontWeight:
                        isCode ? FontWeight.w900 : FontWeight.w600,
                    color: const Color(0xFF1E293B),
                    letterSpacing: isCode ? 4 : 0,
                    fontFamily: isCode ? 'monospace' : null,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onCopy,
            icon: const Icon(Icons.copy_rounded, size: 18),
            color: const Color(0xFF64748B),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            tooltip: 'Copy',
          ),
        ],
      ),
    );
  }
}

class _OutlineButton extends StatelessWidget {
  const _OutlineButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(color: color.withValues(alpha: 0.5)),
        padding: const EdgeInsets.symmetric(vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      icon: Icon(icon, size: 16),
      label: Text(
        label,
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          const Icon(Icons.error_outline_rounded, color: Colors.red, size: 40),
          const SizedBox(height: 12),
          Text(
            'Could not load share link',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: onRetry,
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF2A86FF)),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}
