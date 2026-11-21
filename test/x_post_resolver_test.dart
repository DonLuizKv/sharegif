import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sharegif/src/models.dart';
import 'package:sharegif/src/x_post_resolver.dart';

const exampleId = '2123340238806237233';
const exampleLink = 'https://x.com/rneoatl/status/$exampleId/photo/1';

Map<String, dynamic> mediaFixture({
  String name = 'HXeerapXgAAOYg8',
  String type = 'animated_gif',
}) => {
  'type': type,
  'media_url_https': 'https://pbs.twimg.com/tweet_video_thumb/$name.jpg',
  'video_info': {
    'variants': [
      {
        'bitrate': 0,
        'content_type': 'video/mp4',
        'url': 'https://video.twimg.com/tweet_video/$name.mp4',
      },
    ],
  },
};

Map<String, dynamic> postFixture({List<Object>? media}) => {
  '__typename': 'Tweet',
  'id_str': exampleId,
  'mediaDetails': media ?? [mediaFixture()],
};

XPostResolver fixtureResolver(Map<String, dynamic> post) =>
    XPostResolver(transport: (_) async => XResponse(200, jsonEncode(post)));

void main() {
  test('embed token matches JavaScript, including IDs beyond double integer precision', () {
    for (final entry in {
      exampleId: '55ao4fysnyb',
      '1957913446118285360': '4quyskynvwd',
      '1790637656616943991': '4c9gcitu1vq',
      '623160978427936768': '1idpugrdw8w',
      '700002208306171904': '1p34duhmw5',
    }.entries) {
      expect(syndicationToken(entry.key), entry.value);
    }
    expect(() => syndicationToken('0'), throwsArgumentError);
  });
  test(
    'user photo/1 link resolves an animated GIF served as MP4, with no proxy',
    () async {
      Uri? requested;
      final resolver = XPostResolver(
        transport: (uri) async {
          requested = uri;
          return XResponse(200, jsonEncode(postFixture()));
        },
      );
      final media = await resolver.resolve(MediaLink.parse(exampleLink));
      expect(requested!.host, 'cdn.syndication.twimg.com');
      expect(requested!.queryParameters['id'], exampleId);
      expect(requested!.queryParameters['token'], '55ao4fysnyb');
      expect(media.single.isGif, true);
      expect(
        media.single.uri.toString(),
        'https://video.twimg.com/tweet_video/HXeerapXgAAOYg8.mp4',
      );
    },
  );
  test('accepts legacy hosts, mobile, i/web/status and selected video', () {
    for (final link in [
      'https://twitter.com/r/status/$exampleId?s=20',
      'https://mobile.x.com/r/status/$exampleId',
      'https://x.com/i/web/status/$exampleId',
      'https://x.com/i/status/$exampleId',
    ]) {
      expect(MediaLink.parse(link).postId, exampleId);
    }
    expect(
      MediaLink.parse('https://x.com/u/status/$exampleId/video/2?x=1')
          .mediaIndex,
      2,
    );
    for (final link in [
      'https://x.com/u/status/0',
      'https://x.com/u/status/$exampleId/photo/0',
      'https://x.com:444/u/status/$exampleId',
      'https://x.com/u/status/$exampleId/anything',
    ]) {
      expect(() => MediaLink.parse(link), throwsA(isA<UserMessage>()));
    }
  });
  test('media indices count photos; explicit index never silently selects another video', () async {
    final resolver = fixtureResolver(
      postFixture(
        media: [
          {'type': 'photo'},
          mediaFixture(name: 'second'),
        ],
      ),
    );
    final selected = await resolver.resolve(
      MediaLink.parse('https://x.com/u/status/$exampleId/photo/2'),
    );
    expect(selected.single.index, 2);
    expect(selected.single.uri.path, endsWith('second.mp4'));
    await expectLater(
      resolver.resolve(MediaLink.parse(exampleLink)),
      throwsA(isA<UserMessage>()),
    );
  });
  test('photo links resolve the selected original image without losing video indices', () async {
    final resolver = fixtureResolver(
      postFixture(
        media: [
          {
            'type': 'photo',
            'media_url_https': 'https://pbs.twimg.com/media/photo.jpg',
          },
          mediaFixture(name: 'second'),
        ],
      ),
    );
    final photo = (await resolver.resolve(MediaLink.parse(exampleLink))).single;
    expect(photo.isImage, true);
    expect(photo.label, 'Imagen 1');
    expect(
      photo.uri.toString(),
      'https://pbs.twimg.com/media/photo.jpg?name=orig',
    );
    final items = await resolver.resolve(
      MediaLink.parse('https://x.com/u/status/$exampleId'),
    );
    expect(items.map((m) => m.index), [1, 2]);
    expect(items.last.isImage, false);
  });
  test(
    'multiple playable attachments remain separate for the selection sheet',
    () async {
      final items = await fixtureResolver(
        postFixture(
          media: [
            mediaFixture(),
            mediaFixture(name: 'second'),
          ],
        ),
      ).resolve(MediaLink.parse('https://x.com/u/status/$exampleId'));
      expect(items.map((m) => m.index), [1, 2]);
    },
  );
  test(
    'selects highest-quality safe MP4, ignoring playlists and untrusted URLs',
    () async {
      final fixture = postFixture(
        media: [
          {
            'type': 'video',
            'video_info': {
              'variants': [
                {
                  'content_type': 'application/x-mpegURL',
                  'url': 'https://video.twimg.com/a.m3u8',
                },
                {
                  'content_type': 'video/mp4',
                  'bitrate': 100,
                  'url': 'https://video.twimg.com/vid/320x180/a.mp4',
                },
                {
                  'content_type': 'video/mp4',
                  'bitrate': 9999999,
                  'url': 'https://evil.example/vid/9999x9999/a.mp4',
                },
                {
                  'content_type': 'video/mp4',
                  'bitrate': 1000,
                  'url': 'https://video.twimg.com/vid/720x720/a.mp4?tag=1',
                },
                {
                  'content_type': 'video/mp4',
                  'bitrate': 9999,
                  'url': 'http://video.twimg.com/vid/1080x1080/a.mp4',
                },
              ],
            },
          },
        ],
      );
      final result = await fixtureResolver(fixture)
          .resolve(MediaLink.parse(exampleLink));
      expect(result.single.uri.path, '/vid/720x720/a.mp4');
    },
  );
  test(
    'falls back to a quoted GIF only when no explicit attachment is selected',
    () async {
      final fixture = postFixture(media: [])..['quoted_tweet'] = postFixture();
      final resolver = fixtureResolver(fixture);
      final result = await resolver.resolve(
        MediaLink.parse('https://x.com/u/status/$exampleId'),
      );
      expect(result.single.fromQuote, true);
      await expectLater(
        resolver.resolve(MediaLink.parse(exampleLink)),
        throwsA(isA<UserMessage>()),
      );
    },
  );
  test('supports the legacy video embed schema', () async {
    final fixture = postFixture(media: [])
      ..['video'] = {
        'contentType': 'gif',
        'variants': [
          {
            'type': 'video/mp4',
            'src': 'https://video.twimg.com/tweet_video/a.mp4',
          },
        ],
      };
    expect(
      (await fixtureResolver(fixture).resolve(MediaLink.parse(exampleLink)))
          .single
          .isGif,
      true,
    );
  });
  test('private, deleted, missing media and malformed responses produce user errors', () async {
    for (final response in [
      const XResponse(429, ''),
      const XResponse(403, ''),
      const XResponse(404, ''),
      const XResponse(503, ''),
      const XResponse(200, '{}'),
      const XResponse(200, '<html>'),
      const XResponse(200, '[]'),
      const XResponse(200, '{"__typename":"TweetTombstone"}'),
      XResponse(200, jsonEncode(postFixture(media: []))),
      XResponse(200, jsonEncode(postFixture()..['id_str'] = '123')),
    ]) {
      final resolver = XPostResolver(transport: (_) async => response);
      await expectLater(
        resolver.resolve(MediaLink.parse(exampleLink)),
        throwsA(isA<UserMessage>()),
      );
    }
  });
}
