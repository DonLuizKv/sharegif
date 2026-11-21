# Guía de uso

[Volver al README](../README.md)

ShareGIF tiene dos destinos: **Crear** para importar y editar, y **Mis stickers** para consultar los paquetes guardados. Android es la plataforma de desarrollo actual.

## Importar un archivo

Pulsa **Importar imagen, GIF o video** y elige un archivo con el selector del sistema. La app no solicita acceso general al almacenamiento y trabaja sobre una copia temporal del archivo seleccionado.

| Entrada | Formatos o límites implementados |
| --- | --- |
| Imágenes estáticas | PNG, JPG/JPEG y WebP estático. |
| Animaciones y videos | GIF, MP4, MOV, WebM y M4V; la lectura depende del contenido y del códec. |
| Tamaño de entrada | Hasta 50 × 1024 × 1024 bytes, indicado como 50 MB en la interfaz. |
| Duración de origen animado | Entre 0,2 segundos y 10 minutos. |
| Fragmento para el sticker | Entre 0,2 y 10 segundos, dentro de la duración del archivo. |

La extensión por sí sola no garantiza que un archivo se pueda decodificar. Las imágenes de un solo fotograma se editan sin controles de duración.

## Importar enlaces

Pega un enlace HTTPS en el campo de **Crear** y pulsa **Continuar con enlace**. Puedes usar el botón de portapapeles para añadir enlaces a los que ya tienes escritos.

Se admiten:

- Publicaciones de `x.com` y `twitter.com`, incluidas sus variantes móviles y las rutas `/i/status/…` e `/i/web/status/…`.
- Enlaces a un adjunto específico de una publicación, terminados en `/photo/1`, `/video/2`, etc.
- Enlaces HTTPS directos cuya ruta termina en una extensión admitida; también imágenes de `pbs.twimg.com` con un parámetro `format` compatible.

Los enlaces a perfiles, páginas web que contienen un video y URLs HTTP no son entradas válidas. Si tienes el archivo en el teléfono, puedes importarlo con el selector.

### Publicaciones de X

Si hay varios medios compatibles, ShareGIF permite elegir uno. Un enlace a un adjunto concreto conserva esa selección. Sin selección explícita, si la publicación principal no tiene medios compatibles, puede usar los de una publicación citada.

Los GIFs de X se descargan como MP4 y se convierten conservando la animación. No hace falta iniciar sesión en X dentro de ShareGIF. Las publicaciones privadas, eliminadas, restringidas o no disponibles en los datos públicos de X pueden fallar. La disponibilidad de esta función depende del servicio de X.

### Tandas de enlaces

1. Pega hasta 30 enlaces distintos, separados por espacios o saltos de línea.
2. La app valida toda la tanda antes de descargar y elimina duplicados. Para X, reconoce la misma publicación aunque cambie el dominio o sus parámetros de seguimiento; los adjuntos específicos se distinguen entre sí.
3. Edita el primer archivo y pulsa **Guardar y continuar** para abrir el siguiente.
4. Cada enlace se retira del campo solo después de guardar su sticker correctamente.

Cancelar la selección, salir del editor sin guardar o encontrar un error detiene la tanda. Los enlaces pendientes permanecen en el campo para reintentarlos durante la sesión; no hay una cola persistente garantizada tras cerrar la app. Una publicación con varios medios no importa automáticamente todos sus adjuntos.

## Editar y guardar

**Completo** conserva todo el contenido y rellena el espacio sobrante con transparencia. **Cuadrado** llena el sticker recortando desde el centro. No hay eliminación automática del fondo ni posicionamiento manual del recorte.

Antes de convertir, la vista previa muestra el fotograma inicial y el encuadre; no reproduce el fragmento seleccionado. Después de pulsar **Crear sticker**, puedes revisar el resultado animado y usar **Volver a ajustar** si necesitas cambios.

| Resultado | Límite de la app |
| --- | --- |
| Dimensiones | 512 × 512 píxeles. |
| Sticker estático | WebP de hasta 100 × 1024 bytes. |
| Sticker animado | WebP de hasta 500 × 1024 bytes y 10 segundos. |
| Audio | No se conserva. |
| Paquete | Hasta 30 stickers del mismo tipo; al menos 3 para exportar. |
| Colección | Hasta 10 paquetes. |
| Nombre del paquete | Entre 1 y 60 caracteres, tras quitar espacios de los extremos. |

Elige un paquete existente o crea uno. Solo aparecen paquetes con espacio y del mismo tipo: imágenes y animaciones se guardan por separado. En una tanda, la app propone el último paquete usado si sigue siendo compatible y tiene espacio; en caso contrario, busca otro compatible.

## Añadir a WhatsApp

En **Mis stickers**, abre un paquete con al menos tres stickers y pulsa la acción para añadirlo a WhatsApp. La integración Android busca WhatsApp y, si no está instalado, WhatsApp Business. Si tienes ambos, prioriza WhatsApp.

Confirma la incorporación dentro de WhatsApp. Abrir esa aplicación no equivale a completar la importación. Este flujo todavía requiere validación final en un teléfono Android.

Toca un sticker guardado para verlo o **Eliminar de mi colección**. Al eliminar el último sticker, el paquete desaparece de la colección. La exportación usa una copia independiente: borrar un sticker local no es una orden de borrado en WhatsApp. Para compartir cambios de un paquete, vuelve a exportarlo y verifica el resultado en WhatsApp.

## Datos y privacidad

La colección está en el almacenamiento privado de ShareGIF. No hay cuenta, sincronización ni copia de seguridad propia; el manifiesto Android desactiva el backup de la aplicación. Borrar sus datos o desinstalarla elimina la colección local.

La conversión no requiere conexión. Para importar enlaces, el teléfono sí se conecta a X o al servidor del archivo, que recibe la solicitud de descarga. No se usan cookies de una cuenta de X ni un proxy propio. La app lee el portapapeles cuando pulsas su botón de pegar.

## Problemas habituales

| Problema | Qué hacer |
| --- | --- |
| El enlace no es válido | Usa HTTPS y el enlace de la publicación o del archivo, no el de un perfil. |
| X limita las consultas | Espera y vuelve a intentarlo, o importa un archivo del teléfono. |
| La publicación no está disponible | Prueba una publicación pública accesible sin iniciar sesión. |
| El archivo supera los 50 MB | Reduce el archivo antes de importarlo. |
| La duración de origen no es compatible | Usa una animación de entre 0,2 segundos y 10 minutos. |
| El sticker todavía pesa demasiado | Acorta el fragmento; para imágenes, prueba otro encuadre o archivo. |
| No aparece un paquete para guardar | Comprueba que tenga espacio y sea del mismo tipo que el sticker. |
| No puedes crear otro paquete | El límite es 10; usa uno compatible o elimina los stickers de un paquete que ya no necesites. |
| No puedes añadir el paquete a WhatsApp | Guarda al menos tres stickers y comprueba que WhatsApp esté instalado. |
| Error al guardar | Revisa el espacio disponible y reintenta antes de cerrar el editor. |

Para reportar un problema reproducible, consulta [Contribuir](../CONTRIBUTING.md).
