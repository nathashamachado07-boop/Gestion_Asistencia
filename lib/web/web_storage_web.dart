import 'dart:html' as html;

String? webStorageGet(String key) => html.window.localStorage[key];

void webStorageSet(String key, String value) {
  html.window.localStorage[key] = value;
}

void webStorageRemove(String key) {
  html.window.localStorage.remove(key);
}
