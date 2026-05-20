import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

bool _notificationSupported() => globalContext.has('Notification');

Future<bool> browserNotificationsSupported() async {
  return _notificationSupported();
}

Future<String> browserNotificationPermission() async {
  if (!_notificationSupported()) {
    return 'unsupported';
  }

  return web.Notification.permission;
}

Future<String> requestBrowserNotificationPermission() async {
  if (!_notificationSupported()) {
    return 'unsupported';
  }

  final permission = await web.Notification.requestPermission().toDart;
  return permission.toDart;
}

bool showBrowserNotification({required String title, required String body}) {
  if (!_notificationSupported() || web.Notification.permission != 'granted') {
    return false;
  }

  final notification = web.Notification(
    title,
    web.NotificationOptions(body: body),
  );
  notification.onclick = ((JSAny? _) {
    notification.close();
  }).toJS;

  Timer(const Duration(seconds: 6), () {
    notification.close();
  });
  return true;
}