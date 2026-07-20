import 'package:flutter/material.dart';

/// Storage screen — storage usage statistics.
class StorageScreen extends StatelessWidget {
  const StorageScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Storage')),
      body: const Center(
        child: Text('Storage — Storage usage details will be shown here'),
      ),
    );
  }
}
