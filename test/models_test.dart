import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sharegif/src/models.dart';

// Minimal container fixture: payload decoding is tested with real FFmpeg output
// in tool/verify_conversion.dart; these tests exercise container boundaries.
Uint8List container({
  int width = 512,
  int height = 512,
  List<int> durations = const [100, 100],
}) {
  final bytes = BytesBuilder();
  void chunk(String tag, List<int> payload) {
    bytes.add(tag.codeUnits);
    bytes.add(
      (ByteData(
        4,
      )..setUint32(0, payload.length, Endian.little)).buffer.asUint8List(),
    );
    bytes.add(payload);
    if (payload.length.isOdd) bytes.addByte(0);
  }

  List<int> u24(int value) => [
    value & 255,
    (value >> 8) & 255,
    (value >> 16) & 255,
  ];
  chunk('VP8X', [2, 0, 0, 0, ...u24(width - 1), ...u24(height - 1)]);
  chunk('ANIM', [0, 0, 0, 0, 0, 0]);
  for (final duration in durations) {
    chunk('ANMF', [...List.filled(12, 0), ...u24(duration), 0]);
  }
  final body = bytes.takeBytes();
  return Uint8List.fromList([
    ...('RIFF'.codeUnits),
    ...(ByteData(
      4,
    )..setUint32(0, body.length + 4, Endian.little)).buffer.asUint8List(),
    ...('WEBP'.codeUnits),
    ...body,
  ]);
}

Uint8List staticContainer({int size = 30, int width = 512, int height = 512}) {
  final bytes = Uint8List(size);
  final data = ByteData.sublistView(bytes);
  bytes.setRange(0, 4, 'RIFF'.codeUnits);
  data.setUint32(4, size - 8, Endian.little);
  bytes.setRange(8, 12, 'WEBP'.codeUnits);
  bytes.setRange(12, 16, 'VP8 '.codeUnits);
  data.setUint32(16, size - 20, Endian.little);
  bytes.setRange(23, 26, [0x9d, 0x01, 0x2a]);
  data.setUint16(26, width, Endian.little);
  data.setUint16(28, height, Endian.little);
  return bytes;
}

void main() {
  test('static WebP enforces dimensions and its own 100 KB limit', () {
    final info = WebpInfo.validate(staticContainer());
    expect(info.isAnimated, false);
    expect(info.frames, 1);
    expect(info.durationMs, 0);
    for (final bytes in [
      staticContainer(size: 102402),
      staticContainer(width: 511),
    ]) {
      expect(() => WebpInfo.validate(bytes), throwsA(isA<UserMessage>()));
    }
  });
  test('legacy packs remain animated and static pack type survives JSON', () {
    expect(
      StickerPack.fromJson({'id': 'old', 'name': 'Old', 'stickers': []})
          .isAnimated,
      true,
    );
    const pack = StickerPack(
      id: 'new',
      name: 'Images',
      stickers: [],
      isAnimated: false,
    );
    expect(StickerPack.fromJson(pack.toJson()).isAnimated, false);
  });
  test('image URLs accept supported extensions and X CDN format queries', () {
    for (final url in [
      'https://example.org/photo.JPG',
      'https://example.org/photo.png',
      'https://example.org/photo.webp',
      'https://pbs.twimg.com/media/photo?format=jpg&name=orig',
    ]) {
      expect(MediaLink.parse(url).kind, LinkKind.directMedia);
    }
  });
  group('Media links', () {
    test('accepts X, legacy Twitter and direct CDN video with query', () {
      for (final url in [
        'https://x.com/user/status/123?s=20',
        'https://twitter.com/user/status/123',
        'https://x.com/i/status/123',
      ]) {
        expect(MediaLink.parse(url).kind, LinkKind.xPost);
      }
      expect(
        MediaLink.parse('https://video.twimg.com/a/video.mp4?tag=1').kind,
        LinkKind.directMedia,
      );
    });
    test(
      'rejects profiles, lookalike hosts, credentials and unsafe schemes',
      () {
        for (final url in [
          '',
          'http://x.com/u/status/1',
          'https://x.com/user',
          'https://x.com.evil.test/u/status/1',
          'https://u:p@host/file.gif',
          'file:///video.mp4',
        ]) {
          expect(() => MediaLink.parse(url), throwsA(isA<UserMessage>()));
        }
      },
    );
  });
  test('invalid trim boundaries fail before invoking the encoder', () {
    for (final options in [
      const ConversionOptions(start: -1, end: 2),
      const ConversionOptions(start: 0, end: 11),
      const ConversionOptions(start: 2, end: 1),
      const ConversionOptions(start: 0, end: double.infinity),
    ]) {
      expect(options.validate, throwsA(isA<UserMessage>()));
    }
    expect(
      const ConversionOptions(start: 5, end: 15).validate,
      returnsNormally,
    );
  });
  test('valid animated WebP reports dimensions and exact duration', () {
    final info = WebpInfo.validate(container());
    expect(info.width, 512);
    expect(info.frames, 2);
    expect(info.durationMs, 200);
  });
  test(
    'rejects wrong dimensions, still images, short frames, and long animations',
    () {
      for (final bytes in [
        container(width: 511),
        container(durations: [100]),
        container(durations: [7, 100]),
        container(durations: [5001, 5001]),
        Uint8List(512001),
      ]) {
        expect(() => WebpInfo.validate(bytes), throwsA(isA<UserMessage>()));
      }
    },
  );
  test('rejects truncated RIFF, oversized chunks and trailing bytes', () {
    final bytes = container();
    expect(
      () => WebpInfo.validate(bytes.sublist(0, bytes.length - 1)),
      throwsA(isA<UserMessage>()),
    );
    final corrupt = Uint8List.fromList(bytes);
    ByteData.sublistView(corrupt).setUint32(16, 0xffffffff, Endian.little);
    expect(() => WebpInfo.validate(corrupt), throwsA(isA<UserMessage>()));
    expect(
      () => WebpInfo.validate(Uint8List.fromList([...bytes, 0])),
      throwsA(isA<UserMessage>()),
    );
  });
  test(
    'pack export requires 3 to 30 stickers and metadata survives round trip',
    () {
      const sticker = Sticker(id: 'test', bytes: 100, durationMs: 200);
      for (final count in [0, 1, 2, 31]) {
        expect(
          StickerPack(
            id: 'a',
            name: 'Reacciones',
            stickers: List.filled(count, sticker),
          ).canExport,
          false,
        );
      }
      final pack = StickerPack(
        id: 'a',
        name: 'Reacciones',
        stickers: List.filled(3, sticker),
      );
      expect(pack.canExport, true);
      expect(
        StickerPack.fromJson(pack.toJson()).stickers.first.durationMs,
        200,
      );
    },
  );
}
