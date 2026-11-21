# Desarrollo y verificación

[Volver al README](../README.md) · [Arquitectura](ARQUITECTURA.md) · [Contribuir](../CONTRIBUTING.md)

## Entorno

| Componente | Referencia del proyecto |
| --- | --- |
| Flutter / Dart | Entorno documentado: Flutter 3.50.0 / Dart 3.14.0. `pubspec.yaml` exige Dart `^3.14.0`; el repositorio no fija una instalación de Flutter. |
| Java | Java 21 como entorno de referencia. El código Android tiene objetivos Java/JVM 17; no confundirlos con el JDK que ejecuta Gradle. |
| Android | SDK y herramientas de compilación configurados para Flutter; dispositivo o emulador con API 24 o superior. |
| Gradle | Wrapper 9.5.0, Android Gradle Plugin 9.3.1 y declaración del plugin Kotlin 2.4.20. Consulta los archivos Gradle antes de cambiar versiones. |
| FFmpeg del equipo | Opcional: solo para los scripts de `tool/`. El APK usa FFmpegKit. |
| WhatsApp | Necesario en el teléfono para comprobar la exportación. |

Las fuentes de configuración son [pubspec.yaml](../pubspec.yaml), [settings.gradle.kts](../android/settings.gradle.kts), [build.gradle.kts](../android/app/build.gradle.kts) y [gradle-wrapper.properties](../android/gradle/wrapper/gradle-wrapper.properties). `compileSdk`, `targetSdk` y NDK se toman del SDK de Flutter instalado.

## Preparar y ejecutar

```sh
git clone https://github.com/DonLuizKv/sharegif.git
cd sharegif
flutter --version
java -version
flutter doctor -v
flutter doctor --android-licenses
flutter pub get
flutter devices
flutter run -d <ID_ANDROID>
```

Sustituye `<ID_ANDROID>` por un identificador listado en `flutter devices`. En un teléfono físico, habilita la depuración USB y autoriza el equipo. Si Flutter detecta varias instalaciones de Java, revisa en `flutter doctor -v` cuál usa realmente.

`android/local.properties` contiene rutas locales al SDK de Flutter y Android; no debe versionarse. No se requieren claves de API, un `.env`, cookies de X ni un backend. La primera instalación de dependencias y las importaciones por enlace requieren conexión.

Conserva `pubspec.lock` para mantener las dependencias resueltas de la aplicación. No actualices dependencias como efecto secundario de un cambio de documentación.

## Compilar

```sh
flutter build apk --debug
```

El APK queda en `build/app/outputs/flutter-apk/app-debug.apk`. La versión procede de `pubspec.yaml` (`0.1.3+4` en esta revisión). No uses copias antiguas del APK en otras carpetas como evidencia de una compilación reciente.

El build `release` está configurado con la firma de depuración. Generar un APK release no lo convierte en una distribución preparada para producción; revisa [Antes de distribuir](#antes-de-distribuir).

## Verificación

### Análisis y pruebas Flutter

Desde la raíz del repositorio:

```sh
flutter analyze
flutter test
```

| Pruebas | Responsabilidad |
| --- | --- |
| `test/models_test.dart` | Enlaces, límites de recorte, contenedores WebP y compatibilidad de modelos. |
| `test/link_batch_test.dart` | Orden, duplicados, validación completa y límite de tandas. |
| `test/x_post_resolver_test.dart` | Respuestas simuladas de X, selección de adjuntos, fotos, citas y errores. |
| `test/library_test.dart` | Persistencia, separación de tipos, límites y fallos de almacenamiento. |
| `test/app_test.dart` | Navegación, tandas, errores, imágenes estáticas, texto ampliado y referencias visuales. |

Las pruebas de X usan respuestas controladas; aprobarlas no demuestra que una publicación real siga accesible. Las pruebas de interfaz sustituyen servicios para aislar el flujo y no validan la exportación nativa a WhatsApp.

Las referencias visuales están en `test/goldens/`. Ante un cambio visual intencional, puedes regenerarlas con:

```sh
flutter test --update-goldens test/app_test.dart
```

Inspecciona las imágenes y su diff antes de incluirlas. No actualices referencias solo para hacer desaparecer un fallo; diferencias de entorno o renderizado también necesitan revisión.

### Conversión con FFmpeg del equipo

Necesitas `ffmpeg` en `PATH`, con los codificadores `libwebp` y `libwebp_anim` y los filtros usados por el script:

```sh
ffmpeg -version
ffmpeg -encoders
dart run tool/verify_conversion.dart
```

El script genera entradas PNG, JPG, WebP, GIF y MP4 y prueba los encuadres `contain` y `cover`: diez conversiones en total. Reutiliza `ConversionOptions` y `WebpInfo` para verificar el WebP resultante, incluidos dimensiones, peso y duración del recorte. Crea archivos temporales y los limpia al terminar.

Usa los códecs instalados en el equipo, no el binario de FFmpegKit del teléfono. Tampoco reproduce todo el ajuste progresivo de calidad y FPS de `MediaService`.

### Importación real desde X

Necesitas conexión, `ffmpeg` y `ffprobe` en `PATH`, y una publicación pública que contenga un GIF o video accesible:

```sh
dart run tool/verify_x_import.dart "https://x.com/GIPHY/status/1957913446118285360"
```

El enlace es un ejemplo y puede dejar de estar disponible. El script usa el resolver y descargador de la app, selecciona el primer medio resuelto y convierte hasta tres segundos con 15 FPS y calidad 60. No ofrece selector ni implementa todo el ajuste automático de la app. Úsalo con GIF/video: aunque la app importe fotos, esta herramienta presupone una duración de video.

Un fallo puede provenir de la disponibilidad del enlace, límites de X, la red o los códecs del equipo. Registra cuál de las etapas falla antes de atribuirlo al código Flutter.

## Validar en Android

Estas comprobaciones siguen siendo necesarias para dar por validada una versión en dispositivo:

- Importar una imagen, un GIF y un video local; comprobar ambos encuadres, transparencia y recorte temporal.
- Importar una foto y una animación de X, seleccionar un adjunto y procesar una tanda mixta.
- Salir del editor sin guardar y provocar un error de descarga; comprobar que los enlaces pendientes siguen en el campo.
- Guardar stickers, reiniciar ShareGIF y verificar la persistencia y separación de tipos de paquetes.
- Exportar paquetes estáticos y animados de al menos tres stickers; confirmar que aparecen y funcionan en WhatsApp.
- Cancelar la confirmación en WhatsApp, reintentar y comprobar la actualización de un paquete ya exportado.
- Borrar un sticker de la colección y comprobar que la copia exportada sigue disponible.

Registra versión de la app, dispositivo, versión de Android, variante/versión de WhatsApp y resultado. No uses los resultados históricos del README como comprobación de una nueva versión.

## Problemas del entorno

| Síntoma | Comprobación |
| --- | --- |
| Dart no satisface `^3.14.0` | Revisa `flutter --version` y el SDK de Flutter activo en `PATH`. |
| Gradle no inicia o Java es incompatible | Revisa el JDK usado por Flutter y las versiones fijadas en los archivos Gradle. |
| No aparece el dispositivo | Ejecuta `flutter doctor -v` y `flutter devices`; comprueba el emulador o la autorización USB. |
| Los scripts no encuentran un ejecutable | Comprueba `ffmpeg -version` y, para X, `ffprobe -version` en la misma terminal. |
| Fallan las capturas de referencia | Inspecciona el diff visual y el entorno antes de regenerar las imágenes. |

## Antes de distribuir

- Validar en Android los flujos anteriores, incluida la incorporación real a WhatsApp.
- Configurar una firma de producción y mantener las claves fuera del repositorio.
- Revisar el identificador de aplicación y actualizar la versión de `pubspec.yaml` cuando corresponda.
- Definir la licencia del código de ShareGIF y revisar licencias y avisos de dependencias, FFmpegKit, componentes nativos y Roboto.
- Preparar la política de privacidad y los metadatos de distribución acordes con el comportamiento real de la app.

La variante declarada de FFmpegKit es `video`, no `full-gpl`. Esto identifica la dependencia; no sustituye una revisión de licencias del binario que se distribuya.
