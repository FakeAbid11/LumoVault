import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/auth/auth_service.dart';
import '../../../../core/di/tdlib_providers.dart';
import '../../../settings/presentation/providers/settings_providers.dart';
import '../providers/onboarding_provider.dart';
import '../widgets/country_code.dart';
import '../widgets/country_code_picker.dart';
import '../widgets/onboarding_progress_indicator.dart';

/// Telegram connect screen — links user's Telegram account.
///
/// Handles phone input, code verification, and 2FA (stubbed).
/// Clean abstraction ready for Prompt 4/5 TDLib integration.
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
    // for StubAuthService in tests/dev this is a cheap no-op) before
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
        default:
          _authState = AuthState.error;
          _errorMessage = 'Unexpected error occurred';
      }
    });
  }

  Future<void> _verifyCode() async {
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

    final result = await authService.verifyCode(code);

    if (!mounted) return;

    setState(() {
      switch (result) {
        case AuthSuccess():
          _authState = AuthState.authenticated;
          _onAuthSuccess();
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
  }

  Future<void> _submitPassword() async {
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

    final result = await authService.submitPassword(password);

    if (!mounted) return;

    setState(() {
      switch (result) {
        case AuthSuccess():
          _authState = AuthState.authenticated;
          _onAuthSuccess();
        case AuthError():
          _authState = AuthState.error;
          _errorMessage = result.message;
        default:
          _authState = AuthState.error;
          _errorMessage = 'Unexpected error occurred';
      }
    });
  }

  void _onAuthSuccess() {
    ref.read(onboardingProvider.notifier).completeOnboarding();
    ref.read(onboardingCompletedProvider.notifier).state = true;
    // The two providers above are in-memory only and reset on every cold
    // start, which is why onboarding used to reappear after closing the
    // app. Persist the flag through the same secure-storage-backed
    // settings repository the rest of the app already uses.
    unawaited(ref.read(appSettingsProvider.notifier).completeOnboarding());
    context.go('/timeline');
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
                            'Your photos are stored in your own Telegram account — fully encrypted and private.',
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
                              Icons.error_outline,
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
                                    const Icon(Icons.arrow_drop_down, size: 20),
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
                          onPressed: _verifyCode,
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
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _passwordVisible
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                            ),
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
                          onPressed: _submitPassword,
                          child: const Text('Verify'),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Center(
                        child: TextButton(
                          onPressed: () {},
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
                              Icons.check_circle_outline,
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

            // Back button
            if (_authState != AuthState.authenticated)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
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
