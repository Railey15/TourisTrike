import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:touristrike/core/supabase/touristrike_models.dart';
import 'package:touristrike/core/supabase/touristrike_repository.dart';

const String _paymentProofBucket = 'payment-proofs';

const Map<String, String> paymentDisputeReasons = {
  'not_received': 'I did not receive this payment',
  'wrong_amount': 'The amount is wrong',
  'duplicate': 'This is a duplicate submission',
  'fake_reference': 'The reference number looks invalid',
  'other': 'Other reason',
};

// "Report a problem" — used by either party on a payment_records row.
// TourisTrike does NOT custody funds — GCash-to-GCash direct. Outside AMLA covered-person scope (RA 9160).
class PaymentDisputeScreen extends StatefulWidget {
  const PaymentDisputeScreen({super.key, required this.record});

  final PaymentRecord record;

  @override
  State<PaymentDisputeScreen> createState() => _PaymentDisputeScreenState();
}

class _PaymentDisputeScreenState extends State<PaymentDisputeScreen> {
  final TourisTrikeRepository _repo = TourisTrikeRepository();
  final TextEditingController _descriptionController = TextEditingController();
  final ImagePicker _imagePicker = ImagePicker();

  String _reason = paymentDisputeReasons.keys.first;
  XFile? _evidenceFile;
  bool _submitting = false;

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickEvidence() async {
    final file = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 78,
      maxWidth: 1600,
    );
    if (file == null || !mounted) return;
    setState(() => _evidenceFile = file);
  }

  Future<void> _submit() async {
    if (_submitting) return;
    setState(() => _submitting = true);
    try {
      String? evidenceUrl;
      final file = _evidenceFile;
      if (file != null) {
        final bytes = await file.readAsBytes();
        final ext = file.path.split('.').last.trim().toLowerCase();
        final path =
            '${widget.record.id}/dispute_${DateTime.now().millisecondsSinceEpoch}.${ext.isEmpty ? 'jpg' : ext}';
        final storage = Supabase.instance.client.storage.from(_paymentProofBucket);
        await storage.uploadBinary(
          path,
          Uint8List.fromList(bytes),
          fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: true),
        );
        evidenceUrl = await storage.createSignedUrl(path, 60 * 60 * 24 * 365);
      }

      await _repo.raisePaymentDispute(
        paymentRecordId: widget.record.id as String,
        reason: _reason,
        description: _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
        evidenceUrl: evidenceUrl,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Dispute filed. An admin will review it.')),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to file dispute: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF5F7FB),
        elevation: 0,
        foregroundColor: const Color(0xFF0F172A),
        title: const Text(
          'Report a Problem',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFE7EEF7)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'PHP ${widget.record.amount.toStringAsFixed(2)} — ${widget.record.paymentMethod.toUpperCase()}',
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                ),
                if (widget.record.externalReferenceNo.isNotEmpty)
                  Text(
                    'Ref: ${widget.record.externalReferenceNo}',
                    style: const TextStyle(color: Color(0xFF64748B)),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          const Text('Reason', style: TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          ...paymentDisputeReasons.entries.map(
            (e) => RadioListTile<String>(
              value: e.key,
              groupValue: _reason,
              onChanged: (v) => setState(() => _reason = v ?? _reason),
              title: Text(e.value),
              contentPadding: EdgeInsets.zero,
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _descriptionController,
            minLines: 3,
            maxLines: 5,
            decoration: InputDecoration(
              labelText: 'Description (optional)',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _pickEvidence,
            icon: const Icon(Icons.photo_camera_outlined),
            label: Text(
              _evidenceFile == null ? 'Attach evidence (optional)' : 'Evidence attached',
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton(
              onPressed: _submitting ? null : _submit,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFDC2626),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              child: _submitting
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                    )
                  : const Text(
                      'Submit Report',
                      style: TextStyle(fontWeight: FontWeight.w900, color: Colors.white),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
