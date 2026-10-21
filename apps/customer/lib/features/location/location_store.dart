import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Locally saved display preference only. It does not represent GPS position
/// and must not be used as proof of serviceability or delivery eligibility.
class LocationStore extends ChangeNotifier {
  static const _storageKey = 'alteo.selected_location_label';
  String _label = 'Choose your location';
  bool _loadStarted = false;

  String get label => _label;

  Future<void> load() async {
    if (_loadStarted) return;
    _loadStarted = true;
    try {
      final preferences = await SharedPreferences.getInstance();
      final saved = preferences.getString(_storageKey)?.trim();
      if (saved != null && saved.isNotEmpty) {
        _label = saved;
        notifyListeners();
      }
    } catch (_) {
      // Keep the default label if local preferences are unavailable.
    }
  }

  Future<void> selectLocation(String label) async {
    final normalised = label.trim();
    if (normalised.isEmpty) {
      throw ArgumentError.value(label, 'label', 'Location cannot be empty.');
    }
    _label = normalised;
    notifyListeners();
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(_storageKey, normalised);
    } catch (_) {
      // The UI can still use the value for this session if persistence fails.
    }
  }
}
