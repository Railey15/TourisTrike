import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PrivacyPolicyScreen extends StatefulWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  State<PrivacyPolicyScreen> createState() => _PrivacyPolicyScreenState();
}

class _PrivacyPolicyScreenState extends State<PrivacyPolicyScreen> {
  final SupabaseClient _supabase = Supabase.instance.client;

  bool _loading = true;
  _PolicyDocument? _policy;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    if (mounted) {
      setState(() => _loading = true);
    }

    try {
      final row = await _supabase
          .from('tourism_policies')
          .select()
          .eq('status', 'published')
          .order('updated_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (!mounted) return;
      setState(() {
        _policy = row == null ? null : _PolicyDocument.fromMap(row);
        _loading = false;
      });
    } catch (error, stackTrace) {
      debugPrint('PrivacyPolicyScreen _loadData error: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      setState(() => _loading = false);
      _showError('Unable to load the privacy policy.');
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFFDC2626),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    const bg = Color(0xFFF5F7FB);
    const textDark = Color(0xFF0F172A);

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Column(
          children: [
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
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                color: const Color(0xFF2A86FF),
                onRefresh: _loadData,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
                  children: [
                    if (_loading)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(28),
                          child: CircularProgressIndicator(
                            color: Color(0xFF2A86FF),
                          ),
                        ),
                      )
                    else if (_policy == null)
                      const _EmptyState(
                        message:
                            'No published privacy policy is available yet.',
                      )
                    else
                      _PolicyCard(policy: _policy!),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PolicyDocument {
  const _PolicyDocument({
    required this.title,
    required this.content,
    required this.updatedAt,
  });

  factory _PolicyDocument.fromMap(Map<String, dynamic> map) {
    return _PolicyDocument(
      title: (map['title'] ?? '').toString(),
      content: (map['content'] ?? '').toString(),
      updatedAt: DateTime.tryParse((map['updated_at'] ?? '').toString()),
    );
  }

  final String title;
  final String content;
  final DateTime? updatedAt;

  String get updatedLabel {
    if (updatedAt == null) return 'Unknown date';
    return DateFormat.yMMMMd().format(updatedAt!.toLocal());
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
  const _PolicyCard({required this.policy});

  final _PolicyDocument policy;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE7EEF7)),
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
        children: [
          Text(
            policy.title.trim().isEmpty ? 'Privacy Policy' : policy.title,
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              color: Color(0xFF0F172A),
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Last updated ${policy.updatedLabel}',
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              color: Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            policy.content.trim().isEmpty
                ? 'No policy content was provided.'
                : policy.content,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              color: Color(0xFF64748B),
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE7EEF7)),
      ),
      child: Text(
        message,
        style: const TextStyle(
          color: Color(0xFF64748B),
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}
