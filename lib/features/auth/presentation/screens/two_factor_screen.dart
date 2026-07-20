import 'package:flutter/material.dart';

/// Two-factor authentication screen.
class TwoFactorScreen extends StatelessWidget {
  const TwoFactorScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Two-Factor Authentication')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Two-factor verification',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'Enter your two-factor authentication code.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 32),
            const TextField(
              obscureText: true,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 24, letterSpacing: 8),
              decoration: InputDecoration(
                labelText: 'Password',
                border: OutlineInputBorder(),
              ),
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () {},
                child: const Text('Verify'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
