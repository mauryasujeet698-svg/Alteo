import 'package:flutter/material.dart';

class CustomerLocationPage extends StatefulWidget {
  const CustomerLocationPage({super.key});
  @override
  State<CustomerLocationPage> createState() => _CustomerLocationPageState();
}

class _CustomerLocationPageState extends State<CustomerLocationPage> {
  final _address = TextEditingController();
  String? _label;
  @override
  void dispose() { _address.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Delivery location')),
    body: ListView(padding: const EdgeInsets.all(20), children: [
      const Text('Where should we serve you?', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
      const SizedBox(height: 8),
      const Text('Choose an address to help determine service availability. GPS and map pin selection require location permissions and a configured Mapbox token.', style: TextStyle(color: Color(0xFF68736D), height: 1.45)),
      const SizedBox(height: 16),
      OutlinedButton.icon(onPressed: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Current location needs location permission and GPS integration.'))), icon: const Icon(Icons.my_location_rounded), label: const Text('Use current location')),
      for (final item in ['Home', 'Work', 'Other']) RadioListTile<String>(value: item, groupValue: _label, onChanged: (value) => setState(() => _label = value), title: Text(item), contentPadding: EdgeInsets.zero),
      const SizedBox(height: 8),
      TextField(controller: _address, maxLines: 2, decoration: InputDecoration(labelText: 'Address or landmark', hintText: 'House, street, area', border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)))),
      const SizedBox(height: 18),
      FilledButton(onPressed: () {
        final value = _address.text.trim();
        if (value.isEmpty && _label == null) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Choose an address or enter a landmark.'))); return; }
        Navigator.of(context).pop(value.isNotEmpty ? value : _label);
      }, child: const Text('Confirm location')),
    ]),
  );
}