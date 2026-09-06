import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../../core/di/backup_providers.dart';
import '../../../../core/di/gallery_providers.dart';
import '../../../../core/utils/format_utils.dart';
import '../../../backup/engine/backup_engine.dart';
import '../../../gallery/data/models/device_folder.dart';
import '../providers/storage_providers.dart';

class StorageInsightsScreen extends ConsumerWidget {
  const StorageInsightsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final storageAsync = ref.watch(storageUsageProvider);
    final stats = ref.watch(backupStatsProvider);
    final gallery = ref.watch(galleryRepositoryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Storage Insights')),
      body: storageAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (usage) {
          final photos = gallery.mediaItems.where((m) => !m.isVideo).toList();
          final videos = gallery.mediaItems.where((m) => m.isVideo).toList();
          final photosSize = photos.fold(0, (s, m) => s + m.fileSize);
          final videosSize = videos.fold(0, (s, m) => s + m.fileSize);
          final pendingBytes = usage.deviceMediaBytes - usage.telegramBytes;

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              // ── Donut Chart ──
              _DonutChart(
                backedUpBytes: usage.telegramBytes.clamp(
                  0,
                  usage.deviceMediaBytes,
                ),
                pendingBytes: pendingBytes.clamp(0, usage.deviceMediaBytes),
                totalBytes: usage.deviceMediaBytes,
              ),
              const SizedBox(height: 20),

              // ── Summary Cards ──
              Row(
                children: [
                  Expanded(
                    child: _SummaryCard(
                      label: 'Local',
                      count: '${usage.deviceMediaCount}',
                      size: formatBytes(usage.deviceMediaBytes),
                      color: Colors.blue,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _SummaryCard(
                      label: 'Backed Up',
                      count: '${usage.telegramItemCount}',
                      size: formatBytes(usage.telegramBytes),
                      color: Colors.green,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _SummaryCard(
                      label: 'Pending',
                      count: '${stats.pendingCount + stats.uploadingCount}',
                      size: formatBytes(pendingBytes.clamp(0, 1 << 60)),
                      color: Colors.orange,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // ── Photos vs Videos ──
              const _SectionHeader(title: 'By Type', icon: Symbols.category),
              const SizedBox(height: 8),
              _TypeRow(
                icon: Symbols.photo,
                label: 'Photos',
                count: photos.length,
                size: photosSize,
                totalSize: usage.deviceMediaBytes,
              ),
              const SizedBox(height: 4),
              _TypeRow(
                icon: Symbols.videocam,
                label: 'Videos',
                count: videos.length,
                size: videosSize,
                totalSize: usage.deviceMediaBytes,
              ),
              const SizedBox(height: 24),

              // ── By Folder ──
              if (gallery.folders.isNotEmpty) ...[
                const _SectionHeader(title: 'By Folder', icon: Symbols.folder),
                const SizedBox(height: 8),
                ...gallery.folders.map((f) => _FolderRow(folder: f)),
                const SizedBox(height: 24),
              ],

              // ── App Overhead ──
              const _SectionHeader(title: 'App Data', icon: Symbols.database),
              const SizedBox(height: 8),
              _OverheadRow(
                icon: Icons.image_outlined,
                label: 'Thumbnail Cache',
                size: usage.thumbnailCacheBytes,
              ),
              const SizedBox(height: 4),
              _OverheadRow(
                icon: Icons.code,
                label: 'Metadata Files',
                size: usage.metadataBytes,
              ),
              const SizedBox(height: 4),
              _OverheadRow(
                icon: Icons.storage,
                label: 'Database',
                size: usage.databaseBytes,
              ),
              const SizedBox(height: 4),
              _OverheadRow(
                icon: Icons.folder_outlined,
                label: 'Local Cache',
                size: usage.localCacheBytes,
              ),
              const SizedBox(height: 24),

              // ── Backup Health ──
              const _SectionHeader(
                title: 'Backup Health',
                icon: Symbols.favorite,
              ),
              const SizedBox(height: 8),
              _BackupHealthSection(stats: stats),
            ],
          );
        },
      ),
    );
  }
}

// ─── Donut Chart ───

class _DonutChart extends StatelessWidget {
  const _DonutChart({
    required this.backedUpBytes,
    required this.pendingBytes,
    required this.totalBytes,
  });

  final int backedUpBytes;
  final int pendingBytes;
  final int totalBytes;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final backedUpFrac = totalBytes > 0 ? backedUpBytes / totalBytes : 0.0;
    final pendingFrac = totalBytes > 0 ? pendingBytes / totalBytes : 0.0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            SizedBox(
              width: 120,
              height: 120,
              child: CustomPaint(
                painter: _DonutPainter(
                  backedUpFraction: backedUpFrac,
                  pendingFraction: pendingFrac,
                  backedUpColor: scheme.primary,
                  pendingColor: scheme.errorContainer,
                ),
                child: Center(
                  child: Text(
                    '${(backedUpFrac * 100).round()}%',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Backup Coverage',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _LegendRow(
                    color: scheme.primary,
                    label: 'Backed up',
                    value: formatBytes(backedUpBytes),
                  ),
                  const SizedBox(height: 4),
                  _LegendRow(
                    color: scheme.errorContainer,
                    label: 'Not yet backed up',
                    value: formatBytes(pendingBytes),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter({
    required this.backedUpFraction,
    required this.pendingFraction,
    required this.backedUpColor,
    required this.pendingColor,
  });

  final double backedUpFraction;
  final double pendingFraction;
  final Color backedUpColor;
  final Color pendingColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = min(size.width, size.height) / 2 - 8;
    const strokeWidth = 18.0;

    final bgPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..color = pendingColor.withValues(alpha: 0.3);

    final backedUpPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..color = backedUpColor;

    final pendingPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..color = pendingColor;

    // Background circle.
    canvas.drawCircle(center, radius, bgPaint);

    // Backed up arc.
    final backedUpAngle = 2 * pi * backedUpFraction;
    if (backedUpAngle > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -pi / 2,
        backedUpAngle,
        false,
        backedUpPaint,
      );
    }

    // Pending arc.
    final pendingAngle = 2 * pi * pendingFraction;
    if (pendingAngle > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -pi / 2 + backedUpAngle,
        pendingAngle,
        false,
        pendingPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_DonutPainter oldDelegate) =>
      oldDelegate.backedUpFraction != backedUpFraction ||
      oldDelegate.pendingFraction != pendingFraction;
}

class _LegendRow extends StatelessWidget {
  const _LegendRow({
    required this.color,
    required this.label,
    required this.value,
  });

  final Color color;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(label, style: Theme.of(context).textTheme.bodySmall),
        ),
        Text(
          value,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

// ─── Summary Card ───

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.label,
    required this.count,
    required this.size,
    required this.color,
  });

  final String label;
  final String count;
  final String size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(
                label == 'Local'
                    ? Symbols.phone_android
                    : label == 'Backed Up'
                    ? Symbols.cloud_done
                    : Symbols.hourglass_top,
                size: 18,
                color: color,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              count,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            Text(label, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 2),
            Text(
              size,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Section Header ───

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.icon});

  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 6),
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
      ],
    );
  }
}

// ─── Type Row ───

class _TypeRow extends StatelessWidget {
  const _TypeRow({
    required this.icon,
    required this.label,
    required this.count,
    required this.size,
    required this.totalSize,
  });

  final IconData icon;
  final String label;
  final int count;
  final int size;
  final int totalSize;

  @override
  Widget build(BuildContext context) {
    final fraction = totalSize > 0 ? size / totalSize : 0.0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        label,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      Text(
                        '$count items',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: fraction,
                            minHeight: 6,
                            backgroundColor: Theme.of(
                              context,
                            ).colorScheme.surfaceContainerHighest,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        formatBytes(size),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Folder Row ───

class _FolderRow extends StatelessWidget {
  const _FolderRow({required this.folder});

  final DeviceFolder folder;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const Icon(Symbols.folder, size: 20),
        title: Text(folder.name),
        subtitle: Text('${folder.totalItems} items'),
        trailing: Text(
          formatBytes(folder.totalSize),
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

// ─── Overhead Row ───

class _OverheadRow extends StatelessWidget {
  const _OverheadRow({
    required this.icon,
    required this.label,
    required this.size,
  });

  final IconData icon;
  final String label;
  final int size;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        dense: true,
        leading: Icon(icon, size: 18),
        title: Text(label, style: Theme.of(context).textTheme.bodyMedium),
        trailing: Text(
          formatBytes(size),
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

// ─── Backup Health ───

class _BackupHealthSection extends StatelessWidget {
  const _BackupHealthSection({required this.stats});

  final BackupStats stats;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final lastBackup = stats.lastBackupAt;
    final lastBackupText = lastBackup != null
        ? _timeAgo(lastBackup)
        : 'Never backed up';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _HealthRow(
              icon: Symbols.cloud_done,
              label: 'Last backup',
              value: lastBackupText,
              color: lastBackup != null ? Colors.green : scheme.error,
            ),
            const SizedBox(height: 8),
            if (stats.failedCount > 0)
              GestureDetector(
                onTap: () => context.push('/settings/backup'),
                child: _HealthRow(
                  icon: Symbols.error,
                  label: 'Failed uploads',
                  value: '${stats.failedCount} — Tap to retry',
                  color: scheme.error,
                ),
              ),
            if (stats.uploadingCount > 0) ...[
              const SizedBox(height: 8),
              _HealthRow(
                icon: Symbols.upload,
                label: 'Uploading now',
                value: '${stats.uploadingCount} items',
                color: scheme.primary,
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: stats.progress,
                  minHeight: 6,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                stats.progressDisplay,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _timeAgo(DateTime date) {
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${(diff.inDays / 7).floor()}w ago';
  }
}

class _HealthRow extends StatelessWidget {
  const _HealthRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
        ),
        Text(
          value,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
