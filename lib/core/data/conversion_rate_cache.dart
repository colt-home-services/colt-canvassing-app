import 'package:shared_preferences/shared_preferences.dart';

class ConversionRateCache {
  static const _key = 'manager_conversion_rate_v1';

  static Future<double?> read() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getDouble(_key);
    } catch (_) {
      return null;
    }
  }

  static Future<void> write(double value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_key, value);
    } catch (_) {}
  }
}
