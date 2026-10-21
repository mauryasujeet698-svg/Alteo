import 'dart:async';
import 'dart:convert';

import 'package:customer/core/widgets/catalogue_preview_notice.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final addressBookProvider = Provider<AddressBookStore>((ref) {
  final store = AddressBookStore();
  unawaited(store.load());
  ref.onDispose(store.dispose);
  return store;
});

class SavedAddress {
  const SavedAddress({
    required this.id,
    required this.label,
    required this.address,
    required this.postalCode,
    required this.isDefault,
  });

  final String id;
  final String label;
  final String address;
  final String postalCode;
  final bool isDefault;

  Map<String, Object> toJson() => {
        'id': id,
        'label': label,
        'address': address,
        'postalCode': postalCode,
        'isDefault': isDefault,
      };

  static SavedAddress? fromJson(dynamic value) {
    if (value is! Map<String, dynamic>) return null;
    final id = value['id'];
    final label = value['label'];
    final address = value['address'];
    final postalCode = value['postalCode'];
    final isDefault = value['isDefault'];
    if (id is! String || label is! String || address is! String ||
        postalCode is! String || isDefault is! bool) {
      return null;
    }
    return SavedAddress(
      id: id,
      label: label,
      address: address,
      postalCode: postalCode,
      isDefault: isDefault,
    );
  }
}

/// Local guest address book. Addresses are not synced or used for live
/// serviceability until an authenticated backend integration is implemented.
class AddressBookStore extends ChangeNotifier {
  static const _storageKey = 'alteo.guest_addresses.v1';
  final List<SavedAddress> _addresses = <SavedAddress>[];
  bool _loaded = false;
  int _revision = 0;

  List<SavedAddress> get addresses =>
      List<SavedAddress>.unmodifiable(_addresses);

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
        _addresses.addAll(decoded.map(SavedAddress.fromJson).whereType<SavedAddress>());
        if (_addresses.where((address) => address.isDefault).length > 1) {
          var keptDefault = false;
          for (var i = 0; i < _addresses.length; i++) {
            final address = _addresses[i];
            if (address.isDefault && !keptDefault) {
              keptDefault = true;
            } else if (address.isDefault) {
              _addresses[i] = SavedAddress(
                id: address.id,
                label: address.label,
                address: address.address,
                postalCode: address.postalCode,
                isDefault: false,
              );
            }
          }
        }
        notifyListeners();
      }
    } catch (_) {
      // The app remains usable even when local storage is unavailable.
    }
  }

  Future<void> addAddress({
    required String label,
    required String address,
    required String postalCode,
  }) async {
    final cleanLabel = label.trim();
    final cleanAddress = address.trim();
    final cleanPostalCode = postalCode.trim();
    if (cleanLabel.isEmpty || cleanLabel.length > 40) {
      throw ArgumentError('Enter a label of 1–40 characters.');
    }
    if (cleanAddress.length < 8 || cleanAddress.length > 300) {
      throw ArgumentError('Enter a complete address (8–300 characters).');
    }
    if (!RegExp(r'^[0-9]{6}$').hasMatch(cleanPostalCode)) {
      throw ArgumentError('Enter a valid six-digit PIN code.');
    }

    _revision++;
    final makeDefault = _addresses.isEmpty;
    if (makeDefault) _clearDefaultWithoutNotify();
    _addresses.add(SavedAddress(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      label: cleanLabel,
      address: cleanAddress,
      postalCode: cleanPostalCode,
      isDefault: makeDefault,
    ));
    notifyListeners();
    await _persist();
  }

  void setDefault(String id) {
    if (!_addresses.any((address) => address.id == id)) return;
    _revision++;
    for (var i = 0; i < _addresses.length; i++) {
      final address = _addresses[i];
      _addresses[i] = SavedAddress(
        id: address.id,
        label: address.label,
        address: address.address,
        postalCode: address.postalCode,
        isDefault: address.id == id,
      );
    }
    notifyListeners();
    unawaited(_persist());
  }

  void remove(String id) {
    final index = _addresses.indexWhere((address) => address.id == id);
    if (index < 0) return;
    final wasDefault = _addresses[index].isDefault;
    _revision++;
    _addresses.removeAt(index);
    if (wasDefault && _addresses.isNotEmpty) {
      final address = _addresses.first;
      _addresses[0] = SavedAddress(
        id: address.id,
        label: address.label,
        address: address.address,
        postalCode: address.postalCode,
        isDefault: true,
      );
    }
    notifyListeners();
    unawaited(_persist());
  }

  void _clearDefaultWithoutNotify() {
    for (var i = 0; i < _addresses.length; i++) {
      final address = _addresses[i];
      if (address.isDefault) {
        _addresses[i] = SavedAddress(
          id: address.id,
          label: address.label,
          address: address.address,
          postalCode: address.postalCode,
          isDefault: false,
        );
      }
    }
  }

  Future<void> _persist() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(
        _storageKey,
        jsonEncode(_addresses.map((address) => address.toJson()).toList()),
      );
    } catch (_) {
      // Addresses stay available for this session if storage fails.
    }
  }
}

class SavedAddressesScreen extends ConsumerWidget {
  const SavedAddressesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(addressBookProvider);
    return Scaffold(
      appBar: AppBar(title: Text('Saved addresses', style: Theme.of(context).textTheme.headlineMedium)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          builder: (context) => const _AddressFormSheet(),
        ),
        icon: const Icon(Icons.add_location_alt_outlined),
        label: const Text('Add address'),
      ),
      body: ListenableBuilder(
        listenable: store,
        builder: (context, child) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 100),
            children: [
              const CataloguePreviewNotice(),
              const SizedBox(height: 16),
              if (store.addresses.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 35),
                  child: Column(children: [
                    const Icon(Icons.location_on_outlined, size: 42),
                    const SizedBox(height: 12),
                    Text('No saved addresses yet', style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 6),
                    const Text('Add an address to keep it on this device. It will not be used for checkout until backend serviceability is connected.', textAlign: TextAlign.center),
                  ]),
                )
              else
                for (final address in store.addresses)
                  Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              address.label.toLowerCase() == 'home' ? Icons.home_outlined : address.label.toLowerCase() == 'work' ? Icons.work_outline : Icons.location_on_outlined,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              Flexible(child: Text(address.label, style: Theme.of(context).textTheme.titleMedium)),
                              if (address.isDefault) ...[
                                const SizedBox(width: 8),
                                const Chip(label: Text('Default'), visualDensity: VisualDensity.compact, padding: EdgeInsets.zero),
                              ],
                            ]),
                            const SizedBox(height: 4),
                            Text(address.address),
                            const SizedBox(height: 3),
                            Text('PIN ' + address.postalCode, style: Theme.of(context).textTheme.bodySmall),
                            const SizedBox(height: 8),
                            Wrap(spacing: 8, children: [
                              if (!address.isDefault)
                                TextButton(onPressed: () => store.setDefault(address.id), child: const Text('Set default')),
                              TextButton(
                                onPressed: () => store.remove(address.id),
                                child: const Text('Remove'),
                              ),
                            ]),
                          ])),
                        ],
                      ),
                    ),
                  ),
            ],
          );
        },
      ),
    );
  }
}

class _AddressFormSheet extends ConsumerStatefulWidget {
  const _AddressFormSheet();

  @override
  ConsumerState<_AddressFormSheet> createState() => _AddressFormSheetState();
}

class _AddressFormSheetState extends ConsumerState<_AddressFormSheet> {
  final _label = TextEditingController(text: 'Home');
  final _address = TextEditingController();
  final _postalCode = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _label.dispose();
    _address.dispose();
    _postalCode.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref.read(addressBookProvider).addAddress(
        label: _label.text,
        address: _address.text,
        postalCode: _postalCode.text,
      );
      if (mounted) Navigator.of(context).pop();
    } on ArgumentError catch (error) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message.toString())));
      }
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not save address. Please try again.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, 12, 20, MediaQuery.viewInsetsOf(context).bottom + 22),
          child: SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text('Add an address', style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 16),
              TextField(controller: _label, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Address label', hintText: 'Home, Work or Other')),
              const SizedBox(height: 12),
              TextField(controller: _address, textCapitalization: TextCapitalization.sentences, minLines: 2, maxLines: 4, decoration: const InputDecoration(labelText: 'Full address', hintText: 'House, street, area and city')),
              const SizedBox(height: 12),
              TextField(controller: _postalCode, keyboardType: TextInputType.number, maxLength: 6, decoration: const InputDecoration(labelText: 'PIN code', counterText: '')),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Saving…' : 'Save address on this device')),
              ),
              const SizedBox(height: 8),
              Text('This address is stored locally for now. It is not synced to your account or checked for service availability.', style: Theme.of(context).textTheme.bodySmall),
            ]),
          ),
        ),
      );
}
