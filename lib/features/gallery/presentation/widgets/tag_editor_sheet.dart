import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/gallery_providers.dart';
import 'package:material_symbols_icons/symbols.dart';

/// Bottom sheet for managing tags on a media item.
///
/// Shows existing tags as removable chips, a text field for adding new tags,
/// and autocomplete suggestions from the global tag vocabulary.
class TagEditorSheet extends ConsumerStatefulWidget {
  const TagEditorSheet({required this.mediaId, super.key});

  final String mediaId;

  @override
  ConsumerState<TagEditorSheet> createState() => _TagEditorSheetState();
}

class _TagEditorSheetState extends ConsumerState<TagEditorSheet> {
  late List<String> _tags;
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  List<String> _suggestions = [];

  @override
  void initState() {
    super.initState();
    final item = ref
        .read(galleryRepositoryProvider)
        .getItemById(widget.mediaId);
    _tags = List<String>.from(item?.tags ?? []);
    _loadSuggestions();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _loadSuggestions() async {
    final allTags = await ref.read(allTagsProvider.future);
    if (mounted) {
      setState(() {
        _suggestions = allTags;
      });
    }
  }

  void _addTag(String tag) {
    final trimmed = tag.trim().toLowerCase();
    if (trimmed.isEmpty || _tags.contains(trimmed)) return;
    setState(() {
      _tags.add(trimmed);
      _controller.clear();
    });
    _focusNode.requestFocus();
  }

  void _removeTag(String tag) {
    setState(() {
      _tags.remove(tag);
    });
  }

  Future<void> _save() async {
    await ref.read(galleryRepositoryProvider).setTags(widget.mediaId, _tags);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final query = _controller.text.toLowerCase();
    final filtered = query.isEmpty
        ? _suggestions.where((t) => !_tags.contains(t)).toList()
        : _suggestions
              .where((t) => t.contains(query) && !_tags.contains(t))
              .toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.5,
      minChildSize: 0.3,
      maxChildSize: 0.8,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Tags',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    FilledButton(onPressed: _save, child: const Text('Done')),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // Current tags
              if (_tags.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: _tags.map((tag) {
                      return Chip(
                        label: Text(tag),
                        deleteIcon: const Icon(Symbols.close, size: 16),
                        onDeleted: () => _removeTag(tag),
                        backgroundColor: colorScheme.secondaryContainer,
                        labelStyle: TextStyle(
                          color: colorScheme.onSecondaryContainer,
                        ),
                      );
                    }).toList(),
                  ),
                ),
              if (_tags.isNotEmpty) const SizedBox(height: 12),
              // Add tag input
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    hintText: 'Add a tag...',
                    prefixIcon: Icon(Symbols.label, size: 20),
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (_) => setState(() {}),
                  onSubmitted: _addTag,
                ),
              ),
              const SizedBox(height: 8),
              // Suggestions
              if (filtered.isNotEmpty)
                Expanded(
                  child: ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    children: [
                      Text(
                        'Suggestions',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 4),
                      ...filtered.map((tag) {
                        return ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Symbols.label, size: 18),
                          title: Text(tag),
                          onTap: () => _addTag(tag),
                        );
                      }),
                    ],
                  ),
                )
              else
                const Spacer(),
            ],
          ),
        );
      },
    );
  }
}
