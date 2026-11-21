# ShareGIF

App móvil Flutter para convertir imágenes, GIFs y videos en stickers de WhatsApp. Interfaz en español, almacenamiento privado en el teléfono y conversión local con FFmpeg + libwebp. No hay servidor, cuenta de ShareGIF, analítica ni subida de archivos.

**Plataforma actual: Android.** El código inicial de iOS permanece en el proyecto, pero queda fuera del desarrollo y validación de esta etapa.

## Diseño

- **60 % gris porcelana `#E4E3DE`**: fondo y espacio de descanso.
- **30 % taupe seta `#8B7E71`**: superficies, tarjetas e ilustración.
- **10 % ultra violeta `#6B2BFF`**: acciones y selección.

La proporción es una guía visual aproximada que varía con el contenido y el tamaño de pantalla. Se utilizan tonos derivados oscuros para mantener legibles los textos. Dos destinos: **Crear** y **Mis stickers**. El editor aparece después de importar, para no sobrecargar el inicio.

## Funcionalidad implementada

- Importar PNG, JPG/JPEG, WebP estático, GIF, MP4, MOV, WebM y M4V desde el selector de archivos del sistema, sin permisos generales de almacenamiento.
- Pegar enlaces públicos de X/Twitter, resolver sus fotos, GIFs o videos directamente en X y abrirlos en el editor. Incluye enlaces terminados en `/photo/1`, `/video/1`, versiones móviles e `i/web/status`.
- Pegar hasta 30 enlaces distintos (uno por línea o separados por espacios) y crear los stickers en secuencia. El botón de portapapeles añade los enlaces nuevos a los que ya estaban escritos.
- Al guardar, retirar el enlace completado y abrir el siguiente editor, proponiendo un paquete del mismo tipo mientras tenga espacio. Cancelar o fallar una descarga detiene la tanda y conserva los enlaces pendientes para continuar después.
- Elegir un archivo cuando la publicación contiene varios, o usar el GIF de una publicación citada cuando la principal no tiene medios compatibles. Un enlace a un adjunto concreto siempre conserva esa selección.
- Descargar archivos desde enlaces HTTPS directos, con límites de 50 MB, redirecciones y tiempo de espera.
- Elegir un fragmento de 0,2–10 segundos y conservar la imagen completa con espacio transparente o recortar al centro.
- Convertir a WebP animado de 512 × 512, ajustar calidad y FPS hasta quedar por debajo de 500 KB y validar el contenedor resultante. Conserva transparencias existentes; **no elimina fondos de forma automática**.
- Convertir imágenes a WebP estático de 512 × 512 y hasta 100 KB, con encuadre completo o cuadrado y sin controles de duración. Las imágenes se decodifican localmente con dimensiones acotadas antes de convertirlas.
- Guardar imágenes y animaciones en paquetes separados, incluso al procesar un lote mixto. Los paquetes anteriores se conservan como animados.
- Mostrar el sticker animado antes de guardarlo. La vista anterior a convertir muestra el fotograma inicial y el encuadre; todavía no reproduce el fragmento seleccionado.
- Crear paquetes, guardar stickers de forma persistente, previsualizar y eliminar stickers locales.
- Entregar paquetes de 3–30 stickers a WhatsApp mediante ContentProvider en Android. La confirmación pertenece a WhatsApp; abrirlo no equivale a confirmar una importación.
- Android conserva snapshots de exportación independientes para que editar la colección no rompa paquetes ya compartidos.

## Importación desde X

La app extrae el ID de la publicación y consulta `cdn.syndication.twimg.com/tweet-result`, el endpoint público de publicaciones incrustadas de X. Calcula localmente el parámetro de la consulta y selecciona una variante MP4 de `video.twimg.com`. X entrega sus GIFs como videos MP4; la app conserva la animación al convertirlos a WebP. No usa un proxy, una API de terceros, un backend propio ni cookies de una cuenta.

Este endpoint de X no tiene un contrato público estable. Publicaciones privadas, eliminadas, restringidas o no expuestas en los embeds no se pueden resolver; la app muestra un error específico y permite reintentar. Los límites de consultas también se comunican al usuario. El adaptador está aislado en `x_post_resolver.dart` para poder actualizarlo si X cambia su respuesta. Los archivos y miniaturas resueltos solo se aceptan desde los hosts HTTPS esperados de X. La conversión posterior sigue funcionando sin conexión.

## Ejecutar

Entorno usado: Flutter 3.50.0 / Dart 3.14.0, Java 21. Android mínimo API 24.

```sh
flutter pub get
flutter run
flutter build apk --debug
```

El APK de prueba actualizado, versión **0.1.3+4**, queda en `build/app/outputs/flutter-apk/app-debug.apk`. Si existe un `sharegif-debug.apk` anterior en la carpeta, ese archivo no corresponde a esta actualización.

## Verificación

```sh
flutter analyze
flutter test
dart run tool/verify_conversion.dart
dart run tool/verify_x_import.dart https://x.com/rneoatl/status/2123340238806237233/photo/1
```

Las comprobaciones de `tool/` necesitan FFmpeg en PATH. `verify_conversion.dart` ejecuta la misma receta de conversión usada por la app sobre PNG, JPG, WebP, GIF y MP4 reales, con ambos encuadres. `verify_x_import.dart` usa el mismo resolver y descargador de la app contra una publicación real y convierte el resultado animado. Verifican dimensiones, número de fotogramas, duración y peso con el códec del equipo; no sustituyen las pruebas del plugin en un teléfono Android.

Las pruebas Flutter cubren enlaces inválidos, límites del contenedor WebP, límites de paquetes, persistencia, errores de almacenamiento, navegación, texto ampliado y capturas de la interfaz. Las referencias visuales están en `test/goldens/`.

Comprobaciones de la versión 0.1.3: análisis Dart sin incidencias y 39 pruebas Flutter aprobadas, incluyendo creación secuencial desde varios enlaces, lotes mixtos de imágenes y GIFs, separación y persistencia de tipos de paquetes, decodificación real de PNG, limpieza del enlace después de guardar, conservación de pendientes ante errores/cancelación, selección de fotos de X y capturas de la interfaz. También se verificaron diez conversiones con FFmpeg del equipo (PNG/JPG/WebP/GIF/MP4 × completo/cuadrado). La incorporación final a WhatsApp queda pendiente de validación en un teléfono Android. La compilación muestra un aviso de migración futura de Kotlin en `file_picker`.

La corrección de importación se verificó con el enlace `/rneoatl/status/2123340238806237233/photo/1`: resolución directa, MP4 de 171.202 bytes descargado desde X y WebP válido de 307.974 bytes, 512 × 512, 43 fotogramas y 2.999 ms. Las pruebas adicionales cubren el parámetro de consulta, selección de adjuntos, publicaciones citadas, errores de X, progreso de importación y navegación al editor.

Se verificó un segundo enlace sin selección explícita, `/GIPHY/status/1957913446118285360`: MP4 de 43.468 bytes y WebP válido de 90.550 bytes, 512 × 512, 30 fotogramas y 2.999 ms. Estas comprobaciones usan los mismos archivos Dart de resolución y descarga incluidos en el APK, con FFmpeg del equipo para la etapa de codificación.

Antes de distribuir: probar importación, conversión e incorporación de un paquete en un teléfono Android con WhatsApp instalado; comprobar cancelación y actualización de paquetes; preparar firma de producción, política de privacidad y licencias de distribución. El build Android release todavía usa la firma de desarrollo del scaffold.

## Estructura

- `lib/src/theme.dart`: colores, tipografía e ilustración vectorial.
- `lib/src/app.dart`: inicio, importación y colección.
- `lib/src/editor.dart`: recorte temporal, encuadre y guardado.
- `lib/src/models.dart`: modelos y validación de enlaces / WebP.
- `lib/src/services.dart`: descarga, conversión, persistencia y canal de exportación.
- `lib/src/x_post_resolver.dart`: resolución directa de GIFs/videos públicos de X.
- `lib/src/link_batch.dart`: validación de tandas y eliminación de enlaces repetidos.
- `lib/src/media_downloader.dart`: descarga limitada y archivos parciales con limpieza.
- `android/…/StickerProvider.kt`: contrato Android para WhatsApp y snapshots atómicos.
- `ios/Runner/AppDelegate.swift`: entrega de paquetes en iOS.

Se usa la variante **video** de FFmpegKit, con libwebp y sin los códecs GPL adicionales de la variante full-gpl. Revisar las obligaciones LGPL y las licencias de los componentes nativos antes de distribuir. Roboto incluye su licencia en `assets/fonts/LICENSE.txt`.

## Referencias

- [Requisitos y contrato Android de WhatsApp](https://github.com/WhatsApp/stickers/tree/main/Android)
- [Contrato iOS de WhatsApp](https://github.com/WhatsApp/stickers/tree/main/iOS)
- [Consulta de publicaciones en la API de X](https://docs.x.com/x-api/posts/lookup/introduction)
- [Referencia del endpoint de embeds utilizada por react-tweet](https://github.com/vercel/react-tweet/blob/main/packages/react-tweet/src/api/fetch-tweet.ts)
- [FFmpegKit Video para Flutter](https://pub.dev/packages/ffmpeg_kit_flutter_new_video)
#   s h a r e g i f  
 