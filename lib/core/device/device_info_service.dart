import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';

/// Callback that returns Android manufacturer name.
typedef ManufacturerProvider = Future<String> Function();

/// Service to detect device manufacturer and OS skin.
///
/// Used to show device-specific guidance (e.g., MIUI background restrictions).
class DeviceInfoService {
  DeviceInfoService({ManufacturerProvider? manufacturerProvider})
    : _manufacturerProvider = manufacturerProvider ?? _defaultProvider;

  final ManufacturerProvider _manufacturerProvider;

  /// Cached result of MIUI detection.
  bool? _isMiui;

  /// Cached manufacturer name.
  String? _manufacturer;

  static Future<String> _defaultProvider() async {
    if (!Platform.isAndroid) return '';
    final androidInfo = await DeviceInfoPlugin().androidInfo;
    return androidInfo.manufacturer;
  }

  /// Check if the device is running MIUI (Xiaomi/Redmi/POCO).
  ///
  /// MIUI has aggressive background restrictions that require
  /// device-specific guidance during onboarding.
  Future<bool> isMiuiDevice() async {
    if (_isMiui != null) return _isMiui!;

    try {
      final manufacturer = await _getManufacturer();
      final m = manufacturer.toLowerCase();

      // Xiaomi family: Xiaomi, Redmi, POCO
      _isMiui = m == 'xiaomi' || m == 'redmi' || m == 'poco';
      return _isMiui!;
    } catch (e) {
      // If we can't detect, assume not MIUI to avoid showing unnecessary guidance
      _isMiui = false;
      return false;
    }
  }

  /// Get the device manufacturer name.
  Future<String> _getManufacturer() async {
    if (_manufacturer != null) return _manufacturer!;
    _manufacturer = await _manufacturerProvider();
    return _manufacturer!;
  }

  Future<String> getManufacturer() => _getManufacturer();
}
