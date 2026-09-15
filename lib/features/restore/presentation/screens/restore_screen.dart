import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../shared/widgets/lumo_loading.dart';
import '../providers/restore_providers.dart';
import 'restore_progress_screen.dart';
import 'package:material_symbols_icons/symbols.dart';

/// Restore entry point screen.
///
/// Per PRD Section 10.1: after successful Telegram auth, detect if
/// an existing storage channel has prior backup data and route
/// accordingly.
class RestoreScreen extends ConsumerStatefulWidget {
  const RestoreScreen({super.key});

  @override
  ConsumerState<RestoreScreen> createState() => _RestoreScreenState();
}

class _RestoreScreenState extends ConsumerState<RestoreScreen> {
  bool _isChecking = true;
  bool _hasBackup = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // The progress provider is keep-alive and outlives this route; without
    // clearing it here, a previously COMPLETED restore would make this entry
    // screen re-render the stale 100% progress screen forever (and there was
    // no way to start a second restore).
    ref.read(restoreProgressProvider.notifier).reset();
    _checkForBackup();
  }

  Future<void> _checkForBackup() async {
    try {
      final engine = ref.read(restoreEngineProvider);
      final result = await engine.restoreRepository.detectExistingBackup();

      if (!mounted) return;

      setState(() {
        _isChecking = false;
        _hasBackup = result.hasBackup;
        _error = result.error;
      });

      // Detection alone used to call _startRestore() straight away: the
      // "Would you like to restore it?" copy below had no buttons, and
      // merely opening the screen began downloading the whole library.
      // Restore now waits for an explicit Accept below.
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isChecking = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _startRestore() async {
    try {
      final startRestore = ref.read(startRestoreProvider);
      final success = await startRestore();

      if (!mounted) return;

      if (success) {
        // Navigate to main app after successful restore
        context.go('/local');
      } else {
        setState(() {
          _isChecking = false;
          _hasBackup = false;
          _error = 'Restore could not be started. Please try again.';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isChecking = false;
        _hasBackup = false;
        _error = 'Restore could not be started: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final progress = ref.watch(restoreProgressProvider);

    if (progress.isActive || progress.isComplete) {
      return const RestoreProgressScreen();
    }

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Theme.of(context).colorScheme.primary,
              Theme.of(context).colorScheme.primary.withValues(alpha: 0.8),
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Symbols.cloud_download_rounded,
                    size: 80,
                    color: Theme.of(context).colorScheme.onPrimary,
                  ),
                  const SizedBox(height: 32),
                  Text(
                    'Restore Your Library',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onPrimary,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'We found a backup of your photo library. '
                    'Would you like to restore it?',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Theme.of(
                        context,
                      ).colorScheme.onPrimary.withValues(alpha: 0.9),
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 48),
                  if (_isChecking) ...[
                    const LumoLoading(size: 48),
                    const SizedBox(height: 16),
                    Text(
                      'Checking for existing backup...',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(
                          context,
                        ).colorScheme.onPrimary.withValues(alpha: 0.8),
                      ),
                    ),
                  ] else if (_error != null) ...[
                    Icon(
                      Symbols.error,
                      size: 48,
                      color: Theme.of(context).colorScheme.onError,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _error!,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onPrimary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: () {
                        setState(() {
                          _isChecking = true;
                          _error = null;
                        });
                        _checkForBackup();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(
                          context,
                        ).colorScheme.onPrimary,
                        foregroundColor: Theme.of(context).colorScheme.primary,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 32,
                          vertical: 16,
                        ),
                      ),
                      child: const Text('Try Again'),
                    ),
                    const SizedBox(height: 16),
                    TextButton(
                      onPressed: () {
                        context.go('/onboarding/welcome');
                      },
                      child: Text(
                        'Start Fresh',
                        style: TextStyle(
                          color: Theme.of(
                            context,
                          ).colorScheme.onPrimary.withValues(alpha: 0.9),
                        ),
                      ),
                    ),
                  ] else if (_hasBackup) ...[
                    ElevatedButton(
                      onPressed: _startRestore,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(
                          context,
                        ).colorScheme.onPrimary,
                        foregroundColor: Theme.of(context).colorScheme.primary,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 32,
                          vertical: 16,
                        ),
                      ),
                      child: const Text('Restore'),
                    ),
                    const SizedBox(height: 16),
                    TextButton(
                      onPressed: () => context.go('/local'),
                      child: Text(
                        'No, thanks',
                        style: TextStyle(
                          color: Theme.of(
                            context,
                          ).colorScheme.onPrimary.withValues(alpha: 0.9),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
