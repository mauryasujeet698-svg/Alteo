import 'package:customer/core/theme/alteo_theme.dart';
import 'package:customer/features/preferences/app_preferences_store.dart';
import 'package:customer/routing/app_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AlteoApp extends ConsumerWidget {
  const AlteoApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preferences = ref.watch(appPreferencesStoreProvider);
    return ListenableBuilder(
      listenable: preferences,
      builder: (context, child) => MaterialApp.router(
        title: 'Alteo',
        debugShowCheckedModeBanner: false,
        theme: AlteoTheme.light(),
        darkTheme: AlteoTheme.dark(),
        themeMode: preferences.themeMode,
        routerConfig: ref.watch(appRouterProvider),
      ),
    );
  }
}
