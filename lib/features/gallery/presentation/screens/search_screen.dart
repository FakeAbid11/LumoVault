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

/// Search screen — live search over scanned media (file name, description,
/// album, tags) via [searchProvider]. Results render as a thumbnail grid the
/// same way the timeline does; tap through to the media viewer.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final TextEditingController _controller = TextEditingController();
  String _query = '';
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
                _debounce = Timer(const Duration(milliseconds: 300), () {
                  setState(() => _query = value.trim());
                });
              },
              decoration: InputDecoration(
                hintText: 'Search photos and videos...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
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
          Expanded(child: _buildResults()),
        ],
      ),
    );
  }

  Widget _buildResults() {
    if (_query.isEmpty) {
      return _buildHint(
        icon: Icons.search,
        title: 'Search your library',
        message: 'Find photos and videos by file name,\nalbum, or description.',
      );
    }

    final results = ref.watch(searchProvider(_query));
    final deviceAssets = ref.watch(deviceAssetsProvider);

    return results.when(
      data: (items) => deviceAssets.when(
        data: (assets) => _buildGrid(items, assets),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, s) => _buildGrid(items, const []),
      ),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, s) => Center(child: Text('$e')),
    );
  }

  Widget _buildGrid(List<MediaItem> items, List<AssetEntity> allAssets) {
    if (items.isEmpty) {
      return _buildHint(
        icon: Icons.search_off,
        title: 'No results',
        message: 'Try searching for something else.',
      );
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
      return _buildHint(
        icon: Icons.search_off,
        title: 'No results',
        message: 'Try searching for something else.',
      );
    }

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
        final asset = assets[index];
        return AssetTile(
          asset: asset,
          onTap: () => context.push(
            '/gallery/media/${asset.id}',
            extra: (assets: assets, initialIndex: index),
          ),
        );
      },
    );
  }

  Widget _buildHint({
    required IconData icon,
    required String title,
    required String message,
  }) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 80, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 24),
          Text(title, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
