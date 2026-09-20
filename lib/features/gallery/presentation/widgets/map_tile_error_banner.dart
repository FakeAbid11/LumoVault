import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../../shared/providers/map_tile_status_provider.dart';

/// Failure banner for the map basemap.
///
/// Tile layers show nothing when their HTTP fetches fail — there is no error
/// UI anywhere below [OsmTileLayer] — so fetch errors are reported into
/// [mapTileStatusProvider] and surfaced here: a compact rounded banner for
/// the top of the map. Retry *cycles the tile source* (primary → mirror →
/// …) before reloading, which is the escape hatch for networks that block or
/// intercept the primary domain — the failure mode that produces a blank map
/// with no error at all. Dismiss clears the state without refetching; the
/// banner re-raises if tiles fail again.
class MapTileErrorBanner extends ConsumerWidget {
  const MapTileErrorBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(mapTileStatusProvider);
    if (!status.hasFailures) return const SizedBox.shrink();

    // After the first source switch, the wording reflects what Retry does —
    // a plain "check your connection" would be misleading when the user has
    // already established the connection is not the problem.
    final switched = status.sourceIndex > 0;
    final message = switched
        ? 'Still failing — Retry tries a different map server.'
        : 'Map tiles failed to load. Check your connection.';

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
                message,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: colors.onErrorContainer),
              ),
            ),
            TextButton(
              onPressed: () =>
                  ref.read(mapTileStatusProvider.notifier).requestReload(),
              child: Text(switched ? 'Next server' : 'Retry'),
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
