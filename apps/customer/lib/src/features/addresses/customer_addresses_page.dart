import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/mapbox_service.dart';

class CustomerAddressesPage extends StatefulWidget {
  const CustomerAddressesPage({super.key, this.selectForDelivery = false});
  final bool selectForDelivery;
  @override
  State<CustomerAddressesPage> createState() => _CustomerAddressesPageState();
}

class _CustomerAddressesPageState extends State<CustomerAddressesPage> {
  final client = Supabase.instance.client;
  late Future<List<Map<String, dynamic>>> addresses = _load();
  bool saving = false;

  Future<List<Map<String, dynamic>>> _load() async {
    final user = client.auth.currentUser;
    if (user == null) return [];
    final rows = await client.from('addresses')
      .select('id,label,recipient_name,phone,address_line1,address_line2,locality,city,state,postal_code,latitude,longitude,is_default')
      .eq('user_id', user.id).order('is_default', ascending: false).order('created_at', ascending: false);
    return (rows as List).map((row) => Map<String, dynamic>.from(row as Map)).toList();
  }

  Future<void> _refresh() async {
    setState(() => addresses = _load());
    await addresses;
  }

  Future<void> _addAddress() async {
    final formKey = GlobalKey<FormState>();
    final label = TextEditingController(text: 'Home');
    final recipient = TextEditingController(text: client.auth.currentUser?.userMetadata?['full_name']?.toString() ?? '');
    final phone = TextEditingController();
    final line = TextEditingController();
    final locality = TextEditingController();
    final city = TextEditingController();
    final state = TextEditingController();
    final pin = TextEditingController();
    bool makeDefault = false;
    try {
      final result = await showModalBottomSheet<bool>(
        context: context, isScrollControlled: true, showDragHandle: true,
        builder: (sheetContext) => StatefulBuilder(builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(20, 8, 20, MediaQuery.of(context).viewInsets.bottom + 24),
          child: Form(key: formKey, child: SingleChildScrollView(child: Column(
            mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Add delivery address', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
              const SizedBox(height: 14),
              TextFormField(controller: label, decoration: const InputDecoration(labelText: 'Label (Home, Work)'), validator: (v) => (v?.trim().isEmpty ?? true) ? 'Add a label' : null),
              TextFormField(controller: recipient, decoration: const InputDecoration(labelText: 'Recipient name'), validator: (v) => (v?.trim().length ?? 0) < 2 ? 'Enter recipient name' : null),
              TextFormField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Phone number'), validator: (v) => (v?.trim().length ?? 0) < 8 ? 'Enter a valid phone number' : null),
              TextFormField(controller: line, decoration: const InputDecoration(labelText: 'House and street'), validator: (v) => (v?.trim().length ?? 0) < 3 ? 'Enter house and street' : null),
              TextFormField(controller: locality, decoration: const InputDecoration(labelText: 'Area / locality (optional)')),
              TextFormField(controller: city, decoration: const InputDecoration(labelText: 'City'), validator: (v) => (v?.trim().length ?? 0) < 2 ? 'Enter city' : null),
              TextFormField(controller: state, decoration: const InputDecoration(labelText: 'State'), validator: (v) => (v?.trim().length ?? 0) < 2 ? 'Enter state' : null),
              TextFormField(controller: pin, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'PIN code'), validator: (v) => (v?.trim().length ?? 0) < 5 ? 'Enter a valid PIN code' : null),
              CheckboxListTile(value: makeDefault, contentPadding: EdgeInsets.zero, title: const Text('Set as default address'), onChanged: (v) => setSheetState(() => makeDefault = v ?? false)),
              const SizedBox(height: 8),
              SizedBox(width: double.infinity, child: FilledButton(
                onPressed: saving ? null : () async {
                  if (!(formKey.currentState?.validate() ?? false)) return;
                  Navigator.of(sheetContext).pop(true);
                },
                child: const Text('Save address'),
              )),
            ],
          ))),
        )),
      );
      if (result != true || !mounted) return;
      setState(() => saving = true);
      final user = client.auth.currentUser;
      if (user == null) throw StateError('Sign in is required to save an address.');
      final fullAddress = [line.text.trim(), locality.text.trim(), city.text.trim(), state.text.trim(), pin.text.trim(), 'India'].where((part) => part.isNotEmpty).join(', ');
      final coordinates = await MapboxService.geocode(fullAddress);
      if (makeDefault) {
        await client.from('addresses').update({'is_default': false}).eq('user_id', user.id);
      }
      await client.from('addresses').insert({
        'user_id': user.id,
        'label': label.text.trim(),
        'recipient_name': recipient.text.trim(),
        'phone': phone.text.trim(),
        'address_line1': line.text.trim(),
        'locality': locality.text.trim().isEmpty ? null : locality.text.trim(),
        'city': city.text.trim(),
        'state': state.text.trim(),
        'postal_code': pin.text.trim(),
        'latitude': coordinates == null ? null : coordinates[1],
        'longitude': coordinates == null ? null : coordinates[0],
        'is_default': makeDefault,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Address saved.')));
        await _refresh();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not save address: ${e.toString()}')));
    } finally {
      saving = false;
      label.dispose(); recipient.dispose(); phone.dispose(); line.dispose();
      locality.dispose(); city.dispose(); state.dispose(); pin.dispose();
      if (mounted) setState(() {});
    }
  }

  Future<void> _setDefault(Map<String, dynamic> address) async {
    final user = client.auth.currentUser;
    if (user == null) return;
    try {
      await client.from('addresses').update({'is_default': false}).eq('user_id', user.id);
      await client.from('addresses').update({'is_default': true}).eq('id', address['id']).eq('user_id', user.id);
      await _refresh();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not update default address: ${e.toString()}')));
    }
  }

  Future<void> _delete(Map<String, dynamic> address) async {
    final ok = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: const Text('Delete address?'),
      content: Text('Remove ${address['label'] ?? 'this address'} from your saved addresses?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
      ],
    ));
    if (ok != true) return;
    try {
      await client.from('addresses').delete().eq('id', address['id']).eq('user_id', client.auth.currentUser!.id);
      await _refresh();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not delete address: ${e.toString()}')));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Saved addresses')),
    floatingActionButton: FloatingActionButton.extended(onPressed: saving ? null : _addAddress, icon: const Icon(Icons.add_location_alt_outlined), label: const Text('Add address')),
    body: FutureBuilder<List<Map<String, dynamic>>>(
      future: addresses,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        if (snapshot.hasError) return Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Could not load saved addresses. Check your connection and try again.', textAlign: TextAlign.center),
          const SizedBox(height: 12), FilledButton(onPressed: _refresh, child: const Text('Retry')),
        ])));
        final rows = snapshot.data ?? [];
        if (rows.isEmpty) return const Center(child: Padding(padding: EdgeInsets.all(32), child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.location_on_outlined, size: 56, color: Color(0xFF176B57)),
          SizedBox(height: 12), Text('No saved addresses yet', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
          SizedBox(height: 6), Text('Add your home or work address to make checkout quicker.', textAlign: TextAlign.center),
        ])));
        return RefreshIndicator(onRefresh: _refresh, child: ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 96), itemCount: rows.length,
          itemBuilder: (context, index) {
            final row = rows[index];
            final parts = [row['address_line1'], row['locality'], row['city'], row['state'], row['postal_code']].where((v) => v != null && v.toString().trim().isNotEmpty).join(', ');
            final isDefault = row['is_default'] == true;
            return Card(elevation: 0, margin: const EdgeInsets.only(bottom: 10), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: BorderSide(color: isDefault ? const Color(0xFF176B57) : Theme.of(context).dividerColor.withOpacity(.35))),
              child: ListTile(
                contentPadding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
                leading: CircleAvatar(backgroundColor: const Color(0xFFE1F2E9), child: Icon(row['label'] == 'Work' ? Icons.work_outline : Icons.home_outlined, color: const Color(0xFF176B57))),
                title: Row(children: [Expanded(child: Text((row['label'] ?? 'Address').toString(), style: const TextStyle(fontWeight: FontWeight.w800))), if (isDefault) const Chip(label: Text('Default'), visualDensity: VisualDensity.compact)]),
                subtitle: Text('${row['recipient_name']} • ${row['phone']}\n$parts', maxLines: 4, overflow: TextOverflow.ellipsis),
                isThreeLine: true,
                onTap: widget.selectForDelivery ? () => Navigator.of(context).pop<Map<String, dynamic>>(row) : null,
                trailing: PopupMenuButton<String>(onSelected: (v) { if (v == 'default') _setDefault(row); if (v == 'delete') _delete(row); }, itemBuilder: (_) => [
                  if (!isDefault) const PopupMenuItem(value: 'default', child: Text('Set as default')),
                  const PopupMenuItem(value: 'delete', child: Text('Delete')),
                ]),
              ),
            );
          },
        ));
      },
    ),
  );
}
