# Contribuir a ShareGIF

Gracias por ayudar a mejorar ShareGIF. La documentación y la interfaz se mantienen en español. Android es la plataforma de desarrollo actual; cualquier cambio para iOS debe indicar expresamente cómo se ha validado.

## Preparar un cambio

1. Sigue la [guía de desarrollo](docs/DESARROLLO.md) y reproduce el comportamiento que quieres cambiar.
2. Crea una rama desde `main` con un nombre descriptivo.
3. Mantén el cambio centrado en su objetivo. Actualiza la documentación si modificas formatos, límites, comandos o comportamiento visible.
4. Ejecuta las comprobaciones que correspondan y describe sus resultados en la propuesta.

Para cambios Dart o Flutter:

```sh
dart format lib test tool
flutter analyze
flutter test
```

Añade o ajusta pruebas cuando cambie un comportamiento verificable. Si modificas conversión, ejecuta también `dart run tool/verify_conversion.dart`; si cambias la integración nativa, compila y prueba el flujo en Android. Consulta los requisitos de cada comprobación en [Desarrollo y verificación](docs/DESARROLLO.md#verificación).

Para cambios solo de documentación, revisa los enlaces relativos, comandos, rutas y afirmaciones frente al código. No hacen falta nuevas pruebas de aplicación si no cambia su comportamiento.

## Describir la propuesta

Explica el problema, el resultado esperado y cómo verificaste el cambio. Incluye capturas cuando haya cambios visuales e identifica las comprobaciones que no pudiste ejecutar. Si actualizas referencias de `test/goldens/`, revisa las imágenes antes de incluirlas.

No incluyas APKs, archivos temporales, claves de firma, credenciales, rutas locales de SDK ni cambios accidentales en dependencias. No añadas una licencia al proyecto sin una decisión del titular del código.

## Reportar un error

Abre una incidencia en [GitHub Issues](https://github.com/DonLuizKv/sharegif/issues) con:

- Versión de ShareGIF, dispositivo y versión de Android.
- Pasos mínimos para reproducirlo, resultado esperado y resultado observado.
- Formato, peso y duración aproximada del archivo, si corresponde.
- Mensaje de error y captura o registro relevante, sin información privada.
- Variante y versión de WhatsApp si falla la exportación.

Para errores de X, indica si falla la resolución, descarga o conversión. Comparte un enlace público solo si es apropiado; no publiques archivos privados ni credenciales. La disponibilidad de una publicación puede cambiar sin que cambie ShareGIF.

## Mantener la documentación

El [README](README.md) es la entrada al proyecto. Usa [USO.md](docs/USO.md) para los flujos de la app, [DESARROLLO.md](docs/DESARROLLO.md) para entorno y comprobaciones, y [ARQUITECTURA.md](docs/ARQUITECTURA.md) para decisiones y responsabilidades internas.

Comprueba las versiones contra `pubspec.yaml` y Gradle. Distingue entre comportamiento implementado, prueba automatizada y validación en dispositivo. Evita presentar recuentos históricos de pruebas o descargas antiguas como evidencia de la versión actual.
