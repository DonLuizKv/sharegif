import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'models.dart';

class XMedia {
  const XMedia({
    required this.uri,
    required this.index,
    required this.isGif,
    this.poster,
    this.fromQuote = false,
    this.isImage = false,
  });
  final Uri uri;
  final int index;
  final bool isGif;
  final Uri? poster;
  final bool fromQuote;
  final bool isImage;
  String get label =>
      '${isImage
          ? 'Imagen'
          : isGif
          ? 'GIF'
          : 'Video'} $index${fromQuote ? ' · Publicación citada' : ''}';
}

class XResponse {
  const XResponse(this.status, this.body);
  final int status;
  final String body;
}

typedef XTransport = Future<XResponse> Function(Uri uri);

/// Reads X's public embed data directly. No account cookies, proxy, or backend.
/// This is an undocumented endpoint; keep its schema handling isolated here.
class XPostResolver {
  XPostResolver({XTransport? transport}) : _transport = transport ?? _request;
  final XTransport _transport;

  Future<List<XMedia>> resolve(MediaLink link) async {
    final id = link.postId;
    if (link.kind != LinkKind.xPost || id == null) {
      throw const UserMessage('Copia el enlace de una publicación de X.');
    }
    final response = await _transport(
      Uri.https('cdn.syndication.twimg.com', '/tweet-result', {
        'id': id,
        'lang': 'es',
        'token': syndicationToken(id),
      }),
    );
    if (response.status == 429) {
      throw const UserMessage(
        'X está limitando las consultas. Espera un momento y vuelve a intentarlo.',
      );
    }
    if ([401, 403, 404].contains(response.status)) {
      throw const UserMessage(
        'X no permite consultar esta publicación sin iniciar sesión, o ya no está disponible. Prueba con una publicación pública.',
      );
    }
    if (response.status != 200) {
      throw const UserMessage(
        'X no respondió correctamente. Inténtalo de nuevo en un momento.',
      );
    }
    Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      throw const UserMessage(
        'No pudimos leer la respuesta de X. Inténtalo de nuevo.',
      );
    }
    if (decoded is! Map<String, dynamic>) {
      throw const UserMessage(
        'No pudimos leer la respuesta de X. Inténtalo de nuevo.',
      );
    }
    if (decoded.isEmpty || decoded['__typename'] == 'TweetTombstone') {
      throw const UserMessage(
        'X no expone esta publicación públicamente. Puede haberse eliminado o requerir iniciar sesión.',
      );
    }
    if (decoded['id_str'] != id) {
      throw const UserMessage(
        'X devolvió una publicación distinta. Copia el enlace de nuevo.',
      );
    }
    final own = _media(decoded);
    final selected = link.mediaIndex;
    if (selected != null) {
      final exact = own.where((media) => media.index == selected).toList();
      if (exact.isNotEmpty) return exact;
      throw const UserMessage(
        'El archivo seleccionado no está disponible para descargar. Prueba con el enlace de la publicación completa.',
      );
    }
    if (own.isNotEmpty) return own;
    final quote = decoded['quoted_tweet'];
    if (quote is Map<String, dynamic>) {
      final quoted = _media(quote, fromQuote: true);
      if (quoted.isNotEmpty) return quoted;
    }
    throw const UserMessage(
      'Esta publicación no contiene imágenes, GIFs o videos que X permita descargar. Prueba con otra publicación.',
    );
  }

  static List<XMedia> _media(
    Map<String, dynamic> post, {
    bool fromQuote = false,
  }) {
    final result = <XMedia>[];
    final details = post['mediaDetails'];
    if (details is List && details.isNotEmpty) {
      for (var i = 0; i < details.length; i++) {
        final item = details[i];
        if (item is Map && item['type'] == 'photo') {
          final photo = _trustedUri(item['media_url_https'], 'pbs.twimg.com');
          if (photo != null) {
            result.add(
              XMedia(
                uri: photo.replace(
                  queryParameters: {...photo.queryParameters, 'name': 'orig'},
                ),
                index: i + 1,
                isGif: false,
                isImage: true,
                poster: photo,
                fromQuote: fromQuote,
              ),
            );
          }
          continue;
        }
        if (item is! Map || !['animated_gif', 'video'].contains(item['type'])) {
          continue;
        }
        final info = item['video_info'];
        final uri = _variant(info is Map ? info['variants'] : null);
        if (uri != null) {
          result.add(
            XMedia(
              uri: uri,
              index: i + 1,
              isGif: item['type'] == 'animated_gif',
              poster: _trustedUri(item['media_url_https'], 'pbs.twimg.com'),
              fromQuote: fromQuote,
            ),
          );
        }
      }
      return result;
    }
    // Older embed responses expose one clip in `video` instead of mediaDetails.
    final video = post['video'];
    if (video is Map) {
      final uri = _variant(video['variants']);
      if (uri != null) {
        result.add(
          XMedia(
            uri: uri,
            index: 1,
            isGif: video['contentType'] == 'gif',
            poster: _trustedUri(video['poster'], 'pbs.twimg.com'),
            fromQuote: fromQuote,
          ),
        );
      }
    }
    return result;
  }

  static Uri? _trustedUri(Object? value, String host) {
    if (value is! String) return null;
    final uri = Uri.tryParse(value);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host != host ||
        uri.port != 443 ||
        uri.userInfo.isNotEmpty) {
      return null;
    }
    return uri;
  }

  static Uri? _variant(Object? value) {
    if (value is! List) return null;
    final variants = <({Uri uri, int bitrate, int pixels})>[];
    for (final variant in value) {
      if (variant is! Map ||
          (variant['content_type'] ?? variant['type']) != 'video/mp4') {
        continue;
      }
      final uri = _trustedUri(
        variant['url'] ?? variant['src'],
        'video.twimg.com',
      );
      if (uri == null || !uri.path.endsWith('.mp4')) continue;
      final dimensions = RegExp(r'/(\d+)x(\d+)/').firstMatch(uri.path);
      final pixels = dimensions == null
          ? 0
          : (int.tryParse(dimensions[1]!) ?? 0) *
                (int.tryParse(dimensions[2]!) ?? 0);
      final bitrate = variant['bitrate'];
      variants.add((
        uri: uri,
        bitrate: bitrate is num ? bitrate.toInt() : 0,
        pixels: pixels,
      ));
    }
    variants.sort((a, b) {
      final byPixels = b.pixels.compareTo(a.pixels);
      return byPixels == 0 ? b.bitrate.compareTo(a.bitrate) : byPixels;
    });
    return variants.firstOrNull?.uri;
  }

  static Future<XResponse> _request(Uri uri) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    Future<XResponse> read() async {
      final request = await client.getUrl(uri);
      request.followRedirects = false;
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers.set(
        HttpHeaders.userAgentHeader,
        'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 Chrome/131.0.0.0 Mobile Safari/537.36',
      );
      final response = await request.close();
      if (response.statusCode != 200) return XResponse(response.statusCode, '');
      const maxBytes = 2 * 1024 * 1024;
      if (response.contentLength > maxBytes) {
        throw const UserMessage(
          'La respuesta de X es demasiado grande. Prueba otra publicación.',
        );
      }
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in response) {
        if (bytes.length + chunk.length > maxBytes) {
          throw const UserMessage(
            'La respuesta de X es demasiado grande. Prueba otra publicación.',
          );
        }
        bytes.add(chunk);
      }
      return XResponse(response.statusCode, utf8.decode(bytes.takeBytes()));
    }

    try {
      return await read().timeout(const Duration(seconds: 30));
    } finally {
      client.close(force: true);
    }
  }
}

/// Matches the base-36 JavaScript number used by X's embeds:
/// ((Number(id) / 1e15) * Math.PI).toString(36).replace(/(0+|\.)/g, '').
/// Half an ULP bounds fractional digits, including the final rounding carry.
String syndicationToken(String id) {
  if (!RegExp(r'^[0-9]{1,20}$').hasMatch(id) ||
      BigInt.parse(id) == BigInt.zero) {
    throw ArgumentError.value(id, 'id', 'Expected a positive X post ID');
  }
  final value = double.parse(id) / 1e15 * pi;
  final bits = ByteData(8)..setFloat64(0, value);
  final next = ByteData(8)..setUint64(0, bits.getUint64(0) + 1);
  var tolerance = (next.getFloat64(0) - value) / 2;
  var whole = value.floor();
  var fraction = value - whole;
  final digits = <int>[];
  while (fraction >= tolerance) {
    fraction *= 36;
    tolerance *= 36;
    final digit = fraction.floor();
    digits.add(digit);
    fraction -= digit;
    if ((fraction > .5 || (fraction == .5 && digit.isOdd)) &&
        fraction + tolerance > 1) {
      var last = digits.length - 1;
      while (last >= 0 && digits[last] == 35) {
        digits.removeLast();
        last--;
      }
      if (last < 0) {
        whole++;
      } else {
        digits[last]++;
      }
      break;
    }
  }
  return '${whole.toRadixString(36)}${digits.map((digit) => digit.toRadixString(36)).join()}'
      .replaceAll('0', '');
}
