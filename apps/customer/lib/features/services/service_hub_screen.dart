import 'package:cached_network_image/cached_network_image.dart';
import 'package:customer/core/theme/alteo_theme.dart';
import 'package:customer/core/widgets/catalogue_preview_notice.dart';
import 'package:customer/features/catalog/data/preview_products.dart';
import 'package:customer/features/catalog/presentation/product_card.dart';
import 'package:customer/routing/app_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class ServiceHubScreen extends ConsumerStatefulWidget {
  const ServiceHubScreen({required this.serviceType, super.key});
  final String serviceType;

  @override
  ConsumerState<ServiceHubScreen> createState() => _ServiceHubScreenState();
}

class _ServiceHubScreenState extends ConsumerState<ServiceHubScreen> {
  final pickup = TextEditingController();
  final drop = TextEditingController();
  String vehicle = 'Bike';

  @override
  void dispose() {
    pickup.dispose();
    drop.dispose();
    super.dispose();
  }

  String get title => switch (widget.serviceType) {
        'food' => 'Food Corner',
        'quick' => 'Quick essentials',
        'rides' => 'Alteo Travel',
        'parcel' => 'Send a parcel',
        _ => 'Shop everyday',
      };

  @override
  Widget build(BuildContext context) {
    if (widget.serviceType == 'rides') return rides(context);
    if (widget.serviceType == 'parcel') return parcel(context);
    if (widget.serviceType == 'food') return food(context);
    return shop(context);
  }

  Widget page(BuildContext context, List<Widget> children) => Scaffold(
        appBar: AppBar(title: Text(title, style: Theme.of(context).textTheme.headlineMedium), actions: [
          IconButton(tooltip: 'Open cart', onPressed: () => context.go('/cart'), icon: const Icon(Icons.shopping_bag_outlined)),
          const SizedBox(width: 6),
        ]),
        body: ListView(padding: const EdgeInsets.fromLTRB(18, 6, 18, 28), children: children),
      );

  Widget shop(BuildContext context) {
    final cart = ref.watch(cartStoreProvider);
    return page(context, [
      Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(color: AlteoColors.mint, borderRadius: BorderRadius.circular(20)),
        child: Row(children: [
          const Icon(Icons.shopping_basket_outlined, color: AlteoColors.forest, size: 32),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Everyday, made simpler', style: Theme.of(context).textTheme.titleLarge?.copyWith(color: AlteoColors.forestDeep)),
            const SizedBox(height: 4),
            Text('Preview cart items: ' + cart.itemCount.toString(), style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AlteoColors.forestDeep)),
          ])),
        ]),
      ),
      const SizedBox(height: 14),
      const CataloguePreviewNotice(),
      const SizedBox(height: 18),
      Text('Browse the collection', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 12),
      GridView.builder(
        shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
        itemCount: PreviewProducts.all.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisSpacing: 12, crossAxisSpacing: 12, mainAxisExtent: 280),
        itemBuilder: (context, index) {
          final product = PreviewProducts.all[index];
          return ProductCard(
            product: product,
            onTap: () => context.push('/product/' + product.id),
            onAdd: () {
              cart.add(product);
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(product.name + ' added to preview cart')));
            },
          );
        },
      ),
    ]);
  }

  Widget food(BuildContext context) {
    final restaurants = <({String name, String cuisine, String eta, String rating, String image})>[
      (name: 'The Green Plate', cuisine: 'Healthy bowls · Indian', eta: '25–35 min', rating: '4.8', image: 'https://images.unsplash.com/photo-1547592180-85f173990554?auto=format&fit=crop&w=1000&q=80'),
      (name: 'Tandoori House', cuisine: 'North Indian · Tandoor', eta: '30–40 min', rating: '4.6', image: 'https://images.unsplash.com/photo-1567188040759-fb8a883dc6d8?auto=format&fit=crop&w=1000&q=80'),
      (name: 'Urban Slice', cuisine: 'Pizza · Snacks', eta: '20–30 min', rating: '4.5', image: 'https://images.unsplash.com/photo-1513104890138-7c749659a591?auto=format&fit=crop&w=1000&q=80'),
    ];
    return page(context, [
      const CataloguePreviewNotice(),
      const SizedBox(height: 18),
      Container(
        height: 160, padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(22), gradient: const LinearGradient(colors: [Color(0xFF5B2B20), Color(0xFFBD6849), Color(0xFFE2B18A)])),
        child: Stack(children: [
          Positioned(right: -18, bottom: -30, child: Icon(Icons.ramen_dining_rounded, size: 170, color: Colors.white.withValues(alpha: 0.16))),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: const [
            Text('GOOD FOOD, GOOD MOOD', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w800, fontSize: 10, letterSpacing: 1.2)),
            Spacer(),
            Text('A little joy,\nserved fresh.', style: TextStyle(color: Colors.white, fontSize: 27, fontWeight: FontWeight.w900, height: 1.1)),
            SizedBox(height: 6),
            Text('Sample restaurant discovery', style: TextStyle(color: Colors.white70, fontSize: 12)),
          ]),
        ]),
      ),
      const SizedBox(height: 22),
      Text('Popular near you', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 12),
      for (final r in restaurants)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => showMessage(context, r.name, 'This is sample restaurant content. Live menus, location serviceability, availability and ordering need the food backend. No order can be placed from this preview.'),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(20), border: Border.all(color: Theme.of(context).dividerColor)),
              child: Row(children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: SizedBox(width: 100, height: 100, child: CachedNetworkImage(
                    imageUrl: r.image, fit: BoxFit.cover,
                    placeholder: (context, url) => Container(color: AlteoColors.mint),
                    errorWidget: (context, url, error) => Container(color: AlteoColors.mint, child: const Icon(Icons.restaurant_outlined)),
                  )),
                ),
                const SizedBox(width: 13),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(r.name, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(r.cuisine, style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 9),
                  Row(children: [
                    const Icon(Icons.star_rounded, size: 16, color: Color(0xFFF2B544)),
                    Text(' ' + r.rating),
                    const SizedBox(width: 10),
                    const Icon(Icons.schedule_rounded, size: 15),
                    Text(' ' + r.eta, style: Theme.of(context).textTheme.bodySmall),
                  ]),
                  const SizedBox(height: 8),
                  Text('View menu preview', style: Theme.of(context).textTheme.labelLarge?.copyWith(color: AlteoColors.forest, fontWeight: FontWeight.w800)),
                ])),
              ]),
            ),
          ),
        ),
    ]);
  }

  Widget rides(BuildContext context) => page(context, [
        Container(
          height: 190,
          decoration: BoxDecoration(color: const Color(0xFFEAF0E9), borderRadius: BorderRadius.circular(22), border: Border.all(color: const Color(0xFFD9E3D9))),
          clipBehavior: Clip.antiAlias,
          child: Stack(children: [
            Positioned.fill(child: CustomPaint(painter: _MapPreviewPainter())),
            const Positioned(left: 16, top: 16, child: _MapLabel(icon: Icons.my_location_rounded, label: 'Pickup')),
            const Positioned(right: 16, bottom: 16, child: _MapLabel(icon: Icons.location_on_rounded, label: 'Drop-off')),
            Positioned(left: 16, bottom: 16, child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(9)),
              child: const Text('MAP PREVIEW', style: TextStyle(color: AlteoColors.forestDeep, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 1.1)),
            )),
          ]),
        ),
        const SizedBox(height: 12),
        const CataloguePreviewNotice(),
        const SizedBox(height: 18),
        Text('Where are you going?', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        TextField(controller: pickup, textInputAction: TextInputAction.next, decoration: const InputDecoration(labelText: 'Pickup location', hintText: 'Enter pickup address', prefixIcon: Icon(Icons.my_location_rounded))),
        const SizedBox(height: 10),
        TextField(controller: drop, textInputAction: TextInputAction.done, decoration: const InputDecoration(labelText: 'Destination', hintText: 'Where to?', prefixIcon: Icon(Icons.location_on_outlined))),
        const SizedBox(height: 18),
        Text('Choose a ride', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 10),
        Wrap(spacing: 8, children: [
          for (final choice in ['Bike', 'Auto', 'Car'])
            ChoiceChip(
              avatar: Icon(choice == 'Bike' ? Icons.two_wheeler : choice == 'Auto' ? Icons.electric_rickshaw : Icons.directions_car_outlined, size: 18),
              label: Text(choice), selected: vehicle == choice, onSelected: (_) => setState(() => vehicle = choice),
            ),
        ]),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: () => showMessage(
            context,
            'Ride booking is not connected yet',
            pickup.text.trim().isEmpty || drop.text.trim().isEmpty
                ? 'Enter pickup and destination. Real address search, routing, fare quotes and driver dispatch are still required. No ride was requested.'
                : 'Your ' + vehicle + ' ride from ' + pickup.text.trim() + ' to ' + drop.text.trim() + ' is a preview only. No fare has been quoted and no driver has been contacted.',
          ),
          icon: const Icon(Icons.route_rounded), label: const Text('Check ride availability'),
        ),
      ]);

  Widget parcel(BuildContext context) => page(context, [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(color: const Color(0xFFECE5FA), borderRadius: BorderRadius.circular(20)),
          child: Row(children: [
            const Icon(Icons.local_shipping_outlined, color: Color(0xFF493575), size: 36),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('A simple way to send', style: Theme.of(context).textTheme.titleLarge?.copyWith(color: const Color(0xFF493575))),
              const SizedBox(height: 4),
              Text('Prepare your parcel details. Booking is not live yet.', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: const Color(0xFF493575))),
            ])),
          ]),
        ),
        const SizedBox(height: 14),
        const CataloguePreviewNotice(),
        const SizedBox(height: 20),
        TextField(controller: pickup, decoration: const InputDecoration(labelText: 'Pickup address', prefixIcon: Icon(Icons.my_location_rounded))),
        const SizedBox(height: 12),
        TextField(controller: drop, decoration: const InputDecoration(labelText: 'Delivery address', prefixIcon: Icon(Icons.location_on_outlined))),
        const SizedBox(height: 18),
        Text('Parcel size', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 10),
        const Wrap(spacing: 8, children: [
          Chip(avatar: Icon(Icons.mail_outline, size: 17), label: Text('Small')),
          Chip(avatar: Icon(Icons.inventory_2_outlined, size: 17), label: Text('Medium')),
          Chip(avatar: Icon(Icons.all_inbox_outlined, size: 17), label: Text('Large')),
        ]),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: () => showMessage(
            context,
            'Parcel delivery is not connected yet',
            pickup.text.trim().isEmpty || drop.text.trim().isEmpty
                ? 'Add pickup and delivery addresses to prepare this preview. Live quotes, eligibility checks and delivery assignment require the backend.'
                : 'Your parcel from ' + pickup.text.trim() + ' to ' + drop.text.trim() + ' is only a preview. No courier has been assigned.',
          ),
          icon: const Icon(Icons.calculate_outlined), label: const Text('Check delivery options'),
        ),
      ]);

  void showMessage(BuildContext context, String title, String message) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title), content: Text(message),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Got it'))],
      ),
    );
  }
}

class _MapLabel extends StatelessWidget {
  const _MapLabel({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(11), boxShadow: const [BoxShadow(color: Color(0x18000000), blurRadius: 8, offset: Offset(0, 3))]),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: AlteoColors.forest, size: 16),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(color: AlteoColors.forestDeep, fontSize: 11, fontWeight: FontWeight.w700)),
        ]),
      );
}

class _MapPreviewPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final roads = Paint()..color = Colors.white..strokeWidth = 13..strokeCap = StrokeCap.round..style = PaintingStyle.stroke;
    final minor = Paint()..color = const Color(0xFFD3E0D5)..strokeWidth = 2..style = PaintingStyle.stroke;
    for (var i = 0; i < 5; i++) {
      final y = size.height * (0.15 + i * 0.2);
      canvas.drawLine(Offset(-12, y), Offset(size.width + 12, y + (i.isEven ? 18 : -14)), roads);
    }
    for (var i = 0; i < 5; i++) {
      final x = size.width * (0.12 + i * 0.19);
      canvas.drawLine(Offset(x, -10), Offset(x + (i.isEven ? 18 : -10), size.height + 10), roads);
    }
    for (var i = 0; i < 7; i++) {
      final y = size.height * (0.08 + i * 0.13);
      canvas.drawLine(Offset(0, y), Offset(size.width, y + 8), minor);
    }
    final route = Paint()..color = AlteoColors.forest..strokeWidth = 4..strokeCap = StrokeCap.round..style = PaintingStyle.stroke;
    final path = Path()
      ..moveTo(size.width * 0.19, size.height * 0.25)
      ..lineTo(size.width * 0.34, size.height * 0.36)
      ..lineTo(size.width * 0.47, size.height * 0.32)
      ..lineTo(size.width * 0.55, size.height * 0.53)
      ..lineTo(size.width * 0.72, size.height * 0.62)
      ..lineTo(size.width * 0.82, size.height * 0.81);
    canvas.drawPath(path, route);
    canvas.drawCircle(Offset(size.width * 0.19, size.height * 0.25), 7, Paint()..color = AlteoColors.forest);
    canvas.drawCircle(Offset(size.width * 0.82, size.height * 0.81), 7, Paint()..color = AlteoColors.coral);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
