import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:touristrike/core/auth/signup_response_policy.dart';

void main() {
  const email = 'new@example.com';
  const id = 'real-user';

  User user({
    String? address = email,
    String? confirmedAt,
    String? emailConfirmedAt,
    String? confirmationSentAt = '2026-10-08T00:00:00Z',
    List<UserIdentity>? identities,
  }) => User(
    id: id,
    appMetadata: const {},
    userMetadata: const {},
    aud: 'authenticated',
    email: address,
    createdAt: '2026-10-08T00:00:00Z',
    // ignore: deprecated_member_use
    confirmedAt: confirmedAt,
    emailConfirmedAt: emailConfirmedAt,
    confirmationSentAt: confirmationSentAt,
    identities: identities,
  );

  const emailIdentity = UserIdentity(
    id: 'email-identity',
    userId: id,
    identityData: {'email': email},
    identityId: email,
    provider: 'email',
    createdAt: '2026-10-08T00:00:00Z',
    lastSignInAt: null,
  );

  test('real new or unconfirmed signup enters verification', () {
    final response = AuthResponse(user: user(identities: [emailIdentity]));
    expect(
      classifySignupResponse(response, ' NEW@example.com '),
      SignupResponseState.pendingVerification,
    );
  });

  test(
    'obfuscated confirmed duplicate with empty identities cannot enter OTP',
    () {
      final response = AuthResponse(user: user(identities: []));
      expect(
        classifySignupResponse(response, email),
        SignupResponseState.unexpected,
      );
    },
  );

  test(
    'unknown identities, confirmed account, and mismatched email fail closed',
    () {
      for (final candidate in [
        user(),
        user(identities: [emailIdentity], emailConfirmedAt: '2026-10-08'),
        user(identities: [emailIdentity], confirmedAt: '2026-10-08'),
        user(identities: [emailIdentity], confirmationSentAt: null),
        user(identities: [emailIdentity], address: 'other@example.com'),
      ]) {
        expect(
          classifySignupResponse(AuthResponse(user: candidate), email),
          SignupResponseState.unexpected,
        );
      }
      expect(
        classifySignupResponse(AuthResponse(), email),
        SignupResponseState.unexpected,
      );
    },
  );

  test('unexpected identity and immediate session cannot enter OTP', () {
    final wrongIdentity = UserIdentity(
      id: 'other',
      userId: 'other-user',
      identityData: const {'email': email},
      identityId: email,
      provider: 'email',
      createdAt: null,
      lastSignInAt: null,
    );
    expect(
      classifySignupResponse(
        AuthResponse(user: user(identities: [wrongIdentity])),
        email,
      ),
      SignupResponseState.unexpected,
    );
    final sessionUser = user(identities: [emailIdentity]);
    expect(
      classifySignupResponse(
        AuthResponse(
          session: Session(
            accessToken: 'test-only',
            tokenType: 'bearer',
            user: sessionUser,
          ),
        ),
        email,
      ),
      SignupResponseState.immediateSession,
    );
  });

  test(
    'provider delivery errors remain visible; account existence is private',
    () {
      expect(
        signupAuthErrorMessage(
          const AuthException('SMTP failure', code: 'unexpected_failure'),
        ),
        'SMTP failure',
      );
      expect(
        signupAuthErrorMessage(
          const AuthException(
            'User already registered',
            code: 'user_already_exists',
          ),
        ),
        signupUnavailableMessage,
      );
      expect(
        signupAuthErrorMessage(const AuthException('Email not found')),
        signupUnavailableMessage,
      );
    },
  );
}
