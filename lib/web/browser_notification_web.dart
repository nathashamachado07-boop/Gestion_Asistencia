import 'dart:async';
import 'dart:html' as html;

Future<bool> browserNotificationsSupported() async {
  return html.Notification.supported;
}

Future<String> browserNotificationPermission() async {
  if (!html.Notification.supported) {
    return 'unsupported';
  }

  return html.Notification.permission ?? 'default';
}

Future<String> requestBrowserNotificationPermission() async {
  if (!html.Notification.supported) {
    return 'unsupported';
  }

  return await html.Notification.requestPermission();
}

bool showBrowserNotification({
  required String title,
  required String body,
}) {
  if (!html.Notification.supported ||
      html.Notification.permission != 'granted') {
    return false;
  }

  final notification = html.Notification(title, body: body);
  notification.onClick.listen((_) {
    notification.close();
  });

  Timer(const Duration(seconds: 6), notification.close);
  return true;
}
