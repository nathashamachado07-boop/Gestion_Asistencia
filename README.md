# Gestion Asistencia

Proyecto Flutter con dos apps independientes:

- `Matriz`
- `Sede Norte`

## Entry points

- `lib/main.dart`: app matriz por defecto
- `lib/main_matriz.dart`: app matriz explicita
- `lib/main_sede_norte.dart`: app sede norte

## Reglas de acceso

- La app `Matriz` bloquea usuarios identificados como `Princesa de Gales Norte`.
- La app `Sede Norte` solo permite usuarios de `Princesa de Gales Norte`.
- El bloqueo aplica en login movil y login web.

## Ejecutar en web

Matriz:

```bash
flutter run -d chrome -t lib/main_matriz.dart
```

Sede Norte:

```bash
flutter run -d chrome -t lib/main_sede_norte.dart
```

## Ejecutar en Android

Matriz:

```bash
flutter run --flavor matriz -t lib/main_matriz.dart
```

Sede Norte:

```bash
flutter run --flavor norte -t lib/main_sede_norte.dart
```

## Build Android

APK Matriz:

```bash
flutter build apk --flavor matriz -t lib/main_matriz.dart
```

APK Sede Norte:

```bash
flutter build apk --flavor norte -t lib/main_sede_norte.dart
```
