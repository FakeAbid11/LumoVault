import 'package:flutter/material.dart';

/// Code verification screen — enter SMS code.
class CodeVerificationScreen extends StatelessWidget {
  const CodeVerificationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Verification Code')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Enter the code',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'We sent a code to your phone number.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 32),
            const TextField(
              keyboardType: TextInputType.number,
              maxLength: 5,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 24, letterSpacing: 8),
              decoration: InputDecoration(
                labelText: 'Code',
                counterText: '',
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
            const SizedBox(height: 12),
            TextButton(onPressed: () {}, child: const Text('Resend code')),
          ],
        ),
      ),
    );
  }
}
