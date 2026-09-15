import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_service.dart';
import 'tdlib_providers.dart';

/// Signed-in Telegram account details, as reported by TDLib's `getMe`.
class TelegramAccountInfo {
  const TelegramAccountInfo({
    required this.phoneNumber,
    required this.firstName,
    required this.lastName,
  });

  final String phoneNumber;
  final String firstName;
  final String lastName;

  String get displayName =>
      [firstName, lastName].where((s) => s.isNotEmpty).join(' ');
}

/// The current signed-in account, or `null` if not authenticated.
///
/// [AccountScreen] used to be a static placeholder that always said "Not
/// signed in" regardless of the real TDLib session — it never read any
/// provider. This one does the actual work: makes sure TDLib is connected,
/// syncs [AuthService.currentState] with the real (persisted) TDLib
/// authorization state — which [TelegramAuthRepository.initialize] only
/// otherwise runs during the onboarding flow, so a normal app launch that
/// skips onboarding would never have synced it — and then fetches the
/// account's phone number and name via `getMe` when authenticated.
final accountInfoProvider = FutureProvider<TelegramAccountInfo?>((ref) async {
  await ref.watch(tdLibInitializedProvider.future);

  final authService = ref.watch(authServiceProvider);
  await authService.initialize();

  if (authService.currentState != AuthState.authenticated) {
    return null;
  }

  final client = ref.read(tdLibClientProvider);
  final me = await client.sendRequest(method: 'getMe');

  return TelegramAccountInfo(
    phoneNumber: me['phone_number'] as String? ?? '',
    firstName: me['first_name'] as String? ?? '',
    lastName: me['last_name'] as String? ?? '',
  );
});
