import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../../core/device/miui_settings.dart';

/// A card showing MIUI-specific guidance for reliable background backup.
///
/// Displays step-by-step instructions for enabling background permissions
/// on Xiaomi/Redmi/POCO devices running MIUI.
class MiuiGuidanceCard extends StatefulWidget {
  const MiuiGuidanceCard({required this.packageName, super.key});

  /// The Android package name of the app.
  final String packageName;

  @override
  State<MiuiGuidanceCard> createState() => _MiuiGuidanceCardState();
}

class _MiuiGuidanceCardState extends State<MiuiGuidanceCard> {
  bool _isExpanded = true;
  final Set<int> _completedSteps = {};

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      color: colorScheme.tertiaryContainer,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          InkWell(
            onTap: () => setState(() => _isExpanded = !_isExpanded),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: colorScheme.tertiary,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Symbols.phone_android,
                      color: colorScheme.onTertiary,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'MIUI Background Settings',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                color: colorScheme.onTertiaryContainer,
                              ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Required for reliable backup',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: colorScheme.onTertiaryContainer
                                    .withAlpha(200),
                              ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    _isExpanded ? Symbols.expand_less : Symbols.expand_more,
                    color: colorScheme.onTertiaryContainer,
                  ),
                ],
              ),
            ),
          ),

          // Steps
          if (_isExpanded) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                'Your device requires extra steps for background backup to work:',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onTertiaryContainer.withAlpha(200),
                ),
              ),
            ),

            // Step 1: Autostart
            _buildStep(
              context,
              stepNumber: 1,
              title: 'Enable Autostart',
              description:
                  'Go to Settings → Apps → Manage apps → LumoVault → Autostart',
              icon: Symbols.power_settings_new,
              isCompleted: _completedSteps.contains(1),
              onToggle: () => _toggleStep(1),
              onOpenSettings: () =>
                  MiuiSettings.openAutostartSettings(widget.packageName),
            ),

            // Step 2: Battery Saver
            _buildStep(
              context,
              stepNumber: 2,
              title: 'Disable Battery Saver',
              description:
                  'Go to Settings → Apps → Manage apps → LumoVault → Battery saver → No restrictions',
              icon: Symbols.battery_alert,
              isCompleted: _completedSteps.contains(2),
              onToggle: () => _toggleStep(2),
              onOpenSettings: () =>
                  MiuiSettings.openBatterySettings(widget.packageName),
            ),

            // Step 3: Background Activity
            _buildStep(
              context,
              stepNumber: 3,
              title: 'Allow Background Activity',
              description:
                  'Go to Settings → Apps → Manage apps → LumoVault → Background activity → On',
              icon: Symbols.sync,
              isCompleted: _completedSteps.contains(3),
              onToggle: () => _toggleStep(3),
              onOpenSettings: () =>
                  MiuiSettings.openBatterySettings(widget.packageName),
            ),

            // Step 4: Lock in Recents
            _buildStep(
              context,
              stepNumber: 4,
              title: 'Lock in Recents',
              description:
                  'Open LumoVault, go to Recent Apps, tap the lock icon on LumoVault',
              icon: Symbols.lock,
              isCompleted: _completedSteps.contains(4),
              onToggle: () => _toggleStep(4),
              onOpenSettings: null, // Manual step
            ),

            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }

  void _toggleStep(int step) {
    setState(() {
      if (_completedSteps.contains(step)) {
        _completedSteps.remove(step);
      } else {
        _completedSteps.add(step);
      }

      // Collapse if all steps completed
      if (_completedSteps.length == 4) {
        _isExpanded = false;
      }
    });
  }

  Widget _buildStep(
    BuildContext context, {
    required int stepNumber,
    required String title,
    required String description,
    required IconData icon,
    required bool isCompleted,
    required VoidCallback onToggle,
    VoidCallback? onOpenSettings,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Step number/checkbox
          GestureDetector(
            onTap: onToggle,
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: isCompleted ? colorScheme.tertiary : colorScheme.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isCompleted
                      ? colorScheme.tertiary
                      : colorScheme.onSurfaceVariant.withAlpha(100),
                ),
              ),
              child: isCompleted
                  ? Icon(Symbols.check, color: colorScheme.onTertiary, size: 18)
                  : Center(
                      child: Text(
                        '$stepNumber',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 12),

          // Content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    decoration: isCompleted ? TextDecoration.lineThrough : null,
                    color: isCompleted
                        ? colorScheme.onSurfaceVariant.withAlpha(150)
                        : colorScheme.onTertiaryContainer,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onTertiaryContainer.withAlpha(180),
                  ),
                ),
                if (onOpenSettings != null && !isCompleted) ...[
                  const SizedBox(height: 4),
                  TextButton.icon(
                    onPressed: onOpenSettings,
                    icon: const Icon(Symbols.open_in_new, size: 16),
                    label: const Text('Open Settings'),
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
