import 'package:flutter/material.dart';

class PaymentMethodsScreen extends StatefulWidget {
  const PaymentMethodsScreen({super.key});

  @override
  State<PaymentMethodsScreen> createState() => _PaymentMethodsScreenState();
}

class _PaymentMethodsScreenState extends State<PaymentMethodsScreen> {
  int _selectedIndex = 0;

  final List<PaymentMethod> _methods = [
    const PaymentMethod(
      type: PaymentType.cash,
      title: 'Cash',
      subtitle: 'Pay directly to your driver or guide',
      icon: Icons.payments_rounded,
    ),
  ];

  Future<void> _addMethod() async {
    final method = await showModalBottomSheet<PaymentMethod>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _PaymentMethodSheet(),
    );

    if (method == null) return;

    setState(() {
      _methods.add(method);
      _selectedIndex = _methods.length - 1;
    });
  }

  void _removeMethod(int index) {
    if (_methods[index].type == PaymentType.cash) return;

    setState(() {
      _methods.removeAt(index);
      if (_selectedIndex >= _methods.length) {
        _selectedIndex = 0;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    const bg = Color(0xFFF5F7FB);
    const blue = Color(0xFF2A86FF);
    const textDark = Color(0xFF0F172A);
    const textMid = Color(0xFF64748B);
    const line = Color(0xFFE7EEF7);

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
                      'Payment Methods',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: textDark,
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
                  const Text(
                    'Your Methods',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: textDark,
                    ),
                  ),
                  const SizedBox(height: 10),
                  ..._methods.asMap().entries.map((entry) {
                    final index = entry.key;
                    final method = entry.value;
                    final isSelected = index == _selectedIndex;

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(22),
                        onTap: () => setState(() => _selectedIndex = index),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(22),
                            border: Border.all(
                              color: isSelected ? blue : line,
                              width: isSelected ? 2 : 1,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.045),
                                blurRadius: 18,
                                offset: const Offset(0, 12),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEAF2FF),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Icon(method.icon, color: blue),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      method.title,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w900,
                                        color: textDark,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      method.subtitle,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                        color: textMid,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (isSelected)
                                const Icon(
                                  Icons.check_circle_rounded,
                                  color: blue,
                                ),
                              if (method.type != PaymentType.cash)
                                IconButton(
                                  onPressed: () => _removeMethod(index),
                                  icon: const Icon(
                                    Icons.delete_outline_rounded,
                                    color: Color(0xFFDC2626),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                  const SizedBox(height: 4),
                  InkWell(
                    onTap: _addMethod,
                    borderRadius: BorderRadius.circular(18),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEAF2FF),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: const Color(0xFFBBD7FF)),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.add_rounded, color: blue),
                          SizedBox(width: 8),
                          Text(
                            'Add Payment Method',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              color: blue,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Cash remains available even when no digital method is added.',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: textMid,
                      fontSize: 12,
                    ),
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

class _PaymentMethodSheet extends StatefulWidget {
  const _PaymentMethodSheet();

  @override
  State<_PaymentMethodSheet> createState() => _PaymentMethodSheetState();
}

class _PaymentMethodSheetState extends State<_PaymentMethodSheet> {
  PaymentType _type = PaymentType.gcash;
  final _labelCtrl = TextEditingController();
  final _detailCtrl = TextEditingController();

  @override
  void dispose() {
    _labelCtrl.dispose();
    _detailCtrl.dispose();
    super.dispose();
  }

  bool get _canSave =>
      _labelCtrl.text.trim().isNotEmpty && _detailCtrl.text.trim().isNotEmpty;

  String get _detailLabel =>
      _type == PaymentType.gcash ? 'Mobile number' : 'Last 4 digits';

  String get _detailHint => _type == PaymentType.gcash ? '09XXXXXXXXX' : '1234';

  IconData get _icon => _type == PaymentType.gcash
      ? Icons.account_balance_wallet_rounded
      : Icons.credit_card_rounded;

  @override
  Widget build(BuildContext context) {
    const blue = Color(0xFF2A86FF);
    const textDark = Color(0xFF0F172A);

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
                const Expanded(
                  child: Text(
                    'Add Payment Method',
                    style: TextStyle(
                      color: textDark,
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
            const SizedBox(height: 10),
            SegmentedButton<PaymentType>(
              segments: const [
                ButtonSegment(
                  value: PaymentType.gcash,
                  icon: Icon(Icons.account_balance_wallet_rounded),
                  label: Text('GCash'),
                ),
                ButtonSegment(
                  value: PaymentType.card,
                  icon: Icon(Icons.credit_card_rounded),
                  label: Text('Card'),
                ),
              ],
              selected: {_type},
              onSelectionChanged: (value) {
                setState(() {
                  _type = value.first;
                  _labelCtrl.clear();
                  _detailCtrl.clear();
                });
              },
            ),
            const SizedBox(height: 12),
            _SheetTextField(
              label: 'Label',
              hint: _type == PaymentType.gcash ? 'My GCash' : 'Personal Card',
              controller: _labelCtrl,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 10),
            _SheetTextField(
              label: _detailLabel,
              hint: _detailHint,
              controller: _detailCtrl,
              keyboardType: TextInputType.number,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: !_canSave
                    ? null
                    : () {
                        final detail = _detailCtrl.text.trim();
                        final subtitle = _type == PaymentType.gcash
                            ? _maskPhone(detail)
                            : 'Card ending in ${detail.length <= 4 ? detail : detail.substring(detail.length - 4)}';

                        Navigator.pop(
                          context,
                          PaymentMethod(
                            type: _type,
                            title: _labelCtrl.text.trim(),
                            subtitle: subtitle,
                            icon: _icon,
                          ),
                        );
                      },
                icon: const Icon(Icons.check_rounded),
                label: const Text('Save Method'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: blue,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: const Color(0xFFBBD7FF),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                  textStyle: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _maskPhone(String value) {
    if (value.length <= 4) return value;
    return '${value.substring(0, 4)} ${'*' * (value.length - 7)} ${value.substring(value.length - 3)}';
  }
}

class _SheetTextField extends StatelessWidget {
  const _SheetTextField({
    required this.label,
    required this.hint,
    required this.controller,
    this.keyboardType,
    this.onChanged,
  });

  final String label;
  final String hint;
  final TextEditingController controller;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        filled: true,
        fillColor: const Color(0xFFF8FAFC),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFE7EEF7)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFE7EEF7)),
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
        decoration: const BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: const Color(0xFF0F172A)),
      ),
    );
  }
}

enum PaymentType { cash, gcash, card }

class PaymentMethod {
  const PaymentMethod({
    required this.type,
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  final PaymentType type;
  final String title;
  final String subtitle;
  final IconData icon;
}
