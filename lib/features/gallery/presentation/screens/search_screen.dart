import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../../../core/di/gallery_providers.dart';
import '../../../settings/data/models/app_settings.dart';
import '../../../settings/presentation/providers/settings_providers.dart';
import '../../data/models/media_item.dart';
import '../widgets/asset_tile.dart';
import 'package:material_symbols_icons/symbols.dart';

/// Search screen — live search over scanned media (file name, description,
/// album, tags, AI labels) via [searchProvider]. Includes an AI scan feature
/// that labels photos using EfficientNet-Lite0.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final TextEditingController _controller = TextEditingController();
  String _query = '';
  bool _scanning = false;
  int _scanProgress = 0;
  int _scanTotal = 0;

  /// Debounces keystrokes so the O(n) substring filter over the whole library
  /// (via [searchProvider]) runs once per pause in typing, not per character.
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Search')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _controller,
              autofocus: true,
              onChanged: (value) {
                _debounce?.cancel();
                _debounce = Timer(const Duration(milliseconds: 250), () {
                  if (mounted) setState(() => _query = value.trim());
                });
              },
              decoration: InputDecoration(
                hintText: 'Search photos, videos, or AI labels...',
                prefixIcon: const Icon(Symbols.search),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Symbols.close),
                        tooltip: 'Clear search',
                        onPressed: () {
                          _debounce?.cancel();
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
          if (_scanning) _buildScanProgress(),
          Expanded(child: _buildResults()),
        ],
      ),
    );
  }

  Widget _buildScanProgress() {
    final progress = _scanTotal > 0 ? _scanProgress / _scanTotal : 0.0;
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
              'AI scanning: $_scanProgress / $_scanTotal photos',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onPrimaryContainer,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Symbols.close, size: 18),
            onPressed: () => setState(() => _scanning = false),
            tooltip: 'Stop scan',
          ),
        ],
      ),
    );
  }

  Widget _buildResults() {
    if (_query.isEmpty) {
      return _buildHint();
    }

    final results = ref.watch(searchProvider(_query));
    final deviceAssets = ref.watch(deviceAssetsProvider);

    return deviceAssets.when(
      data: (assets) => _buildGrid(results, assets),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, s) => _buildGrid(results, const []),
    );
  }

  Widget _buildHint() {
    final unlabeled = ref.watch(unlabeledItemsProvider);
    final labeledCount = ref.watch(labeledCountProvider);

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
              'Find photos and videos by file name,\nalbum, tags, or AI labels.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 32),
            // AI Scan Card
            Card(
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
                    if (unlabeled.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _scanning ? null : () => _startScan(),
                          icon: _scanning
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
                            _scanning
                                ? 'Scanning...'
                                : 'AI Scan (${unlabeled.length} remaining)',
                          ),
                        ),
                      ),
                    ] else if (labeledCount > 0) ...[
                      const SizedBox(height: 8),
                      Text(
                        'All photos have been labeled',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGrid(List<MediaItem> items, List<AssetEntity> allAssets) {
    if (items.isEmpty) {
      return _buildHint();
    }

    final byId = {for (final a in allAssets) a.id: a};
    final resolved = <MediaItem>[];
    final assets = <AssetEntity>[];
    for (final item in items) {
      final asset = byId[item.localId];
      if (asset == null) continue;
      resolved.add(item);
      assets.add(asset);
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
              'No results',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Try searching for something else.',
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
        // AI label chips for matched items
        if (resolved.any((item) => item.aiLabels.isNotEmpty))
          SizedBox(
            height: 40,
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
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _startScan() async {
    final unlabeled = ref.read(unlabeledItemsProvider);
    if (unlabeled.isEmpty) return;

    setState(() {
      _scanning = true;
      _scanProgress = 0;
      _scanTotal = unlabeled.length;
    });

    try {
      final classifier = ref.read(imageClassifierProvider);
      final repository = ref.read(galleryRepositoryProvider);
      await classifier.init();

      if (!classifier.isReady) {
        debugPrint('[SearchScreen] Classifier failed to initialize');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Could not start the AI scanner on this device.'),
            ),
          );
        }
        return;
      }

      for (var i = 0; i < unlabeled.length; i++) {
        if (!_scanning) break;

        final item = unlabeled[i];
        final asset = await AssetEntity.fromId(item.localId);
        if (asset == null) continue;

        final labels = await classifier.classify(asset);
        if (labels.isNotEmpty) {
          await repository.labelMediaItem(item.localId, labels);
        }

        if (mounted) {
          setState(() => _scanProgress = i + 1);
        }
      }
    } catch (e) {
      debugPrint('[SearchScreen] Scan failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('AI scan failed. Please try again.')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _scanning = false);
        ref.invalidate(unlabeledItemsProvider);
        ref.invalidate(labeledCountProvider);
      }
    }
  }
}
