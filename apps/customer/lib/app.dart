import 'package:customer/core/theme/alteo_theme.dart';
import 'package:customer/routing/app_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AlteoApp extends ConsumerWidget {
  const AlteoApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'Alteo',
      debugShowCheckedModeBanner: false,
      theme: AlteoTheme.light(),
      darkTheme: AlteoTheme.dark(),
      themeMode: ThemeMode.system,
      routerConfig: ref.watch(appRouterProvider),
    );
  }
}
