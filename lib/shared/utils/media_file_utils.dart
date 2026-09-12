/// Shared helpers for media file-name checks.
library;

/// Whether [fileName] refers to an animated GIF (".gif" extension).
///
/// photo_manager types GIFs as plain images, so type alone can't
/// distinguish them — the extension is the signal.
bool isGifFileName(String? fileName) =>
    (fileName ?? '').toLowerCase().endsWith('.gif');
