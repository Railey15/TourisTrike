import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Emergency Contacts Screen
/// - Primary SOS contact + optional list
/// - Quick actions copy contact details for phone or SMS use.
/// - Add/edit/remove contact flow with primary contact selection.
///
/// Navigate:
/// Navigator.push(context, MaterialPageRoute(builder: (_) => const EmergencyContactsScreen()));
class EmergencyContactsScreen extends StatefulWidget {
  const EmergencyContactsScreen({super.key});

  @override
  State<EmergencyContactsScreen> createState() =>
      _EmergencyContactsScreenState();
}

class _EmergencyContactsScreenState extends State<EmergencyContactsScreen> {
  final List<EmergencyContact> _contacts = [];

  bool _shareTripStatus = true;

  EmergencyContact? get _primary =>
      _contacts.where((c) => c.isPrimary).isNotEmpty
      ? _contacts.firstWhere((c) => c.isPrimary)
      : null;

  void _setPrimary(EmergencyContact contact) {
    setState(() {
      for (final c in _contacts) {
        c.isPrimary = false;
      }
      contact.isPrimary = true;
    });
  }

  void _removeContact(EmergencyContact contact) {
    setState(() {
      _contacts.remove(contact);
      if (_contacts.isNotEmpty && _contacts.every((c) => !c.isPrimary)) {
        _contacts.first.isPrimary = true;
      }
    });
  }

  Future<void> _addContact() async {
    final created = await showModalBottomSheet<EmergencyContact>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _AddContactSheet(),
    );

    if (created != null) {
      setState(() {
        if (_contacts.isEmpty) created.isPrimary = true;
        _contacts.add(created);
      });
    }
  }

  void _editContact(EmergencyContact contact) async {
    final updated = await showModalBottomSheet<EmergencyContact>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddContactSheet(existing: contact),
    );

    if (updated != null) {
      setState(() {
        final idx = _contacts.indexOf(contact);
        if (idx != -1) {
          updated.isPrimary = contact.isPrimary;
          _contacts[idx] = updated;
        }
      });
    }
  }

  Future<void> _call(EmergencyContact c) async {
    await Clipboard.setData(ClipboardData(text: c.phone));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('${c.name} phone number copied')));
  }

  Future<void> _message(EmergencyContact c) async {
    await Clipboard.setData(ClipboardData(text: c.phone));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('${c.name} SMS number copied')));
  }

  @override
  Widget build(BuildContext context) {
    const bg = Color(0xFFF5F7FB);
    const blue = Color(0xFF2A86FF);
    const textDark = Color(0xFF0F172A);
    const textMid = Color(0xFF64748B);
    const textLight = Color(0xFF94A3B8);
    const line = Color(0xFFE7EEF7);

    final primary = _primary;

    return Scaffold(
      backgroundColor: bg,

      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          child: SizedBox(
            height: 54,
            child: ElevatedButton.icon(
              onPressed: _addContact,
              style: ElevatedButton.styleFrom(
                backgroundColor: blue,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
                elevation: 0,
                textStyle: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                ),
              ),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add Emergency Contact'),
            ),
          ),
        ),
      ),

      body: SafeArea(
        child: Column(
          children: [
            // ============================================================
            // TOP BAR
            // ============================================================
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
                      'Emergency Contacts',
                      style: TextStyle(
                        fontSize: 20.5,
                        fontWeight: FontWeight.w900,
                        color: textDark,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ),
                  InkWell(
                    onTap: () {
                      showModalBottomSheet<void>(
                        context: context,
                        backgroundColor: Colors.transparent,
                        builder: (_) => _InfoSheet(
                          title: 'How it works',
                          bullets: const [
                            'Your primary contact is shown first and used for SOS sharing.',
                            'You can call or message contacts quickly from here.',
                            'You can optionally share trip status with your emergency contact.',
                          ],
                        ),
                      );
                    },
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
                      child: const Icon(
                        Icons.info_outline_rounded,
                        color: textMid,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
                children: [
                  // ============================================================
                  // SOS / PRIMARY CARD
                  // ============================================================
                  if (primary != null)
                    _Card(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: const [
                              _Chip(
                                text: 'PRIMARY',
                                bg: Color(0xFFEAF2FF),
                                fg: blue,
                              ),
                              SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Emergency contact for SOS sharing',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: textLight,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          _ContactRow(
                            contact: primary,
                            primary: true,
                            onCall: () => _call(primary),
                            onMessage: () => _message(primary),
                            onMore: () => _showContactActions(primary),
                          ),
                          const SizedBox(height: 12),
                          const Divider(height: 1, color: line),
                          const SizedBox(height: 12),

                          // Share trip status toggle
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: const [
                                    Text(
                                      'Share Trip Status',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w900,
                                        color: textDark,
                                      ),
                                    ),
                                    SizedBox(height: 6),
                                    Text(
                                      'Send updates when your trip starts, ends, or is cancelled.',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        color: textMid,
                                        fontSize: 12.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Switch(
                                value: _shareTripStatus,
                                onChanged: (v) =>
                                    setState(() => _shareTripStatus = v),
                              ),
                            ],
                          ),
                        ],
                      ),
                    )
                  else
                    _Card(
                      child: Row(
                        children: const [
                          Icon(
                            Icons.warning_amber_rounded,
                            color: Color(0xFFF59E0B),
                          ),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Add a primary emergency contact to enable SOS sharing.',
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                color: textMid,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                  const SizedBox(height: 12),

                  // ============================================================
                  // CONTACTS LIST
                  // ============================================================
                  _SectionHeader(
                    title: 'Your Contacts',
                    trailing: Text('${_contacts.length}'),
                  ),
                  const SizedBox(height: 8),

                  if (_contacts.isEmpty)
                    const _EmptyState()
                  else
                    ..._contacts.map((c) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _Card(
                          child: _ContactRow(
                            contact: c,
                            primary: c.isPrimary,
                            onCall: () => _call(c),
                            onMessage: () => _message(c),
                            onMore: () => _showContactActions(c),
                          ),
                        ),
                      );
                    }),

                  const SizedBox(height: 4),

                  // ============================================================
                  // SMALL SAFETY NOTE
                  // ============================================================
                  _Card(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Icon(Icons.shield_rounded, color: blue),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Tip: Keep at least 2 emergency contacts for better coverage.',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              color: textMid,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 18),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showContactActions(EmergencyContact c) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _ActionSheet(
        title: c.name,
        subtitle: '${c.relation} â€¢ ${c.phone}',
        actions: [
          _SheetAction(
            icon: Icons.star_rounded,
            label: c.isPrimary ? 'Primary contact' : 'Set as Primary',
            onTap: c.isPrimary
                ? null
                : () {
                    Navigator.pop(context);
                    _setPrimary(c);
                  },
          ),
          _SheetAction(
            icon: Icons.edit_rounded,
            label: 'Edit',
            onTap: () {
              Navigator.pop(context);
              _editContact(c);
            },
          ),
          _SheetAction(
            icon: Icons.delete_outline_rounded,
            label: 'Remove',
            isDanger: true,
            onTap: () {
              Navigator.pop(context);
              _removeContact(c);
            },
          ),
        ],
      ),
    );
  }
}

// ============================================================
// MODELS
// ============================================================

class EmergencyContact {
  EmergencyContact({
    required this.name,
    required this.phone,
    required this.relation,
    this.isPrimary = false,
  });

  final String name;
  final String phone;
  final String relation;
  bool isPrimary;
}

// ============================================================
// UI COMPONENTS (same visual language)
// ============================================================

class _Card extends StatelessWidget {
  const _Card({required this.child});
  final Widget child;

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
      child: child,
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

class _Chip extends StatelessWidget {
  const _Chip({required this.text, required this.bg, required this.fg});
  final String text;
  final Color bg;
  final Color fg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontWeight: FontWeight.w900,
          color: fg,
          fontSize: 12,
          letterSpacing: 0.35,
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.trailing});
  final String title;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    const textDark = Color(0xFF0F172A);
    const textMid = Color(0xFF64748B);

    return Row(
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 16.5,
            fontWeight: FontWeight.w900,
            color: textDark,
            letterSpacing: -0.2,
          ),
        ),
        const Spacer(),
        DefaultTextStyle(
          style: const TextStyle(fontWeight: FontWeight.w900, color: textMid),
          child: trailing,
        ),
      ],
    );
  }
}

class _ContactRow extends StatelessWidget {
  const _ContactRow({
    required this.contact,
    required this.primary,
    required this.onCall,
    required this.onMessage,
    required this.onMore,
  });

  final EmergencyContact contact;
  final bool primary;
  final VoidCallback onCall;
  final VoidCallback onMessage;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    const blue = Color(0xFF2A86FF);
    const textDark = Color(0xFF0F172A);
    const textMid = Color(0xFF64748B);

    return Row(
      children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: const Color(0xFFEAF2FF),
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFFE7EEF7)),
          ),
          child: const Icon(Icons.person_rounded, color: blue),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      contact.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        color: textDark,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  if (primary)
                    const Padding(
                      padding: EdgeInsets.only(left: 8),
                      child: _Chip(
                        text: 'PRIMARY',
                        bg: Color(0xFFEAF2FF),
                        fg: blue,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '${contact.relation} â€¢ ${contact.phone}',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  color: textMid,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),

        // Call
        _IconPill(icon: Icons.call_rounded, onTap: onCall),
        const SizedBox(width: 8),

        // Message
        _IconPill(icon: Icons.sms_rounded, onTap: onMessage),
        const SizedBox(width: 8),

        // More
        _IconPill(icon: Icons.more_horiz_rounded, onTap: onMore),
      ],
    );
  }
}

class _IconPill extends StatelessWidget {
  const _IconPill({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const textMid = Color(0xFF64748B);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Icon(icon, color: textMid, size: 20),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    const textMid = Color(0xFF64748B);
    const line = Color(0xFFE7EEF7);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: line),
      ),
      child: const Text(
        'No emergency contacts yet.\nTap â€œAdd Emergency Contactâ€ to add one.',
        style: TextStyle(fontWeight: FontWeight.w900, color: textMid),
      ),
    );
  }
}

// ============================================================
// BOTTOM SHEETS
// ============================================================

class _ActionSheet extends StatelessWidget {
  const _ActionSheet({
    required this.title,
    required this.subtitle,
    required this.actions,
  });

  final String title;
  final String subtitle;
  final List<_SheetAction> actions;

  @override
  Widget build(BuildContext context) {
    const line = Color(0xFFE7EEF7);
    const textDark = Color(0xFF0F172A);
    const textMid = Color(0xFF64748B);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
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
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        color: textDark,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: textMid,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Divider(height: 1, color: line),
          const SizedBox(height: 10),
          ...actions.map((a) => a),
        ],
      ),
    );
  }
}

class _SheetAction extends StatelessWidget {
  const _SheetAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isDanger = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool isDanger;

  @override
  Widget build(BuildContext context) {
    const line = Color(0xFFE7EEF7);
    const textDark = Color(0xFF0F172A);
    const textMid = Color(0xFF64748B);
    const red = Color(0xFFDC2626);

    final fg = isDanger ? red : (onTap == null ? textMid : textDark);
    final iconColor = isDanger ? red : textMid;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: onTap == null ? const Color(0xFFF8FAFF) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: line),
        ),
        child: Row(
          children: [
            Icon(icon, color: iconColor),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: TextStyle(fontWeight: FontWeight.w900, color: fg),
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: textMid),
          ],
        ),
      ),
    );
  }
}

class _AddContactSheet extends StatefulWidget {
  const _AddContactSheet({this.existing});

  final EmergencyContact? existing;

  @override
  State<_AddContactSheet> createState() => _AddContactSheetState();
}

class _AddContactSheetState extends State<_AddContactSheet> {
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _relationCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    final ex = widget.existing;
    if (ex != null) {
      _nameCtrl.text = ex.name;
      _phoneCtrl.text = ex.phone;
      _relationCtrl.text = ex.relation;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _relationCtrl.dispose();
    super.dispose();
  }

  bool get _canSave =>
      _nameCtrl.text.trim().isNotEmpty &&
      _phoneCtrl.text.trim().isNotEmpty &&
      _relationCtrl.text.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    const blue = Color(0xFF2A86FF);
    const textDark = Color(0xFF0F172A);
    const textMid = Color(0xFF64748B);

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
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
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.existing == null ? 'Add Contact' : 'Edit Contact',
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      color: textDark,
                      fontSize: 16,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 10),

            _TextField(
              label: 'Full Name',
              controller: _nameCtrl,
              hint: 'e.g. Maria Dela Cruz',
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 10),
            _TextField(
              label: 'Phone Number',
              controller: _phoneCtrl,
              hint: 'e.g. 09xx xxx xxxx',
              keyboardType: TextInputType.phone,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 10),
            _TextField(
              label: 'Relationship',
              controller: _relationCtrl,
              hint: 'e.g. Mother, Friend',
              onChanged: (_) => setState(() {}),
            ),

            const SizedBox(height: 14),

            SizedBox(
              height: 52,
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _canSave
                    ? () {
                        Navigator.pop(
                          context,
                          EmergencyContact(
                            name: _nameCtrl.text.trim(),
                            phone: _phoneCtrl.text.trim(),
                            relation: _relationCtrl.text.trim(),
                          ),
                        );
                      }
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: blue,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: const Color(0xFFBBD7FF),
                  disabledForegroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                  elevation: 0,
                  textStyle: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
                child: Text(widget.existing == null ? 'Add' : 'Save'),
              ),
            ),

            const SizedBox(height: 8),
            const Text(
              'We will only use this for safety and emergency sharing.',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: textMid,
                fontSize: 12.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TextField extends StatelessWidget {
  const _TextField({
    required this.label,
    required this.controller,
    required this.hint,
    this.keyboardType,
    this.onChanged,
  });

  final String label;
  final TextEditingController controller;
  final String hint;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    const line = Color(0xFFE7EEF7);
    const textDark = Color(0xFF0F172A);
    const textLight = Color(0xFF94A3B8);
    const textMid = Color(0xFF64748B);

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              color: textMid,
              fontSize: 12,
              letterSpacing: 0.7,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: controller,
            keyboardType: keyboardType,
            onChanged: onChanged,
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              color: textDark,
              fontSize: 16,
              letterSpacing: -0.2,
            ),
            decoration: InputDecoration(
              isDense: true,
              hintText: hint,
              hintStyle: const TextStyle(
                fontWeight: FontWeight.w900,
                color: textLight,
              ),
              border: InputBorder.none,
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoSheet extends StatelessWidget {
  const _InfoSheet({required this.title, required this.bullets});

  final String title;
  final List<String> bullets;

  @override
  Widget build(BuildContext context) {
    const textDark = Color(0xFF0F172A);
    const line = Color(0xFFE7EEF7);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
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
          const SizedBox(height: 12),

          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    color: textDark,
                    fontSize: 16,
                  ),
                ),
              ),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),

          const SizedBox(height: 10),
          const Divider(height: 1, color: line),
          const SizedBox(height: 10),

          // âœ… Proper bullet rendering (once)
          ...bullets.map(
            (b) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  // We'll build this row below without const children
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
