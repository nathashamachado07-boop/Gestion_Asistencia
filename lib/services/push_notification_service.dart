import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'firebase_service.dart';

const AndroidNotificationChannel _highImportanceChannel =
    AndroidNotificationChannel(
  'intesud_high_importance',
  'INTESUD Avisos',
  description: 'Notificaciones de solicitudes aprobadas y avisos generales.',
  importance: Importance.max,
);

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await PushNotificationService.instance.initializeLocalNotifications();
  await PushNotificationService.instance.showRemoteMessage(message);
}

class PushNotificationService {
  PushNotificationService._();

  static final PushNotificationService instance = PushNotificationService._();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  final FirebaseService _firebaseService = FirebaseService();

  bool _initialized = false;
  bool _localInitialized = false;
  String? _currentUserEmail;
  String? _currentUserSedeId;
  StreamSubscription<String>? _tokenRefreshSubscription;
  StreamSubscription<RemoteMessage>? _foregroundMessageSubscription;
  StreamSubscription<RemoteMessage>? _messageOpenedSubscription;

  Future<void> initialize() async {
    if (_initialized || kIsWeb) {
      return;
    }

    _initialized = true;
    await initializeLocalNotifications();

    await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );

    await _messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    _foregroundMessageSubscription?.cancel();
    _foregroundMessageSubscription = FirebaseMessaging.onMessage.listen(
      showRemoteMessage,
    );

    _messageOpenedSubscription?.cancel();
    _messageOpenedSubscription = FirebaseMessaging.onMessageOpenedApp.listen(
      (_) {},
    );
  }

  Future<void> initializeLocalNotifications() async {
    if (_localInitialized || kIsWeb) {
      return;
    }

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initializationSettings =
        InitializationSettings(android: android);

    await _localNotifications.initialize(initializationSettings);

    final androidPlugin = _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    await androidPlugin?.createNotificationChannel(_highImportanceChannel);
    await androidPlugin?.requestNotificationsPermission();

    _localInitialized = true;
  }

  Future<void> identifyUser({
    required String correo,
    String? sedeId,
  }) async {
    if (kIsWeb) {
      return;
    }

    _currentUserEmail = correo.trim().toLowerCase();
    _currentUserSedeId = sedeId?.trim();

    await initialize();
    await _saveCurrentToken();

    _tokenRefreshSubscription?.cancel();
    _tokenRefreshSubscription = _messaging.onTokenRefresh.listen((token) async {
      if (_currentUserEmail == null || _currentUserEmail!.isEmpty) {
        return;
      }

      await _firebaseService.registrarTokenNotificacion(
        correo: _currentUserEmail!,
        sedeId: _currentUserSedeId,
        token: token,
      );
    });
  }

  Future<void> _saveCurrentToken() async {
    final correo = _currentUserEmail;
    if (correo == null || correo.isEmpty) {
      return;
    }

    final token = await _messaging.getToken();
    if (token == null || token.isEmpty) {
      return;
    }

    await _firebaseService.registrarTokenNotificacion(
      correo: correo,
      sedeId: _currentUserSedeId,
      token: token,
    );
  }

  Future<void> showRemoteMessage(RemoteMessage message) async {
    if (kIsWeb) {
      return;
    }

    await initializeLocalNotifications();

    final notification = message.notification;
    final title =
        notification?.title ?? message.data['title']?.toString() ?? 'INTESUD';
    final body =
        notification?.body ?? message.data['body']?.toString() ?? 'Tienes un nuevo aviso.';

    await _localNotifications.show(
      message.hashCode,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _highImportanceChannel.id,
          _highImportanceChannel.name,
          channelDescription: _highImportanceChannel.description,
          importance: Importance.max,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
      ),
    );
  }
}
