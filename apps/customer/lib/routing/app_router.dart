import 'package:customer/features/cart/cart_screen.dart';
import 'package:customer/features/cart/cart_store.dart';
import 'package:customer/features/checkout/checkout_screen.dart';
import 'package:customer/features/explore/explore_screen.dart';
import 'package:customer/features/home/home_screen.dart';
import 'package:customer/features/orders/orders_screen.dart';
import 'package:customer/features/profile/profile_screen.dart';
import 'package:customer/features/catalog/presentation/product_detail_screen.dart';
import 'package:customer/features/shell/customer_shell.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

final cartStoreProvider = Provider<CartStore>((ref) {
  final store = CartStore();
  ref.onDispose(store.dispose);
  return store;
});

final appRouterProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    initialLocation: '/home',
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) => CustomerShell(
          navigationShell: navigationShell,
        ),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/home',
                builder: (context, state) => const HomeScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/explore',
                builder: (context, state) => const ExploreScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/orders',
                builder: (context, state) => const OrdersScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/profile',
                builder: (context, state) => const ProfileScreen(),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/cart',
        builder: (context, state) => const CartScreen(),
      ),
      GoRoute(
        path: '/product/:productId',
        builder: (context, state) => ProductDetailScreen(
          productId: state.pathParameters['productId'] ?? '',
        ),
      ),
      GoRoute(
        path: '/checkout',
        builder: (context, state) => const CheckoutScreen(),
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});
