import 'package:flutter/material.dart';

class CustomerOrdersPage extends StatelessWidget {
  const CustomerOrdersPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Your orders')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  height: 88,
                  width: 88,
                  decoration: BoxDecoration(color: const Color(0xFFE1F2E9), borderRadius: BorderRadius.circular(28)),
                  child: const Icon(Icons.receipt_long_rounded, size: 42, color: Color(0xFF176B57)),
                ),
                const SizedBox(height: 20),
                const Text('Your orders will appear here', textAlign: TextAlign.center, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                const Text('Once ordering is connected to Alteo services, you can track food, shopping, rides and parcel activity from this page.', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF737B76), height: 1.5)),
                const SizedBox(height: 20),
                FilledButton.icon(onPressed: () => Navigator.of(context).popUntil((route) => route.isFirst), icon: const Icon(Icons.explore_rounded), label: const Text('Explore Alteo')),
              ],
            ),
          ),
        ),
      );
}