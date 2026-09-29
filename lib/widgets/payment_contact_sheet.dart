import 'package:flutter/material.dart';

class PaymentContact {
  const PaymentContact({required this.name, required this.email});
  final String name;
  final String email;

  factory PaymentContact.fromAccount({
    Map<String, dynamic>? profile,
    String? authEmail,
  }) {
    final fullName = profile?['full_name']?.toString().trim() ?? '';
    final parts = [
      profile?['first_name'],
      profile?['middle_name'],
      profile?['last_name'],
    ].map((v) => v?.toString().trim() ?? '').where((v) => v.isNotEmpty);
    return PaymentContact(
      name: fullName.isNotEmpty ? fullName : parts.join(' '),
      email: authEmail?.trim() ?? '',
    );
  }
}

/// Transaction-only contact data. This sheet performs no profile/auth writes.
class PaymentContactSheet extends StatefulWidget {
  const PaymentContactSheet({super.key, this.name = '', this.email = ''});
  final String name;
  final String email;
  @override
  State<PaymentContactSheet> createState() => _PaymentContactSheetState();
}

class _PaymentContactSheetState extends State<PaymentContactSheet> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.name);
  late final _email = TextEditingController(text: widget.email);
  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Payment contact information',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Name'),
              validator: (value) =>
                  (value ?? '').trim().isEmpty ? 'Enter a name' : null,
            ),
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Email'),
              validator: (value) =>
                  RegExp(
                    r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
                  ).hasMatch((value ?? '').trim())
                  ? null
                  : 'Enter a valid email',
            ),
            const SizedBox(height: 12),
            const Text('Used for this payment only.'),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () {
                if (_form.currentState!.validate()) {
                  Navigator.pop(
                    context,
                    PaymentContact(
                      name: _name.text.trim(),
                      email: _email.text.trim(),
                    ),
                  );
                }
              },
              child: const Text('Continue to PayMongo'),
            ),
          ],
        ),
      ),
    ),
  );
}
