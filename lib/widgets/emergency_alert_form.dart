import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../core/models/emergency_photo.dart';
import '../core/services/emergency_service.dart';

typedef SubmitEmergencyAlert =
    Future<EmergencyAlertResult> Function(
      String alertId,
      String note,
      EmergencyPhoto? photo,
    );

class EmergencyAlertForm extends StatefulWidget {
  const EmergencyAlertForm({super.key, required this.onSubmit, this.pickPhoto});
  final SubmitEmergencyAlert onSubmit;
  final Future<XFile?> Function()? pickPhoto;

  @override
  State<EmergencyAlertForm> createState() => _EmergencyAlertFormState();
}

class _EmergencyAlertFormState extends State<EmergencyAlertForm> {
  final _note = TextEditingController();
  final _alertId = EmergencyService.newAlertId();
  EmergencyPhoto? _photo;
  bool _picking = false;
  bool _confirming = false;
  String? _photoError;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    if (_picking || _confirming) return;
    setState(() {
      _picking = true;
      _photoError = null;
    });
    try {
      final file =
          await (widget.pickPhoto?.call() ??
              ImagePicker().pickImage(
                source: ImageSource.gallery,
                requestFullMetadata: false,
              ));
      if (file == null) {
        return; // Preserve previous photo if picker is cancelled.
      }
      final photo = await EmergencyPhoto.fromFile(file);
      if (mounted) setState(() => _photo = photo);
    } on PlatformException {
      if (mounted) {
        setState(
          () => _photoError =
              'Unable to access photos. Check photo permissions and try again.',
        );
      }
    } on FormatException catch (error) {
      if (mounted) setState(() => _photoError = error.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _photoError = 'Unable to select this photo. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _confirm() async {
    if (_confirming || _picking) return;
    setState(() => _confirming = true);
    // This dialog has no data/network side effects until its affirmative action.
    final result = await showDialog<EmergencyAlertResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _FinalConfirmation(
        onSubmit: () => widget.onSubmit(_alertId, _note.text.trim(), _photo),
      ),
    );
    if (!mounted) return;
    setState(() => _confirming = false);
    if (result != null) Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_confirming && !_picking,
    child: AlertDialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: const Text('Emergency Alert'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Your current location and tour information will be sent after you confirm.',
            ),
            const SizedBox(height: 12),
            const Text(
              'Notify your emergency contacts, assigned driver, and TourisTrike tourism office.',
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _note,
              maxLength: 200,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: 'Add a note (optional)',
                filled: true,
                fillColor: Color(0xFFF8FAFC),
                border: OutlineInputBorder(),
              ),
            ),
            OutlinedButton.icon(
              onPressed: _picking || _confirming ? null : _pick,
              icon: const Icon(Icons.add_photo_alternate_outlined),
              label: Text(
                _picking
                    ? 'Selecting...'
                    : _photo == null
                    ? 'Attach Photo'
                    : 'Replace Photo',
              ),
            ),
            if (_photo != null) ...[
              const SizedBox(height: 8),
              const Text('Attached photo'),
              const SizedBox(height: 6),
              Image.memory(
                _photo!.bytes,
                width: 100,
                height: 80,
                cacheWidth: 200,
                fit: BoxFit.cover,
                semanticLabel: 'Attached emergency photo',
              ),
              TextButton(
                onPressed: _confirming || _picking
                    ? null
                    : () => setState(() {
                        _photo = null;
                        _photoError = null;
                      }),
                child: const Text('Remove'),
              ),
            ],
            if (_photoError != null)
              Text(_photoError!, style: const TextStyle(color: Colors.red)),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _confirming || _picking
              ? null
              : () => Navigator.pop(context),
          style: TextButton.styleFrom(foregroundColor: const Color(0xFF64748B)),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _confirming || _picking ? null : _confirm,
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFFDC2626),
          ),
          child: const Text('Send Alert'),
        ),
      ],
    ),
  );
}

class _FinalConfirmation extends StatefulWidget {
  const _FinalConfirmation({required this.onSubmit});
  final Future<EmergencyAlertResult> Function() onSubmit;
  @override
  State<_FinalConfirmation> createState() => _FinalConfirmationState();
}

class _FinalConfirmationState extends State<_FinalConfirmation> {
  bool _sending = false;
  String? _error;

  Future<void> _send() async {
    if (_sending) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final result = await widget.onSubmit();
      if (mounted) Navigator.of(context).pop(result);
    } catch (_) {
      if (mounted) {
        setState(() {
          _sending = false;
          _error = 'Unable to confirm the alert was saved. Please retry.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_sending,
    child: AlertDialog(
      title: const Text('Send Emergency Alert?'),
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Are you sure you want to send this emergency alert?\n'
            'Your current location, tour information, note, and attached photo (if any) '
            'will be sent to your emergency contacts and the TourisTrike tourism office.',
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_error!, style: const TextStyle(color: Colors.red)),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _sending ? null : () => Navigator.pop(context),
          style: TextButton.styleFrom(foregroundColor: const Color(0xFF64748B)),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _sending ? null : _send,
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFFDC2626),
          ),
          child: _sending
              ? const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 8),
                    Text('Sending...'),
                  ],
                )
              : const Text('Yes, Send Alert'),
        ),
      ],
    ),
  );
}
