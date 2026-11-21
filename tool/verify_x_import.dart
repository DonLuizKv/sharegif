// Live network/codec check using the app's resolver, downloader and encoder recipe.
// dart run tool/verify_x_import.dart https://x.com/user/status/id/photo/1
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:sharegif/src/media_downloader.dart';
import 'package:sharegif/src/models.dart';
import 'package:sharegif/src/x_post_resolver.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.isEmpty) throw ArgumentError('Provide a public X post URL');
  final job = await Directory.systemTemp.createTemp('sharegif_x_import_');
  try {
    final link = MediaLink.parse(arguments.first);
    final media = await XPostResolver().resolve(link);
    stdout.writeln('Resolved ${link.postId}: ${media.length} media item(s)');
    final selected = media.first;
    final input = File('${job.path}/source.mp4');
    await MediaDownloader().download(selected.uri, input);
    stdout.writeln(
      'Downloaded ${selected.isGif ? 'animated GIF (MP4)' : 'video'}: ${await input.length()} bytes from ${selected.uri.host}',
    );
    final probe = await Process.run('ffprobe', [
      '-v',
      'error',
      '-show_format',
      '-show_streams',
      '-of',
      'json',
      input.path,
    ]);
    if (probe.exitCode != 0) throw StateError(probe.stderr.toString());
    final info = jsonDecode(probe.stdout as String) as Map<String, dynamic>;
    final duration = double.parse(info['format']['duration'] as String);
    final output = File('${job.path}/sticker.webp');
    final options = ConversionOptions(start: 0, end: min(3, duration));
    final encoded = await Process.run('ffmpeg', [
      '-hide_banner',
      '-loglevel',
      'error',
      ...options.arguments(
        input: input.path,
        output: output.path,
        fps: 15,
        quality: 60,
      ),
    ]);
    if (encoded.exitCode != 0) throw StateError(encoded.stderr.toString());
    final webp = WebpInfo.validate(await output.readAsBytes());
    stdout.writeln(
      'VALID STICKER: ${webp.width}x${webp.height}, ${webp.frames} frames, ${webp.durationMs} ms, ${await output.length()} bytes',
    );
  } finally {
    await job.delete(recursive: true);
  }
}
