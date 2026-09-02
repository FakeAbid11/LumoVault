import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../../shared/providers/map_tile_status_provider.dart';

/// Failure banner for the map basemap.
///
/// Tile layers show nothing when their HTTP fetches fail — there is no error
/// UI anywhere below [OsmTileLayer] — so fetch errors are reported into
/// [mapTileStatusProvider] and surfaced here: a compact rounded banner for
/// the top of the map with a Retry action (drop + re-request every tile) and
/// a dismiss. Retry hides the banner immediately and reloads; if tiles fail
/// again the banner re-raises.
class MapTileErrorBanner extends ConsumerWidget {
  const MapTileErrorBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(mapTileStatusProvider);
    if (!status.hasFailures) return const SizedBox.shrink();

    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.errorContainer,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
        child: Row(
          children: [
            Icon(Symbols.wifi_off, size: 18, color: colors.onErrorContainer),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Map tiles failed to load. Check your connection.',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: colors.onErrorContainer),
              ),
            ),
            TextButton(
              onPressed: () =>
                  ref.read(mapTileStatusProvider.notifier).requestReload(),
              child: const Text('Retry'),
            ),
            IconButton(
              icon: const Icon(Symbols.close, size: 18),
              onPressed: () => ref.read(mapTileStatusProvider.notifier).reset(),
              tooltip: 'Dismiss',
            ),
          ],
        ),
      ),
    );
  }
}
