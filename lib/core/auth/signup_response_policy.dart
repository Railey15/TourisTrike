import 'package:supabase_flutter/supabase_flutter.dart';

enum SignupResponseState { pendingVerification, immediateSession, unexpected }

/// A confirmed duplicate signup can return an obfuscated user with no identities.
/// Only a real, unconfirmed email identity is eligible for the signup OTP screen.
SignupResponseState classifySignupResponse(
  AuthResponse response,
  String requestedEmail,
) {
  if (response.session != null) return SignupResponseState.immediateSession;

  final user = response.user;
  final email = requestedEmail.trim().toLowerCase();
  if (user == null ||
      user.isAnonymous ||
      user.id.isEmpty ||
      email.isEmpty ||
      user.email?.trim().toLowerCase() != email ||
      user.emailConfirmedAt != null ||
      // Some Auth responses still populate the legacy confirmation field.
      // ignore: deprecated_member_use
      user.confirmedAt != null ||
      user.confirmationSentAt == null) {
    return SignupResponseState.unexpected;
  }

  final hasEmailIdentity =
      user.identities?.any((identity) {
        final identityEmail = identity.identityData?['email'];
        return identity.provider == 'email' &&
            identity.userId == user.id &&
            (identityEmail == null ||
                identityEmail.toString().trim().toLowerCase() == email);
      }) ??
      false;

  return hasEmailIdentity
      ? SignupResponseState.pendingVerification
      : SignupResponseState.unexpected;
}

const signupUnavailableMessage =
    'We could not start email verification. Please try again later, or sign in or reset your password if you already have an account.';

/// Preserve the provider's actionable errors without disclosing account existence.
String signupAuthErrorMessage(AuthException error) {
  final code = error.code?.toLowerCase() ?? '';
  final message = error.message.trim();
  final lowerMessage = message.toLowerCase();
  if (code == 'user_already_exists' ||
      code == 'email_exists' ||
      code == 'identity_already_exists' ||
      code == 'user_not_found' ||
      code == 'email_not_confirmed' ||
      lowerMessage.contains('already registered') ||
      lowerMessage.contains('already exists') ||
      lowerMessage.contains('already in use') ||
      lowerMessage.contains('user not found') ||
      lowerMessage.contains('email not found') ||
      lowerMessage.contains('account not found') ||
      lowerMessage.contains('does not exist') ||
      lowerMessage.contains('not confirmed')) {
    return signupUnavailableMessage;
  }
  return message.isEmpty ? signupUnavailableMessage : message;
}
