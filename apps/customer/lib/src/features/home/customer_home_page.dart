import 'dart:async';

import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:geolocator/geolocator.dart';
import 'package:alteo_notifications/alteo_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/customer_content_service.dart';
import '../../services/customer_preferences.dart';
import '../../services/customer_location_service.dart';
import '../location/customer_location_picker_page.dart';
import '../addresses/customer_addresses_page.dart';
import '../services/service_browse_page.dart';
import '../auth/customer_auth_page.dart';
import '../cart/customer_cart_page.dart';

class CustomerHomePage extends StatefulWidget {
 const CustomerHomePage({super.key, this.enableRealtimeBanners = true, this.enableBackendQueries = true});
 final bool enableRealtimeBanners;
 final bool enableBackendQueries;
 @override State<CustomerHomePage> createState()=>_CustomerHomePageState();
}
class _CustomerHomePageState extends State<CustomerHomePage> {
 CustomerContentService? content;
 late Future<List<CustomerBanner>> banners;
 late Future<List<CustomerProduct>> products;
 String kind='all';
 Map<String, int> cartQuantities = <String, int>{};
 int get cartItemCount => cartQuantities.values.fold<int>(0, (sum, quantity) => sum + quantity);
 final Set<String> busyCartProductIds = <String>{};
 final stt.SpeechToText speech = stt.SpeechToText();
 final ValueNotifier<String> _voiceTranscript = ValueNotifier<String>('');
 final PageController bannerController = PageController(viewportFraction: .96);
 int bannerIndex = 0;
 StreamSubscription<List<Map<String, dynamic>>>? bannerSubscription;
 StreamSubscription<List<Map<String, dynamic>>>? productSubscription;
 @override void initState(){super.initState();unawaited(_autoSelectCurrentLocation());if(widget.enableBackendQueries){content=CustomerContentService(Supabase.instance.client);refresh();unawaited(_reloadCartQuantities());}else{banners=Future.value(<CustomerBanner>[]);products=Future.value(<CustomerProduct>[]);}if(widget.enableRealtimeBanners && widget.enableBackendQueries){try{bannerSubscription=Supabase.instance.client.from('app_banners').stream(primaryKey:['id']).eq('active',true).order('priority').listen((rows){if(mounted)setState(()=>banners=Future.value(rows.map((row)=>CustomerBanner.fromMap(row)).toList()));},onError:(_){/* Keep the fallback banner visible if realtime is unavailable. */});productSubscription=Supabase.instance.client.from('seller_products').stream(primaryKey:['id']).eq('status','active').listen((_){if(mounted)setState(refresh);},onError:(_){/* Pull-to-refresh remains available if realtime is offline. */});}catch(_) {}}}
 @override void dispose(){bannerSubscription?.cancel();productSubscription?.cancel();bannerController.dispose();_voiceTranscript.dispose();speech.stop();super.dispose();}
 Future<void> _voiceSearch() async {
  if (!widget.enableBackendQueries) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Voice search is unavailable in preview mode.')));
    return;
  }
  if (speech.isListening) {
    await speech.stop();
    return;
  }
  try {
    final available = await speech.initialize(
      onError: (error) {
        _voiceTranscript.value = 'Speech recognition error: ${error.errorMsg}. Try again or type your search.';
      },
    ).timeout(const Duration(seconds: 12));
    if (!available) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Speech recognition is unavailable. Enable Google speech services or type your search.'),
          duration: Duration(seconds: 4),
        ));
      }
      return;
    }

    String? localeId;
    try {
      final locales = await speech.locales();
      final preferHindi = alteoPreferredLanguage.value.toLowerCase().contains('hindi') ||
          alteoPreferredLanguage.value.contains('हिन्दी');
      final preference = preferHindi ? <String>['hi_IN', 'hi-IN', 'hi'] : <String>['en_IN', 'en-IN', 'en_US', 'en-US'];
      for (final preferred in preference) {
        final match = locales.where((locale) =>
          locale.localeId.toLowerCase().replaceAll('-', '_') == preferred.toLowerCase().replaceAll('-', '_'));
        if (match.isNotEmpty) {
          localeId = match.first.localeId;
          break;
        }
      }
    } catch (_) {
      // Let Android choose the current system speech locale when locale listing is unavailable.
    }

    _voiceTranscript.value = '';
    final dialogFuture = showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.mic_rounded, color: Color(0xFF176B57), size: 32),
        title: const Text('Voice search'),
        content: ValueListenableBuilder<String>(
          valueListenable: _voiceTranscript,
          builder: (context, transcript, _) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Say the name of a product, grocery or food item.'),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF4EE),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  transcript.isEmpty ? 'Listening…' : transcript,
                  style: const TextStyle(fontWeight: FontWeight.w700, height: 1.4),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(null), child: const Text('Cancel')),
          ValueListenableBuilder<String>(
            valueListenable: _voiceTranscript,
            builder: (context, transcript, _) => FilledButton(
              onPressed: transcript.trim().isEmpty ? null : () => Navigator.of(dialogContext).pop(transcript.trim()),
              child: const Text('Search'),
            ),
          ),
        ],
      ),
    );

    try {
      await speech.listen(
        localeId: localeId,
        onResult: (result) {
          final words = result.recognizedWords.trim();
          if (words.isNotEmpty) _voiceTranscript.value = words;
        },
        listenFor: const Duration(seconds: 15),
        pauseFor: const Duration(seconds: 3),
        partialResults: true,
        cancelOnError: true,
        listenMode: stt.ListenMode.dictation,
      );
    } catch (e) {
      _voiceTranscript.value = 'Could not start the microphone. Check microphone permission and try again.';
    }

    final query = await dialogFuture;
    await speech.stop();
    if (!mounted || query == null || query.trim().isEmpty) return;
    await showSearch<String>(
      context: context,
      delegate: _ProductSearch(onAdd: addToCart, pincode: _selectedPincode),
      query: query.trim(),
    );
  } catch (e) {
    await speech.stop();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Voice search could not start. Please check microphone permission or use text search.'),
        duration: Duration(seconds: 4),
      ));
    }
  }
 }
 void refresh(){try{content=CustomerContentService(Supabase.instance.client);banners=content!.loadBanners();final pin=_selectedPincode;products=pin==null?Future.value(<CustomerProduct>[]):content!.loadProducts(kind:kind=='all'?null:kind,pincode:pin);}catch(_){banners=Future.error(StateError('Banner unavailable'));products=Future.value(<CustomerProduct>[]);}}
 @override Widget build(BuildContext context)=>ValueListenableBuilder<String>(valueListenable:alteoPreferredLanguage,builder:(context,language,_)=>SafeArea(child: Stack(children:[Positioned.fill(child: RefreshIndicator(onRefresh:()async{setState(refresh);await Future.wait([banners,products]);},child:CustomScrollView(physics:const AlwaysScrollableScrollPhysics(),slivers:[
  SliverToBoxAdapter(child:header()),
  SliverToBoxAdapter(child:bannerList()),
  SliverToBoxAdapter(child:Padding(padding:const EdgeInsets.fromLTRB(18,8,18,22),child:TextField(readOnly:true,onTap:()=>showSearch(context:context,delegate:_ProductSearch(onAdd:addToCart)),decoration:InputDecoration(hintText:alteoText('Search items, food and essentials'),prefixIcon:const Icon(Icons.search_rounded),suffixIcon:IconButton(tooltip:'Voice search',onPressed:_voiceSearch,icon:const Icon(Icons.mic_none_rounded)),filled:true,fillColor:Colors.white,border:OutlineInputBorder(borderRadius:BorderRadius.circular(17),borderSide:const BorderSide(color:Color(0xFFE5EAE5))))))),
  SliverToBoxAdapter(child:section(alteoText('Explore services'),alteoText('Shopping, food and everyday essentials'))),
  SliverToBoxAdapter(child:SizedBox(height:112,child:ListView(scrollDirection:Axis.horizontal,padding:const EdgeInsets.symmetric(horizontal:18),children:[
   service('Food',Icons.restaurant_rounded,const Color(0xFFFFE8D9),const Color(0xFFB94E18)),service('Quick',Icons.shopping_basket_rounded,const Color(0xFFE3F4D8),const Color(0xFF357A35)),service('Shop',Icons.shopping_bag_rounded,const Color(0xFFE5E9FF),const Color(0xFF4857B8)),service('Rides',Icons.directions_car_rounded,const Color(0xFFFFF0C7),const Color(0xFF8C6410)),service('Parcel',Icons.local_shipping_rounded,const Color(0xFFDDF3F1),const Color(0xFF187B73))
  ]))),
  SliverToBoxAdapter(child:section(alteoText('Discover items'),alteoText('Listed by Alteo marketplace partners'))),
  SliverToBoxAdapter(child:SizedBox(height:42,child:ListView(scrollDirection:Axis.horizontal,padding:const EdgeInsets.symmetric(horizontal:18),children:[filter('All','all'),filter('Groceries','quick'),filter('Food','food'),filter('Shopping','shopping')]))),
  SliverToBoxAdapter(child:FutureBuilder<List<CustomerProduct>>(future:products,builder:(context,s){
   if(s.connectionState==ConnectionState.waiting)return const Padding(padding:EdgeInsets.all(28),child:Center(child:CircularProgressIndicator()));
   if(s.hasError)return empty('Could not load items','Check your connection and pull down to refresh.');
   final items=s.data??[];
   if(items.isEmpty){final pin=_selectedPincode;final serviceable=alteoPublicServiceability.value?['serviceable']==true;return empty(pin==null?'Choose your delivery PIN code':!serviceable?'This PIN code is not serviceable yet':'Your marketplace is getting ready',pin==null?'Choose your location or enter a PIN code to explore local services.':!serviceable?'Try another PIN code to explore Alteo services near you.':'No products are currently listed for this area. Check back soon.');}
   return Padding(padding:const EdgeInsets.fromLTRB(18,10,18,24),child:GridView.builder(shrinkWrap:true,physics:const NeverScrollableScrollPhysics(),itemCount:items.length,gridDelegate:const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount:2,crossAxisSpacing:12,mainAxisSpacing:12,childAspectRatio:.68),itemBuilder:(context,i)=>productCard(items[i])));
  })),
  const SliverToBoxAdapter(child:SizedBox(height:76))
 ]))), if (cartItemCount > 0) Positioned(
   right: 12,
   bottom: 12,
   child: Material(
     color: const Color(0xFF064E3B),
     borderRadius: BorderRadius.circular(18),
     elevation: 7,
     child: InkWell(
       borderRadius: BorderRadius.circular(18),
       onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const CustomerCartPage())).then((_) => _reloadCartQuantities()),
       child: Padding(
         padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
         child: Row(mainAxisSize: MainAxisSize.min, children: [
           const Icon(Icons.shopping_bag_outlined, color: Colors.white, size: 20),
           const SizedBox(width: 8),
           Text('View cart · $cartItemCount', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
           const SizedBox(width: 8),
           const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 18),
         ]),
       ),
     ),
   ),
 )])));
 Future<void> _autoSelectCurrentLocation() async {
  if (!widget.enableBackendQueries) return;
  // Wait for the first-launch permission request. Do not prompt repeatedly if
  // the customer declines; preserve browsing and manual address search.
  try {
    await AlteoFirstLaunchPermissionGate.waitUntilComplete('customer').timeout(const Duration(seconds: 35));
  } catch (_) {}
  if (!mounted) return;
  final existing = alteoLocationSelection.value;
  if (existing != null && existing['source'] != 'current') return;
  final current = await CustomerLocationService.currentLocationIfPermitted();
  if (current == null || !mounted) return;
  final display = (current['display_address']?.toString() ?? '').trim();
  final location = display.isNotEmpty ? display : (current['formatted_address']?.toString() ?? '').trim();
  if (location.isEmpty) return;
  await setAlteoDeliveryLocation(location, details: current, source: 'current');
  await _refreshServiceabilityForPin(current['postal_code']?.toString());
 }


 String? get _selectedPincode {
  final pin = alteoPublicServiceability.value?['pincode']?.toString().trim() ?? '';
  return RegExp(r'^[1-9][0-9]{5}$').hasMatch(pin) ? pin : null;
 }

 Future<void> _refreshServiceabilityForPin(String? rawPin) async {
  final pin = (rawPin ?? '').trim();
  if (!RegExp(r'^[1-9][0-9]{5}$').hasMatch(pin)) {
   await setAlteoPublicServiceability(null);
   if (mounted) setState(refresh);
   return;
  }
  try {
   content ??= CustomerContentService(Supabase.instance.client);
   final result = await content!.getPublicServiceability(pin).timeout(const Duration(seconds: 12));
   await setAlteoPublicServiceability(result);
   if (mounted) setState(refresh);
  } catch (_) {
   if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('We could not check local availability. Please try again.')));
  }
 }

 Future<void> _enterPincode() async {
  final controller = TextEditingController(text: _selectedPincode ?? '');
  try {
   final pin = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
     title: const Text('Explore your area'),
     content: TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      maxLength: 6,
      decoration: const InputDecoration(labelText: '6-digit PIN code', hintText: 'Enter your delivery PIN code', prefixIcon: Icon(Icons.location_on_outlined)),
     ),
     actions: [
      TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
      FilledButton(onPressed: () => Navigator.pop(dialogContext, controller.text.trim()), child: const Text('Check area')),
     ],
    ),
   );
   if (!mounted || pin == null) return;
   if (!RegExp(r'^[1-9][0-9]{5}$').hasMatch(pin)) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a valid 6-digit PIN code.')));
    return;
   }
   content ??= CustomerContentService(Supabase.instance.client);
   final result = await content!.getPublicServiceability(pin).timeout(const Duration(seconds: 12));
   await setAlteoPublicServiceability(result);
   if (result['serviceable'] != true) {
    if (mounted) {
     setState(refresh);
     ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Alteo is not available in this PIN code yet. Try another PIN code.')));
    }
    return;
   }
   final locality = (result['locality']?.toString() ?? '').trim();
   final district = (result['district']?.toString() ?? '').trim();
   final stateName = (result['state']?.toString() ?? '').trim();
   final display = [locality, district, pin].where((part) => part.isNotEmpty).join(' · ');
   final full = [locality, district, stateName, pin, 'India'].where((part) => part.isNotEmpty).join(', ');
   final details = <String, dynamic>{
    ...result,
    'postal_code': pin,
    'formatted_address': full.isEmpty ? 'PIN code $pin' : full,
    'display_address': display.isEmpty ? 'PIN code $pin' : display,
   };
   await setAlteoDeliveryLocation(details['display_address'].toString(), details: details, source: 'pincode');
   if (mounted) {
    setState(refresh);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('You can explore services in this area without signing in.')));
   }
  } catch (_) {
   if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('We could not check that PIN code. Please try again.')));
  } finally {
   controller.dispose();
  }
 }

 Future<void> _chooseLocation() async {
  await showModalBottomSheet<void>(
   context: context, showDragHandle: true, isScrollControlled: true,
   builder: (sheetContext) => SafeArea(child: Padding(
    padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
     Align(alignment: Alignment.centerLeft, child: Text(alteoText('Choose delivery location'), style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900))),
     const SizedBox(height: 10),
     ValueListenableBuilder<Map<String, dynamic>?>(
      valueListenable: alteoLocationSelection,
      builder: (context, selection, _) => ListTile(
       leading: const Icon(Icons.my_location_rounded, color: Color(0xFF176B57)),
       title: Text(alteoText('Use current location')),
       subtitle: Text((selection?['source'] == 'current')
        ? (selection?['formatted_address']?.toString() ?? alteoText('Detect your location with GPS'))
        : alteoText('Detect your location with GPS')),
       onTap: () async { Navigator.pop(sheetContext); await _useCurrentLocation(); },
      ),
     ),
     ListTile(
      leading: const Icon(Icons.pin_drop_outlined, color: Color(0xFF176B57)),
      title: const Text('Enter PIN code'),
      subtitle: const Text('Check your area without signing in'),
      onTap: () async {
       Navigator.pop(sheetContext);
       await _enterPincode();
      },
     ),
     ListTile(
      leading: const Icon(Icons.map_outlined, color: Color(0xFF176B57)),
      title: const Text('Choose exact location'),
      subtitle: const Text('Search an address or tap the map to place the pin'),
      onTap: () async {
       Navigator.pop(sheetContext);
       final current = alteoLocationSelection.value;
       final result = await Navigator.of(context).push<Map<String, dynamic>>(MaterialPageRoute(
        builder: (_) => CustomerLocationPickerPage(
         initialLatitude: (current?['latitude'] as num?)?.toDouble(),
         initialLongitude: (current?['longitude'] as num?)?.toDouble(),
         initialAddress: current?['formatted_address']?.toString(),
        ),
       ));
       if (!mounted || result == null) return;
       final full = (result['formatted_address']?.toString() ?? '').trim();
       final display = (result['display_address']?.toString() ?? '').trim();
       await setAlteoDeliveryLocation(display.isNotEmpty ? display : (full.isNotEmpty ? full : 'Selected location'), details: result, source: 'manual');
       await _refreshServiceabilityForPin(result['postal_code']?.toString());
      },
     ),
     ListTile(
      leading: const Icon(Icons.bookmark_border_rounded, color: Color(0xFF176B57)),
      title: Text(alteoText('Choose saved address')),
      subtitle: Text(alteoText('Select from your saved delivery addresses')),
      onTap: () async {
       Navigator.pop(sheetContext);
       if (Supabase.instance.client.auth.currentUser == null) {
        await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const CustomerAuthPage()));
        if (!mounted || Supabase.instance.client.auth.currentUser == null) return;
       }
       final selectedAddress = await Navigator.of(context).push<Map<String, dynamic>>(MaterialPageRoute(builder: (_) => const CustomerAddressesPage(selectForDelivery: true)));
       if (!mounted || selectedAddress == null) return;
       final full = [
        selectedAddress['address_line1'], selectedAddress['address_line2'],
        selectedAddress['locality'], selectedAddress['city'], selectedAddress['state'],
        selectedAddress['postal_code'], 'India',
       ].where((part) => part != null && part.toString().trim().isNotEmpty).join(', ');
       final display = [
        selectedAddress['locality'], selectedAddress['city'], selectedAddress['postal_code'],
       ].where((part) => part != null && part.toString().trim().isNotEmpty).join(' · ');
       final details = <String, dynamic>{
        ...selectedAddress,
        'formatted_address': full,
        'display_address': display.isNotEmpty ? display : (selectedAddress['label']?.toString() ?? 'Saved address'),
       };
       await setAlteoDeliveryLocation(details['display_address'].toString(), details: details, source: 'saved');
       await _refreshServiceabilityForPin(selectedAddress['postal_code']?.toString());
      },
     ),
    ]),
   )),
  );
 }

 Future<void> _useCurrentLocation() async {
  try {
   if (!await Geolocator.isLocationServiceEnabled()) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Turn on Location services in your phone settings, then try again.')));
    return;
   }
   var permission = await Geolocator.checkPermission();
   if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
   if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Allow location access or select the exact location on the map.')));
    return;
   }
   if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Finding your delivery address…')));
   final result = await CustomerLocationService.currentLocationIfPermitted();
   if (result == null || !mounted) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('We could not determine your address. Search or select a location on the map.')));
    return;
   }
   final display = (result['display_address']?.toString() ?? '').trim();
   final full = (result['formatted_address']?.toString() ?? '').trim();
   await setAlteoDeliveryLocation(display.isNotEmpty ? display : (full.isNotEmpty ? full : 'Selected map location'), details: result, source: 'current');
   await _refreshServiceabilityForPin(result['postal_code']?.toString());
   if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Delivery address updated.')));
  } catch (_) {
   if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('We could not detect your address. Select it on the map or search manually.')));
  }
 }

Widget header() => Padding(
  padding: const EdgeInsets.fromLTRB(18, 8, 18, 14),
  child: Row(
    children: [
      Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(color: const Color(0xFF176B57), borderRadius: BorderRadius.circular(15)),
        child: const Stack(
          alignment: Alignment.center,
          children: [
            Text('A', style: TextStyle(fontSize: 31, fontWeight: FontWeight.w900, color: Colors.white)),
            Positioned(right: 10, top: 9, child: CircleAvatar(radius: 3.5, backgroundColor: Color(0xFFFFA21A))),
          ],
        ),
      ),
      const SizedBox(width: 11),
      Expanded(
        child: InkWell(
          onTap: _chooseLocation,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: ValueListenableBuilder<String>(
              valueListenable: alteoDeliveryLocation,
              builder: (context, location, _) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(alteoText('DELIVERING TO'), style: const TextStyle(fontSize: 10, letterSpacing: 1.2, fontWeight: FontWeight.w800, color: Color(0xFF737B76))),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Expanded(child: Text(location, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800))),
                      const Icon(Icons.keyboard_arrow_down_rounded, size: 20),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      IconButton(
        tooltip: cartItemCount == 0 ? 'Cart' : 'Cart · $cartItemCount item(s)',
        onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const CustomerCartPage())).then((_) => _reloadCartQuantities()),
        icon: Badge(
          isLabelVisible: cartItemCount > 0,
          label: Text(cartItemCount > 99 ? '99+' : '$cartItemCount'),
          child: const Icon(Icons.shopping_cart_outlined, size: 24),
        ),
      ),
      IconButton(
        tooltip: 'Notifications',
        onPressed: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Notifications will appear here when enabled.'))),
        icon: const Icon(Icons.notifications_none_rounded, size: 27),
      ),
    ],
  ),
);

 Widget bannerList() => FutureBuilder<List<CustomerBanner>>(
  future: banners,
  builder: (context, snapshot) {
    if (snapshot.connectionState == ConnectionState.waiting) {
      return const SizedBox(height: 185, child: Center(child: CircularProgressIndicator()));
    }
    final items = snapshot.data ?? [];
    if (items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(18, 2, 18, 12),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(23),
          child: Container(
            height: 190,
            decoration: const BoxDecoration(
              gradient: LinearGradient(colors: [Color(0xFF155C4B), Color(0xFF49A27D)]),
            ),
            child: const Padding(
              padding: EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('EVERYDAY, MADE EASIER', style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
                  SizedBox(height: 8),
                  Text('Discover more with Alteo', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900)),
                  SizedBox(height: 5),
                  Text('New offers and services are coming soon.', style: TextStyle(color: Colors.white, height: 1.4)),
                ],
              ),
            ),
          ),
        ),
      );
    }
    return Column(children: [
      SizedBox(
        height: 205,
        child: PageView.builder(
          itemCount: items.length,
          controller: bannerController,
          onPageChanged: (index) => setState(() => bannerIndex = index),
          itemBuilder: (context, index) {
            final banner = items[index];
            return Padding(
              padding: const EdgeInsets.fromLTRB(6, 0, 6, 14),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(23),
                  onTap: () => _openBanner(banner),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(23),
                    child: Stack(fit: StackFit.expand, children: [
                      if (banner.imageUrl.isNotEmpty)
                        Image.network(banner.imageUrl, fit: BoxFit.cover, errorBuilder: (_, __, ___) => gradient())
                      else
                        gradient(),
                      Container(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                            colors: [Color(0xE815382E), Color(0x2038584A)],
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(20),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: SizedBox(
                            width: 245,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(banner.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 24, height: 1.05, fontWeight: FontWeight.w900, color: Colors.white)),
                                if (banner.subtitle.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Text(banner.subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, height: 1.35, fontSize: 12)),
                                ],
                                const SizedBox(height: 10),
                                const Text('EXPLORE ALTEO  ›', style: TextStyle(color: Colors.white, letterSpacing: 1, fontWeight: FontWeight.w800, fontSize: 10)),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ]),
                  ),
                ),
              ),
            );
          },
        ),
      ),
      if (items.length > 1)
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(items.length, (index) => AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: index == bannerIndex ? 18 : 6,
              height: 6,
              decoration: BoxDecoration(
                color: index == bannerIndex ? const Color(0xFF176B57) : const Color(0xFFD3DCD5),
                borderRadius: BorderRadius.circular(10),
              ),
            )),
          ),
        ),
    ]);
  },
);
 Future<void> _openBanner(CustomerBanner b) async {
  if(b.actionType=='service' && b.actionValue.isNotEmpty){await Navigator.of(context).push(MaterialPageRoute<void>(builder:(_)=>ServiceBrowsePage(service:b.actionValue)));return;}
  if(b.actionType=='url' && b.actionValue.isNotEmpty){final uri=Uri.tryParse(b.actionValue);if(uri!=null && uri.scheme=='https' && await canLaunchUrl(uri)){await launchUrl(uri,mode:LaunchMode.externalApplication);}else if(mounted){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('This banner link is invalid or unavailable.')));}return;}
  if(b.actionType=='offer'){ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(b.subtitle.isEmpty?b.title:b.subtitle)));}
 }
 Widget gradient()=>Container(decoration:const BoxDecoration(gradient:LinearGradient(colors:[Color(0xFF155C4B),Color(0xFF49A27D)],begin:Alignment.topLeft,end:Alignment.bottomRight)),child:const Align(alignment:Alignment.centerRight,child:Padding(padding:EdgeInsets.only(right:20),child:Icon(Icons.shopping_basket_rounded,size:88,color:Color(0x44FFFFFF)))));
 Widget section(String a,String b)=>Padding(padding:const EdgeInsets.fromLTRB(18,16,18,10),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(a,style:const TextStyle(fontSize:19,fontWeight:FontWeight.w900,letterSpacing:-.3)),const SizedBox(height:3),Text(b,style:const TextStyle(fontSize:12,color:Color(0xFF748078)))]));
 Widget service(String n,IconData icon,Color bg,Color fg)=>Padding(padding:const EdgeInsets.only(right:12),child:InkWell(onTap:(){if(_selectedPincode==null || alteoPublicServiceability.value?['serviceable']!=true){_chooseLocation();return;}Navigator.of(context).push(MaterialPageRoute<void>(builder:(_)=>ServiceBrowsePage(service:n)));},borderRadius:BorderRadius.circular(18),child:SizedBox(width:82,child:Column(children:[Container(width:70,height:70,decoration:BoxDecoration(color:bg,borderRadius:BorderRadius.circular(21)),child:Icon(icon,color:fg,size:29)),const SizedBox(height:8),Text(alteoText(n),style:const TextStyle(fontWeight:FontWeight.w800,fontSize:12))]))));
 Widget filter(String label,String value)=>Padding(padding:const EdgeInsets.only(right:8),child:ChoiceChip(label:Text(alteoText(label)),selected:kind==value,onSelected:(_)=>setState(() {kind=value;final pin=_selectedPincode;products=pin==null?Future.value(<CustomerProduct>[]):content!.loadProducts(kind:kind=='all'?null:kind,pincode:pin);})));
 Widget empty(String title,String detail)=>Padding(padding:const EdgeInsets.fromLTRB(24,30,24,40),child:Column(children:[const Icon(Icons.storefront_outlined,size:44,color:Color(0xFF176B57)),const SizedBox(height:10),Text(title,textAlign:TextAlign.center,style:const TextStyle(fontWeight:FontWeight.w800,fontSize:15)),const SizedBox(height:6),Text(detail,textAlign:TextAlign.center,style:const TextStyle(color:Color(0xFF748078),height:1.4,fontSize:12))]));
 Future<void> _reloadCartQuantities() async {
  final client = Supabase.instance.client;
  if (client.auth.currentUser == null || content == null) {
    if (mounted) setState(() => cartQuantities = <String, int>{});
    return;
  }
  try {
    final quantities = await content!.loadCartQuantities().timeout(const Duration(seconds: 12));
    if (mounted) setState(() => cartQuantities = quantities);
  } catch (_) {
    // A cart read failure should not prevent catalogue browsing.
  }
}

Future<void> addToCart(CustomerProduct p) async {
  if (Supabase.instance.client.auth.currentUser == null) {
    await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const CustomerAuthPage()));
    if (!mounted || Supabase.instance.client.auth.currentUser == null) return;
    await _reloadCartQuantities();
  }
  await _changeQuantity(p, 1);
}

Future<void> _changeQuantity(CustomerProduct p, int delta) async {
  if (busyCartProductIds.contains(p.id)) return;
  if (Supabase.instance.client.auth.currentUser == null) {
    await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const CustomerAuthPage()));
    if (!mounted || Supabase.instance.client.auth.currentUser == null) return;
    await _reloadCartQuantities();
  }
  final previous = cartQuantities[p.id] ?? 0;
  final next = (previous + delta).clamp(0, 99).toInt();
  if (!mounted || next == previous) return;
  // Optimistic UI: the cart badge and floating cart chip react immediately.
  setState(() {
    busyCartProductIds.add(p.id);
    if (next == 0) {
      cartQuantities.remove(p.id);
    } else {
      cartQuantities[p.id] = next;
    }
  });
  try {
    await content!.setCartQuantity(p.id, next);
  } catch (_) {
    if (mounted) {
      setState(() {
        if (previous == 0) {
          cartQuantities.remove(p.id);
        } else {
          cartQuantities[p.id] = previous;
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not update your cart. Please try again.')));
    }
  } finally {
    if (mounted) setState(() => busyCartProductIds.remove(p.id));
  }
}

Widget productCard(CustomerProduct p) {
  final quantity = cartQuantities[p.id] ?? 0;
  final busy = busyCartProductIds.contains(p.id);
  return Container(
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: const Color(0xFFE7EBE7))),
    child: Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => _openProductDetails(p),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(17)),
              child: SizedBox(
                width: double.infinity,
                child: p.imageUrl.isEmpty
                  ? Container(color: const Color(0xFFEAF2EC), child: const Icon(Icons.shopping_bag_outlined, size: 48, color: Color(0xFF176B57)))
                  : Image.network(p.imageUrl, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(color: const Color(0xFFEAF2EC), child: const Icon(Icons.shopping_bag_outlined, size: 48, color: Color(0xFF176B57)))),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(11, 10, 11, 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(p.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, height: 1.25)),
              const SizedBox(height: 5),
              Text(p.priceLabel, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: Color(0xFF176B57))),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: quantity == 0
                  ? IconButton.filledTonal(
                      tooltip: 'Add one to cart',
                      onPressed: busy ? null : () => _changeQuantity(p, 1),
                      icon: busy ? const SizedBox(width: 17, height: 17, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.add_rounded),
                      style: IconButton.styleFrom(backgroundColor: const Color(0xFFD8F1E5), foregroundColor: const Color(0xFF176B57)),
                    )
                  : Container(
                      decoration: BoxDecoration(color: const Color(0xFFE2F4EA), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFB8DDCB))),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        IconButton(
                          tooltip: 'Remove one',
                          visualDensity: VisualDensity.compact,
                          onPressed: busy ? null : () => _changeQuantity(p, -1),
                          icon: const Icon(Icons.remove_rounded),
                        ),
                        SizedBox(width: 22, child: Center(child: Text('$quantity', style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF176B57))))),
                        IconButton(
                          tooltip: 'Add one',
                          visualDensity: VisualDensity.compact,
                          onPressed: busy ? null : () => _changeQuantity(p, 1),
                          icon: const Icon(Icons.add_rounded),
                        ),
                      ]),
                    ),
              ),
            ]),
          ),
        ]),
      ),
    ),
  );
}
 Future<void> _openProductDetails(CustomerProduct p) async {
  await Navigator.of(context).push<void>(MaterialPageRoute(builder:(_)=>CustomerProductDetailsPage(product:p,onAddToCart:()=>addToCart(p))));
 }

}
class _ProductSearch extends SearchDelegate<String>{
 _ProductSearch({required this.onAdd, this.pincode});
 final Future<void> Function(CustomerProduct) onAdd;
 final String? pincode;
 @override List<Widget>? buildActions(BuildContext context)=>[IconButton(onPressed:()=>query='',icon:const Icon(Icons.clear))];
 @override Widget? buildLeading(BuildContext context)=>IconButton(onPressed:()=>close(context,''),icon:const Icon(Icons.arrow_back));
 @override Widget buildResults(BuildContext context)=>_results(context);
 @override Widget buildSuggestions(BuildContext context)=>query.trim().isEmpty?const Center(child:Text('Search products, groceries and essentials')):_results(context);
 Widget _results(BuildContext context){
  if(query.trim().isEmpty)return const Center(child:Text('Type or say an item name to search.'));
  return FutureBuilder<List<Map<String,dynamic>>>(
   future:CustomerContentService(Supabase.instance.client).searchProducts(query:query.trim(),pincode:pincode).then((products)=>products.map((item)=><String,dynamic>{'id':item.id,'name':item.name,'description':item.description,'price_minor':item.priceMinor,'image_url':item.imageUrl,'kind':item.kind}).toList()),
   builder:(context,s){
    if(s.connectionState==ConnectionState.waiting)return const Center(child:CircularProgressIndicator());
    if(s.hasError)return const Center(child:Padding(padding:EdgeInsets.all(24),child:Text('Search is temporarily unavailable. Pull down on Home to retry.',textAlign:TextAlign.center)));
    final rows=s.data??[];
    if(rows.isEmpty)return Center(child:Padding(padding:const EdgeInsets.all(24),child:Text(pincode==null?'Choose a serviceable PIN code from Home to see local items.':'No matching items are listed in this area yet.',textAlign:TextAlign.center)));
    return ListView.separated(padding:const EdgeInsets.all(14),itemCount:rows.length,separatorBuilder:(_,__)=>const Divider(),itemBuilder:(context,i){
     final p=CustomerProduct.fromMap(rows[i]);
     return ListTile(
      leading:ClipRRect(borderRadius:BorderRadius.circular(10),child:SizedBox(width:54,height:54,child:p.imageUrl.isEmpty?const ColoredBox(color:Color(0xFFEAF2EC),child:Icon(Icons.shopping_bag_outlined)):Image.network(p.imageUrl,fit:BoxFit.cover,errorBuilder:(_,__,___)=>const ColoredBox(color:Color(0xFFEAF2EC),child:Icon(Icons.shopping_bag_outlined))))),
      title:Text(p.name,style:const TextStyle(fontWeight:FontWeight.w800)),
      subtitle:Text(p.priceLabel),
      trailing:IconButton(tooltip:'Add to cart',onPressed:()=>onAdd(p),icon:const Icon(Icons.add_shopping_cart_rounded)),
      onTap:()=>Navigator.of(context).push<void>(MaterialPageRoute(builder:(_)=>CustomerProductDetailsPage(product:p,onAddToCart:()=>onAdd(p)))),
     );
    });
   },
  );
 }
}
class CustomerProductDetailsPage extends StatelessWidget {
 const CustomerProductDetailsPage({super.key,required this.product,required this.onAddToCart});
 final CustomerProduct product;
 final Future<void> Function() onAddToCart;

 @override
 Widget build(BuildContext context)=>Scaffold(
  appBar:AppBar(title:const Text('Item details')),
  body:SafeArea(child:ListView(padding:const EdgeInsets.fromLTRB(18,8,18,28),children:[
   ClipRRect(borderRadius:BorderRadius.circular(22),child:AspectRatio(aspectRatio:1.05,child:product.imageUrl.isEmpty
    ?Container(color:const Color(0xFFEAF2EC),child:const Icon(Icons.shopping_bag_outlined,size:84,color:Color(0xFF176B57)))
    :Image.network(product.imageUrl,fit:BoxFit.cover,errorBuilder:(_,__,___)=>Container(color:const Color(0xFFEAF2EC),child:const Icon(Icons.shopping_bag_outlined,size:84,color:Color(0xFF176B57)))))),
   const SizedBox(height:20),
   Text(product.name,style:Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight:FontWeight.w900)),
   const SizedBox(height:8),
   Text(product.priceLabel,style:const TextStyle(fontSize:25,fontWeight:FontWeight.w900,color:Color(0xFF176B57))),
   const SizedBox(height:18),
   const Text('Description',style:TextStyle(fontSize:18,fontWeight:FontWeight.w800)),
   const SizedBox(height:7),
   Text(product.description.trim().isEmpty?'No description has been added for this item yet.':product.description,style:const TextStyle(fontSize:15,height:1.55,color:Color(0xFF59635D))),
   const SizedBox(height:16),
   Container(padding:const EdgeInsets.all(14),decoration:BoxDecoration(color:const Color(0xFFEAF4EE),borderRadius:BorderRadius.circular(14)),child:Row(children:[
    const Icon(Icons.local_shipping_outlined,color:Color(0xFF176B57)),
    const SizedBox(width:10),
    Expanded(child:Text('Delivery availability and final fulfilment details are confirmed for your location at checkout.',style:const TextStyle(height:1.4,color:Color(0xFF285E4E))))
   ])),
   const SizedBox(height:22),
   FilledButton.icon(onPressed:()=>onAddToCart(),icon:const Icon(Icons.add_shopping_cart_rounded),label:const Text('Add to cart'),style:FilledButton.styleFrom(minimumSize:const Size.fromHeight(52))),
  ])),
 );
}
