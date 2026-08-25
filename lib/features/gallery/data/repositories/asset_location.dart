import 'dart:async';

import 'package:photo_manager/photo_manager.dart';

import '../models/media_item.dart';

/// Read GPS coordinates from a device [AssetEntity]'s EXIF.
///
/// Returns `(latitude, longitude)`, both null when the photo has no location
/// fix, when the read fails, or when the platform returns the `(0, 0)`
/// null-island sentinel that photo_manager uses for "no coordinates".
///
/// On Android this requires the `ACCESS_MEDIA_LOCATION` permission; without it
/// the platform hands back stripped/zero coordinates, which this treats as no
/// location. Never throws — a photo without GPS must not break a scan.
Future<(double?, double?)> readCoordinates(AssetEntity asset) async {
  try {
    final latlng = await asset.latlngAsync();
    if (latlng == null) return (null, null);
    final lat = latlng.latitude;
    final lng = latlng.longitude;
    // (0, 0) is the "no fix" sentinel — a real photo taken at null island is
    // vanishingly unlikely and not worth a false pin in the ocean.
    if (lat == 0 && lng == 0) return (null, null);
    return (lat, lng);
  } catch (_) {
    return (null, null);
  }
}

/// Resolve GPS coordinates for a batch of device [assets], returning a
/// lightweight [MediaItem] for each asset that carries a location fix.
///
/// This is the Map tab's "show what's in the gallery, not just what's been
/// backed up" path. It reads EXIF GPS directly (via [reader], defaulting to
/// [readCoordinates]) WITHOUT hashing the file, so located photos appear on
/// the map immediately — the same way the Local tab shows them before any
/// backup scan has run. The expensive part of a scan is the SHA-256 hash, not
/// the coordinate read, so this stays consistent with "display never waits on
/// the slow scan". Assets without a fix are omitted.
///
/// Reads run [concurrency] at a time so a large library issues a steady
/// trickle of platform calls instead of tens of thousands at once, and each
/// read is bounded by [perAssetTimeout] so a single stuck asset (e.g. a
/// cloud-only photo that has to be re-fetched) can't stall the whole map —
/// the same defensive posture the scanners take. The [reader] seam lets tests
/// supply coordinates without photo_manager.
Future<List<MediaItem>> resolveAssetLocations(
  List<AssetEntity> assets, {
  int concurrency = 12,
  Duration perAssetTimeout = const Duration(seconds: 10),
  Future<(double?, double?)> Function(AssetEntity asset) reader =
      readCoordinates,
}) async {
  // Bound one reader call, always yielding a `(double?, double?)`. Written as a
  // typed local (rather than an inline `.timeout(onTimeout: () => (null, null))`)
  // so the awaited future is reified as `(double?, double?)`: a reader that
  // returns a non-nullable `(double, double)` makes `Future.timeout` reject a
  // `(null, null)` onTimeout fallback at runtime, since the future's reified
  // type argument wins over the declared one. Omitting onTimeout sidesteps that
  // — a timeout throws, which we map to "no fix" here instead.
  Future<(double?, double?)> read(AssetEntity asset) async {
    try {
      return await reader(asset).timeout(perAssetTimeout);
    } on TimeoutException {
      return (null, null);
    }
  }

  final located = <MediaItem>[];
  for (var start = 0; start < assets.length; start += concurrency) {
    final end = start + concurrency;
    final chunk = assets.sublist(
      start,
      end > assets.length ? assets.length : end,
    );
    final resolved = await Future.wait(
      chunk.map((asset) async {
        final (lat, lng) = await read(asset);
        if (lat == null || lng == null) return null;
        return _locatedMediaItem(asset, lat, lng);
      }),
    );
    located.addAll(resolved.whereType<MediaItem>());
  }
  return located;
}

/// A minimal [MediaItem] describing a located device asset for the Map tab.
///
/// Only the fields the map and its marker actually read are populated: the
/// coordinates, the id (which the thumbnail loader turns into a device
/// thumbnail — see `MediaTile.defaultThumbnailLoader`), and enough of the
/// media type for the video affordance. There is deliberately no file hash and
/// no file read here — that is the scan's job, and requiring it is exactly the
/// coupling that used to keep un-scanned photos off the map.
MediaItem _locatedMediaItem(AssetEntity asset, double lat, double lng) {
  final mimeType = switch (asset.type) {
    AssetType.image => 'image/jpeg',
    AssetType.video => 'video/mp4',
    AssetType.audio => 'audio/mpeg',
    _ => 'application/octet-stream',
  };
  return MediaItem(
    localId: asset.id,
    fileHash: '',
    filePath: '',
    fileName: asset.title ?? asset.id,
    mimeType: mimeType,
    fileSize: 0,
    width: asset.width,
    height: asset.height,
    durationMs: asset.type == AssetType.video ? asset.duration * 1000 : null,
    createdAt: asset.createDateTime,
    modifiedAt: asset.modifiedDateTime,
    scannedAt: DateTime.now(),
    status: MediaStatus.pending,
    latitude: lat,
    longitude: lng,
  );
}
