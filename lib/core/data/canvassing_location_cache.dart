import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class SavedCanvassingLocation {
  const SavedCanvassingLocation({this.town, this.street, this.address});

  final String? town;
  final String? street;
  final String? address;

  bool get hasTown => town != null && town!.trim().isNotEmpty;
  bool get hasStreet => street != null && street!.trim().isNotEmpty;
  bool get hasAddress => address != null && address!.trim().isNotEmpty;
}

class CanvassingLocationCache {
  static const _key = 'last_canvassing_location_v1';

  static Future<SavedCanvassingLocation?> read() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final town = decoded['town']?.toString().trim();
      final street = decoded['street']?.toString().trim();
      final address = decoded['address']?.toString().trim();
      if ((town == null || town.isEmpty) &&
          (street == null || street.isEmpty) &&
          (address == null || address.isEmpty)) {
        return null;
      }
      return SavedCanvassingLocation(
        town: town == null || town.isEmpty ? null : town,
        street: street == null || street.isEmpty ? null : street,
        address: address == null || address.isEmpty ? null : address,
      );
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveTown(String town) async {
    await _write(town: town);
  }

  static Future<void> saveStreet({
    required String town,
    required String street,
  }) async {
    await _write(town: town, street: street);
  }

  static Future<void> saveHouse({
    required String town,
    required String street,
    required String address,
  }) async {
    await _write(town: town, street: street, address: address);
  }

  static Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
    } catch (_) {}
  }

  static Future<void> _write({
    required String town,
    String? street,
    String? address,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _key,
        jsonEncode({
          'town': town.trim(),
          if (street != null && street.trim().isNotEmpty)
            'street': street.trim(),
          if (address != null && address.trim().isNotEmpty)
            'address': address.trim(),
        }),
      );
    } catch (_) {}
  }
}
