import 'dart:math';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> showReportBookingUserSheet(
  BuildContext context, {
  required String bookingId,
  required String reportedUserId,
  required String reportedName,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  constraints: const BoxConstraints(maxWidth: 640),
  builder: (_) => _ReportBookingUserSheet(
    bookingId: bookingId,
    reportedUserId: reportedUserId,
    reportedName: reportedName,
  ),
);

class _ReportBookingUserSheet extends StatefulWidget {
  const _ReportBookingUserSheet({
    required this.bookingId,
    required this.reportedUserId,
    required this.reportedName,
  });
  final String bookingId;
  final String reportedUserId;
  final String reportedName;
  @override
  State<_ReportBookingUserSheet> createState() =>
      _ReportBookingUserSheetState();
}

class _ReportBookingUserSheetState extends State<_ReportBookingUserSheet> {
  static const categories = {
    'safety': 'Safety',
    'conduct': 'Conduct',
    'service': 'Service',
    'payment': 'Payment',
    'other': 'Other',
  };
  final _description = TextEditingController();
  String _category = 'conduct';
  XFile? _evidence;
  bool _busy = false;
  String? _error;
  String? _submittedComplaintId;
  String? _uploadedPath;

  @override
  void dispose() {
    _description.dispose();
    super.dispose();
  }

  Future<void> _pickEvidence() async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1800,
    );
    if (file != null && mounted) setState(() => _evidence = file);
  }

  Future<void> _submit() async {
    if (_busy) return;
    final text = _description.text.trim();
    if (text.length < 20 || text.length > 2000) {
      setState(
        () => _error = 'Describe what happened in 20 to 2,000 characters.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final client = Supabase.instance.client;
    String? complaintId = _submittedComplaintId;
    try {
      if (complaintId == null) {
        complaintId = (await client.rpc(
          'submit_municipal_complaint',
          params: {
            'p_booking_id': widget.bookingId,
            'p_reported_user_id': widget.reportedUserId,
            'p_category': _category,
            'p_description': text,
          },
        )).toString();
        _submittedComplaintId = complaintId;
      }
      if (_evidence != null) {
        final bytes = await _evidence!.readAsBytes();
        if (bytes.length > 10485760) {
          throw StateError(
            'The evidence image exceeds 10 MB. The report was submitted without evidence.',
          );
        }
        final name = _evidence!.name.toLowerCase();
        final type = name.endsWith('.png')
            ? 'image/png'
            : name.endsWith('.webp')
            ? 'image/webp'
            : 'image/jpeg';
        final suffix = type == 'image/png'
            ? 'png'
            : type == 'image/webp'
            ? 'webp'
            : 'jpg';
        final nonce = Random.secure().nextInt(1 << 32).toRadixString(16);
        final path =
            _uploadedPath ??
            '$complaintId/${DateTime.now().microsecondsSinceEpoch}-$nonce.$suffix';
        if (_uploadedPath == null) {
          await client.storage
              .from('municipal-complaint-evidence')
              .uploadBinary(
                path,
                bytes,
                fileOptions: FileOptions(contentType: type),
              );
          _uploadedPath = path;
        }
        await client.rpc(
          'attach_municipal_complaint_evidence',
          params: {
            'p_complaint_id': complaintId,
            'p_storage_path': path,
            'p_file_name': _evidence!.name,
            'p_content_type': type,
          },
        );
      }
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context);
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Report submitted to the municipal tourism office.'),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(
        () => _error = complaintId == null
            ? 'Unable to submit this report: $error'
            : 'Report $complaintId was submitted, but evidence could not be attached: $error',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      20,
      8,
      20,
      MediaQuery.viewInsetsOf(context).bottom + 20,
    ),
    child: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Report ${widget.reportedName}',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 6),
          Text(
            'Booking #${widget.bookingId.substring(0, 8).toUpperCase()} · Reviewed by the municipal tourism office.',
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            initialValue: _category,
            decoration: const InputDecoration(
              labelText: 'Category',
              border: OutlineInputBorder(),
            ),
            items: categories.entries
                .map(
                  (entry) => DropdownMenuItem(
                    value: entry.key,
                    child: Text(entry.value),
                  ),
                )
                .toList(),
            onChanged: _busy
                ? null
                : (value) => setState(() => _category = value ?? _category),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _description,
            maxLines: 5,
            maxLength: 2000,
            enabled: !_busy,
            decoration: const InputDecoration(
              labelText: 'What happened?',
              hintText: 'Include the date, place, and relevant details.',
              border: OutlineInputBorder(),
            ),
          ),
          OutlinedButton.icon(
            onPressed: _busy ? null : _pickEvidence,
            icon: const Icon(Icons.attach_file),
            label: Text(
              _evidence == null
                  ? 'Add evidence image (optional)'
                  : _evidence!.name,
            ),
          ),
          const Text(
            'Submitting a report does not automatically suspend anyone.',
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(_error!, style: const TextStyle(color: Colors.red)),
            ),
          const SizedBox(height: 14),
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: _busy
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Submit report'),
          ),
        ],
      ),
    ),
  );
}
