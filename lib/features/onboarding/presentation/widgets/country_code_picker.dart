import 'package:flutter/material.dart';

import 'country_code.dart';

/// Opens a searchable bottom sheet for picking a [CountryCode].
///
/// Returns the selected [CountryCode], or null if the user dismissed the
/// sheet without picking one.
Future<CountryCode?> showCountryCodePicker(BuildContext context) {
  return showModalBottomSheet<CountryCode>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => const _CountryCodePickerSheet(),
  );
}

class _CountryCodePickerSheet extends StatefulWidget {
  const _CountryCodePickerSheet();

  @override
  State<_CountryCodePickerSheet> createState() =>
      _CountryCodePickerSheetState();
}

class _CountryCodePickerSheetState extends State<_CountryCodePickerSheet> {
  final _searchController = TextEditingController();
  late List<CountryCode> _filtered = kCountryCodes;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    setState(() {
      _filtered = kCountryCodes.where((c) => c.matches(query)).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.5,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                controller: _searchController,
                autofocus: false,
                onChanged: _onSearchChanged,
                decoration: const InputDecoration(
                  hintText: 'Search country or code',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            Expanded(
              child: _filtered.isEmpty
                  ? const Center(child: Text('No matching countries'))
                  : ListView.builder(
                      controller: scrollController,
                      itemCount: _filtered.length,
                      itemBuilder: (context, index) {
                        final country = _filtered[index];
                        return ListTile(
                          leading: Text(
                            country.flag,
                            style: const TextStyle(fontSize: 24),
                          ),
                          title: Text(country.name),
                          trailing: Text(
                            country.dialCode,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          onTap: () => Navigator.of(context).pop(country),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}
