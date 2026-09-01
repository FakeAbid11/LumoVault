import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/auth/auth_service.dart';
import '../../../../core/di/backup_providers.dart';
import '../../../../core/di/tdlib_providers.dart';
import '../../../restore/presentation/providers/restore_providers.dart';
import '../../../settings/presentation/providers/settings_providers.dart';
import '../providers/onboarding_provider.dart';
import '../widgets/country_code.dart';
import '../widgets/country_code_picker.dart';
import '../widgets/onboarding_progress_indicator.dart';
import 'package:material_symbols_icons/symbols.dart';

/// Telegram connect screen — links user's Telegram account.
///
/// Handles phone input, code verification, and 2FA password entry, all
/// against the real TDLib client via [AuthService].
class TelegramConnectScreen extends ConsumerStatefulWidget {
  const TelegramConnectScreen({super.key});

  @override
  ConsumerState<TelegramConnectScreen> createState() =>
      _TelegramConnectScreenState();
}

class _TelegramConnectScreenState extends ConsumerState<TelegramConnectScreen> {
  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _passwordVisible = false;

  AuthState _authState = AuthState.unauthenticated;
  String? _errorMessage;
  String? _sentPhoneNumber;
  CountryCode _selectedCountry = kDefaultCountryCode;

  @override
  void dispose() {
    _phoneController.dispose();
    _codeController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _pickCountry() async {
    final picked = await showCountryCodePicker(context);
    if (picked != null && mounted) {
      setState(() => _selectedCountry = picked);
    }
  }

  /// Complete onboarding without a Telegram account. The app stays fully
  /// usable for local galleries; the Timeline tab's sign-in prompt is how a
  /// skipped user returns to this screen when they're ready.
  Future<void> _skipForNow() async {
    ref.read(onboardingProvider.notifier).completeOnboarding();
    ref.read(onboardingCompletedProvider.notifier).state = true;

    // Single-write contract, same as _onAuthSuccess: persist onboarding
    // completion (and any folders picked in the previous step) together.
    final selectedFolders = ref.read(onboardingProvider).selectedFolders;
    await ref
        .read(appSettingsProvider.notifier)
        .updateField(
          (s) => s.copyWith(
            onboardingCompleted: true,
            includedFolders: selectedFolders.toList(),
          ),
        );

    if (!mounted) return;
    context.go('/local');
  }

  /// Explain what the 2FA password is and where to reset it.
  ///
  /// This used to be a dead button — TDLib offers no in-app reset here
  /// (resetting requires Telegram's own recovery flow), so the honest
  /// behavior is to say so and hand off to Telegram support.
  Future<void> _showForgotPasswordHelp(BuildContext context) async {
    final reset = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Forgot your password?'),
        content: const Text(
          'This is the two-step verification password set on your Telegram '
          'account — not a LumoVault password.\n\n'
          'To reset it, contact Telegram support through the official '
          'Telegram app (Settings → Privacy and Security → Two-Step '
          'Verification → Forgot password), or via the Telegram website. '
          'Resets can take a few days.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Close'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Open Telegram Help'),
          ),
        ],
      ),
    );

    if (reset != true || !context.mounted) return;
    final uri = Uri.parse('https://telegram.org/support');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Could not open link')));
      }
    }
  }

  Future<void> _sendCode() async {
    final authService = ref.read(authServiceProvider);
    final localNumber = _phoneController.text.trim();

    if (localNumber.isEmpty) {
      setState(() => _errorMessage = 'Please enter your phone number');
      return;
    }

    final phone = '${_selectedCountry.dialCode}$localNumber';

    setState(() {
      _errorMessage = null;
      _authState = AuthState.loading;
    });

    // Establish the auth service's connection (for the real TDLib-backed
    // implementation this brings up the TDLib client + setTdlibParameters;
    // for test stubs this is a cheap no-op) before
    // attempting to use it.
    try {
      await authService.initialize();
    } catch (e, stackTrace) {
      debugPrint('[TelegramConnectScreen] authService.initialize() failed: $e');
      debugPrint('$stackTrace');
      if (!mounted) return;
      setState(() {
        _authState = AuthState.error;
        _errorMessage = 'Could not connect to Telegram. Please try again.';
      });
      return;
    }

    if (!mounted) return;

    // If TDLib already has an active session (e.g. from a previous login),
    // skip sending a code and go straight to the authenticated flow.
    if (authService.currentState == AuthState.authenticated) {
      debugPrint(
        '[TelegramConnectScreen] Already authenticated, skipping sendCode',
      );
      setState(() => _authState = AuthState.authenticated);
      unawaited(_onAuthSuccess());
      return;
    }

    final result = await authService.sendCode(phone);

    if (!mounted) return;

    setState(() {
      switch (result) {
        case AuthCodeSent():
          _authState = AuthState.codeSent;
          _sentPhoneNumber = result.phoneNumber;
        case AuthError():
          _authState = AuthState.error;
          _errorMessage = result.message;
          debugPrint(
            '[TelegramConnectScreen] sendCode failed: '
            'code=${result.code} message=${result.message}',
          );
        default:
          _authState = AuthState.error;
          _errorMessage = 'Unexpected error occurred';
      }
    });
  }

  Future<void> _verifyCode() async {
    // Re-entry guard: the button is disabled while loading, but this also
    // stops a rapid second tap from re-firing the TDLib request mid-flight.
    if (_authState == AuthState.loading) return;
    final authService = ref.read(authServiceProvider);
    final code = _codeController.text.trim();

    if (code.isEmpty) {
      setState(() => _errorMessage = 'Please enter the verification code');
      return;
    }

    setState(() {
      _errorMessage = null;
      _authState = AuthState.loading;
    });

    try {
      final result = await authService.verifyCode(code);

      if (!mounted) return;

      setState(() {
        switch (result) {
          case AuthSuccess():
            _authState = AuthState.authenticated;
            unawaited(_onAuthSuccess());
          case AuthPasswordRequired():
            _authState = AuthState.passwordRequired;
          case AuthError():
            _authState = AuthState.error;
            _errorMessage = result.message;
          default:
            _authState = AuthState.error;
            _errorMessage = 'Unexpected error occurred';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _authState = AuthState.error;
        _errorMessage = 'Could not verify code. Please try again.';
      });
    }
  }

  Future<void> _submitPassword() async {
    // Re-entry guard: same rationale as _verifyCode.
    if (_authState == AuthState.loading) return;
    final authService = ref.read(authServiceProvider);
    final password = _passwordController.text;

    if (password.isEmpty) {
      setState(() => _errorMessage = 'Please enter your password');
      return;
    }

    setState(() {
      _errorMessage = null;
      _authState = AuthState.loading;
    });

    try {
      final result = await authService.submitPassword(password);

      if (!mounted) return;

      setState(() {
        switch (result) {
          case AuthSuccess():
            _authState = AuthState.authenticated;
            unawaited(_onAuthSuccess());
          case AuthError():
            _authState = AuthState.error;
            _errorMessage = result.message;
          default:
            _authState = AuthState.error;
            _errorMessage = 'Unexpected error occurred';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _authState = AuthState.error;
        _errorMessage = 'Could not verify password. Please try again.';
      });
    }
  }

  Future<void> _onAuthSuccess() async {
    ref.read(onboardingProvider.notifier).completeOnboarding();
    ref.read(onboardingCompletedProvider.notifier).state = true;

    // Persist both onboarding completion and folder selection in a single
    // write. Previously these were two separate unawaited() calls that raced:
    // both read the old settings from storage before either wrote, so the
    // second persist could overwrite onboardingCompleted back to false.
    final selectedFolders = ref.read(onboardingProvider).selectedFolders;
    await ref
        .read(appSettingsProvider.notifier)
        .updateField(
          (s) => s.copyWith(
            onboardingCompleted: true,
            includedFolders: selectedFolders.toList(),
          ),
        );

    // Trigger an immediate scan + backup so the user's selected folders
    // start backing up right away instead of waiting for the next
    // WorkManager schedule. Deliberately NOT awaited: startBackup() drains the
    // entire upload queue (BackupEngine._processQueue), so awaiting it here
    // would pin the user on the "Setting up..." screen until the whole first
    // backup finished uploading, instead of letting them into the app while it
    // runs in the background.
    unawaited(() async {
      try {
        final engine = ref.read(backupEngineProvider.notifier);
        await engine.scanAndEnqueue();
        await engine.startBackup();
      } catch (_) {
        // Non-fatal — the user can always tap Start Backup manually.
      }
    }());

    // A fresh app install (or a genuinely new user) both land here after
    // entering phone + code — TDLib's local session gets wiped by an
    // uninstall too, so there's no way to tell them apart before this
    // point. shouldShowRestoreProvider already existed for exactly this
    // check but was never actually called from anywhere, so a returning
    // user who reinstalled always landed straight on an empty Local/
    // Timeline with no indication a backup already existed on Telegram.
    bool hasExistingBackup = false;
    try {
      hasExistingBackup = await ref.read(shouldShowRestoreProvider.future);
    } catch (_) {
      // If detection fails, fall through to the normal Local landing
      // rather than blocking onboarding on it — the user can still find
      // Restore manually from Settings.
    }

    if (!mounted) return;
    context.go(hasExistingBackup ? '/restore' : '/local');
  }

  @override
  Widget build(BuildContext context) {
    final onboarding = ref.watch(onboardingProvider);
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Connect Telegram')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        children: [
                          Icon(
                            Icons.telegram,
                            size: 48,
                            color: colorScheme.onPrimaryContainer,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Secure Backup',
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(
                                  color: colorScheme.onPrimaryContainer,
                                ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Your photos are stored in a private channel in your own Telegram account — only you can access them.',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: colorScheme.onPrimaryContainer
                                      .withValues(alpha: 0.8),
                                ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),

                    // Error state
                    if (_authState == AuthState.error) ...[
                      Center(
                        child: Column(
                          children: [
                            Icon(
                              Symbols.error,
                              size: 64,
                              color: colorScheme.error,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Connection Error',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _errorMessage ?? 'An unexpected error occurred',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                            ),
                            const SizedBox(height: 24),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton(
                                onPressed: () {
                                  // Invalidate the cached TDLib initialization
                                  // so a fresh connection attempt is made.
                                  ref.invalidate(tdLibInitializedProvider);
                                  setState(() {
                                    _authState = AuthState.unauthenticated;
                                    _errorMessage = null;
                                  });
                                },
                                child: const Text('Try Again'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    // Phone input phase
                    if (_authState == AuthState.unauthenticated ||
                        _authState == AuthState.loading) ...[
                      Text(
                        'Enter your phone number',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'We\'ll send a verification code to your Telegram.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _phoneController,
                        keyboardType: TextInputType.phone,
                        enabled: _authState != AuthState.loading,
                        decoration: InputDecoration(
                          labelText: 'Phone Number',
                          hintText: '234 567 8900',
                          prefixIcon: Padding(
                            padding: const EdgeInsets.only(left: 4),
                            child: InkWell(
                              onTap: _authState == AuthState.loading
                                  ? null
                                  : _pickCountry,
                              borderRadius: BorderRadius.circular(8),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      _selectedCountry.flag,
                                      style: const TextStyle(fontSize: 20),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(_selectedCountry.dialCode),
                                    const Icon(
                                      Symbols.arrow_drop_down,
                                      size: 20,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          border: const OutlineInputBorder(),
                          errorText: _errorMessage,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Your phone number is used only for Telegram authentication.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: _authState == AuthState.loading
                              ? null
                              : _sendCode,
                          child: _authState == AuthState.loading
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text('Send Code'),
                        ),
                      ),
                    ],

                    // Code verification phase
                    if (_authState == AuthState.codeSent) ...[
                      Text(
                        'Enter verification code',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'We sent a code to $_sentPhoneNumber',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _codeController,
                        keyboardType: TextInputType.number,
                        maxLength: 5,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 24, letterSpacing: 8),
                        decoration: InputDecoration(
                          labelText: 'Code',
                          counterText: '',
                          border: const OutlineInputBorder(),
                          errorText: _errorMessage,
                        ),
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: _authState == AuthState.loading
                              ? null
                              : _verifyCode,
                          child: const Text('Verify'),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Center(
                        child: TextButton(
                          onPressed: () {
                            setState(() {
                              _authState = AuthState.unauthenticated;
                              _errorMessage = null;
                            });
                          },
                          child: const Text('Wrong number?'),
                        ),
                      ),
                    ],

                    // 2FA password phase
                    if (_authState == AuthState.passwordRequired) ...[
                      Text(
                        'Two-factor authentication',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Enter your Telegram password.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _passwordController,
                        obscureText: !_passwordVisible,
                        decoration: InputDecoration(
                          labelText: 'Password',
                          prefixIcon: const Icon(Symbols.lock),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _passwordVisible
                                  ? Symbols.visibility_off
                                  : Symbols.visibility,
                            ),
                            tooltip: _passwordVisible
                                ? 'Hide password'
                                : 'Show password',
                            onPressed: () {
                              setState(() {
                                _passwordVisible = !_passwordVisible;
                              });
                            },
                          ),
                          border: const OutlineInputBorder(),
                          errorText: _errorMessage,
                        ),
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: _authState == AuthState.loading
                              ? null
                              : _submitPassword,
                          child: const Text('Verify'),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Center(
                        child: TextButton(
                          onPressed: () => _showForgotPasswordHelp(context),
                          child: const Text('Forgot password?'),
                        ),
                      ),
                    ],

                    // Success state
                    if (_authState == AuthState.authenticated) ...[
                      Center(
                        child: Column(
                          children: [
                            Icon(
                              Symbols.check_circle,
                              size: 64,
                              color: colorScheme.primary,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Connected!',
                              style: Theme.of(context).textTheme.headlineSmall,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Setting up your secure vault...',
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            // Progress indicator
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: OnboardingProgressIndicator(
                currentStep: onboarding.currentStep,
              ),
            ),

            // Skip button — lets a user defer Telegram login and explore the
            // app first. Only offered while unauthenticated: once signed in,
            // completing onboarding is the only path forward. The Timeline
            // tab's sign-in prompt is how a skipped user returns here.
            if (_authState == AuthState.unauthenticated)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
                child: SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: _skipForNow,
                    child: const Text('Skip for now'),
                  ),
                ),
              ),

            // Back button
            if (_authState != AuthState.authenticated)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 56),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () {
                      ref.read(onboardingProvider.notifier).previousStep();
                      context.pop();
                    },
                    child: const Text('Back'),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
