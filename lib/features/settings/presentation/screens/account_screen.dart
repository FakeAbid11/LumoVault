import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/di/account_providers.dart';
import '../../../../core/di/gallery_providers.dart';
import '../../../../core/di/tdlib_providers.dart';
import '../../../../core/utils/format_utils.dart';
import 'package:material_symbols_icons/symbols.dart';

/// Account screen — shows the signed-in Telegram account, or a sign-in
/// prompt if none is connected.
class AccountScreen extends ConsumerWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accountInfo = ref.watch(accountInfoProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Account')),
      body: accountInfo.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) =>
            _AccountError(onRetry: () => ref.invalidate(accountInfoProvider)),
        data: (account) => account == null
            // The /onboarding/* routes are redirected to /local once
            // onboarding is complete — from this screen that made 'Sign In'
            // do nothing at all. /connect-telegram is the standalone twin.
            ? _SignedOut(onSignIn: () => context.push('/connect-telegram'))
            : _SignedIn(account: account),
      ),
    );
  }
}

class _SignedIn extends ConsumerWidget {
  const _SignedIn({required this.account});

  final TelegramAccountInfo account;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Keep the storage tile honest as the library changes.
    ref.watch(galleryDataVersionProvider);
    final initials = account.displayName.isNotEmpty
        ? account.displayName[0].toUpperCase()
        : '?';

    return ListView(
      children: [
        const SizedBox(height: 16),
        Center(
          child: CircleAvatar(
            radius: 48,
            backgroundColor: Theme.of(context).colorScheme.primaryContainer,
            child: Text(
              initials,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Center(
          child: Text(
            account.displayName.isNotEmpty
                ? account.displayName
                : account.phoneNumber,
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: Text(
            'Connected to Telegram',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(height: 32),
        const Divider(),
        ListTile(
          title: const Text('Phone Number'),
          // TDLib's getMe.phone_number already carries the international
          // prefix; unconditional '+' rendering it as '++91…'.
          subtitle: Text(
            account.phoneNumber.isNotEmpty
                ? account.phoneNumber.startsWith('+')
                      ? account.phoneNumber
                      : '+${account.phoneNumber}'
                : 'Unknown',
          ),
        ),
        ListTile(
          title: const Text('Storage'),
          // Real device-library size — the tile used to hardcode '0 B used'
          // while a stats screen one tap away computed the truth.
          subtitle: Text(
            '${formatBytes(ref.watch(galleryRepositoryProvider).totalSize)} '
            'on this device',
          ),
          trailing: const Icon(Symbols.chevron_right),
          onTap: () => context.push('/settings/backup/stats'),
        ),
        const Divider(),
        ListTile(
          title: Text(
            'Sign Out',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
          onTap: () => _confirmSignOut(context, ref),
        ),
      ],
    );
  }

  Future<void> _confirmSignOut(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text(
          'You will need to verify your phone number again to sign back in. '
          'Your backed-up photos stay safely in your Telegram account.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await ref.read(authServiceProvider).logout();
    if (!context.mounted) return;
    ref.invalidate(accountInfoProvider);
  }
}

class _SignedOut extends StatelessWidget {
  const _SignedOut({required this.onSignIn});

  final VoidCallback onSignIn;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        const SizedBox(height: 16),
        Center(
          child: CircleAvatar(
            radius: 48,
            backgroundColor: Theme.of(context).colorScheme.primaryContainer,
            child: Icon(
              Symbols.person,
              size: 48,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Center(
          child: Text(
            'Not signed in',
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: Text(
            'Sign in to start backing up your photos.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(height: 24),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: FilledButton(
            onPressed: onSignIn,
            child: const Text('Sign In'),
          ),
        ),
      ],
    );
  }
}

class _AccountError extends StatelessWidget {
  const _AccountError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Symbols.error,
            size: 48,
            color: Theme.of(context).colorScheme.error,
          ),
          const SizedBox(height: 16),
          const Text('Could not load account details.'),
          const SizedBox(height: 16),
          FilledButton(onPressed: onRetry, child: const Text('Try Again')),
        ],
      ),
    );
  }
}
