import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final favoriteStoreProvider = Provider<FavoriteStore>((ref) {
  final store = FavoriteStore();
  unawaited(store.load());
  ref.onDispose(store.dispose);
  return store;
});

/// Locally persisted favourites for guest browsing. Server sync is not enabled.
class FavoriteStore extends ChangeNotifier {
  static const _storageKey = 'alteo.guest_favourites.v1';
  final Set<String> _ids = <String>{};
  int _revision = 0;
  bool _loaded = false;

  bool contains(String productId) => _ids.contains(productId);
  Set<String> get ids => Set<String>.unmodifiable(_ids);

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    final startingRevision = _revision;
    try {
      final preferences = await SharedPreferences.getInstance();
      final raw = preferences.getString(_storageKey);
      if (raw == null || startingRevision != _revision) return;
      final decoded = jsonDecode(raw);
      if (decoded is List<dynamic>) {
        _ids.addAll(decoded.whereType<String>().where((id) => id.isNotEmpty));
        notifyListeners();
      }
    } catch (_) {
      // Favourites continue to work for this session if local storage is absent.
    }
  }

  void toggle(String productId) {
    if (productId.isEmpty) return;
    _revision++;
    if (!_ids.add(productId)) _ids.remove(productId);
    notifyListeners();
    unawaited(_persist());
  }

  Future<void> _persist() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(_storageKey, jsonEncode(_ids.toList()));
    } catch (_) {
      // Keep the session state when local persistence is unavailable.
    }
  }
}
