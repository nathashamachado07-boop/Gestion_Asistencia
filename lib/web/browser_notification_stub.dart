Future<bool> browserNotificationsSupported() async => false;

Future<String> browserNotificationPermission() async => 'unsupported';

Future<String> requestBrowserNotificationPermission() async => 'unsupported';

bool showBrowserNotification({
  required String title,
  required String body,
}) {
  return false;
}
