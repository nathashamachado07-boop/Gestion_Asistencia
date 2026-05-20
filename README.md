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

## Generar certificado .p12 de prueba

Para probar el flujo de firma digital interna en Windows puedes generar un certificado PKCS#12 de prueba con:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\generar_certificado_prueba_p12.ps1
```

Eso crea estos archivos en `scripts\generated-certificates`:

- `PruebaFirmaInterna.p12`
- `PruebaFirmaInterna.pfx`
- `PruebaFirmaInterna.cer`

Si quieres definir otro nombre y otra clave:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\generar_certificado_prueba_p12.ps1 -CommonName "Juan Perez" -Password "MiClave123!" -Overwrite
```

Sube el archivo `.p12` o `.pfx` al perfil del usuario y usa la misma clave al firmar.
