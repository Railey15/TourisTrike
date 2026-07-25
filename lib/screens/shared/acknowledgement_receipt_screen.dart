import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'package:touristrike/core/supabase/touristrike_models.dart';
import 'package:touristrike/core/supabase/touristrike_repository.dart';

// Acknowledgement receipt only. Official Invoice is the driver/operator or LGU responsibility.
// TourisTrike does NOT custody funds — GCash-to-GCash direct. Outside AMLA covered-person scope (RA 9160).
class AcknowledgementReceiptScreen extends StatefulWidget {
  const AcknowledgementReceiptScreen({
    super.key,
    required this.record,
    this.payerName,
    this.payeeName,
  });

  final PaymentRecord record;
  final String? payerName;
  final String? payeeName;

  @override
  State<AcknowledgementReceiptScreen> createState() =>
      _AcknowledgementReceiptScreenState();
}

class _AcknowledgementReceiptScreenState
    extends State<AcknowledgementReceiptScreen> {
  final TourisTrikeRepository _repo = TourisTrikeRepository();

  String? _payerName;
  String? _payeeName;
  bool _loading = true;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    _payerName = widget.payerName;
    _payeeName = widget.payeeName;
    _loadNames();
  }

  Future<void> _loadNames() async {
    try {
      if (_payerName == null) {
        final profile = await _repo.fetchProfile(widget.record.payerId);
        _payerName = profile?.displayName ?? 'Tourist';
      }
      if (_payeeName == null) {
        final profile = await _repo.fetchProfile(widget.record.payeeId);
        _payeeName = profile?.displayName ?? 'Driver';
      }
    } catch (_) {
      _payerName ??= 'Tourist';
      _payeeName ??= 'Driver';
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _exportPdf() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final doc = pw.Document();
      final r = widget.record;
      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a5,
          build: (context) {
            return pw.Padding(
              padding: const pw.EdgeInsets.all(28),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'Acknowledgement Receipt',
                    style: pw.TextStyle(
                      fontSize: 20,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text('Receipt No: ${r.receiptNo.isEmpty ? '-' : r.receiptNo}'),
                  pw.Text(
                    'Date: ${r.payeeConfirmedAt != null ? DateFormat('MMMM dd, yyyy hh:mm a').format(r.payeeConfirmedAt!) : '-'}',
                  ),
                  pw.Divider(height: 24),
                  pw.Text('Received from: ${_payerName ?? '-'}'),
                  pw.Text('Received by: ${_payeeName ?? '-'}'),
                  pw.SizedBox(height: 12),
                  pw.Text(
                    'Amount: PHP ${r.amount.toStringAsFixed(2)}',
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14),
                  ),
                  pw.Text('Payment Method: ${r.paymentMethod.toUpperCase()}'),
                  if (r.externalReferenceNo.isNotEmpty)
                    pw.Text('Reference No: ${r.externalReferenceNo}'),
                  pw.SizedBox(height: 12),
                  pw.Text('For: ${r.serviceDescription.isEmpty ? '-' : r.serviceDescription}'),
                  pw.Spacer(),
                  pw.Divider(),
                  pw.Text(
                    'This is a proof of payment (supplementary document) and is not a '
                    'BIR-registered Invoice. The service provider is responsible for '
                    'issuing the official Invoice where applicable.',
                    style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
                  ),
                ],
              ),
            );
          },
        ),
      );
      final bytes = await doc.save();
      await Printing.sharePdf(
        bytes: bytes,
        filename: 'acknowledgement-receipt-${r.receiptNo.isEmpty ? r.id : r.receiptNo}.pdf',
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.record;
    const bg = Color(0xFFF5F7FB);
    const blue = Color(0xFF2A86FF);
    const textDark = Color(0xFF0F172A);
    const textMid = Color(0xFF64748B);

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        foregroundColor: textDark,
        title: const Text(
          'Acknowledgement Receipt',
          style: TextStyle(fontWeight: FontWeight.w900, color: textDark),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x14000000),
                        blurRadius: 14,
                        offset: Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const Icon(Icons.receipt_long_rounded, color: blue, size: 40),
                      const SizedBox(height: 8),
                      const Text(
                        'Acknowledgement Receipt',
                        style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: textDark),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        r.receiptNo.isEmpty ? 'Pending confirmation' : r.receiptNo,
                        style: const TextStyle(fontWeight: FontWeight.w700, color: textMid),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        'PHP ${r.amount.toStringAsFixed(2)}',
                        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 32, color: textDark),
                      ),
                      const SizedBox(height: 20),
                      const Divider(height: 1),
                      const SizedBox(height: 16),
                      _ReceiptRow(label: 'Received from', value: _payerName ?? '-'),
                      _ReceiptRow(label: 'Received by', value: _payeeName ?? '-'),
                      _ReceiptRow(
                        label: 'Date',
                        value: r.payeeConfirmedAt != null
                            ? DateFormat('MMM dd, yyyy hh:mm a').format(r.payeeConfirmedAt!)
                            : 'Awaiting confirmation',
                      ),
                      _ReceiptRow(label: 'Payment Method', value: r.paymentMethod.toUpperCase()),
                      if (r.externalReferenceNo.isNotEmpty)
                        _ReceiptRow(label: 'Reference No.', value: r.externalReferenceNo),
                      if (r.serviceDescription.isNotEmpty)
                        _ReceiptRow(label: 'For', value: r.serviceDescription),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFFBEB),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFFDE68A)),
                  ),
                  child: const Text(
                    'This is a proof of payment (supplementary document) and is not a '
                    'BIR-registered Invoice. The service provider is responsible for '
                    'issuing the official Invoice where applicable.',
                    style: TextStyle(color: Color(0xFF92400E), fontWeight: FontWeight.w600, height: 1.4),
                  ),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton.icon(
                    onPressed: r.isConfirmed && !_exporting ? _exportPdf : null,
                    icon: _exporting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
                          )
                        : const Icon(Icons.ios_share_rounded),
                    label: Text(_exporting ? 'Preparing...' : 'Share Receipt'),
                    style: FilledButton.styleFrom(
                      backgroundColor: blue,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _ReceiptRow extends StatelessWidget {
  const _ReceiptRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: const TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}
