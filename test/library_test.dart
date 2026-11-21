import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sharegif/src/models.dart';
import 'package:sharegif/src/services.dart';

import 'models_test.dart' show container, staticContainer;

void main() {
  test(
    'static packs persist their type and reject animated additions',
    () async {
      final root = await Directory.systemTemp.createTemp('sharegif_static_');
      addTearDown(() => root.delete(recursive: true));
      final still = await File('${root.path}/still.webp')
          .writeAsBytes(staticContainer());
      final moving = await File('${root.path}/moving.webp')
          .writeAsBytes(container());
      final tray = await File('${root.path}/tray.png').writeAsBytes([1, 2, 3]);
      final library = StickerLibrary(root);
      final converted = ConvertedSticker(
        still,
        tray,
        WebpInfo.validate(await still.readAsBytes()),
      );
      var pack = await library.save(converted, name: 'Imágenes');
      expect(pack.isAnimated, false);
      pack = await library.save(converted, packId: pack.id);
      await expectLater(
        library.save(
          ConvertedSticker(
            moving,
            tray,
            WebpInfo.validate(await moving.readAsBytes()),
          ),
          packId: pack.id,
        ),
        throwsA(isA<UserMessage>()),
      );
      expect(library.packs.single.stickers.length, 2);
      await library.removeSticker(pack, pack.stickers.first);
      final saved = jsonDecode(
        await File('${root.path}/library.json').readAsString(),
      ) as List;
      expect(
        StickerPack.fromJson(saved.single as Map<String, dynamic>).isAnimated,
        false,
      );
    },
  );
  test(
    'saving, updating and deleting persist the collection atomically',
    () async {
      final root = await Directory.systemTemp.createTemp('sharegif_library_');
      addTearDown(() => root.delete(recursive: true));
      final webp = await File('${root.path}/source.webp')
          .writeAsBytes(container());
      final tray = await File('${root.path}/source.png')
          .writeAsBytes([1, 2, 3]);
      final converted = ConvertedSticker(
        webp,
        tray,
        WebpInfo.validate(await webp.readAsBytes()),
      );
      final library = StickerLibrary(root);
      var pack = await library.save(converted, name: 'Reacciones');
      final first = pack.stickers.first;
      expect(await library.stickerFile(pack, first).exists(), true);
      pack = await library.save(converted, packId: pack.id);
      expect(pack.stickers.length, 2);
      final index = jsonDecode(
        await File('${root.path}/library.json').readAsString(),
      ) as List;
      expect(
        StickerPack.fromJson(index.single as Map<String, dynamic>)
            .stickers
            .length,
        2,
      );
      expect(await File('${root.path}/library.json.tmp').exists(), false);
      await library.removeSticker(pack, first);
      expect(library.packs.single.stickers.length, 1);
      expect(await library.stickerFile(pack, first).exists(), false);
      await library.removeSticker(
        library.packs.single,
        library.packs.single.stickers.single,
      );
      expect(library.packs, isEmpty);
    },
  );
  test('failed storage never advertises a sticker in the collection', () async {
    final root = await Directory.systemTemp.createTemp('sharegif_failed_');
    addTearDown(() => root.delete(recursive: true));
    final webp = await File('${root.path}/source.webp')
        .writeAsBytes(container());
    final library = StickerLibrary(root);
    final converted = ConvertedSticker(
      webp,
      File('${root.path}/missing.png'),
      WebpInfo.validate(await webp.readAsBytes()),
    );
    await expectLater(
      library.save(converted),
      throwsA(isA<FileSystemException>()),
    );
    expect(library.packs, isEmpty);
    expect(await File('${root.path}/library.json').exists(), false);
  });
}
