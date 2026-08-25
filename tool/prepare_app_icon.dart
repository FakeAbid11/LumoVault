// Builds the launcher-icon source images from the raw logo render.
//
// The render (`assets/icon/source_logo.png`) is a landscape frame: the icon
// tile sits centred on a dark backdrop with a coloured glow bleeding to the
// edges. That glow defeats luminance-based bounds detection — it is brighter
// than the tile's own dark-purple corner — so the tile rectangle is given
// explicitly below and verified by eye against the generated output.
//
// Outputs, all 1024x1024:
//   app_icon.png            — the tile, square, for legacy mipmaps
//   app_icon_foreground.png — the tile inset to Android's adaptive safe zone
//   app_icon_background.png — the tile's gradient, extended edge to edge
//
// Run: dart run tool/prepare_app_icon.dart [left top width height]
import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart';

/// The icon tile's rectangle within the source render.
const _tile = (left: 300, top: 22, width: 944, height: 978);

/// Output edge length. 1024 is the largest size any consumer needs (Play
/// Store listing); every mipmap density downsamples from it.
const _size = 1024;

/// Corner radius of the tile in the render, as a fraction of its edge.
///
/// Deliberately a shade wider than the artwork's actual radius: the masking
/// this drives only needs to guarantee the dark backdrop outside the arc is
/// gone, and overshooting eats gradient (which is replaced) rather than
/// leaving a dark crescent behind.
const _cornerRadius = 0.24;

void main(List<String> args) {
  final rect = args.length == 4
      ? (
          left: int.parse(args[0]),
          top: int.parse(args[1]),
          width: int.parse(args[2]),
          height: int.parse(args[3]),
        )
      : _tile;

  final src = decodePng(File('assets/icon/source_logo.png').readAsBytesSync())!;
  stdout.writeln('source ${src.width}x${src.height} -> crop $rect');

  final tile = copyResize(
    copyCrop(
      src,
      x: rect.left,
      y: rect.top,
      width: rect.width,
      height: rect.height,
    ),
    width: _size,
    height: _size,
    interpolation: Interpolation.cubic,
  );

  final gradient = _background(tile);

  // Full-bleed square: the tile's rounded corners are replaced by its own
  // gradient, so a launcher masking to a circle, squircle or rounded square
  // never exposes the render's dark backdrop at the edges.
  final squared = gradient.clone();
  final rounded = tile.convert(numChannels: 4);
  _roundCorners(rounded, (_size * _cornerRadius).round());
  compositeImage(squared, rounded);

  _write('app_icon.png', squared);
  _write('app_icon_foreground.png', _foreground(tile));
  _write('app_icon_background.png', gradient);
}

/// The tile at full canvas size with its rounded corners punched out.
///
/// No inset is applied here on purpose. flutter_launcher_icons wraps the
/// foreground drawable in `<inset android:inset="16%">`, which lands the
/// artwork at 68% of the 108dp adaptive canvas — just inside the 72dp Android
/// guarantees survives masking. Pre-scaling as well would inset it twice and
/// leave the shield looking lost in the middle of the icon.
///
/// The corners are transparent rather than gradient-filled so the background
/// layer shows through them; because that background was sampled from this
/// very tile, the join is seamless whatever shape the launcher masks to.
Image _foreground(Image tile) {
  final art = tile.convert(numChannels: 4);
  _roundCorners(art, (_size * _cornerRadius).round());
  return art;
}

/// A diagonal gradient sampled from the tile's four corners.
///
/// Using the tile's own colours means the foreground's edges melt into the
/// background instead of showing a seam, whatever shape the launcher masks
/// the icon to.
Image _background(Image tile) {
  // 20% in from each corner: far enough past the tile's rounded edge to be
  // reading gradient rather than the dark backdrop behind it, and still clear
  // of the shield and its light beam.
  final inset = (_size * 0.20).round();
  final topLeft = tile.getPixel(inset, inset);
  final topRight = tile.getPixel(_size - 1 - inset, inset);
  final bottomLeft = tile.getPixel(inset, _size - 1 - inset);
  final bottomRight = tile.getPixel(_size - 1 - inset, _size - 1 - inset);

  final canvas = Image(width: _size, height: _size, numChannels: 4);
  for (var y = 0; y < _size; y++) {
    final v = y / (_size - 1);
    for (var x = 0; x < _size; x++) {
      final u = x / (_size - 1);
      // Bilinear blend of the four corners: reproduces the render's
      // purple -> blue -> cyan sweep closely enough to be seamless.
      int channel(num tl, num tr, num bl, num br) {
        final top = tl + (tr - tl) * u;
        final bottom = bl + (br - bl) * u;
        return (top + (bottom - top) * v).round().clamp(0, 255);
      }

      canvas.setPixelRgba(
        x,
        y,
        channel(topLeft.r, topRight.r, bottomLeft.r, bottomRight.r),
        channel(topLeft.g, topRight.g, bottomLeft.g, bottomRight.g),
        channel(topLeft.b, topRight.b, bottomLeft.b, bottomRight.b),
        255,
      );
    }
  }
  return canvas;
}

/// Zero the alpha outside a rounded rectangle of the given corner [radius].
void _roundCorners(Image image, int radius) {
  final w = image.width;
  final h = image.height;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      // Distance from the nearest corner's arc centre, only inside the
      // corner squares — everywhere else is untouched.
      final dx = x < radius
          ? radius - x
          : (x >= w - radius ? x - (w - radius - 1) : 0);
      final dy = y < radius
          ? radius - y
          : (y >= h - radius ? y - (h - radius - 1) : 0);
      if (dx == 0 || dy == 0) continue;
      final d = math.sqrt(dx * dx + dy * dy);
      if (d <= radius) continue;
      // Feather the last pixel of the arc so the edge isn't visibly jagged.
      final alpha = d >= radius + 1 ? 0 : ((radius + 1 - d) * 255).round();
      final p = image.getPixel(x, y);
      image.setPixelRgba(x, y, p.r, p.g, p.b, alpha);
    }
  }
}

void _write(String name, Image image) {
  File('assets/icon/$name').writeAsBytesSync(encodePng(image));
  stdout.writeln('wrote assets/icon/$name (${image.width}x${image.height})');
}
