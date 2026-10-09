import 'package:flutter/material.dart';

class ReportAssignedDriverButton extends StatelessWidget {
  const ReportAssignedDriverButton({super.key, required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFFB91C1C),
          backgroundColor: const Color(0xFFFEF2F2),
          disabledForegroundColor: const Color(0xFF94A3B8),
          disabledBackgroundColor: const Color(0xFFF8FAFC),
          side: BorderSide(
            color: onPressed == null
                ? const Color(0xFFE2E8F0)
                : const Color(0xFFFCA5A5),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w800),
        ),
        icon: const Icon(Icons.report_outlined, size: 19),
        label: const Text('Report Assigned Driver'),
      ),
    );
  }
}
