import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:touristrike/core/supabase/touristrike_models.dart';
import 'package:touristrike/core/supabase/touristrike_repository.dart';

// TourisTrike does NOT custody funds — GCash-to-GCash direct. Outside AMLA covered-person scope (RA 9160).
// This sheet only displays the payee's personal GCash QR/number and records the
// reference number the payer enters. The money moves directly between the two
// personal GCash accounts; TourisTrike never touches it.

const String _paymentProofBucket = 'payment-proofs';

/// Opens the GCash-or-cash payment sheet and returns the created [PaymentRecord]
/// once the payer submits, or null if they cancel.
Future<PaymentRecord?> showGcashPaymentSheet(
  BuildContext context, {
  required String payeeId,
  required String payeeName,
  required String gcashQrUrl,
  required String gcashNumber,
  required String gcashName,
  required double amount,
  required String serviceDescription,
  dynamic bookingId,
  dynamic rideId,
  String paymentStage = 'full',
}) {
  return showModalBottomSheet<PaymentRecord>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => GcashPaymentSheet(
      payeeId: payeeId,
      payeeName: payeeName,
      gcashQrUrl: gcashQrUrl,
      gcashNumber: gcashNumber,
      gcashName: gcashName,
      amount: amount,
      serviceDescription: serviceDescription,
      bookingId: bookingId,
      rideId: rideId,
      paymentStage: paymentStage,
    ),
  );
}

class GcashPaymentSheet extends StatefulWidget {
  const GcashPaymentSheet({
    super.key,
    required this.payeeId,
    required this.payeeName,
    required this.gcashQrUrl,
    required this.gcashNumber,
    required this.gcashName,
    required this.amount,
    required this.serviceDescription,
    this.bookingId,
    this.rideId,
    this.paymentStage = 'full',
  });

  final String payeeId;
  final String payeeName;
  final String gcashQrUrl;
  final String gcashNumber;
  final String gcashName;
  final double amount;
  final String serviceDescription;
  final dynamic bookingId;
  final dynamic rideId;
  final String paymentStage;

  @override
  State<GcashPaymentSheet> createState() => _GcashPaymentSheetState();
}

class _GcashPaymentSheetState extends State<GcashPaymentSheet> {
  final TourisTrikeRepository _repo = TourisTrikeRepository();
  final TextEditingController _referenceController = TextEditingController();
  final ImagePicker _imagePicker = ImagePicker();

  String _method = 'gcash';
  bool _showReferenceForm = false;
  XFile? _proofFile;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.gcashQrUrl.isEmpty &&
        (widget.gcashNumber.isEmpty || widget.gcashName.isEmpty)) {
      _method = 'cash';
    }
  }

  @override
  void dispose() {
    _referenceController.dispose();
    super.dispose();
  }

  bool get _hasGcashDetails =>
      widget.gcashQrUrl.trim().isNotEmpty ||
      (widget.gcashNumber.trim().isNotEmpty && widget.gcashName.trim().isNotEmpty);

  Future<void> _pickProof() async {
    final file = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 78,
      maxWidth: 1600,
    );
    if (file == null || !mounted) return;
    setState(() => _proofFile = file);
  }

  Future<void> _submit() async {
    if (_submitting) return;

    if (_method == 'gcash') {
      final ref = _referenceController.text.trim();
      if (!RegExp(r'^\d{10,13}$').hasMatch(ref)) {
        setState(() => _error = 'Enter a valid 10–13 digit GCash reference number.');
        return;
      }
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final record = await _repo.createPaymentRecord(
        rideId: widget.rideId,
        bookingId: widget.bookingId,
        payeeId: widget.payeeId,
        amount: widget.amount,
        paymentMethod: _method,
        paymentStage: widget.paymentStage,
        externalReferenceNo: _method == 'gcash'
            ? _referenceController.text.trim()
            : null,
        serviceDescription: widget.serviceDescription,
      );

      if (_method == 'gcash' && _proofFile != null) {
        try {
          final signedUrl = await _uploadProof(record.id as String, _proofFile!);
          await _repo.attachPaymentProof(
            paymentRecordId: record.id as String,
            proofImageUrl: signedUrl,
          );
        } catch (_) {
          // Proof upload is best-effort — the payment record itself already
          // exists and is awaiting confirmation either way.
        }
      }

      unawaited(
        _repo.notifyUser(
          userId: widget.payeeId,
          title: 'Payment submitted',
          body:
              '₱${widget.amount.toStringAsFixed(2)} via ${_method == 'gcash' ? 'GCash' : 'cash'} '
              'is awaiting your confirmation.',
          type: 'payment_submitted',
        ),
      );

      if (!mounted) return;
      Navigator.of(context).pop(record);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = 'Unable to submit payment: $error';
      });
    }
  }

  Future<String> _uploadProof(String paymentRecordId, XFile file) async {
    final bytes = await file.readAsBytes();
    final ext = file.path.split('.').last.trim().toLowerCase();
    final path =
        '$paymentRecordId/proof_${DateTime.now().millisecondsSinceEpoch}.${ext.isEmpty ? 'jpg' : ext}';
    final storage = Supabase.instance.client.storage.from(_paymentProofBucket);
    await storage.uploadBinary(
      path,
      Uint8List.fromList(bytes),
      fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: true),
    );
    return storage.createSignedUrl(path, 60 * 60 * 24 * 365);
  }

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(symbol: '₱', decimalDigits: 2);
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            20,
            14,
            20,
            MediaQuery.of(context).padding.bottom + 20,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE2E8F0),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Pay Directly',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                widget.serviceDescription,
                style: const TextStyle(
                  color: Color(0xFF64748B),
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0F7FF),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Column(
                  children: [
                    Text(
                      currency.format(widget.amount),
                      style: const TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF2A86FF),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Amount due to ${widget.payeeName}',
                      style: const TextStyle(
                        color: Color(0xFF64748B),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _MethodChip(
                      label: 'GCash',
                      icon: Icons.qr_code_2_rounded,
                      selected: _method == 'gcash',
                      enabled: _hasGcashDetails,
                      onTap: _hasGcashDetails
                          ? () => setState(() {
                              _method = 'gcash';
                              _error = null;
                            })
                          : null,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _MethodChip(
                      label: 'Cash',
                      icon: Icons.payments_rounded,
                      selected: _method == 'cash',
                      enabled: true,
                      onTap: () => setState(() {
                        _method = 'cash';
                        _error = null;
                      }),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              if (_method == 'gcash') ..._buildGcashSection() else ..._buildCashSection(),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: const TextStyle(
                    color: Color(0xFFDC2626),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  onPressed: _submitting || (_method == 'gcash' && !_showReferenceForm)
                      ? (_method == 'gcash' && !_showReferenceForm
                            ? () => setState(() => _showReferenceForm = true)
                            : null)
                      : _submit,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF2A86FF),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: _submitting
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          _method == 'gcash' && !_showReferenceForm
                              ? 'I Already Paid'
                              : _method == 'gcash'
                              ? 'Submit Payment'
                              : 'Confirm Cash Payment',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildGcashSection() {
    if (!_hasGcashDetails) {
      return const [
        Text(
          'This driver has not set up GCash payment details yet. Please pay in cash.',
          style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w700),
        ),
      ];
    }

    return [
      const Text(
        'Buksan ang GCash app, i-scan ang QR sa ibaba, at bayaran ang tamang halaga.',
        style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w700, height: 1.4),
      ),
      const SizedBox(height: 14),
      if (widget.gcashQrUrl.trim().isNotEmpty)
        Center(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: SizedBox(
              width: 220,
              height: 220,
              child: Image.network(
                widget.gcashQrUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Container(
                  color: const Color(0xFFF8FAFC),
                  alignment: Alignment.center,
                  child: const Text('QR preview unavailable'),
                ),
              ),
            ),
          ),
        ),
      const SizedBox(height: 12),
      if (widget.gcashName.trim().isNotEmpty || widget.gcashNumber.trim().isNotEmpty)
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.gcashName.trim().isNotEmpty)
                Text(
                  widget.gcashName,
                  style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF0F172A)),
                ),
              if (widget.gcashNumber.trim().isNotEmpty)
                Text(
                  widget.gcashNumber,
                  style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF64748B)),
                ),
            ],
          ),
        ),
      if (_showReferenceForm) ...[
        const SizedBox(height: 16),
        TextField(
          controller: _referenceController,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: 'GCash Reference Number',
            hintText: 'e.g. 1234567890123',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: _pickProof,
          icon: const Icon(Icons.photo_camera_outlined),
          label: Text(
            _proofFile == null ? 'Attach screenshot (optional)' : 'Screenshot attached',
          ),
        ),
      ],
    ];
  }

  List<Widget> _buildCashSection() {
    return const [
      Text(
        'Bayaran ang driver ng cash. Kumpirmahin niya sa app na natanggap niya ang bayad.',
        style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w700, height: 1.4),
      ),
    ];
  }
}

class _MethodChip extends StatelessWidget {
  const _MethodChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFF2A86FF) : const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            children: [
              Icon(icon, color: selected ? Colors.white : const Color(0xFF64748B)),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: selected ? Colors.white : const Color(0xFF64748B),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
