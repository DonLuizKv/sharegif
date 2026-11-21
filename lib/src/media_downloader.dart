import 'dart:async';
import 'dart:io';

import 'models.dart';

/// Shared by the Android import flow and the live-link verification tool.
class MediaDownloader {
  static const maxBytes = 50 * 1024 * 1024;

  Future<void> download(Uri uri, File destination) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20);
    final partial = File('${destination.path}.part');
    var timedOut = false;
    final deadline = Timer(const Duration(minutes: 2), () {
      timedOut = true;
      client.close(force: true);
    });
    try {
      var current = uri;
      HttpClientResponse? response;
      for (var redirect = 0; redirect < 5; redirect++) {
        if (current.scheme != 'https' || current.userInfo.isNotEmpty) {
          throw const UserMessage(
            'El enlace debe usar una conexión HTTPS segura.',
          );
        }
        final request = await client.getUrl(current);
        request.followRedirects = false;
        response = await request.close().timeout(const Duration(seconds: 30));
        if ([301, 302, 303, 307, 308].contains(response.statusCode)) {
          final location = response.headers.value(HttpHeaders.locationHeader);
          if (location == null) {
            throw const UserMessage('El enlace no está disponible.');
          }
          current = current.resolve(location);
          await response.drain<void>().timeout(const Duration(seconds: 10));
          response = null;
          continue;
        }
        break;
      }
      if (response == null || response.statusCode != 200) {
        throw const UserMessage(
          'No se pudo descargar el archivo. Vuelve a intentarlo con el enlace de la publicación.',
        );
      }
      if (response.contentLength > maxBytes) {
        throw const UserMessage('El archivo supera los 50 MB.');
      }
      final sink = partial.openWrite();
      var total = 0;
      try {
        await for (final chunk in response.timeout(
          const Duration(seconds: 30),
        )) {
          total += chunk.length;
          if (total > maxBytes) {
            throw const UserMessage('El archivo supera los 50 MB.');
          }
          sink.add(chunk);
        }
        await sink.flush();
      } finally {
        await sink.close();
      }
      if (total == 0) {
        throw const UserMessage(
          'X devolvió un archivo vacío. Prueba otra publicación.',
        );
      }
      await partial.rename(destination.path);
    } catch (_) {
      if (timedOut) {
        throw const UserMessage(
          'La descarga tardó demasiado. Inténtalo de nuevo.',
        );
      }
      rethrow;
    } finally {
      deadline.cancel();
      client.close(force: true);
      if (await partial.exists()) await partial.delete();
    }
  }
}
