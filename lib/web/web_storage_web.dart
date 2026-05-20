import 'package:web/web.dart' as web;

String? webStorageGet(String key) => web.window.localStorage.getItem(key);

void webStorageSet(String key, String value) {
  web.window.localStorage.setItem(key, value);
}

void webStorageRemove(String key) {
  web.window.localStorage.removeItem(key);
}