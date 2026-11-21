import 'models.dart';

class PendingLink {
  const PendingLink(this.source, this.media);
  final String source;
  final MediaLink media;

  /// Validate the entire batch before downloading anything. Tracking parameters
  /// and X/Twitter host aliases must not create accidental duplicate stickers.
  static List<PendingLink> parseBatch(String input) {
    final sources = input.trim().split(RegExp(r'\s+'));
    final result = <PendingLink>[];
    final seen = <String>{};
    for (var index = 0; index < sources.length; index++) {
      final source = sources[index];
      late final MediaLink media;
      try {
        media = MediaLink.parse(source);
      } on UserMessage catch (error) {
        throw UserMessage(
          sources.length == 1
              ? error.message
              : 'Enlace ${index + 1}: ${error.message}',
        );
      }
      final key = media.kind == LinkKind.xPost
          ? 'x:${media.postId}:${media.mediaIndex ?? 'all'}'
          : media.uri.toString();
      if (seen.add(key)) result.add(PendingLink(source, media));
    }
    if (result.length > 30) {
      throw const UserMessage(
        'Puedes crear hasta 30 stickers por tanda. Divide los enlaces en grupos más pequeños.',
      );
    }
    return result;
  }
}
