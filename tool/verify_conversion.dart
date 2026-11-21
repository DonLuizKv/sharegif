// Host-side codec verification. Uses the exact same recipe as the mobile plugin.
// Run: dart run tool/verify_conversion.dart (requires FFmpeg on PATH).
import 'dart:io';

import 'package:sharegif/src/models.dart';

Future<void> main() async {
  final directory = await Directory.systemTemp.createTemp('sharegif_codec_');
  Future<void> run(List<String> args) async {
    final result = await Process.run('ffmpeg', [
      '-hide_banner',
      '-loglevel',
      'error',
      ...args,
    ]);
    if (result.exitCode != 0) throw StateError(result.stderr.toString());
  }

  try {
    for (final extension in ['png', 'jpg', 'webp']) {
      final input = '${directory.path}/source.$extension';
      await run([
        '-y',
        '-f',
        'lavfi',
        '-i',
        'testsrc2=size=800x600',
        '-frames:v',
        '1',
        input,
      ]);
      for (final fit in StickerFit.values) {
        final output = '${directory.path}/${extension}_${fit.name}.webp';
        await run(
          ConversionOptions(
            start: 0,
            end: 0,
            fit: fit,
          ).imageArguments(input: input, output: output, quality: 60),
        );
        final bytes = await File(output).readAsBytes();
        final info = WebpInfo.validate(bytes);
        if (info.isAnimated ||
            info.durationMs != 0 ||
            bytes.length > 100 * 1024) {
          throw StateError('Invalid static sticker');
        }
        stdout.writeln(
          '$extension / ${fit.name}: ${info.width}×${info.height}, ${bytes.length} bytes — OK',
        );
      }
    }
    for (final extension in ['gif', 'mp4']) {
      final input = '${directory.path}/source.$extension';
      await run([
        '-y',
        '-f',
        'lavfi',
        '-i',
        'testsrc2=size=320x180:rate=15:duration=3',
        input,
      ]);
      for (final fit in StickerFit.values) {
        final output = '${directory.path}/${extension}_${fit.name}.webp';
        await run(
          ConversionOptions(
            start: .2,
            end: 2.2,
            fit: fit,
          ).arguments(input: input, output: output, fps: 15, quality: 60),
        );
        final bytes = await File(output).readAsBytes();
        final info = WebpInfo.validate(bytes);
        if ((info.durationMs - 2000).abs() > 100) {
          throw StateError('Wrong trim duration: ${info.durationMs}');
        }
        stdout.writeln(
          '$extension / ${fit.name}: ${info.width}×${info.height}, ${info.frames} frames, ${info.durationMs} ms, ${bytes.length} bytes — OK',
        );
      }
    }
  } finally {
    await directory.delete(recursive: true);
  }
}
