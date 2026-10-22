import 'package:flutter/material.dart';

class CustomerSearchPage extends StatefulWidget {
  const CustomerSearchPage({super.key});
  @override
  State<CustomerSearchPage> createState() => _CustomerSearchPageState();
}

class _CustomerSearchPageState extends State<CustomerSearchPage> {
  final _controller = TextEditingController();
  static const _services = ['Food and restaurants', 'Groceries and essentials', 'Shopping', 'Bike rides', 'Car rides', 'Parcel delivery'];
  @override
  void dispose() { _controller.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    final query = _controller.text.trim().toLowerCase();
    final results = _services.where((item) => item.toLowerCase().contains(query)).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Search Alteo')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(children: [
          TextField(
            controller: _controller, autofocus: true, onChanged: (_) => setState(() {}),
            decoration: InputDecoration(hintText: 'Food, groceries, rides…', prefixIcon: const Icon(Icons.search_rounded), filled: true, fillColor: Colors.white, border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none)),
          ),
          const SizedBox(height: 16),
          Align(alignment: Alignment.centerLeft, child: Text(query.isEmpty ? 'POPULAR SEARCHES' : 'RESULTS', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.1, color: Color(0xFF68736D)))),
          const SizedBox(height: 8),
          Expanded(child: results.isEmpty ? const Center(child: Text('No matching service. Try another search.')) : ListView.builder(
            itemCount: results.length,
            itemBuilder: (context, index) => ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const CircleAvatar(backgroundColor: Color(0xFFE3F2E9), child: Icon(Icons.search_rounded, color: Color(0xFF176B57))),
              title: Text(results[index]),
              trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14),
              onTap: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Search results from local partners will appear after backend catalogue setup.'), behavior: SnackBarBehavior.floating)),
            ),
          )),
        ]),
      ),
    );
  }
}