import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/di/account_providers.dart';
import '../../../../core/di/tdlib_providers.dart';

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
            ? _SignedOut(onSignIn: () => context.push('/onboarding/telegram'))
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
          subtitle: Text(
            account.phoneNumber.isNotEmpty
                ? '+${account.phoneNumber}'
                : 'Unknown',
          ),
        ),
        ListTile(
          title: const Text('Storage'),
          subtitle: const Text('0 B used'),
          trailing: const Icon(Icons.chevron_right),
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
              Icons.person,
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
            Icons.error_outline,
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
