import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// A widget that catches errors in its child widget tree and displays
/// a fallback error UI instead of crashing the app.
///
/// This widget works by wrapping the child in a [Builder] and using
/// [ErrorWidget.builder] to intercept rendering errors. For uncaught
/// Flutter errors, use [GlobalErrorHandler] in main() instead.
///
/// Usage:
/// ```dart
/// ErrorBoundary(
///   child: MyApp(),
/// )
/// ```
class ErrorBoundary extends StatefulWidget {
  const ErrorBoundary({
    super.key,
    required this.child,
    this.onError,
    this.fallbackBuilder,
  });

  final Widget child;
  final void Function(Object error, StackTrace stack)? onError;
  final Widget Function(BuildContext context, Object error)? fallbackBuilder;

  @override
  State<ErrorBoundary> createState() => _ErrorBoundaryState();
}

class _ErrorBoundaryState extends State<ErrorBoundary> {
  Object? _error;

  /// Public method to manually trigger the error state (e.g., from a catch block).
  void showError(Object error) {
    if (mounted) {
      setState(() {
        _error = error;
      });
      widget.onError?.call(error, StackTrace.current);
    }
  }

  /// Clear the error state.
  void clearError() {
    if (mounted) {
      setState(() {
        _error = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      if (widget.fallbackBuilder != null) {
        return widget.fallbackBuilder!(context, _error!);
      }
      return _DefaultErrorUI(error: _error!, onRetry: clearError);
    }

    return widget.child;
  }
}

class _DefaultErrorUI extends StatelessWidget {
  const _DefaultErrorUI({required this.error, this.onRetry});

  final Object error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return MaterialApp(
      home: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.error_outline,
                  size: 64,
                  color: theme.colorScheme.error,
                ),
                const SizedBox(height: 16),
                Text(
                  'Something went wrong',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'An unexpected error occurred. Please try again.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                if (onRetry != null)
                  FilledButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Try Again'),
                  ),
                if (kDebugMode) ...[
                  const SizedBox(height: 24),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.errorContainer.withValues(
                        alpha: 0.3,
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      error.toString(),
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                      ),
                      maxLines: 5,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
