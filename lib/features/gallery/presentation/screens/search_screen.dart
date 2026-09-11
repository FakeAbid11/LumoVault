import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../../../core/di/gallery_providers.dart';
import '../../../../shared/utils/snackbars.dart';
import '../../../../shared/widgets/error_state.dart';
import '../../../settings/data/models/app_settings.dart';
import '../../../settings/presentation/providers/settings_providers.dart';
import '../providers/ai_scan_provider.dart';
import '../../data/models/media_item.dart';
import '../widgets/asset_tile.dart';
import 'package:material_symbols_icons/symbols.dart';

/// Search screen — live search over scanned media (file name, description,
/// album, tags, AI labels) via [searchProvider]. Includes an AI scan feature
/// that labels photos using EfficientNet-Lite0, and a visual "find similar"
/// mode driven by CLIP image embeddings.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key, this.similarTo});

  /// When set, the screen shows photos visually similar to this item
  /// (CLIP image-embedding cosine similarity) instead of keyword search.
  final String? similarTo;

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final TextEditingController _controller = TextEditingController();
  String _query = '';
  _SearchFilter _activeFilter = _SearchFilter.all;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Trigger background geocoding for items with GPS but no location name.
    ref.watch(geocodeItemsProvider);
    // Trigger background embedding generation for images without CLIP embeddings.
    ref.watch(generateEmbeddingsProvider);

    // Scan failures (no photos / model failed to load) surface as a snackbar;
    // the AI card also shows them inline.
    ref.listen(aiScanControllerProvider, (previous, next) {
      if (!next.running &&
          next.error != null &&
          previous?.error != next.error) {
        showLumoSnackBar(context, next.error!);
      }
    });

    final similarTo = widget.similarTo;
    final semanticMode = ref.watch(semanticModeProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(similarTo != null ? 'Similar photos' : 'Search'),
        actions: [
          if (similarTo == null)
            IconButton(
              icon: Icon(semanticMode ? Symbols.psychology : Symbols.search),
              tooltip: semanticMode ? 'Semantic search ON' : 'Keyword search',
              onPressed: () =>
                  ref.read(semanticModeProvider.notifier).state = !semanticMode,
            ),
        ],
      ),
      body: similarTo != null
          ? _buildSimilarResults(similarTo)
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: TextField(
                    controller: _controller,
                    autofocus: true,
                    onChanged: (value) => setState(() => _query = value.trim()),
                    decoration: InputDecoration(
                      hintText: semanticMode
                          ? 'Describe what you\'re looking for…'
                          : 'Search by name, tag, AI label, or location...',
                      prefixIcon: const Icon(Symbols.search),
                      suffixIcon: _query.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Symbols.close),
                              onPressed: () {
                                _controller.clear();
                                setState(() => _query = '');
                              },
                            ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(28),
                      ),
                      filled: true,
                    ),
                  ),
                ),
                // Filter chips — height scales with the accessibility text setting
                // so the chips aren't clipped at large font scales.
                SizedBox(
                  height: MediaQuery.textScalerOf(context).scale(40),
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    children: [
                      _buildSearchFilterChip('All', _SearchFilter.all),
                      const SizedBox(width: 6),
                      _buildSearchFilterChip('People', _SearchFilter.people),
                      const SizedBox(width: 6),
                      _buildSearchFilterChip(
                        'Locations',
                        _SearchFilter.locations,
                      ),
                      const SizedBox(width: 6),
                      _buildSearchFilterChip('Tags', _SearchFilter.tags),
                      const SizedBox(width: 6),
                      _buildSearchFilterChip(
                        'AI Labels',
                        _SearchFilter.aiLabels,
                      ),
                    ],
                  ),
                ),
                if (ref.watch(aiScanControllerProvider).running)
                  _buildScanProgress(),
                Expanded(child: _buildResults()),
              ],
            ),
    );
  }

  Widget _buildScanProgress() {
    final scan = ref.watch(aiScanControllerProvider);
    final progress = scan.total > 0 ? scan.completed / scan.total : 0.0;
    final pace = scan.etaMinutes != null
        ? ' · ~${scan.etaMinutes!.ceil()} min left'
        : '';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Row(
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2, value: progress),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'AI scanning: ${scan.completed} / ${scan.total} photos$pace',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onPrimaryContainer,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Symbols.close, size: 18),
            onPressed: () => ref.read(aiScanControllerProvider.notifier).stop(),
            tooltip: 'Stop scan',
          ),
        ],
      ),
    );
  }

  Widget _buildResults() {
    final similarTo = widget.similarTo;
    if (similarTo != null) {
      return _buildSimilarResults(similarTo);
    }

    // Semantic mode ranks by CLIP text-embedding similarity instead of
    // keyword matching.
    if (ref.watch(semanticModeProvider) && _query.isNotEmpty) {
      return _buildSemanticResults(_query);
    }

    if (_query.isEmpty) {
      return _buildHint();
    }

    var results = ref.watch(searchProvider(_query));
    final deviceAssets = ref.watch(deviceAssetsProvider);

    // Apply active filter.
    final repository = ref.read(galleryRepositoryProvider);
    switch (_activeFilter) {
      case _SearchFilter.all:
        break;
      case _SearchFilter.people:
        results = results.where((item) {
          final names = repository.personNamesForItem(item.localId);
          return names.isNotEmpty;
        }).toList();
      case _SearchFilter.locations:
        results = results.where((item) => item.locationName != null).toList();
      case _SearchFilter.tags:
        results = results.where((item) => item.tags.isNotEmpty).toList();
      case _SearchFilter.aiLabels:
        results = results.where((item) => item.aiLabels.isNotEmpty).toList();
    }

    return deviceAssets.when(
      data: (assets) {
        // Also search device assets by title for photos not in the repository
        // (e.g. photos from folders excluded from backup).
        final repository = ref.read(galleryRepositoryProvider);
        final repoIds = {
          for (final item in repository.mediaItems) item.localId,
        };
        final queryLower = _query.toLowerCase();
        final extra = <AssetEntity>[
          for (final a in assets)
            if (!repoIds.contains(a.id) &&
                (a.title?.toLowerCase().contains(queryLower) ?? false))
              a,
        ];
        return _buildGrid(results, assets, extraAssets: extra);
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, s) => ErrorState(
        error: e.toString(),
        onRetry: () => ref.invalidate(deviceAssetsProvider),
      ),
    );
  }

  /// Visual "find similar" results for [localId], ranked by CLIP image
  /// embedding similarity via [similarItemsProvider].
  Widget _buildSimilarResults(String localId) {
    final similarAsync = ref.watch(similarItemsProvider(localId));
    final deviceAssets = ref.watch(deviceAssetsProvider);

    return deviceAssets.when(
      data: (assets) => similarAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, s) => ErrorState(
          error: e.toString(),
          onRetry: () => ref.invalidate(similarItemsProvider(localId)),
        ),
        data: (items) {
          final byId = {for (final a in assets) a.id: a};
          final resolved = <MediaItem>[];
          final resolvedAssets = <AssetEntity>[];
          for (final item in items) {
            final asset = byId[item.localId];
            if (asset == null) continue;
            resolved.add(item);
            resolvedAssets.add(asset);
          }
          if (resolved.isEmpty) return _buildSimilarEmptyState();

          return GridView.builder(
            padding: const EdgeInsets.all(2),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: galleryCrossAxisCount(
                ref.watch(settingsGridSizeProvider),
                ref.watch(settingsCompactModeProvider),
              ),
              crossAxisSpacing: 2,
              mainAxisSpacing: 2,
            ),
            itemCount: resolved.length,
            itemBuilder: (context, index) {
              return AssetTile(
                asset: resolvedAssets[index],
                onTap: () => context.push(
                  '/gallery/media/${resolvedAssets[index].id}',
                  extra: (assets: resolvedAssets, initialIndex: index),
                ),
              );
            },
          );
        },
      ),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, s) => ErrorState(
        error: e.toString(),
        onRetry: () => ref.invalidate(deviceAssetsProvider),
      ),
    );
  }

  Widget _buildSimilarEmptyState() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Symbols.image_search,
              size: 80,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 24),
            Text(
              'No similar photos yet',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Similar photos are matched by on-device AI.\n'
              'Keep the Search tab open for a moment so it\ncan generate '
              'embeddings, then try again.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Semantic results for the query — ranked by CLIP text-embedding cosine
  /// similarity against the stored image embeddings (not keyword matching).
  Widget _buildSemanticResults(String query) {
    final semanticAsync = ref.watch(semanticTextSearchProvider(query));
    final deviceAssets = ref.watch(deviceAssetsProvider);

    return deviceAssets.when(
      data: (assets) => semanticAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, s) => ErrorState(
          error: e.toString(),
          onRetry: () => ref.invalidate(semanticTextSearchProvider(query)),
        ),
        data: (items) {
          final byId = {for (final a in assets) a.id: a};
          final resolved = <MediaItem>[];
          final resolvedAssets = <AssetEntity>[];
          for (final item in items) {
            final asset = byId[item.localId];
            if (asset == null) continue;
            resolved.add(item);
            resolvedAssets.add(asset);
          }
          if (resolved.isEmpty) return _buildSemanticEmptyState();

          return GridView.builder(
            padding: const EdgeInsets.all(2),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: galleryCrossAxisCount(
                ref.watch(settingsGridSizeProvider),
                ref.watch(settingsCompactModeProvider),
              ),
              crossAxisSpacing: 2,
              mainAxisSpacing: 2,
            ),
            itemCount: resolved.length,
            itemBuilder: (context, index) {
              return AssetTile(
                asset: resolvedAssets[index],
                onTap: () => context.push(
                  '/gallery/media/${resolvedAssets[index].id}',
                  extra: (assets: resolvedAssets, initialIndex: index),
                ),
              );
            },
          );
        },
      ),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, s) => ErrorState(
        error: e.toString(),
        onRetry: () => ref.invalidate(deviceAssetsProvider),
      ),
    );
  }

  Widget _buildSemanticEmptyState() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Symbols.psychology,
              size: 80,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 24),
            Text(
              'No semantic matches yet',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Semantic search ranks your photos by meaning.\n'
              'Photo embeddings are generated while this tab\nis open — give '
              'it a moment and try again.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHint() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Symbols.search,
              size: 80,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 24),
            Text(
              'Search your library',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Find photos and videos by file name,\nalbum, tags, AI labels, or location.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 32),
            // AI Scan Card
            const _AiScanCard(),
          ],
        ),
      ),
    );
  }

  Widget _buildGrid(
    List<MediaItem> items,
    List<AssetEntity> allAssets, {
    List<AssetEntity> extraAssets = const [],
  }) {
    if (items.isEmpty && extraAssets.isEmpty) {
      return _buildHint();
    }

    final byId = {for (final a in allAssets) a.id: a};
    final resolved = <MediaItem>[];
    final assets = <AssetEntity>[];
    var cloudOnly = 0;
    for (final item in items) {
      final asset = byId[item.localId];
      if (asset == null) {
        // Cloud-only match (no local file to render in this grid) — counted
        // so the UI can say so instead of hiding it silently.
        cloudOnly++;
        continue;
      }
      resolved.add(item);
      assets.add(asset);
    }

    // Append device-only assets not already in repository results.
    final existingIds = {for (final a in assets) a.id};
    for (final a in extraAssets) {
      if (!existingIds.contains(a.id)) {
        existingIds.add(a.id);
        assets.add(a);
        resolved.add(
          MediaItem(
            localId: a.id,
            fileHash: '',
            filePath: '',
            fileName: a.title ?? a.id,
            mimeType: a.type == AssetType.image ? 'image/jpeg' : 'video/mp4',
            fileSize: 0,
            width: a.width,
            height: a.height,
            durationMs: a.type == AssetType.video ? a.duration * 1000 : null,
            createdAt: a.createDateTime,
            modifiedAt: a.modifiedDateTime,
            scannedAt: DateTime.now(),
            status: MediaStatus.pending,
          ),
        );
      }
    }

    if (resolved.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Symbols.search_off,
              size: 80,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 24),
            Text(
              cloudOnly > 0 ? 'Found in your Telegram backup' : 'No results',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              cloudOnly > 0
                  ? '$cloudOnly ${cloudOnly == 1 ? 'match is' : 'matches are'} '
                        'cloud-only — restore from Telegram\nto view them here.'
                  : 'Try searching for something else.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        if (cloudOnly > 0)
          Container(
            width: double.infinity,
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              '$cloudOnly cloud-only '
              '${cloudOnly == 1 ? 'match is' : 'matches are'} not shown — '
              'restore from Telegram to view.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        // AI label chips for matched items — height scales with the
        // accessibility text setting.
        if (resolved.any((item) => item.aiLabels.isNotEmpty))
          SizedBox(
            height: MediaQuery.textScalerOf(context).scale(40),
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                for (final item in resolved)
                  for (final label in item.aiLabels)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 8,
                      ),
                      child: Chip(
                        label: Text(
                          label.replaceFirst('ai_', ''),
                          style: const TextStyle(fontSize: 12),
                        ),
                        backgroundColor: Theme.of(
                          context,
                        ).colorScheme.secondaryContainer,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
              ],
            ),
          ),
        // Grid
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(2),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: galleryCrossAxisCount(
                ref.watch(settingsGridSizeProvider),
                ref.watch(settingsCompactModeProvider),
              ),
              crossAxisSpacing: 2,
              mainAxisSpacing: 2,
            ),
            itemCount: resolved.length,
            itemBuilder: (context, index) {
              final asset = assets[index];
              final item = resolved[index];
              return Stack(
                children: [
                  AssetTile(
                    asset: asset,
                    onTap: () => context.push(
                      '/gallery/media/${asset.id}',
                      extra: (assets: assets, initialIndex: index),
                    ),
                  ),
                  if (item.aiLabels.isNotEmpty)
                    Positioned(
                      top: 4,
                      right: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Theme.of(
                            context,
                          ).colorScheme.primaryContainer.withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Symbols.auto_awesome,
                              size: 12,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            const SizedBox(width: 2),
                            Text(
                              item.aiLabels.first
                                  .replaceFirst('ai_', '')
                                  .replaceAll('_', ' '),
                              style: TextStyle(
                                fontSize: 10,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onPrimaryContainer,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (item.locationName != null)
                    Positioned(
                      bottom: 4,
                      left: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.tertiaryContainer
                              .withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Symbols.location_on,
                              size: 12,
                              color: Theme.of(context).colorScheme.tertiary,
                            ),
                            const SizedBox(width: 2),
                            Text(
                              item.locationName!,
                              style: TextStyle(
                                fontSize: 10,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onTertiaryContainer,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSearchFilterChip(String label, _SearchFilter filter) {
    final isSelected = _activeFilter == filter;
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => setState(() => _activeFilter = filter),
      selectedColor: Theme.of(context).colorScheme.primaryContainer,
      checkmarkColor: Theme.of(context).colorScheme.onPrimaryContainer,
    );
  }
}

class _AiScanCard extends ConsumerWidget {
  const _AiScanCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scan = ref.watch(aiScanControllerProvider);
    final labeledCount = ref.watch(labeledCountProvider);
    final deviceAssetsAsync = ref.watch(deviceAssetsProvider);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Icon(
                  Symbols.auto_awesome,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'AI Photo Labels',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (labeledCount > 0)
              Text(
                '$labeledCount photos labeled',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            if (scan.error != null && !scan.running) ...[
              const SizedBox(height: 8),
              Text(
                scan.error!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ],
            const SizedBox(height: 12),
            deviceAssetsAsync.when(
              data: (allAssets) {
                final totalImages = allAssets
                    .where((a) => a.type == AssetType.image)
                    .length;
                final remaining = totalImages - labeledCount;
                if (remaining <= 0) {
                  return Text(
                    'All photos have been labeled',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  );
                }
                return SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: scan.running
                        ? null
                        : () => ref
                              .read(aiScanControllerProvider.notifier)
                              .start(),
                    icon: scan.running
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Symbols.smart_toy, size: 18),
                    label: Text(
                      scan.running
                          ? 'Scanning… ${scan.completed} / ${scan.total}'
                          : 'AI Scan ($remaining remaining)',
                    ),
                  ),
                );
              },
              loading: () => const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              error: (_, __) => const Text('Could not load photos'),
            ),
          ],
        ),
      ),
    );
  }
}

enum _SearchFilter { all, people, locations, tags, aiLabels }
