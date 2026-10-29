import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../auth/customer_auth_page.dart';
import '../orders/customer_orders_page.dart';
import 'package:geolocator/geolocator.dart';
import 'package:alteo_notifications/alteo_notifications.dart';
import '../../services/mapbox_service.dart';
import '../../services/customer_location_service.dart';
import '../../services/customer_preferences.dart';
import '../location/customer_location_picker_page.dart';

class CustomerCartPage extends StatefulWidget {
 const CustomerCartPage({super.key});
 @override State<CustomerCartPage> createState()=>_CustomerCartPageState();
}
class _CustomerCartPageState extends State<CustomerCartPage>{
 late Future<List<Map<String,dynamic>>> items;
 final Set<String> _updatingItems = <String>{};
 @override void initState(){super.initState();items=load();}
 Future<List<Map<String,dynamic>>> load()async{
  final client=Supabase.instance.client;
  final user=client.auth.currentUser;
  if(user==null)return [];
  final cart=await client.from('carts').select('id').eq('customer_id',user.id).eq('status','active').maybeSingle();
  if(cart==null)return [];
  final rows=await client.from('cart_items').select('id,quantity,product_id,seller_products(name,price_minor,image_url,seller_id,kind)').eq('cart_id',cart['id']).order('created_at');
  return (rows as List).map((e)=>Map<String,dynamic>.from(e as Map)).toList();
 }

 Future<void> _changeQuantity(Map<String, dynamic> row, int delta) async {
  final id = row['id']?.toString();
  if (id == null || _updatingItems.contains(id)) return;
  final current = (row['quantity'] as num?)?.toInt() ?? 1;
  final next = (current + delta).clamp(0, 99).toInt();
  if (next == current) return;
  setState(() => _updatingItems.add(id));
  try {
   if (next == 0) {
    await Supabase.instance.client.from('cart_items').delete().eq('id', id);
   } else {
    await Supabase.instance.client.from('cart_items').update({'quantity': next}).eq('id', id);
   }
   if (mounted) setState(() => items = load());
  } catch (_) {
   if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('We could not update that item. Please try again.')));
   if (mounted) setState(() => items = load());
  } finally {
   if (mounted) setState(() => _updatingItems.remove(id));
  }
 }

 Future<void> checkout() async {
  final userAtStart = Supabase.instance.client.auth.currentUser;
  final recipient = TextEditingController(text: userAtStart?.userMetadata?['full_name']?.toString() ?? '');
  final phone = TextEditingController(text: userAtStart?.phone ?? '');
  final addressLine = TextEditingController();
  final city = TextEditingController();
  final stateName = TextEditingController();
  final postalCode = TextEditingController();
  final label = TextEditingController(text: 'Home');
  bool saveAddress = false;
  bool locating = false;
  double? selectedLatitude;
  double? selectedLongitude;
  String selectedPaymentMethod = 'cod';
  List<Map<String, dynamic>> savedAddresses = [];
  Map<String, dynamic>? selectedAddress;
  Map<String, dynamic>? selectedLocation = alteoLocationSelection.value;
  try {
   // When checkout opens, use the latest GPS address if the customer has not
   // chosen a saved or manual address. No extra tap is required.
   try {
    await AlteoFirstLaunchPermissionGate.waitUntilComplete('customer').timeout(const Duration(seconds: 35));
   } catch (_) {}
   if (selectedLocation == null || selectedLocation['source'] == 'current') {
    final live = await CustomerLocationService.currentLocationIfPermitted();
    if (live != null) {
     selectedLocation = live;
     final display = (live['display_address']?.toString() ?? '').trim();
     final full = (live['formatted_address']?.toString() ?? '').trim();
     await setAlteoDeliveryLocation(display.isNotEmpty ? display : full, details: live, source: 'current');
    }
   }
   if (selectedLocation != null) {
    selectedLatitude = (selectedLocation['latitude'] as num?)?.toDouble();
    selectedLongitude = (selectedLocation['longitude'] as num?)?.toDouble();
    addressLine.text = [
     selectedLocation['address_line1'], selectedLocation['locality'],
    ].where((part) => part != null && part.toString().trim().isNotEmpty).join(', ');
    if (addressLine.text.trim().isEmpty) addressLine.text = selectedLocation['formatted_address']?.toString() ?? '';
    city.text = selectedLocation['city']?.toString() ?? '';
    stateName.text = selectedLocation['state']?.toString() ?? '';
    postalCode.text = selectedLocation['postal_code']?.toString() ?? '';
   }
   final userForAddresses = Supabase.instance.client.auth.currentUser;
   if (userForAddresses != null) {
    try {
     final rows = await Supabase.instance.client.from('addresses').select('id,label,recipient_name,phone,address_line1,locality,city,state,postal_code,latitude,longitude,is_default').eq('user_id', userForAddresses.id).order('is_default', ascending: false);
     savedAddresses = (rows as List).map((row) => Map<String, dynamic>.from(row as Map)).toList();
    } catch (_) { /* Manual entry remains available if saved addresses cannot load. */ }
   }
   if (selectedLocation?['source'] == 'saved' && selectedLocation?['id'] != null) {
    for (final address in savedAddresses) {
     if (address['id'].toString() == (selectedLocation?['id']?.toString() ?? '')) {
      selectedAddress = address;
      break;
     }
    }
   }
   final confirmed = await showDialog<bool>(context: context, builder: (dialogContext) => StatefulBuilder(builder: (dialogContext, setDialogState) => AlertDialog(
    title: const Text('Delivery details'),
    content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
     if (savedAddresses.isNotEmpty) DropdownButtonFormField<String>(
      value: selectedAddress?['id']?.toString(),
      decoration: const InputDecoration(labelText: 'Use a saved address'),
      items: savedAddresses.map((address) => DropdownMenuItem<String>(
       value: address['id'].toString(),
       child: Text('${address['label'] ?? 'Saved address'}', overflow: TextOverflow.ellipsis),
      )).toList(),
      onChanged: (id) async {
       final matches = savedAddresses.where((address) => address['id'].toString() == id).toList();
       if (matches.isEmpty) return;
       final match = matches.first;
       final full = [
        match['address_line1'], match['address_line2'], match['locality'],
        match['city'], match['state'], match['postal_code'], 'India',
       ].where((part) => part != null && part.toString().trim().isNotEmpty).join(', ');
       final display = [
        match['locality'], match['city'], match['postal_code'],
       ].where((part) => part != null && part.toString().trim().isNotEmpty).join(' · ');
       final selection = <String, dynamic>{
        ...match,
        'formatted_address': full,
        'display_address': display.isNotEmpty ? display : (match['label']?.toString() ?? 'Saved address'),
        'source': 'saved',
       };
       selectedLocation = selection;
       setDialogState(() {
        selectedAddress = match;
        selectedLatitude = (match['latitude'] as num?)?.toDouble();
        selectedLongitude = (match['longitude'] as num?)?.toDouble();
        recipient.text = (match['recipient_name'] ?? '').toString();
        phone.text = (match['phone'] ?? '').toString();
        addressLine.text = (match['address_line1'] ?? '').toString();
        city.text = (match['city'] ?? '').toString();
        stateName.text = (match['state'] ?? '').toString();
        postalCode.text = (match['postal_code'] ?? '').toString();
       });
       final showAddress = selection['display_address'].toString();
       await setAlteoDeliveryLocation(showAddress, details: selection, source: 'saved');
      },
     ),
     Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
       color: const Color(0xFFEAF4EE),
       borderRadius: BorderRadius.circular(15),
       border: Border.all(color: const Color(0xFFD1E5D8)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
       Row(children: [
        const Icon(Icons.location_on_rounded, color: Color(0xFF176B57)),
        const SizedBox(width: 8),
        const Expanded(child: Text('Delivery location', style: TextStyle(fontWeight: FontWeight.w900))),
        TextButton(
         onPressed: locating ? null : () async {
          setDialogState(() => locating = true);
          try {
           final result = await Navigator.of(dialogContext).push<Map<String, dynamic>>(MaterialPageRoute(
            builder: (_) => CustomerLocationPickerPage(
             initialLatitude: selectedLatitude,
             initialLongitude: selectedLongitude,
             initialAddress: selectedLocation?['formatted_address']?.toString(),
            ),
           ));
           if (result != null) {
            selectedLocation = result;
            selectedAddress = null;
            selectedLatitude = (result['latitude'] as num?)?.toDouble();
            selectedLongitude = (result['longitude'] as num?)?.toDouble();
            addressLine.text = [
             result['address_line1'], result['locality'],
            ].where((part) => part != null && part.toString().trim().isNotEmpty).join(', ');
            if (addressLine.text.trim().isEmpty) addressLine.text = result['formatted_address']?.toString() ?? '';
            city.text = result['city']?.toString() ?? '';
            stateName.text = result['state']?.toString() ?? '';
            postalCode.text = result['postal_code']?.toString() ?? '';
            final display = (result['display_address']?.toString() ?? '').trim();
            final full = (result['formatted_address']?.toString() ?? '').trim();
            await setAlteoDeliveryLocation(display.isNotEmpty ? display : full, details: result, source: 'manual');
            setDialogState(() {});
           }
          } catch (_) {
           if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('We could not open the location picker. Please try again.')));
          } finally {
           if (context.mounted) setDialogState(() => locating = false);
          }
         },
         child: Text(locating ? 'Opening…' : 'Change'),
        ),
       ]),
       Text(
        (selectedLocation?['formatted_address']?.toString().trim().isNotEmpty ?? false)
          ? (selectedLocation?['formatted_address']?.toString() ?? '')
          : selectedLatitude != null
            ? 'Your current map point is selected. Add house or street details below.'
            : 'Your detected location will be used when available. You can pin a different address.',
        style: const TextStyle(fontSize: 12, height: 1.4, color: Color(0xFF365D50)),
       ),
       Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
         onPressed: locating ? null : () async {
          setDialogState(() => locating = true);
          try {
           if (!await Geolocator.isLocationServiceEnabled()) {
            if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Turn on Location services and try again.')));
            return;
           }
           var permission = await Geolocator.checkPermission();
           if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
           if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
            if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Allow location access or choose the address on the map.')));
            return;
           }
           final result = await CustomerLocationService.currentLocationIfPermitted();
           if (result == null) {
            if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('We could not detect your address. Choose it on the map instead.')));
            return;
           }
           selectedLocation = result;
           selectedAddress = null;
           selectedLatitude = (result['latitude'] as num?)?.toDouble();
           selectedLongitude = (result['longitude'] as num?)?.toDouble();
           addressLine.text = [
            result['address_line1'], result['locality'],
           ].where((part) => part != null && part.toString().trim().isNotEmpty).join(', ');
           if (addressLine.text.trim().isEmpty) addressLine.text = result['formatted_address']?.toString() ?? '';
           city.text = result['city']?.toString() ?? '';
           stateName.text = result['state']?.toString() ?? '';
           postalCode.text = result['postal_code']?.toString() ?? '';
           final display = (result['display_address']?.toString() ?? '').trim();
           final full = (result['formatted_address']?.toString() ?? '').trim();
           await setAlteoDeliveryLocation(display.isNotEmpty ? display : full, details: result, source: 'current');
           setDialogState(() {});
          } catch (_) {
           if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('We could not detect your address. Please try again or choose it on the map.')));
          } finally {
           if (context.mounted) setDialogState(() => locating = false);
          }
         },
         icon: locating
           ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
           : const Icon(Icons.my_location_rounded, size: 18),
         label: Text(locating ? 'Detecting…' : 'Use current location'),
        ),
       ),
      ]),
     ),
     TextField(controller: recipient, decoration: const InputDecoration(labelText: 'Recipient name')),
     TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Phone number')),
     TextField(controller: addressLine, minLines: 1, maxLines: 2, onChanged: (_) { selectedAddress = null; selectedLatitude = null; selectedLongitude = null; }, decoration: const InputDecoration(labelText: 'House and street')),
     TextField(controller: city, onChanged: (_) { selectedAddress = null; selectedLatitude = null; selectedLongitude = null; }, decoration: const InputDecoration(labelText: 'City')),
     TextField(controller: stateName, onChanged: (_) { selectedAddress = null; selectedLatitude = null; selectedLongitude = null; }, decoration: const InputDecoration(labelText: 'State')),
     TextField(controller: postalCode, keyboardType: TextInputType.number, onChanged: (_) { selectedAddress = null; selectedLatitude = null; selectedLongitude = null; }, decoration: const InputDecoration(labelText: 'PIN code')),
     TextField(controller: label, decoration: const InputDecoration(labelText: 'Save address as (optional)')),
     CheckboxListTile(contentPadding: EdgeInsets.zero, value: saveAddress, onChanged: (value) => setDialogState(() => saveAddress = value ?? false), title: const Text('Save these details for next time')),
     const SizedBox(height: 12),
     const Align(alignment: Alignment.centerLeft, child: Text('Payment method', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900))),
     const SizedBox(height: 4),
     RadioListTile<String>(
      contentPadding: EdgeInsets.zero,
      value: 'cod',
      groupValue: selectedPaymentMethod,
      onChanged: (value) => setDialogState(() => selectedPaymentMethod = value ?? 'cod'),
      title: const Text('Cash on delivery'),
      subtitle: const Text('Pay in cash when your order arrives'),
      secondary: const Icon(Icons.payments_outlined, color: Color(0xFF176B57)),
     ),
     const Divider(height: 4),
     const ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(Icons.account_balance_rounded, color: Color(0xFF9AA39D)),
      title: Text('UPI', style: TextStyle(color: Color(0xFF7D8780))),
      subtitle: Text('Coming soon'),
      trailing: Icon(Icons.lock_outline_rounded, size: 18, color: Color(0xFF9AA39D)),
      dense: true,
     ),
     const ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(Icons.credit_card_rounded, color: Color(0xFF9AA39D)),
      title: Text('Cards, wallets and net banking', style: TextStyle(color: Color(0xFF7D8780))),
      subtitle: Text('Not available yet'),
      trailing: Icon(Icons.lock_outline_rounded, size: 18, color: Color(0xFF9AA39D)),
      dense: true,
     ),
    ])),
    actions: [
     TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
     FilledButton(onPressed: selectedPaymentMethod == 'cod' ? () => Navigator.pop(dialogContext, true) : null, child: const Text('Place order')),
    ],
   )));
   if (confirmed != true || !mounted) return;
   if (recipient.text.trim().length < 2 ||
       phone.text.trim().length < 8 ||
       addressLine.text.trim().length < 3 ||
       city.text.trim().length < 2 ||
       stateName.text.trim().length < 2 ||
       !RegExp(r'^[1-9][0-9]{5}$').hasMatch(postalCode.text.trim())) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter the recipient, phone, full address and a valid 6-digit PIN code.')));
    return;
   }

   if (selectedLatitude == null || selectedLongitude == null) {
    final addressQuery = [addressLine.text.trim(), city.text.trim(), stateName.text.trim(), postalCode.text.trim()]
      .where((part) => part.isNotEmpty).join(', ');
    final coordinates = await MapboxService.geocode(addressQuery);
    if (coordinates != null && coordinates.length >= 2) {
      selectedLongitude = coordinates[0];
      selectedLatitude = coordinates[1];
    }
   }
   final client = Supabase.instance.client;
   final user = client.auth.currentUser;
   if (user == null) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sign in is required to place an order. You can keep exploring without signing in.')));
    return;
   }
   try {
    final serviceability = await client.rpc(
      'get_public_serviceability',
      params: {'p_pincode': postalCode.text.trim()},
    ).timeout(const Duration(seconds: 12));
    if (serviceability is! Map || serviceability['serviceable'] != true) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Alteo is not delivering to this PIN code yet. Choose another address.')));
      return;
    }
   } catch (_) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('We could not verify delivery availability. Please try again.')));
    return;
   }
   if (saveAddress && selectedAddress == null) {
    try {
     await client.from('addresses').insert({
      'user_id': user.id,
      'label': label.text.trim().isEmpty ? 'Home' : label.text.trim(),
      'recipient_name': recipient.text.trim(),
      'phone': phone.text.trim(),
      'address_line1': addressLine.text.trim(),
      'city': city.text.trim(),
      'state': stateName.text.trim(),
      'postal_code': postalCode.text.trim(),
      'latitude': selectedLatitude,
      'longitude': selectedLongitude,
      'is_default': false,
     });
    } catch (e) {
     if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
       const SnackBar(content: Text('Address could not be saved. Your order was not submitted. Check your connection and try again.')),
      );
     }
     return;
    }
   }
   final cart = await client.from('carts').select('id').eq('customer_id', user.id).eq('status', 'active').maybeSingle();
   if (cart == null) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Your cart is empty.')));
    return;
   }
   final currentItems = await load();
   if (currentItems.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Your cart is empty.')));
    return;
   }
   final groups = <String, List<Map<String, dynamic>>>{};
   for (final row in currentItems) {
    final product = row['seller_products'] as Map? ?? {};
    final groupKey = (product['seller_id']?.toString() ?? '') + '|' + (product['kind']?.toString() ?? '');
    groups.putIfAbsent(groupKey, () => <Map<String, dynamic>>[]).add(row);
   }

   try {
    var createdCount = 0;
    var groupIndex = 0;
    for (final group in groups.values) {
     final payload = group.map((row) => <String, dynamic>{
      'product_id': row['product_id'],
      'quantity': row['quantity'],
     }).toList();
     await client.rpc('create_customer_order', params: {
      'p_items': payload,
      'p_delivery_address': {
       'recipient_name': recipient.text.trim(),
       'phone': phone.text.trim(),
       'address_line1': addressLine.text.trim(),
       'city': city.text.trim(),
       'state': stateName.text.trim(),
       'postal_code': postalCode.text.trim(),
       'latitude': selectedLatitude,
       'longitude': selectedLongitude,
       'area_code': postalCode.text.trim(),
      },
      'p_idempotency_key': 'cart-' + cart['id'].toString() + '-' + groupIndex.toString(),
      'p_payment_method': selectedPaymentMethod,
     });
     createdCount++;
     groupIndex++;
    }
    await client.from('carts').delete().eq('id', cart['id']);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(createdCount.toString() + (createdCount == 1 ? ' order placed with Cash on Delivery. Please pay when it arrives.' : ' orders placed with Cash on Delivery. Please pay when they arrive.'))));
    setState(() => items = load());
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const CustomerOrdersPage()));
   } catch (e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('We could not place the order. Check your delivery details and service availability, then try again. Orders already placed will not be duplicated.')));
   }
  } finally {
   recipient.dispose();
   phone.dispose();
   addressLine.dispose();
   city.dispose();
   stateName.dispose();
   postalCode.dispose();
   label.dispose();
  }
 }

 @override Widget build(BuildContext context){
  final signedIn=Supabase.instance.client.auth.currentUser!=null;
  return Scaffold(appBar:AppBar(title:const Text('Your cart'),actions:[IconButton(onPressed:()=>setState(()=>items=load()),icon:const Icon(Icons.refresh))]),body:!signedIn?Center(child:Padding(padding:const EdgeInsets.all(24),child:Column(mainAxisSize:MainAxisSize.min,children:[const Icon(Icons.shopping_cart_outlined,size:54,color:Color(0xFF176B57)),const SizedBox(height:12),const Text('Your cart is ready when you are',style:TextStyle(fontSize:19,fontWeight:FontWeight.w800),textAlign:TextAlign.center),const SizedBox(height:8),const Text('You can keep exploring Alteo without signing in. Sign in only when you want to save a cart or continue to checkout.',textAlign:TextAlign.center,style:TextStyle(height:1.45)),const SizedBox(height:14),FilledButton(onPressed:()=>Navigator.of(context).pop(),child:const Text('Continue exploring')),TextButton(onPressed:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>const CustomerAuthPage())).then((_)=>setState(()=>items=load())),child:const Text('Sign in when ready'))]))):FutureBuilder<List<Map<String,dynamic>>>(future:items,builder:(context,s){
   if(s.connectionState==ConnectionState.waiting)return const Center(child:CircularProgressIndicator());
   if(s.hasError)return const Center(child:Padding(padding:EdgeInsets.all(24),child:Text('Could not load your cart. Pull refresh to try again.')));
   final list=s.data??[];
   if(list.isEmpty)return const Center(child:Padding(padding:EdgeInsets.all(28),child:Column(mainAxisSize:MainAxisSize.min,children:[Icon(Icons.shopping_basket_outlined,size:56,color:Color(0xFF176B57)),SizedBox(height:14),Text('Your cart is empty',style:TextStyle(fontSize:20,fontWeight:FontWeight.w800)),SizedBox(height:6),Text('Add items from the home catalogue to see them here.',textAlign:TextAlign.center)])));
   var total=0;
   for(final row in list){final p=row['seller_products'] as Map?;total+=(((p?['price_minor'] as num?)?.toInt()??0)*(row['quantity'] as int? ??1));}
   return Column(children:[
    Expanded(child:ListView.separated(padding:const EdgeInsets.all(16),itemCount:list.length,separatorBuilder:(_,__)=>const SizedBox(height:8),itemBuilder:(context,i){
     final row=list[i],p=(row['seller_products'] as Map?)??{};
     final quantity = (row['quantity'] as num?)?.toInt() ?? 1;
     final unitPrice = (p['price_minor'] as num?)?.toInt() ?? 0;
     final lineTotal = unitPrice * quantity;
     final busy = _updatingItems.contains(row['id']?.toString());
     final imageUrl = p['image_url']?.toString() ?? '';
     return Card(
      elevation: 0,
      color: Colors.white,
      margin: const EdgeInsets.only(bottom: 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(17)),
      child: Padding(
       padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
       child: Row(children: [
        ClipRRect(
         borderRadius: BorderRadius.circular(10),
         child: SizedBox(width: 60, height: 60, child: imageUrl.startsWith('https://')
          ? Image.network(imageUrl, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const ColoredBox(color: Color(0xFFEAF2EC), child: Icon(Icons.shopping_bag_outlined)))
          : const ColoredBox(color: Color(0xFFEAF2EC), child: Icon(Icons.shopping_bag_outlined))),
        ),
        const SizedBox(width: 11),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
         Text((p['name'] as String?) ?? 'Item', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900)),
         const SizedBox(height: 4),
         Text('₹${(unitPrice / 100).toStringAsFixed(0)} each', style: const TextStyle(fontSize: 12, color: Color(0xFF68736D))),
         const SizedBox(height: 4),
         Text('Line total ₹${(lineTotal / 100).toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF176B57))),
        ])),
        const SizedBox(width: 6),
        Container(
         decoration: BoxDecoration(color: const Color(0xFFE2F4EA), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFB8DDCB))),
         child: Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(
           tooltip: 'Decrease quantity',
           visualDensity: VisualDensity.compact,
           constraints: const BoxConstraints.tightFor(width: 34, height: 38),
           onPressed: busy ? null : () => _changeQuantity(row, -1),
           icon: const Icon(Icons.remove_rounded, size: 18),
          ),
          SizedBox(width: 20, child: Center(child: busy ? const SizedBox(width: 13, height: 13, child: CircularProgressIndicator(strokeWidth: 2)) : Text('$quantity', style: const TextStyle(fontWeight: FontWeight.w900)))),
          IconButton(
           tooltip: 'Increase quantity',
           visualDensity: VisualDensity.compact,
           constraints: const BoxConstraints.tightFor(width: 34, height: 38),
           onPressed: busy ? null : () => _changeQuantity(row, 1),
           icon: const Icon(Icons.add_rounded, size: 18),
          ),
         ]),
        ),
       ]),
      ),
     );
    })),
    SafeArea(top:false,child:Padding(padding:const EdgeInsets.all(16),child:Column(children:[Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[const Text('Subtotal',style:TextStyle(fontSize:16,fontWeight:FontWeight.w800)),Text('₹${(total/100).toStringAsFixed(0)}',style:const TextStyle(fontSize:18,fontWeight:FontWeight.w900))]),const SizedBox(height:10),const Text('Cash on delivery is available now. UPI, cards, wallets and net banking are coming soon.',style:TextStyle(fontSize:12,color:Color(0xFF737B76))),const SizedBox(height:8),SizedBox(width:double.infinity,child:FilledButton(onPressed:checkout,child:const Text('Checkout · Cash on delivery')))])))
   ]);
  }));
 }
}