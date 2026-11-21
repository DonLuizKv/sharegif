import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:ffmpeg_kit_flutter_new_video/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_video/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new_video/return_code.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'models.dart';
import 'media_downloader.dart';
import 'x_post_resolver.dart';

String newId() =>
    '${DateTime.now().microsecondsSinceEpoch}_${Random.secure().nextInt(1 << 32)}';

class ImportedMedia {
  const ImportedMedia(
    this.file,
    this.thumbnail,
    this.duration, {
    this.isAnimated = true,
  });
  final File file;
  final File thumbnail;
  final double duration;
  final bool isAnimated;
  Future<void> dispose() async {
    if (await file.parent.exists()) await file.parent.delete(recursive: true);
  }
}

class ConvertedSticker {
  const ConvertedSticker(this.file, this.tray, this.info);
  final File file;
  final File tray;
  final WebpInfo info;
}

class MediaService {
  MediaService({XPostResolver? xResolver})
    : _xResolver = xResolver ?? XPostResolver();
  final XPostResolver _xResolver;
  static const maxInputBytes = 50 * 1024 * 1024;

  Future<ImportedMedia?> importLink(
    MediaLink link, {
    required void Function(String) onProgress,
    required Future<XMedia?> Function(List<XMedia>) chooseMedia,
  }) async {
    var uri = link.uri;
    if (link.kind == LinkKind.xPost) {
      onProgress('Buscando el archivo en X…');
      final media = await _xResolver.resolve(link);
      final selected = media.length == 1
          ? media.single
          : await chooseMedia(media);
      if (selected == null) return null;
      uri = selected.uri;
    }
    onProgress('Descargando archivo…');
    return download(uri, onProgress: onProgress);
  }

  Future<Directory> _job() async => Directory(
    p.join((await getTemporaryDirectory()).path, 'sharegif', newId()),
  ).create(recursive: true);

  Future<ImportedMedia> importFile(String path) async {
    final source = File(path);
    if (await source.length() > maxInputBytes) {
      throw const UserMessage(
        'El archivo supera los 50 MB. Elige uno más pequeño.',
      );
    }
    final directory = await _job();
    try {
      final copy = await source.copy(
        p.join(directory.path, 'source${p.extension(path).toLowerCase()}'),
      );
      return await _inspect(copy);
    } catch (_) {
      await directory.delete(recursive: true);
      rethrow;
    }
  }

  Future<ImportedMedia> download(
    Uri uri, {
    void Function(String)? onProgress,
  }) async {
    final directory = await _job();
    final file = File(
      p.join(directory.path, 'source${p.extension(uri.path).toLowerCase()}'),
    );
    try {
      await MediaDownloader().download(uri, file);
      onProgress?.call('Preparando el editor…');
      return await _inspect(file);
    } catch (_) {
      await directory.delete(recursive: true);
      rethrow;
    }
  }

  Future<ImportedMedia> _inspect(File file) async {
    final thumbnail = File(p.join(file.parent.path, 'preview.png'));
    final reader = await file.open();
    final List<int> header;
    try {
      header = await reader.read(12);
    } finally {
      await reader.close();
    }
    final imageSignature =
        header.length >= 12 &&
        ((header[0] == 0x89 &&
                header[1] == 0x50 &&
                header[2] == 0x4e &&
                header[3] == 0x47) ||
            (header[0] == 0xff && header[1] == 0xd8 && header[2] == 0xff) ||
            String.fromCharCodes(header.take(3)) == 'GIF' ||
            (String.fromCharCodes(header.take(4)) == 'RIFF' &&
                String.fromCharCodes(header.skip(8)) == 'WEBP'));
    if (imageSignature) {
      final codec = await ui.instantiateImageCodecWithSize(
        await ui.ImmutableBuffer.fromFilePath(file.path),
        getTargetSize: (width, height) => width >= height
            ? ui.TargetImageSize(width: min(width, 2048))
            : ui.TargetImageSize(height: min(height, 2048)),
      );
      try {
        if (codec.frameCount == 1) {
          final frame = await codec.getNextFrame();
          try {
            final png = await frame.image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            if (png == null) {
              throw const UserMessage('No pudimos leer esta imagen.');
            }
            await thumbnail.writeAsBytes(
              png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes),
            );
          } finally {
            frame.image.dispose();
          }
          return ImportedMedia(file, thumbnail, 0, isAnimated: false);
        }
      } finally {
        codec.dispose();
      }
    }
    final session = await FFprobeKit.getMediaInformation(file.path);
    final info = session.getMediaInformation();
    final duration = double.tryParse(info?.getDuration() ?? '') ?? 0;
    if (duration < 0.2 ||
        !duration.isFinite ||
        duration > 600 ||
        !(info?.getStreams().any((s) => s.getType() == 'video') ?? false)) {
      throw const UserMessage(
        'Elige un GIF animado o video de entre 0,2 segundos y 10 minutos.',
      );
    }
    await _execute([
      '-y',
      '-i',
      file.path,
      '-frames:v',
      '1',
      '-vf',
      'scale=512:512:force_original_aspect_ratio=decrease',
      thumbnail.path,
    ]);
    return ImportedMedia(file, thumbnail, duration);
  }

  Future<void> _execute(List<String> arguments) async {
    final session = await FFmpegKit.executeWithArguments(arguments);
    if (!ReturnCode.isSuccess(await session.getReturnCode())) {
      throw const UserMessage(
        'No pudimos procesar este archivo. Prueba con otra imagen, GIF o video.',
      );
    }
  }

  Future<ConvertedSticker> convert(
    ImportedMedia media,
    ConversionOptions options,
    void Function(String) onProgress,
  ) async {
    if (media.isAnimated) options.validate();
    if (media.isAnimated && options.end > media.duration + 0.01) {
      throw const UserMessage('El fragmento supera la duración del archivo.');
    }
    final output = File(
      p.join(media.file.parent.path, 'sticker_${newId()}.webp'),
    );
    final input = media.isAnimated ? media.file.path : media.thumbnail.path;
    final maxBytes = (media.isAnimated ? 500 : 100) * 1024;
    for (final fps in media.isAnimated ? [15, 10] : [15]) {
      for (final quality in [80, 60, 40, 25, 10]) {
        onProgress(
          quality == 80 && fps == 15
              ? 'Creando tu sticker…'
              : 'Ajustando el tamaño para WhatsApp…',
        );
        await _execute(
          media.isAnimated
              ? options.arguments(
                  input: input,
                  output: output.path,
                  fps: fps,
                  quality: quality,
                )
              : options.imageArguments(
                  input: input,
                  output: output.path,
                  quality: quality,
                ),
        );
        if (await output.length() <= maxBytes) {
          final info = WebpInfo.validate(await output.readAsBytes());
          if (info.isAnimated != media.isAnimated) {
            throw const UserMessage(
              'No pudimos conservar la animación. Prueba otro fragmento.',
            );
          }
          final tray = File(
            p.join(media.file.parent.path, 'tray_${newId()}.png'),
          );
          await _execute([
            '-y',
            if (media.isAnimated) ...['-ss', options.start.toStringAsFixed(3)],
            '-i',
            input,
            '-frames:v',
            '1',
            '-vf',
            '${options.imageFilter},scale=96:96',
            tray.path,
          ]);
          if (await tray.length() > 50 * 1024) {
            throw const UserMessage(
              'No pudimos crear la miniatura del paquete.',
            );
          }
          return ConvertedSticker(output, tray, info);
        }
      }
    }
    throw UserMessage(
      media.isAnimated
          ? 'Este fragmento todavía pesa demasiado. Acórtalo un poco y vuelve a intentarlo.'
          : 'Esta imagen todavía pesa demasiado. Prueba con otra imagen o encuadre.',
    );
  }
}

class StickerLibrary {
  StickerLibrary(this.root);
  final Directory root;
  List<StickerPack> packs = [];
  static Future<StickerLibrary> open() async {
    final root = Directory(
      p.join((await getApplicationDocumentsDirectory()).path, 'sharegif'),
    );
    await root.create(recursive: true);
    final library = StickerLibrary(root);
    final index = File(p.join(root.path, 'library.json'));
    if (await index.exists()) {
      final json = jsonDecode(await index.readAsString()) as List;
      library.packs = json
          .map((j) => StickerPack.fromJson(j as Map<String, dynamic>))
          .toList();
    }
    return library;
  }

  File stickerFile(StickerPack pack, Sticker sticker) =>
      File(p.join(root.path, pack.id, sticker.filename));
  File trayFile(StickerPack pack) =>
      File(p.join(root.path, pack.id, 'tray.png'));

  Future<void> _commit(List<StickerPack> next) async {
    final temporary = File(p.join(root.path, 'library.json.tmp'));
    await temporary.writeAsString(
      jsonEncode(next.map((p) => p.toJson()).toList()),
      flush: true,
    );
    await temporary.rename(p.join(root.path, 'library.json'));
    packs = next;
  }

  Future<StickerPack> save(
    ConvertedSticker converted, {
    String? packId,
    String name = 'Mis reacciones',
  }) async {
    final existing = packId == null
        ? null
        : packs.firstWhere((p) => p.id == packId);
    if (existing != null && existing.stickers.length >= 30) {
      throw const UserMessage(
        'Este paquete está lleno. Crea otro para guardar tu sticker.',
      );
    }
    if (existing == null && packs.length >= 10) {
      throw const UserMessage(
        'Ya tienes 10 paquetes. Guarda el sticker en uno existente.',
      );
    }
    final cleanName = name.trim();
    if (cleanName.isEmpty || cleanName.length > 60) {
      throw const UserMessage('Escribe un nombre de entre 1 y 60 caracteres.');
    }
    final info = WebpInfo.validate(await converted.file.readAsBytes());
    if (existing != null && existing.isAnimated != info.isAnimated) {
      throw const UserMessage(
        'Las imágenes y las animaciones necesitan paquetes separados.',
      );
    }
    final id = existing?.id ?? newId();
    final directory = Directory(p.join(root.path, id));
    await directory.create(recursive: true);
    final sticker = Sticker(
      id: newId(),
      bytes: await converted.file.length(),
      durationMs: info.durationMs,
    );
    final destination = File(p.join(directory.path, sticker.filename));
    try {
      await converted.file.copy(destination.path);
      if (existing == null) {
        await converted.tray.copy(p.join(directory.path, 'tray.png'));
      }
      final pack = StickerPack(
        id: id,
        name: existing?.name ?? cleanName,
        isAnimated: info.isAnimated,
        stickers: [...?existing?.stickers, sticker],
      );
      await _commit([
        for (final item in packs)
          if (item.id == id) pack else item,
        if (existing == null) pack,
      ]);
      return pack;
    } catch (_) {
      if (await destination.exists()) await destination.delete();
      rethrow;
    }
  }

  Future<void> removeSticker(StickerPack pack, Sticker sticker) async {
    final current = packs.firstWhere((p) => p.id == pack.id);
    final remaining = current.stickers
        .where((s) => s.id != sticker.id)
        .toList();
    await _commit([
      for (final item in packs)
        if (item.id != pack.id)
          item
        else if (remaining.isNotEmpty)
          StickerPack(
            id: item.id,
            name: item.name,
            stickers: remaining,
            isAnimated: item.isAnimated,
          ),
    ]);
    // WhatsApp reads an independent native snapshot, never these editable drafts.
    try {
      await stickerFile(pack, sticker).delete();
    } on FileSystemException {
      /* Index already committed. */
    }
  }

  Future<void> export(StickerPack pack) async {
    if (!pack.canExport) {
      throw const UserMessage(
        'Necesitas entre 3 y 30 stickers para añadir este paquete a WhatsApp.',
      );
    }
    if (!Platform.isAndroid && !Platform.isIOS) {
      throw const UserMessage(
        'Añadir a WhatsApp está disponible en Android y iPhone.',
      );
    }
    for (final sticker in pack.stickers) {
      final info = WebpInfo.validate(
        await stickerFile(pack, sticker).readAsBytes(),
      );
      if (info.isAnimated != pack.isAnimated) {
        throw const UserMessage(
          'Este paquete mezcla imágenes y animaciones. Guárdalas en paquetes separados.',
        );
      }
    }
    await const MethodChannel(
      'sharegif/whatsapp',
    ).invokeMethod<void>('addPack', {
      'id': pack.id,
      'name': pack.name,
      'animated': pack.isAnimated,
      'tray': trayFile(pack).path,
      'stickers': pack.stickers.map((s) => stickerFile(pack, s).path).toList(),
      'version': pack.stickers.map((s) => s.id).join('_'),
    });
  }
}

String friendlyError(Object error) {
  if (error is UserMessage) return error.message;
  if (error is PlatformException) {
    return error.message ??
        'No se pudo completar la acción. Inténtalo de nuevo.';
  }
  if (error is SocketException ||
      error is TimeoutException ||
      error is HttpException) {
    return 'No pudimos conectar. Revisa tu conexión o importa un archivo del teléfono.';
  }
  if (error is FileSystemException) {
    return 'No pudimos acceder al archivo. Revisa el espacio disponible e inténtalo de nuevo.';
  }
  return 'Algo salió mal. Inténtalo de nuevo o elige otro archivo.';
}
