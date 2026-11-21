import 'dart:typed_data';

class UserMessage implements Exception {
  const UserMessage(this.message);
  final String message;
  @override
  String toString() => message;
}

class Sticker {
  const Sticker({
    required this.id,
    required this.bytes,
    required this.durationMs,
  });
  final String id;
  final int bytes;
  final int durationMs;
  String get filename => '$id.webp';
  Map<String, dynamic> toJson() => {
    'id': id,
    'bytes': bytes,
    'durationMs': durationMs,
  };
  factory Sticker.fromJson(Map<String, dynamic> json) => Sticker(
    id: json['id'] as String,
    bytes: json['bytes'] as int,
    durationMs: json['durationMs'] as int,
  );
}

class StickerPack {
  const StickerPack({
    required this.id,
    required this.name,
    required this.stickers,
    this.isAnimated = true,
  });
  final String id;
  final String name;
  final List<Sticker> stickers;
  final bool isAnimated;
  bool get canExport => stickers.length >= 3 && stickers.length <= 30;
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'isAnimated': isAnimated,
    'stickers': stickers.map((s) => s.toJson()).toList(),
  };
  factory StickerPack.fromJson(Map<String, dynamic> json) => StickerPack(
    id: json['id'] as String,
    name: json['name'] as String,
    isAnimated: json['isAnimated'] as bool? ?? true,
    stickers: (json['stickers'] as List)
        .map((s) => Sticker.fromJson(s as Map<String, dynamic>))
        .toList(),
  );
}

enum StickerFit { contain, cover }

class ConversionOptions {
  const ConversionOptions({
    required this.start,
    required this.end,
    this.fit = StickerFit.contain,
  });
  final double start;
  final double end;
  final StickerFit fit;
  double get duration => end - start;
  void validate() {
    if (!start.isFinite ||
        !end.isFinite ||
        start < 0 ||
        duration < 0.2 ||
        duration > 10.001) {
      throw const UserMessage('Elige un fragmento de entre 0,2 y 10 segundos.');
    }
  }

  String get imageFilter {
    final sizing = fit == StickerFit.contain
        ? 'scale=512:512:force_original_aspect_ratio=decrease,format=rgba,pad=512:512:(ow-iw)/2:(oh-ih)/2:color=0x00000000'
        : 'scale=512:512:force_original_aspect_ratio=increase,crop=512:512,format=rgba';
    return '$sizing,setsar=1';
  }

  String filter(int fps) => 'fps=$fps,$imageFilter';

  List<String> imageArguments({
    required String input,
    required String output,
    required int quality,
  }) => [
    '-y',
    '-i',
    input,
    '-frames:v',
    '1',
    '-an',
    '-map_metadata',
    '-1',
    '-vf',
    imageFilter,
    '-c:v',
    'libwebp',
    '-lossless',
    '0',
    '-q:v',
    '$quality',
    '-compression_level',
    '6',
    output,
  ];

  List<String> arguments({
    required String input,
    required String output,
    required int fps,
    required int quality,
  }) {
    validate();
    return [
      '-y',
      '-ss',
      start.toStringAsFixed(3),
      '-i',
      input,
      '-t',
      duration.toStringAsFixed(3),
      '-an',
      '-map_metadata',
      '-1',
      '-vf',
      filter(fps),
      '-c:v',
      'libwebp_anim',
      '-lossless',
      '0',
      '-q:v',
      '$quality',
      '-compression_level',
      '6',
      '-loop',
      '0',
      output,
    ];
  }
}

class WebpInfo {
  const WebpInfo(this.width, this.height, this.frames, this.durationMs);
  final int width;
  final int height;
  final int frames;
  final int durationMs;
  bool get isAnimated => frames > 1;

  /// Validate the RIFF container instead of trusting a filename or estimated size.
  static WebpInfo validate(Uint8List bytes) {
    const error = UserMessage(
      'No se pudo crear un sticker compatible. Prueba con otro archivo.',
    );
    if (bytes.length < 30 || bytes.length > 500 * 1024) throw error;
    final data = ByteData.sublistView(bytes);
    String tag(int offset) =>
        String.fromCharCodes(bytes.sublist(offset, offset + 4));
    int u24(int offset) =>
        bytes[offset] | (bytes[offset + 1] << 8) | (bytes[offset + 2] << 16);
    if (tag(0) != 'RIFF' ||
        tag(8) != 'WEBP' ||
        data.getUint32(4, Endian.little) + 8 != bytes.length) {
      throw error;
    }
    int width = 0, height = 0, frames = 0, duration = 0;
    bool animated = false;
    bool stillFrame = false;
    var offset = 12;
    while (offset + 8 <= bytes.length) {
      final size = data.getUint32(offset + 4, Endian.little);
      final payload = offset + 8;
      if (payload + size > bytes.length) throw error;
      if (tag(offset) == 'VP8X' && size >= 10) {
        animated = bytes[payload] & 2 != 0;
        width = u24(payload + 4) + 1;
        height = u24(payload + 7) + 1;
      }
      if (tag(offset) == 'ANMF' && size >= 16) {
        final frameDuration = u24(payload + 12);
        if (frameDuration < 8) throw error;
        frames++;
        duration += frameDuration;
      }
      if (tag(offset) == 'VP8 ' && size >= 10) {
        if (bytes[payload + 3] != 0x9d ||
            bytes[payload + 4] != 0x01 ||
            bytes[payload + 5] != 0x2a) {
          throw error;
        }
        final w = data.getUint16(payload + 6, Endian.little) & 0x3fff;
        final h = data.getUint16(payload + 8, Endian.little) & 0x3fff;
        if (width != 0 && (width != w || height != h)) throw error;
        width = w;
        height = h;
        stillFrame = true;
      }
      if (tag(offset) == 'VP8L' && size >= 5) {
        if (bytes[payload] != 0x2f) throw error;
        final bits = data.getUint32(payload + 1, Endian.little);
        final w = (bits & 0x3fff) + 1;
        final h = ((bits >> 14) & 0x3fff) + 1;
        if (width != 0 && (width != w || height != h)) throw error;
        width = w;
        height = h;
        stillFrame = true;
      }
      offset = payload + size + (size & 1);
    }
    if (offset != bytes.length ||
        width != 512 ||
        height != 512 ||
        (animated
            ? frames < 2 || duration > 10000 || duration < 1 || stillFrame
            : !stillFrame || frames != 0 || bytes.length > 100 * 1024)) {
      throw error;
    }
    return WebpInfo(width, height, animated ? frames : 1, duration);
  }
}

enum LinkKind { xPost, directMedia }

class MediaLink {
  const MediaLink(this.uri, this.kind);
  final Uri uri;
  final LinkKind kind;
  static final _postPath = RegExp(
    r'^/(?:[A-Za-z0-9_]+/status|i/(?:web/)?status)/([0-9]{1,20})(?:/(?:photo|video)/([1-9][0-9]?))?/?$',
  );
  String? get postId =>
      kind == LinkKind.xPost ? _postPath.firstMatch(uri.path)?.group(1) : null;
  int? get mediaIndex {
    final index = kind == LinkKind.xPost
        ? _postPath.firstMatch(uri.path)?.group(2)
        : null;
    return index == null ? null : int.parse(index);
  }

  static MediaLink parse(String input) {
    final uri = Uri.tryParse(input.trim());
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      throw const UserMessage(
        'Pega un enlace HTTPS válido de X, una imagen, un GIF o un video.',
      );
    }
    const xHosts = {
      'x.com',
      'www.x.com',
      'twitter.com',
      'www.twitter.com',
      'mobile.twitter.com',
      'mobile.x.com',
      'm.x.com',
      'm.twitter.com',
    };
    if (xHosts.contains(uri.host.toLowerCase())) {
      if (!_postPath.hasMatch(uri.path) ||
          uri.port != 443 ||
          BigInt.parse(_postPath.firstMatch(uri.path)!.group(1)!) ==
              BigInt.zero) {
        throw const UserMessage(
          'Copia el enlace de una publicación, no el de un perfil.',
        );
      }
      return MediaLink(uri, LinkKind.xPost);
    }
    if (!RegExp(
          r'\.(gif|mp4|mov|webm|m4v|png|jpg|jpeg|webp)$',
          caseSensitive: false,
        ).hasMatch(uri.path) &&
        !(uri.host == 'pbs.twimg.com' &&
            [
              'png',
              'jpg',
              'jpeg',
              'webp',
            ].contains(uri.queryParameters['format']))) {
      throw const UserMessage(
        'Este enlace no apunta a una imagen, GIF o video. Puedes importar el archivo desde tu teléfono.',
      );
    }
    return MediaLink(uri, LinkKind.directMedia);
  }
}
