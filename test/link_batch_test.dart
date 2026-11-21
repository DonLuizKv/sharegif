import 'package:flutter_test/flutter_test.dart';
import 'package:sharegif/src/link_batch.dart';
import 'package:sharegif/src/models.dart';

void main() {
  test('accepts multiple lines or spaces and preserves order', () {
    final batch = PendingLink.parseBatch(
      ' https://x.com/a/status/123/photo/1\n\nhttps://x.com/b/status/456  https://cdn.example/a.gif ',
    );
    expect(batch.map((item) => item.media.postId), ['123', '456', null]);
    expect(batch.last.media.kind, LinkKind.directMedia);
  });
  test(
    'deduplicates X aliases and tracking but keeps different attachments',
    () {
      final batch = PendingLink.parseBatch(
        'https://x.com/a/status/123?s=20\nhttps://twitter.com/a/status/123\nhttps://x.com/a/status/123/photo/1\nhttps://x.com/a/status/123/video/2',
      );
      expect(batch.length, 3);
      expect(batch.map((item) => item.media.mediaIndex), [null, 1, 2]);
    },
  );
  test('rejects the whole batch with the invalid link position', () {
    expect(
      () => PendingLink.parseBatch('https://x.com/a/status/123\ninvalid'),
      throwsA(
        isA<UserMessage>().having(
          (e) => e.message,
          'message',
          startsWith('Enlace 2:'),
        ),
      ),
    );
    expect(() => PendingLink.parseBatch('  '), throwsA(isA<UserMessage>()));
  });
  test('allows up to 30 distinct links', () {
    String links(int count) => List.generate(
      count,
      (index) => 'https://x.com/a/status/${index + 1}',
    ).join('\n');
    expect(PendingLink.parseBatch(links(30)).length, 30);
    expect(
      () => PendingLink.parseBatch(links(31)),
      throwsA(isA<UserMessage>()),
    );
  });
}
