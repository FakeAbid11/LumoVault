import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../providers/settings_providers.dart';
import 'package:material_symbols_icons/symbols.dart';

/// About screen — app information, licenses, and links.
class AboutScreen extends ConsumerWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final packageInfo = ref.watch(appPackageInfoProvider);
    final versionText = packageInfo.when(
      data: (info) => 'Version ${info.version} (build ${info.buildNumber})',
      loading: () => 'Version …',
      error: (_, __) => 'Version unavailable',
    );

    return Scaffold(
      appBar: AppBar(title: const Text('About')),
      body: ListView(
        children: [
          const SizedBox(height: 32),
          Center(
            child: Icon(
              Symbols.photo_library,
              size: 72,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: Text(
              'LumoVault',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
          ),
          const SizedBox(height: 4),
          Center(
            child: Text(
              versionText,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              'Original quality photo backup powered by Telegram',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(height: 32),
          const Divider(),
          ListTile(
            leading: const Icon(Symbols.description),
            title: const Text('Licenses'),
            trailing: const Icon(Symbols.chevron_right),
            onTap: () => showLicensePage(
              context: context,
              applicationName: 'LumoVault',
              applicationVersion: packageInfo.valueOrNull?.version,
            ),
          ),
          ListTile(
            leading: const Icon(Symbols.privacy_tip),
            title: const Text('Privacy Policy'),
            trailing: const Icon(Symbols.chevron_right),
            onTap: () => _launchUrl(context, 'https://lumovault.app/privacy'),
          ),
          ListTile(
            leading: const Icon(Symbols.gavel),
            title: const Text('Open Source Licenses'),
            subtitle: const Text('View third-party licenses'),
            trailing: const Icon(Symbols.chevron_right),
            onTap: () => showLicensePage(
              context: context,
              applicationName: 'LumoVault',
              useRootNavigator: true,
            ),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Symbols.code),
            title: const Text('Source Code'),
            subtitle: const Text('github.com/FakeAbid11/LumoVault'),
            trailing: const Icon(Symbols.chevron_right),
            onTap: () =>
                _launchUrl(context, 'https://github.com/FakeAbid11/LumoVault'),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Future<void> _launchUrl(BuildContext context, String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not open $url')));
      }
    }
  }
}
