import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../settings/presentation/providers/settings_providers.dart';
import '../providers/app_lock_provider.dart';
import '../screens/app_lock_screen.dart';

/// Wraps the app and covers it with [AppLockScreen] whenever it is locked.
///
/// Also re-locks on backgrounding when "Require on App Open" is set, so a
/// task-switcher preview can't be used to read the vault.
class AppLockGate extends ConsumerStatefulWidget {
  const AppLockGate({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends ConsumerState<AppLockGate>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.paused &&
        state != AppLifecycleState.hidden) {
      return;
    }

    final settings = ref.read(appSettingsProvider);
    if (!settings.requireAuthOnAppOpen) return;
    if (!ref.read(appLockEnabledProvider)) return;

    ref.read(appLockProvider.notifier).lock();
  }

  @override
  Widget build(BuildContext context) {
    final locked = ref.watch(appLockProvider).locked;
    final enabled = ref.watch(appLockEnabledProvider);

    // If the user turns the lock off from the settings screen while the lock
    // screen is up, don't strand them behind a challenge they can't answer.
    if (locked && !enabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ref.read(appLockProvider.notifier).unlockWithoutChallenge();
        }
      });
    }

    return Stack(
      children: [
        widget.child,
        if (locked && enabled)
          const Positioned.fill(child: Material(child: AppLockScreen())),
      ],
    );
  }
}
