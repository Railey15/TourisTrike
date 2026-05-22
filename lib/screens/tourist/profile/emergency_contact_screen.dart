import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

class EmergencyContactsScreen extends StatefulWidget {
  const EmergencyContactsScreen({super.key});

  @override
  State<EmergencyContactsScreen> createState() =>
      _EmergencyContactsScreenState();
}

class _EmergencyContactsScreenState extends State<EmergencyContactsScreen> {
  final SupabaseClient _supabase = Supabase.instance.client;

  bool _loading = true;
  bool _saving = false;
  List<_EmergencyContact> _contacts = const [];
  RealtimeChannel? _realtimeChannel;

  User? get _user => _supabase.auth.currentUser;

  @override
  void initState() {
    super.initState();
    _loadData();
    _subscribeToRealtime();
  }

  @override
  void dispose() {
    _realtimeChannel?.unsubscribe();
    super.dispose();
  }

  Future<void> _loadData() async {
    final userId = _user?.id;
    if (userId == null) {
      if (mounted) {
        setState(() {
          _loading = false;
          _contacts = const [];
        });
      }
      return;
    }

    if (mounted) {
      setState(() => _loading = true);
    }

    try {
      final rows = await _supabase
          .from('emergency_contacts')
          .select()
          .eq('tourist_id', userId)
          .order('updated_at', ascending: false);

      if (!mounted) return;
      setState(() {
        _contacts = (rows as List<dynamic>)
            .map(
              (row) => _EmergencyContact.fromMap(
                Map<String, dynamic>.from(row as Map),
              ),
            )
            .toList();
        _loading = false;
      });
    } catch (error, stackTrace) {
      debugPrint('EmergencyContactsScreen _loadData error: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      setState(() => _loading = false);
      _showError('Unable to load emergency contacts.');
    }
  }

  void _subscribeToRealtime() {
    final userId = _user?.id;
    if (userId == null) return;

    _realtimeChannel?.unsubscribe();
    _realtimeChannel = _supabase
        .channel('emergency_contacts_$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'emergency_contacts',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'tourist_id',
            value: userId,
          ),
          callback: (_) => _loadData(),
        )
        .subscribe();
  }

  Future<void> _saveData({
    String? contactId,
    required _EmergencyContactDraft draft,
  }) async {
    final userId = _user?.id;
    if (userId == null || _saving) {
      if (userId == null) {
        _showError('No active session found. Please log in again.');
      }
      return;
    }

    if (mounted) {
      setState(() => _saving = true);
    }

    try {
      final payload = <String, dynamic>{
        'tourist_id': userId,
        'name': draft.name.trim(),
        'phone_number': draft.phoneNumber.trim(),
        'relationship': draft.relationship.trim(),
        'email': draft.email.trim().isEmpty ? null : draft.email.trim(),
        'updated_at': DateTime.now().toIso8601String(),
      };

      if (contactId == null) {
        await _supabase.from('emergency_contacts').insert(payload);
        _showSuccess('Emergency contact added.');
      } else {
        await _supabase
            .from('emergency_contacts')
            .update(payload)
            .eq('id', contactId)
            .eq('tourist_id', userId);
        _showSuccess('Emergency contact updated.');
      }

      await _loadData();
    } catch (error, stackTrace) {
      debugPrint('EmergencyContactsScreen _saveData error: $error');
      debugPrintStack(stackTrace: stackTrace);
      _showError('Unable to save this emergency contact.');
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _deleteData(_EmergencyContact contact) async {
    final userId = _user?.id;
    if (userId == null) {
      _showError('No active session found. Please log in again.');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Remove contact?'),
        content: Text('Delete ${contact.name} from your emergency contacts?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
            ),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    if (mounted) {
      setState(() => _saving = true);
    }

    try {
      await _supabase
          .from('emergency_contacts')
          .delete()
          .eq('id', contact.id)
          .eq('tourist_id', userId);
      _showSuccess('Emergency contact removed.');
      await _loadData();
    } catch (error, stackTrace) {
      debugPrint('EmergencyContactsScreen _deleteData error: $error');
      debugPrintStack(stackTrace: stackTrace);
      _showError('Unable to remove this emergency contact.');
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  void _showSuccess(String message) => _showSnack(message, isError: false);

  void _showError(String message) => _showSnack(message, isError: true);

  void _showSnack(String message, {required bool isError}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          backgroundColor: isError
              ? const Color(0xFFDC2626)
              : const Color(0xFF16A34A),
        ),
      );
  }

  Future<void> _openEditor({_EmergencyContact? contact}) async {
    final draft = await showModalBottomSheet<_EmergencyContactDraft>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EmergencyContactSheet(contact: contact),
    );

    if (draft == null) return;
    await _saveData(contactId: contact?.id, draft: draft);
  }

  Future<void> _launch(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  @override
  Widget build(BuildContext context) {
    const bg = Color(0xFFF5F7FB);
    const blue = Color(0xFF2A86FF);
    const textDark = Color(0xFF0F172A);

    return Scaffold(
      backgroundColor: bg,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _saving ? null : () => _openEditor(),
        backgroundColor: blue,
        foregroundColor: Colors.white,
        icon: _saving
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.add_rounded),
        label: const Text(
          'Add Contact',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          color: blue,
          onRefresh: _loadData,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
            children: [
              Row(
                children: [
                  _CircleButton(
                    icon: Icons.arrow_back_rounded,
                    onTap: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Emergency Contacts',
                      style: TextStyle(
                        color: textDark,
                        fontWeight: FontWeight.w900,
                        fontSize: 20,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const _HeroCard(),
              const SizedBox(height: 14),
              const Text(
                'Your Contacts',
                style: TextStyle(
                  color: textDark,
                  fontWeight: FontWeight.w900,
                  fontSize: 17,
                ),
              ),
              const SizedBox(height: 10),
              if (_loading)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(28),
                    child: CircularProgressIndicator(color: blue),
                  ),
                )
              else if (_contacts.isEmpty)
                const _EmptyState()
              else
                ..._contacts.map(
                  (contact) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _ContactCard(
                      contact: contact,
                      onCall: () =>
                          _launch('tel:${contact.phoneNumber.trim()}'),
                      onText: () =>
                          _launch('sms:${contact.phoneNumber.trim()}'),
                      onEmail: contact.email.trim().isEmpty
                          ? null
                          : () => _launch('mailto:${contact.email.trim()}'),
                      onEdit: () => _openEditor(contact: contact),
                      onDelete: () => _deleteData(contact),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmergencyContact {
  const _EmergencyContact({
    required this.id,
    required this.name,
    required this.phoneNumber,
    required this.relationship,
    required this.email,
  });

  factory _EmergencyContact.fromMap(Map<String, dynamic> map) {
    return _EmergencyContact(
      id: (map['id'] ?? '').toString(),
      name: (map['name'] ?? '').toString(),
      phoneNumber: (map['phone_number'] ?? '').toString(),
      relationship: (map['relationship'] ?? '').toString(),
      email: (map['email'] ?? '').toString(),
    );
  }

  final String id;
  final String name;
  final String phoneNumber;
  final String relationship;
  final String email;
}

class _EmergencyContactDraft {
  const _EmergencyContactDraft({
    required this.name,
    required this.phoneNumber,
    required this.relationship,
    required this.email,
  });

  final String name;
  final String phoneNumber;
  final String relationship;
  final String email;
}

class _HeroCard extends StatelessWidget {
  const _HeroCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFEFF6FF), Color(0xFFF0FDF4)],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFD6E8FF)),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Safety First',
            style: TextStyle(
              color: Color(0xFF0F172A),
              fontWeight: FontWeight.w900,
              fontSize: 18,
            ),
          ),
          SizedBox(height: 6),
          Text(
            'These contacts are loaded from your account in realtime so your latest safety information is always available.',
            style: TextStyle(
              color: Color(0xFF475569),
              fontWeight: FontWeight.w800,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _ContactCard extends StatelessWidget {
  const _ContactCard({
    required this.contact,
    required this.onCall,
    required this.onText,
    required this.onEmail,
    required this.onEdit,
    required this.onDelete,
  });

  final _EmergencyContact contact;
  final VoidCallback onCall;
  final VoidCallback onText;
  final VoidCallback? onEmail;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    const blue = Color(0xFF2A86FF);
    const textDark = Color(0xFF0F172A);
    const textMid = Color(0xFF64748B);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE7EEF7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF2FF),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(Icons.emergency_share_rounded, color: blue),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      contact.name,
                      style: const TextStyle(
                        color: textDark,
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      contact.relationship.trim().isEmpty
                          ? 'No relationship specified'
                          : contact.relationship,
                      style: const TextStyle(
                        color: textMid,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined, color: blue),
              ),
              IconButton(
                onPressed: onDelete,
                icon: const Icon(
                  Icons.delete_outline_rounded,
                  color: Color(0xFFDC2626),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _InfoRow(icon: Icons.phone_rounded, label: contact.phoneNumber),
          if (contact.email.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            _InfoRow(icon: Icons.email_outlined, label: contact.email),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _ActionChip(
                icon: Icons.call_rounded,
                label: 'Call',
                onTap: onCall,
              ),
              _ActionChip(
                icon: Icons.sms_rounded,
                label: 'Text',
                onTap: onText,
              ),
              if (onEmail != null)
                _ActionChip(
                  icon: Icons.email_rounded,
                  label: 'Email',
                  onTap: onEmail!,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: const Color(0xFF64748B)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }
}

class _ActionChip extends StatelessWidget {
  const _ActionChip({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFEAF2FF),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: const Color(0xFF2A86FF)),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                color: Color(0xFF2A86FF),
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CircleButton extends StatelessWidget {
  const _CircleButton({required this.icon, required this.onTap});

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

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE7EEF7)),
      ),
      child: const Text(
        'No emergency contacts yet. Add at least one trusted contact for safety sharing.',
        style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w900),
      ),
    );
  }
}

class _EmergencyContactSheet extends StatefulWidget {
  const _EmergencyContactSheet({this.contact});

  final _EmergencyContact? contact;

  @override
  State<_EmergencyContactSheet> createState() => _EmergencyContactSheetState();
}

class _EmergencyContactSheetState extends State<_EmergencyContactSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _relationshipCtrl;
  late final TextEditingController _emailCtrl;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.contact?.name ?? '');
    _phoneCtrl = TextEditingController(text: widget.contact?.phoneNumber ?? '');
    _relationshipCtrl = TextEditingController(
      text: widget.contact?.relationship ?? '',
    );
    _emailCtrl = TextEditingController(text: widget.contact?.email ?? '');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _relationshipCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: const Color(0xFFE2E8F0),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.contact == null
                          ? 'Add Emergency Contact'
                          : 'Edit Emergency Contact',
                      style: const TextStyle(
                        color: Color(0xFF0F172A),
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _SheetTextField(
                controller: _nameCtrl,
                label: 'Name',
                validator: _requiredValidator,
              ),
              const SizedBox(height: 10),
              _SheetTextField(
                controller: _phoneCtrl,
                label: 'Phone Number',
                keyboardType: TextInputType.phone,
                validator: _requiredValidator,
              ),
              const SizedBox(height: 10),
              _SheetTextField(
                controller: _relationshipCtrl,
                label: 'Relationship',
                validator: _requiredValidator,
              ),
              const SizedBox(height: 10),
              _SheetTextField(
                controller: _emailCtrl,
                label: 'Email',
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: () {
                    if (!_formKey.currentState!.validate()) return;
                    Navigator.pop(
                      context,
                      _EmergencyContactDraft(
                        name: _nameCtrl.text,
                        phoneNumber: _phoneCtrl.text,
                        relationship: _relationshipCtrl.text,
                        email: _emailCtrl.text,
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2A86FF),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  child: Text(
                    widget.contact == null ? 'Add Contact' : 'Save Changes',
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String? _requiredValidator(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'This field is required.';
    }
    return null;
  }
}

class _SheetTextField extends StatelessWidget {
  const _SheetTextField({
    required this.controller,
    required this.label,
    this.keyboardType,
    this.validator,
  });

  final TextEditingController controller;
  final String label;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: const Color(0xFFF8FAFC),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0xFFE7EEF7)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0xFFE7EEF7)),
        ),
      ),
    );
  }
}
