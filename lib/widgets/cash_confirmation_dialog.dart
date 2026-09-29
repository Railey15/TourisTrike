import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class CashConfirmationPromptGate {
  final Set<String> _presented = {};
  bool shouldPresent(String paymentId) => _presented.add(paymentId);
}

class CashConfirmationDialog extends StatefulWidget {
  const CashConfirmationDialog({
    super.key,
    required this.amount,
    required this.onConfirm,
  });
  final double amount;
  final Future<void> Function() onConfirm;
  @override
  State<CashConfirmationDialog> createState() => _CashConfirmationDialogState();
}

class _CashConfirmationDialogState extends State<CashConfirmationDialog> {
  bool _busy = false;
  String? _error;
  Future<void> _confirm() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onConfirm();
      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          final code = error.toString();
          _error = code.contains('CASH_PAYMENT_STATE_CHANGED')
              ? 'The amount changed. Refresh the tour before confirming cash.'
              : code.contains('NOT_ASSIGNED_PAYMENT_DRIVER') ||
                    code.contains('BOOKING_NOT_ACTIVE')
              ? 'This cash confirmation is no longer available for your assignment.'
              : 'Cash could not be confirmed. Check your connection and retry.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      title: const Text('Confirm cash payment'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'The Tourist selected Cash for the remaining balance. '
              'Confirm only after receiving your allocated share.',
            ),
            const SizedBox(height: 16),
            const Text('Amount received'),
            Text(
              '₱${NumberFormat('#,##0.00').format(widget.amount)}',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Not yet'),
        ),
        FilledButton(
          onPressed: _busy ? null : _confirm,
          child: Text(_busy ? 'Confirming…' : 'Confirm Cash Received'),
        ),
      ],
    ),
  );
}
