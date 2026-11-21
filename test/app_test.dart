import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sharegif/src/app.dart';
import 'package:sharegif/src/services.dart';
import 'package:sharegif/src/editor.dart';
import 'package:sharegif/src/models.dart';
import 'package:sharegif/src/x_post_resolver.dart';

import 'x_post_resolver_test.dart'
    show exampleLink, exampleId, postFixture, mediaFixture;
import 'models_test.dart' show container, staticContainer;

class TestImportedMedia extends ImportedMedia {
  TestImportedMedia(
    super.file,
    super.thumbnail,
    super.duration, {
    super.isAnimated,
  });
  bool disposed = false;
  @override
  Future<void> dispose() async {
    disposed = true;
  }
}

class TestMediaService extends MediaService {
  TestMediaService({XTransport? transport, this.failure})
    : super(
        xResolver: XPostResolver(
          transport:
              transport ??
              ((_) async => XResponse(200, jsonEncode(postFixture()))),
        ),
      ) {
    directory = Directory.systemTemp.createTempSync('sharegif_widget_');
    image = File('${directory.path}/preview.png')
      ..writeAsBytesSync(
        File('test/fixtures/still.png').readAsBytesSync(),
      );
    addTearDown(() {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });
  }
  late final Directory directory;
  late final File image;
  final Object? failure;
  Uri? downloaded;
  final downloads = <Uri>[];
  final imported = <TestImportedMedia>[];
  Uri? failUri;
  @override
  Future<ImportedMedia> download(
    Uri uri, {
    void Function(String)? onProgress,
  }) async {
    downloaded = uri;
    downloads.add(uri);
    if (failure != null && (failUri == null || failUri == uri)) throw failure!;
    final media = TestImportedMedia(
      File('${directory.path}/source.mp4'),
      image,
      3,
      isAnimated: !uri.path.endsWith('.jpg'),
    );
    imported.add(media);
    return media;
  }

  @override
  Future<ConvertedSticker> convert(
    ImportedMedia media,
    ConversionOptions options,
    void Function(String) onProgress,
  ) async {
    final bytes = media.isAnimated ? container() : staticContainer();
    final file = File('${directory.path}/converted.webp')
      ..writeAsBytesSync(bytes);
    return ConvertedSticker(file, image, WebpInfo.validate(bytes));
  }
}

class RecordingLibrary extends StickerLibrary {
  RecordingLibrary() : super(Directory.systemTemp);
  final destinations = <String?>[];
  bool failSaving = false;
  @override
  Future<StickerPack> save(
    ConvertedSticker converted, {
    String? packId,
    String name = 'Mis reacciones',
  }) async {
    if (failSaving) throw const UserMessage('No hay espacio para guardar.');
    destinations.add(packId);
    final previous = packs.where((pack) => pack.id == packId).firstOrNull;
    final pack = StickerPack(
      id: previous?.id ?? 'pack_${packs.length}',
      name: previous?.name ?? name,
      isAnimated: converted.info.isAnimated,
      stickers: [
        ...?previous?.stickers,
        Sticker(
          id: 'sticker_${destinations.length}',
          bytes: 100,
          durationMs: 200,
        ),
      ],
    );
    packs = [
      for (final item in packs)
        if (item.id != pack.id) item,
      pack,
    ];
    return pack;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final font = FontLoader('Roboto')
      ..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf'))
      ..addFont(rootBundle.load('assets/fonts/Roboto-Bold.ttf'));
    await font.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });
  Future<void> pumpHome(
    WidgetTester tester, {
    Size size = const Size(390, 844),
    double scale = 1,
    MediaService? mediaService,
    StickerLibrary? library,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      ShareGifApp(
        libraryLoader: () async =>
            library ?? StickerLibrary(Directory.systemTemp),
        mediaService: mediaService,
      ),
    );
    await tester.pumpAndSettle();
  }

  String inputText(WidgetTester tester) =>
      tester.widget<TextField>(find.byType(TextField).first).controller!.text;
  Future<void> tapEditorButton(WidgetTester tester, String label) async {
    final scrollable = find
        .descendant(
          of: find.byType(EditorScreen),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(
      find.text(label),
      220,
      scrollable: scrollable,
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text(label));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'mixed image and GIF links use separate packs and clear the batch',
    (tester) async {
      final service = TestMediaService();
      final library = RecordingLibrary();
      await pumpHome(tester, mediaService: service, library: library);
      await tester.enterText(
        find.byType(TextField),
        'https://example.org/photo.jpg\n$exampleLink\nhttps://example.org/second.jpg',
      );
      await tester.pump();
      await tester.tap(find.text('Crear stickers de los enlaces'));
      await tester.pumpAndSettle();
      expect(find.byType(RangeSlider), findsNothing);
      await tapEditorButton(tester, 'Crear sticker');
      expect(find.text('WebP estático'), findsOneWidget);
      await tapEditorButton(tester, 'Guardar y continuar');
      expect(find.byType(RangeSlider), findsOneWidget);
      await tapEditorButton(tester, 'Crear sticker');
      await tapEditorButton(tester, 'Guardar y continuar');
      expect(find.byType(RangeSlider), findsNothing);
      await tapEditorButton(tester, 'Crear sticker');
      await tapEditorButton(tester, 'Guardar sticker');
      expect(library.destinations, [null, null, 'pack_0']);
      expect(
        library.packs.where((p) => !p.isAnimated).single.stickers.length,
        2,
      );
      expect(
        library.packs.where((p) => p.isAnimated).single.stickers.length,
        1,
      );
      await tester.tap(find.text('Crear'));
      await tester.pumpAndSettle();
      expect(inputText(tester), isEmpty);
    },
  );

  testWidgets('local still images open without invoking video probing', (
    tester,
  ) async {
    final service = TestMediaService();
    final channel = const MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => service.directory.path);
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    await tester.runAsync(() async {
      final media = await MediaService().importFile(service.image.path);
      try {
        expect(media.isAnimated, false);
        expect(media.duration, 0);
        expect(await media.thumbnail.length(), greaterThan(0));
      } finally {
        await media.dispose();
      }
    });
  });

  testWidgets(
    'saving a single X sticker clears its link; failed save preserves it',
    (tester) async {
      final service = TestMediaService();
      final library = RecordingLibrary()..failSaving = true;
      await pumpHome(tester, mediaService: service, library: library);
      await tester.enterText(find.byType(TextField), exampleLink);
      await tester.tap(find.text('Continuar con enlace'));
      await tester.pumpAndSettle();
      await tapEditorButton(tester, 'Crear sticker');
      await tapEditorButton(tester, 'Guardar sticker');
      expect(find.text('No hay espacio para guardar.'), findsOneWidget);
      expect(library.packs, isEmpty);
      library.failSaving = false;
      await tapEditorButton(tester, 'Guardar sticker');
      await tester.tap(find.text('Crear'));
      await tester.pumpAndSettle();
      expect(inputText(tester), isEmpty);
      expect(service.imported.single.disposed, true);
      expect(library.packs.single.stickers.length, 1);
    },
  );

  testWidgets(
    'two X links create two stickers in the same chosen pack and clear the batch',
    (tester) async {
      const second = 'https://x.com/GIPHY/status/1957913446118285360';
      final service = TestMediaService(
        transport: (uri) async => XResponse(
          200,
          jsonEncode(postFixture()..['id_str'] = uri.queryParameters['id']),
        ),
      );
      final library = RecordingLibrary();
      await pumpHome(tester, mediaService: service, library: library);
      await tester.enterText(find.byType(TextField), '$exampleLink\n$second');
      await tester.pump();
      await tester.ensureVisible(find.text('Crear stickers de los enlaces'));
      await tester.tap(find.text('Crear stickers de los enlaces'));
      await tester.pumpAndSettle();
      expect(find.text('STICKER 1 DE 2'), findsOneWidget);
      await tapEditorButton(tester, 'Crear sticker');
      await tapEditorButton(tester, 'Guardar y continuar');
      expect(find.text('STICKER 2 DE 2'), findsOneWidget);
      expect(service.imported.first.disposed, true);
      await tapEditorButton(tester, 'Crear sticker');
      await tapEditorButton(tester, 'Guardar sticker');
      expect(library.packs.single.stickers.length, 2);
      expect(library.destinations, [null, 'pack_0']);
      expect(service.imported.every((media) => media.disposed), true);
      await tester.tap(find.text('Crear'));
      await tester.pumpAndSettle();
      expect(inputText(tester), isEmpty);
    },
  );

  testWidgets(
    'cancel leaves current and remaining links; already saved links stay removed',
    (tester) async {
      const second = 'https://cdn.example/second.gif';
      const third = 'https://cdn.example/third.gif';
      final service = TestMediaService();
      final library = RecordingLibrary();
      await pumpHome(tester, mediaService: service, library: library);
      await tester.enterText(
        find.byType(TextField),
        '$exampleLink\n$second\n$third',
      );
      await tester.pump();
      await tester.ensureVisible(find.text('Crear stickers de los enlaces'));
      await tester.tap(find.text('Crear stickers de los enlaces'));
      await tester.pumpAndSettle();
      await tapEditorButton(tester, 'Crear sticker');
      await tapEditorButton(tester, 'Guardar y continuar');
      await tester.tap(find.byTooltip('Volver'));
      await tester.pumpAndSettle();
      expect(inputText(tester), '$second\n$third');
      expect(service.downloads.length, 2);
      expect(library.packs.single.stickers.length, 1);
    },
  );

  testWidgets(
    'failed download keeps unsaved links and does not fetch the rest',
    (tester) async {
      const second = 'https://cdn.example/second.gif';
      const third = 'https://cdn.example/third.gif';
      final service = TestMediaService(
        failure: const UserMessage('Descarga fallida.'),
      )..failUri = Uri.parse(second);
      final library = RecordingLibrary();
      await pumpHome(tester, mediaService: service, library: library);
      await tester.enterText(
        find.byType(TextField),
        '$exampleLink\n$second\n$third',
      );
      await tester.pump();
      await tester.ensureVisible(find.text('Crear stickers de los enlaces'));
      await tester.tap(find.text('Crear stickers de los enlaces'));
      await tester.pumpAndSettle();
      await tapEditorButton(tester, 'Crear sticker');
      await tapEditorButton(tester, 'Guardar y continuar');
      expect(inputText(tester), '$second\n$third');
      expect(service.downloads.length, 2);
      expect(
        find.textContaining('Enlace 2 de 3: Descarga fallida.'),
        findsOneWidget,
      );
    },
  );

  testWidgets('home design and empty collection navigation', (tester) async {
    await pumpHome(tester);
    expect(find.text('Ese GIF merece\nser un sticker.'), findsOneWidget);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/home.png'),
    );
    await tester.tap(find.text('Mis stickers'));
    await tester.pumpAndSettle();
    expect(find.text('Tu primer sticker\nes el comienzo.'), findsOneWidget);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/collection.png'),
    );
    await tester.tap(find.text('Crear mi primer sticker'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
  });
  testWidgets(
    'invalid links and download errors stay on the form and allow retry',
    (tester) async {
      final service = TestMediaService(
        failure: const UserMessage('Descarga de prueba fallida.'),
      );
      await pumpHome(tester, mediaService: service);
      await tester.enterText(find.byType(TextField), 'not a link');
      await tester.tap(find.text('Continuar con enlace'));
      await tester.pumpAndSettle();
      expect(find.textContaining('HTTPS válido'), findsOneWidget);
      await tester.enterText(find.byType(TextField), exampleLink);
      await tester.pump();
      await tester.ensureVisible(find.text('Continuar con enlace'));
      await tester.tap(find.text('Continuar con enlace'));
      await tester.pumpAndSettle();
      expect(find.text('Descarga de prueba fallida.'), findsOneWidget);
      expect(find.text('Continuar con enlace'), findsOneWidget);
      expect(find.byType(EditorScreen), findsNothing);
    },
  );
  testWidgets('user X photo/1 link resolves, downloads and opens the editor', (
    tester,
  ) async {
    final pending = Completer<XResponse>();
    final service = TestMediaService(transport: (_) => pending.future);
    await pumpHome(tester, mediaService: service);
    await tester.enterText(find.byType(TextField), exampleLink);
    await tester.tap(find.text('Continuar con enlace'));
    await tester.pump();
    expect(find.text('Buscando el archivo en X…'), findsOneWidget);
    pending.complete(XResponse(200, jsonEncode(postFixture())));
    await tester.pumpAndSettle();
    expect(
      service.downloaded.toString(),
      'https://video.twimg.com/tweet_video/HXeerapXgAAOYg8.mp4',
    );
    expect(find.byType(EditorScreen), findsOneWidget);
    expect(find.text('Trae el GIF de X'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'multiple attachments can be selected or cancelled without downloading',
    (tester) async {
      final service = TestMediaService(
        transport: (_) async => XResponse(
          200,
          jsonEncode(
            postFixture(
              media: [
                mediaFixture(),
                mediaFixture(name: 'second'),
              ],
            ),
          ),
        ),
      );
      await pumpHome(tester, mediaService: service);
      await tester.enterText(
        find.byType(TextField),
        'https://x.com/u/status/$exampleId',
      );
      await tester.tap(find.text('Continuar con enlace'));
      // Import stays busy while the picker is open; its progress indicator
      // intentionally keeps animating behind the sheet.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('¿Cuál convertimos?'), findsOneWidget);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(service.downloaded, isNull);
      await tester.tap(find.text('Continuar con enlace'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('GIF 2'));
      await tester.pumpAndSettle();
      expect(service.downloaded!.path, endsWith('second.mp4'));
      expect(find.byType(EditorScreen), findsOneWidget);
    },
  );
  testWidgets('small phone and large text do not overflow', (tester) async {
    await pumpHome(tester, size: const Size(320, 640), scale: 1.7);
    expect(tester.takeException(), isNull);
    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Mis stickers'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  testWidgets('library failure keeps error visible and offers retry', (
    tester,
  ) async {
    await tester.pumpWidget(
      ShareGifApp(
        libraryLoader: () async =>
            throw const FileSystemException('unreadable'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Reintentar'), findsOneWidget);
    expect(
      find.textContaining('Tus archivos siguen guardados'),
      findsOneWidget,
    );
  });
}
