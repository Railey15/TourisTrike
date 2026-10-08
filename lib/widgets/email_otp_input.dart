import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

String maskVerificationEmail(String email) {
  final parts = email.split('@');
  if (parts.length != 2 || parts.first.isEmpty || parts.last.isEmpty) {
    return '••••';
  }
  final local = parts.first;
  final visible = local.length <= 2 ? local.substring(0, 1) : local.substring(0, 2);
  return '$visible••••@${parts.last}';
}

/// A single text input supports paste and keyboard autofill while drawing
/// separate cells. The controller remains in memory only and is never logged.
class EmailOtpInput extends StatelessWidget {
  const EmailOtpInput({super.key, required this.controller, this.length = 6});

  final TextEditingController controller;
  final int length;

  @override
  Widget build(BuildContext context) {
    final code = controller.text;
    return SizedBox(
      height: 62,
      child: Stack(
        children: [
          Row(
            children: List.generate(length, (index) => Expanded(
              child: Container(
                margin: EdgeInsets.only(right: index == length - 1 ? 0 : 7),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: index == code.length
                      ? const Color(0xFF2A86FF) : const Color(0xFFE2E8F0)),
                ),
                child: Text(index < code.length ? code[index] : '',
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
              ),
            )),
          ),
          Positioned.fill(
            child: Semantics(
              label: '$length-digit verification code',
              child: TextField(
                controller: controller,
                autofocus: true,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.oneTimeCode],
                enableSuggestions: false,
                autocorrect: false,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(length),
                ],
                maxLength: length,
                style: const TextStyle(color: Colors.transparent),
                cursorColor: Colors.transparent,
                showCursor: false,
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  counterText: '',
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
