import 'dart:async';

import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/customer_content_service.dart';
import '../services/service_browse_page.dart';
import '../auth/customer_auth_page.dart';
import '../cart/customer_cart_page.dart';

class CustomerHomePage extends StatefulWidget {
 const CustomerHomePage({super.key, this.enableRealtimeBanners = true});
 final bool enableRealtimeBanners;
 @override State<CustomerHomePage> createState()=>_CustomerHomePageState();
}
class _CustomerHomePageState extends State<CustomerHomePage> {
 CustomerContentService? content;
 late Future<List<CustomerBanner>> banners;
 late Future<List<CustomerProduct>> products;
 String kind='all';
 final stt.SpeechToText speech = stt.SpeechToText();
 final PageController bannerController = PageController(viewportFraction: .91);
 int bannerIndex = 0;
 StreamSubscription<List<Map<String, dynamic>>>? bannerSubscription;
 @override void initState(){super.initState();content=CustomerContentService(Supabase.instance.client);refresh();if(widget.enableRealtimeBanners){try{bannerSubscription=Supabase.instance.client.from('app_banners').stream(primaryKey:['id']).eq('active',true).order('priority').listen((rows){if(mounted)setState(()=>banners=Future.value(rows.map((row)=>CustomerBanner.fromMap(row)).toList()));},onError:(_){/* Keep the fallback banner visible if realtime is unavailable. */});}catch(_) {}}}
 @override void dispose(){bannerSubscription?.cancel();bannerController.dispose();speech.stop();super.dispose();}
 Future<void> _voiceSearch() async {
  try {
   final available = await speech.initialize(onError: (_) { if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Voice search is not available on this device.'))); });
   if(!available){if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enable speech recognition on your device to use voice search.')));return;}
   await speech.listen(onResult:(result){if(result.finalResult && result.recognizedWords.trim().isNotEmpty && mounted){speech.stop();showSearch(context:context,delegate:_ProductSearch(onAdd:addToCart),query:result.recognizedWords.trim());}});
   if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Listening… say the name of an item or product.')));
  } catch (_) {if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not start voice search. You can still type your search.')));}
 }
 void refresh(){try{content=CustomerContentService(Supabase.instance.client);banners=content!.loadBanners();products=content!.loadProducts(kind:kind=='all'?null:kind);}catch(e){banners=Future.error(e);products=Future.error(e);}}
 @override Widget build(BuildContext context)=>RefreshIndicator(onRefresh:()async{setState(refresh);await Future.wait([banners,products]);},child:CustomScrollView(physics:const AlwaysScrollableScrollPhysics(),slivers:[
  SliverToBoxAdapter(child:header()),
  SliverToBoxAdapter(child:bannerList()),
  SliverToBoxAdapter(child:Padding(padding:const EdgeInsets.fromLTRB(18,0,18,16),child:TextField(readOnly:true,onTap:()=>showSearch(context:context,delegate:_ProductSearch(onAdd:addToCart)),decoration:InputDecoration(hintText:'Search items, food and essentials',prefixIcon:const Icon(Icons.search_rounded),suffixIcon:IconButton(tooltip:'Voice search',onPressed:_voiceSearch,icon:const Icon(Icons.mic_none_rounded)),filled:true,fillColor:Colors.white,border:OutlineInputBorder(borderRadius:BorderRadius.circular(17),borderSide:const BorderSide(color:Color(0xFFE5EAE5))))))),
  SliverToBoxAdapter(child:Padding(padding:const EdgeInsets.fromLTRB(18,0,18,10),child:InkWell(borderRadius:BorderRadius.circular(20),onTap:()=>Navigator.of(context).push(MaterialPageRoute<void>(builder:(_)=>ServiceBrowsePage(service:'Rides'))),child:Container(padding:const EdgeInsets.all(17),decoration:BoxDecoration(color:Colors.white,borderRadius:BorderRadius.circular(20),border:Border.all(color:const Color(0xFFE5EAE5))),child:Row(children:[Container(width:52,height:52,decoration:BoxDecoration(color:const Color(0xFFFFF0C7),borderRadius:BorderRadius.circular(16)),child:const Icon(Icons.directions_car_filled_rounded,color:Color(0xFF8C6410),size:28)),const SizedBox(width:13),const Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text('Where are you going?',style:TextStyle(fontSize:15,fontWeight:FontWeight.w900)),SizedBox(height:4),Text('Book a ride with Alteo',style:TextStyle(fontSize:12,color:Color(0xFF748078)))])),const Icon(Icons.arrow_forward_rounded,color:Color(0xFF176B57))]))))),
  SliverToBoxAdapter(child:section('Explore services','Shopping, food and everyday essentials')),
  SliverToBoxAdapter(child:SizedBox(height:116,child:ListView(scrollDirection:Axis.horizontal,padding:const EdgeInsets.symmetric(horizontal:18),children:[
   service('Food',Icons.restaurant_rounded,const Color(0xFFFFE8D9),const Color(0xFFB94E18)),service('Quick',Icons.shopping_basket_rounded,const Color(0xFFE3F4D8),const Color(0xFF357A35)),service('Shop',Icons.shopping_bag_rounded,const Color(0xFFE5E9FF),const Color(0xFF4857B8)),service('Rides',Icons.directions_car_rounded,const Color(0xFFFFF0C7),const Color(0xFF8C6410)),service('Parcel',Icons.local_shipping_rounded,const Color(0xFFDDF3F1),const Color(0xFF187B73))
  ]))),
  SliverToBoxAdapter(child:section('Discover items','Listed by Alteo marketplace partners')),
  SliverToBoxAdapter(child:SizedBox(height:42,child:ListView(scrollDirection:Axis.horizontal,padding:const EdgeInsets.symmetric(horizontal:18),children:[filter('All','all'),filter('Groceries','quick'),filter('Food','food'),filter('Shopping','shopping')]))),
  SliverToBoxAdapter(child:FutureBuilder<List<CustomerProduct>>(future:products,builder:(context,s){
   if(s.connectionState==ConnectionState.waiting)return const Padding(padding:EdgeInsets.all(28),child:Center(child:CircularProgressIndicator()));
   if(s.hasError)return empty('Could not load items','Check Supabase public read policies, then pull down to retry.');
   final items=s.data??[];
   if(items.isEmpty)return empty('Your marketplace is getting ready','Active products will appear here automatically when sellers publish them.');
   return Padding(padding:const EdgeInsets.fromLTRB(18,10,18,24),child:GridView.builder(shrinkWrap:true,physics:const NeverScrollableScrollPhysics(),itemCount:items.length,gridDelegate:const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount:2,crossAxisSpacing:12,mainAxisSpacing:12,childAspectRatio:.68),itemBuilder:(context,i)=>productCard(items[i])));
  })),
  const SliverToBoxAdapter(child:SizedBox(height:20))
 ]));
 Widget header()=>Padding(padding:const EdgeInsets.fromLTRB(18,14,18,16),child:Row(children:[
  Container(width:44,height:44,decoration:BoxDecoration(color:const Color(0xFF176B57),borderRadius:BorderRadius.circular(15)),child:const Icon(Icons.explore_rounded,color:Colors.white,size:27)),
  const SizedBox(width:11),const Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text('DELIVERING TO',style:TextStyle(fontSize:10,letterSpacing:1.2,fontWeight:FontWeight.w800,color:Color(0xFF737B76))),SizedBox(height:3),Text('Choose your location  ⌄',style:TextStyle(fontSize:14,fontWeight:FontWeight.w800))])),
  IconButton(tooltip:'Cart',onPressed:()=>Navigator.of(context).push(MaterialPageRoute<void>(builder:(_)=>const CustomerCartPage())),icon:const Icon(Icons.shopping_cart_outlined,size:24)),
  IconButton(onPressed:()=>ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Notifications will appear here when enabled.'))),icon:const Icon(Icons.notifications_none_rounded,size:27))
 ]));
 Widget bannerList() => FutureBuilder<List<CustomerBanner>>(
  future: banners,
  builder: (context, snapshot) {
    if (snapshot.connectionState == ConnectionState.waiting) {
      return const SizedBox(height: 185, child: Center(child: CircularProgressIndicator()));
    }
    final items = snapshot.data ?? [];
    if (items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(23),
          child: Container(
            height: 165,
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
        height: 185,
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
 Widget service(String n,IconData icon,Color bg,Color fg)=>Padding(padding:const EdgeInsets.only(right:12),child:InkWell(onTap:()=>Navigator.of(context).push(MaterialPageRoute<void>(builder:(_)=>ServiceBrowsePage(service:n))),borderRadius:BorderRadius.circular(18),child:SizedBox(width:78,child:Column(children:[Container(width:64,height:64,decoration:BoxDecoration(color:bg,borderRadius:BorderRadius.circular(21)),child:Icon(icon,color:fg,size:29)),const SizedBox(height:8),Text(n,style:const TextStyle(fontWeight:FontWeight.w800,fontSize:12))]))));
 Widget filter(String label,String value)=>Padding(padding:const EdgeInsets.only(right:8),child:ChoiceChip(label:Text(label),selected:kind==value,onSelected:(_)=>setState(() {kind=value;products=content!.loadProducts(kind:kind=='all'?null:kind);})));
 Widget empty(String title,String detail)=>Padding(padding:const EdgeInsets.fromLTRB(24,30,24,40),child:Column(children:[const Icon(Icons.storefront_outlined,size:44,color:Color(0xFF176B57)),const SizedBox(height:10),Text(title,textAlign:TextAlign.center,style:const TextStyle(fontWeight:FontWeight.w800,fontSize:15)),const SizedBox(height:6),Text(detail,textAlign:TextAlign.center,style:const TextStyle(color:Color(0xFF748078),height:1.4,fontSize:12))]));
 Future<void> addToCart(CustomerProduct p) async {
  if(Supabase.instance.client.auth.currentUser==null){await Navigator.of(context).push<bool>(MaterialPageRoute(builder:(_)=>const CustomerAuthPage()));if(!mounted||Supabase.instance.client.auth.currentUser==null)return;}
  try{await content!.addToCart(p.id);if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('${p.name} added to your cart.')));}
  catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Could not add item: $e')));}
 }
 Widget productCard(CustomerProduct p)=>Container(decoration:BoxDecoration(color:Colors.white,borderRadius:BorderRadius.circular(18),border:Border.all(color:const Color(0xFFE7EBE7))),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
  Expanded(child:ClipRRect(borderRadius:const BorderRadius.vertical(top:Radius.circular(17)),child:SizedBox(width:double.infinity,child:p.imageUrl.isEmpty?Container(color:const Color(0xFFEAF2EC),child:const Icon(Icons.shopping_bag_outlined,size:48,color:Color(0xFF176B57))):Image.network(p.imageUrl,fit:BoxFit.cover,errorBuilder:(_,__,___)=>Container(color:const Color(0xFFEAF2EC),child:const Icon(Icons.shopping_bag_outlined,size:48,color:Color(0xFF176B57))))))),
  Padding(padding:const EdgeInsets.fromLTRB(11,10,11,12),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
   Text(p.name,maxLines:2,overflow:TextOverflow.ellipsis,style:const TextStyle(fontSize:13,fontWeight:FontWeight.w800,height:1.25)),const SizedBox(height:5),Text(p.priceLabel,style:const TextStyle(fontSize:15,fontWeight:FontWeight.w900,color:Color(0xFF176B57))),const SizedBox(height:8),
   SizedBox(width:double.infinity,child:OutlinedButton(onPressed:()=>addToCart(p),style:OutlinedButton.styleFrom(padding:const EdgeInsets.symmetric(vertical:8),minimumSize:Size.zero),child:const Text('Add to cart')))
  ]))
 ]));
}
class _ProductSearch extends SearchDelegate<String>{
 _ProductSearch({required this.onAdd});
 final Future<void> Function(CustomerProduct) onAdd;
 @override List<Widget>? buildActions(BuildContext context)=>[IconButton(onPressed:()=>query='',icon:const Icon(Icons.clear))];
 @override Widget? buildLeading(BuildContext context)=>IconButton(onPressed:()=>close(context,''),icon:const Icon(Icons.arrow_back));
 @override Widget buildResults(BuildContext context)=>_results(context);
 @override Widget buildSuggestions(BuildContext context)=>query.trim().isEmpty?const Center(child:Text('Search products, groceries and essentials')):_results(context);
 Widget _results(BuildContext context){
  if(query.trim().isEmpty)return const Center(child:Text('Type or say an item name to search.'));
  return FutureBuilder<List<Map<String,dynamic>>>(
   future:Supabase.instance.client.from('seller_products').select('id,name,description,price_minor,image_url,kind').eq('status','active').ilike('name','%${query.trim()}%').order('created_at',ascending:false).limit(30),
   builder:(context,s){
    if(s.connectionState==ConnectionState.waiting)return const Center(child:CircularProgressIndicator());
    if(s.hasError)return const Center(child:Padding(padding:EdgeInsets.all(24),child:Text('Search is temporarily unavailable. Pull down on Home to retry.',textAlign:TextAlign.center)));
    final rows=s.data??[];
    if(rows.isEmpty)return const Center(child:Text('No matching items yet.'));
    return ListView.separated(padding:const EdgeInsets.all(14),itemCount:rows.length,separatorBuilder:(_,__)=>const Divider(),itemBuilder:(context,i){
     final p=CustomerProduct.fromMap(rows[i]);
     return ListTile(
      leading:ClipRRect(borderRadius:BorderRadius.circular(10),child:SizedBox(width:54,height:54,child:p.imageUrl.isEmpty?const ColoredBox(color:Color(0xFFEAF2EC),child:Icon(Icons.shopping_bag_outlined)):Image.network(p.imageUrl,fit:BoxFit.cover,errorBuilder:(_,__,___)=>const ColoredBox(color:Color(0xFFEAF2EC),child:Icon(Icons.shopping_bag_outlined))))),
      title:Text(p.name,style:const TextStyle(fontWeight:FontWeight.w800)),
      subtitle:Text(p.priceLabel),
      trailing:IconButton(tooltip:'Add to cart',onPressed:()=>onAdd(p),icon:const Icon(Icons.add_shopping_cart_rounded)),
     );
    });
   },
  );
 }
}