import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Shared push-notification registration for the six Alteo Android apps.
/// Firebase configuration is supplied at build time; the app stays usable
/// when a Firebase project has not yet been configured.
@pragma('vm:entry-point')
Future<void> alteoFirebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    if (Firebase.apps.isEmpty) await Firebase.initializeApp();
  } catch (_) {
    // Native notification payloads can still be displayed by Android.
  }
}

class AlteoPushNotifications {
  AlteoPushNotifications._();

  static final AlteoPushNotifications instance = AlteoPushNotifications._();

  static const channelId = 'alteo_updates';
  static const channelName = 'Alteo updates';
  static const channelDescription = 'Order, ride, delivery and account updates';

  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();
  final StreamController<Map<String, dynamic>> _openedMessages =
      StreamController<Map<String, dynamic>>.broadcast();

  SupabaseClient? _client;
  FirebaseMessaging? _messaging;
  StreamSubscription<AuthState>? _authSubscription;
  StreamSubscription<String>? _tokenSubscription;
  bool _initialized = false;
  bool _localNotificationsInitialized = false;
  String? _appId;

  /// Emits data payloads when a user taps a notification. Apps can subscribe
  /// later to route to order/ride/detail pages.
  Stream<Map<String, dynamic>> get openedMessages => _openedMessages.stream;

  Future<void> initialize({
    required SupabaseClient client,
    required String appId,
  }) async {
    if (_initialized) return;
    _client = client;
    _appId = appId;

    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp();
      }
      _messaging = FirebaseMessaging.instance;
      FirebaseMessaging.onBackgroundMessage(alteoFirebaseMessagingBackgroundHandler);

      await _initializeLocalNotifications();
      FirebaseMessaging.onMessage.listen(_showForegroundNotification);
      FirebaseMessaging.onMessageOpenedApp.listen(
        (message) => _openedMessages.add(Map<String, dynamic>.from(message.data)),
      );

      _authSubscription = client.auth.onAuthStateChange.listen((state) {
        if (state.session != null) {
          unawaited(_requestPermissionAndRegister());
        }
      });

      final initialMessage = await _messaging!.getInitialMessage();
      if (initialMessage != null) {
        _openedMessages.add(Map<String, dynamic>.from(initialMessage.data));
      }
      if (client.auth.currentSession != null) {
        unawaited(_requestPermissionAndRegister());
      }
      _tokenSubscription = _messaging!.onTokenRefresh.listen(_saveToken);
      _initialized = true;
    } catch (error, stackTrace) {
      // Missing Firebase Android config is a setup issue, not a reason to
      // prevent customers or partners from opening the app.
      debugPrint('Alteo push notifications are not configured: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  Future<void> _initializeLocalNotifications() async {
    if (_localNotificationsInitialized) return;
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    );
    await _localNotifications.initialize(
      settings,
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload == null || payload.isEmpty) return;
        try {
          final decoded = jsonDecode(payload);
          if (decoded is Map<String, dynamic>) {
            _openedMessages.add(decoded);
          }
        } catch (_) {
          // Ignore malformed optional notification payloads.
        }
      },
    );
    const channel = AndroidNotificationChannel(
      channelId,
      channelName,
      description: channelDescription,
      importance: Importance.high,
    );
    await _localNotifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
    _localNotificationsInitialized = true;
  }

  Future<void> _requestPermissionAndRegister() async {
    // Admin operations must never trigger location/notification permission prompts.
    if (_appId == 'admin') return;
    final messaging = _messaging;
    if (messaging == null) return;
    final user = _client?.auth.currentUser;
    if (user == null) return;
    try {
      final settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      if (settings.authorizationStatus != AuthorizationStatus.authorized &&
          settings.authorizationStatus != AuthorizationStatus.provisional) {
        return;
      }
      // Customer broadcast notifications are delivered through an FCM topic,
      // so they can reach all opted-in customer installs without token fan-out.
      if (_appId == 'customer') {
        await messaging.subscribeToTopic('alteo_customers');
      } else if (_appId == 'delivery_partner') {
        await messaging.subscribeToTopic('alteo_delivery_partners');
      }
      final token = await messaging.getToken();
      if (token != null && token.isNotEmpty) await _saveToken(token);
    } catch (error) {
      debugPrint('Could not register Alteo push token: $error');
    }
  }

  Future<void> _saveToken(String token) async {
    final client = _client;
    final user = client?.auth.currentUser;
    final appId = _appId;
    if (client == null || user == null || appId == null || token.isEmpty) return;
    try {
      await client.from('user_device_tokens').upsert(
        <String, dynamic>{
          'user_id': user.id,
          'app_id': appId,
          'token': token,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        onConflict: 'app_id,token',
      );
    } catch (error) {
      debugPrint('Could not save Alteo push token. Apply the device-token migration: $error');
    }
  }

  /// Call this before Supabase sign-out so the token mapping can be removed
  /// while the user's access token is still active.
  Future<void> unregisterCurrentDevice() async {
    final client = _client;
    final user = client?.auth.currentUser;
    final appId = _appId;
    final messaging = _messaging;
    if (client == null || user == null || appId == null || messaging == null) return;
    try {
      final token = await messaging.getToken();
      if (token == null || token.isEmpty) return;
      await client.from('user_device_tokens')
          .delete()
          .eq('user_id', user.id)
          .eq('app_id', appId)
          .eq('token', token);
    } catch (error) {
      debugPrint('Could not remove Alteo push-token association: $error');
    }
  }

  Future<void> _showForegroundNotification(RemoteMessage message) async {
    if (!_localNotificationsInitialized) return;
    final notification = message.notification;
    final title = notification?.title ?? message.data['title']?.toString();
    final body = notification?.body ?? message.data['body']?.toString();
    if ((title == null || title.isEmpty) && (body == null || body.isEmpty)) return;
    await _localNotifications.show(
      DateTime.now().millisecondsSinceEpoch.remainder(2147483647),
      title ?? 'Alteo update',
      body ?? '',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          channelName,
          channelDescription: channelDescription,
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
        iOS: DarwinNotificationDetails(),
      ),
      payload: jsonEncode(message.data),
    );
  }

  Future<void> dispose() async {
    await _authSubscription?.cancel();
    await _tokenSubscription?.cancel();
    _authSubscription = null;
    _tokenSubscription = null;
  }
}


/// Requests runtime permissions once on the first launch of each non-admin app.
/// Android displays these system prompts when the app is opened for the first time,
/// not during APK installation. A denied permission never blocks app startup.
class AlteoFirstLaunchPermissionGate extends StatefulWidget {
  const AlteoFirstLaunchPermissionGate({
    super.key,
    required this.appId,
    required this.child,
  });

  final String appId;
  final Widget child;

  /// Can be disabled by deterministic widget tests; normal app builds keep this enabled.
  static bool enabled = true;

  static final Map<String, Completer<void>> _completion = <String, Completer<void>>{};

  static Completer<void> _forApp(String appId) =>
      _completion.putIfAbsent(appId, Completer<void>.new);

  static Future<void> waitUntilComplete(String appId) => _forApp(appId).future;

  @override
  State<AlteoFirstLaunchPermissionGate> createState() => _AlteoFirstLaunchPermissionGateState();
}

class _AlteoFirstLaunchPermissionGateState extends State<AlteoFirstLaunchPermissionGate> {
  bool _started = false;
  static const _notificationSettings = InitializationSettings(
    android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    iOS: DarwinInitializationSettings(),
  );

  @override
  void initState() {
    super.initState();
    if (!AlteoFirstLaunchPermissionGate.enabled) {
      final completion = AlteoFirstLaunchPermissionGate._forApp(widget.appId);
      if (!completion.isCompleted) completion.complete();
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_started) {
        _started = true;
        unawaited(_requestOnce());
      }
    });
  }

  Future<void> _requestOnce() async {
    final completion = AlteoFirstLaunchPermissionGate._forApp(widget.appId);
    if (!AlteoFirstLaunchPermissionGate.enabled) {
      if (!completion.isCompleted) completion.complete();
      return;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'alteo_first_launch_permissions_v1_${widget.appId}';
      if (prefs.getBool(key) != true) {
        // Location prompt first, followed by notifications.
        try {
          final current = await Geolocator.checkPermission();
          if (current == LocationPermission.denied) {
            await Geolocator.requestPermission();
          }
        } catch (_) {
          // Permission APIs may be unavailable on a simulator or restricted device.
        }

        await _requestNotifications();
        await prefs.setBool(key, true);
      }
    } catch (_) {
      // A preferences or permissions failure must never prevent the app from opening.
    } finally {
      if (!completion.isCompleted) completion.complete();
    }
  }

  Future<void> _requestNotifications() async {
    final local = FlutterLocalNotificationsPlugin();
    try {
      await local.initialize(_notificationSettings);
      final android = local.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      await android?.requestNotificationsPermission();
    } catch (_) {
      // Continue to the FCM prompt below where Firebase is configured.
    }
    try {
      if (Firebase.apps.isEmpty) await Firebase.initializeApp();
      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission(alert: true, badge: true, sound: true);
    } catch (_) {
      // The Android notification prompt above still works without Firebase setup.
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
