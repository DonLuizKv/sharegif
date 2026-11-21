import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'editor.dart';
import 'link_batch.dart';
import 'models.dart';
import 'services.dart';
import 'theme.dart';
import 'x_post_resolver.dart';

class ShareGifApp extends StatelessWidget {
  const ShareGifApp({super.key, this.libraryLoader, this.mediaService});
  final Future<StickerLibrary> Function()? libraryLoader;
  final MediaService? mediaService;
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'ShareGIF',
    theme: appTheme(),
    home: HomeScreen(
      libraryLoader: libraryLoader ?? StickerLibrary.open,
      mediaService: mediaService,
    ),
  );
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.libraryLoader, this.mediaService});
  final Future<StickerLibrary> Function() libraryLoader;
  final MediaService? mediaService;
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _link = TextEditingController();
  late final MediaService _media;
  StickerLibrary? _library;
  String? _loadError;
  String? _error;
  bool _busy = false;
  String _progress = 'Preparando archivo…';
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    _media = widget.mediaService ?? MediaService();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loadError = null);
    try {
      final library = await widget.libraryLoader();
      if (mounted) setState(() => _library = library);
    } catch (_) {
      if (mounted) {
        setState(
          () => _loadError = 'No pudimos abrir tus stickers. Tus archivos siguen guardados; vuelve a intentarlo.',
        );
      }
    }
  }

  @override
  void dispose() {
    _link.dispose();
    super.dispose();
  }

  void _message(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _import({List<PendingLink>? batch}) async {
    if (_busy || _library == null) return;
    setState(() {
      _busy = true;
      _error = null;
      _progress = 'Preparando archivo…';
    });
    final pending = batch == null ? null : List<PendingLink>.of(batch);
    final total = batch?.length ?? 1;
    var saved = 0;
    var position = 1;
    String? preferredPackId;
    try {
      for (var index = 0; index < total; index++) {
        position = index + 1;
        ImportedMedia? media;
        try {
          if (batch != null) {
            media = await _media.importLink(
              batch[index].media,
              onProgress: (message) {
                if (mounted) {
                  setState(
                    () => _progress = total > 1
                        ? '$position/$total · $message'
                        : message,
                  );
                }
              },
              chooseMedia: _chooseMedia,
            );
            if (media == null) break;
          } else {
            final picked = await FilePicker.platform.pickFiles(
              type: FileType.custom,
              allowedExtensions: [
                'png',
                'jpg',
                'jpeg',
                'webp',
                'gif',
                'mp4',
                'mov',
                'webm',
                'm4v',
              ],
              withData: false,
            );
            final path = picked?.files.single.path;
            if (path == null) break;
            media = await _media.importFile(path);
          }
          if (!mounted) return;
          final packId = await Navigator.of(context).push<String>(
            MaterialPageRoute(
              builder: (_) => EditorScreen(
                media: media!,
                service: _media,
                library: _library!,
                initialPackId: preferredPackId,
                batchPosition: position,
                batchTotal: total,
              ),
            ),
          );
          if (!mounted) return;
          if (packId == null) break;
          preferredPackId = packId;
          saved++;
          // A link is consumed only after the library has successfully saved it.
          if (pending != null) {
            pending.removeAt(0);
            _link.text = pending.map((item) => item.source).join('\n');
          }
        } finally {
          if (media != null) {
            try {
              await media.dispose();
            } on FileSystemException {
              // A cleanup failure must not requeue an already saved sticker.
            }
          }
        }
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = total > 1
              ? 'Enlace $position de $total: ${friendlyError(error)} Los enlaces pendientes siguen aquí.'
              : friendlyError(error),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          if (saved == total) _tab = 1;
        });
        if (saved > 0) {
          _message(
            saved == 1
                ? 'Sticker guardado en tu colección.'
                : '$saved stickers guardados en tu colección.',
          );
        }
      }
    }
  }

  Future<void> _fromLink() async {
    if (_busy) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _error = null);
    try {
      final batch = PendingLink.parseBatch(_link.text);
      _link.text = batch.map((item) => item.source).join('\n');
      await _import(batch: batch);
    } catch (error) {
      if (mounted) setState(() => _error = friendlyError(error));
    }
  }

  Future<XMedia?> _chooseMedia(List<XMedia> media) async {
    if (!mounted) return null;
    return showModalBottomSheet<XMedia>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetContext).height * .75,
          ),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            children: [
              const Text(
                '¿Cuál convertimos?',
                style: TextStyle(fontSize: 25, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              const Text(
                'Elige una imagen, GIF o video de esta publicación.',
                style: TextStyle(color: Palette.muted),
              ),
              const SizedBox(height: 16),
              for (final item in media)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Material(
                    color: Palette.porcelain,
                    borderRadius: BorderRadius.circular(18),
                    child: ListTile(
                      contentPadding: const EdgeInsets.all(12),
                      leading: SizedBox(
                        width: 64,
                        height: 64,
                        child: item.poster == null
                            ? const Icon(Icons.gif_box_outlined)
                            : ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Image.network(
                                  item.poster.toString(),
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, error, stack) =>
                                      const Icon(Icons.gif_box_outlined),
                                ),
                              ),
                      ),
                      title: Text(item.label),
                      trailing: const Icon(Icons.arrow_forward_rounded),
                      onTap: () => Navigator.pop(sheetContext, item),
                    ),
                  ),
                ),
              TextButton(
                onPressed: () => Navigator.pop(sheetContext),
                child: const Text('Cancelar'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _help() => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(24, 0, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Del GIF al chat.',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
            ),
            SizedBox(height: 24),
            _HelpStep(
              '01',
              'Trae tu reacción',
              'Pega uno o varios enlaces de X, uno por línea. Ajusta y guarda cada sticker para pasar al siguiente. También puedes importar un archivo de tu teléfono.',
            ),
            _HelpStep(
              '02',
              'Dale tu encuadre',
              'Elige un fragmento de hasta 10 segundos. Conserva la imagen completa o recórtala en cuadrado.',
            ),
            _HelpStep(
              '03',
              'Llévala a WhatsApp',
              'Guarda al menos 3 stickers en un paquete y toca Añadir a WhatsApp. Confirma la importación allí.',
            ),
            Notice(
              'La conversión y tu colección se quedan en el teléfono. Solo necesitas internet para descargar un archivo.',
              icon: Icons.phonelink_lock_outlined,
            ),
          ],
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 16, 16, 8),
                  child: Row(
                    children: [
                      const StickerMark(size: 34),
                      const SizedBox(width: 10),
                      const Text(
                        'sharegif',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 24,
                          letterSpacing: -1,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        tooltip: 'Cómo funciona',
                        onPressed: _help,
                        icon: const Icon(Icons.help_outline_rounded, size: 22),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _loadError != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Notice(_loadError!),
                                TextButton(
                                  onPressed: _load,
                                  child: const Text('Reintentar'),
                                ),
                              ],
                            ),
                          ),
                        )
                      : _library == null
                      ? const Center(child: CircularProgressIndicator())
                      : _tab == 0
                      ? _create()
                      : _collection(),
                ),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: Palette.line)),
          ),
          child: NavigationBar(
            height: 72,
            backgroundColor: Palette.porcelain,
            surfaceTintColor: Colors.transparent,
            indicatorColor: Palette.violet.withValues(alpha: .10),
            selectedIndex: _tab,
            onDestinationSelected: _busy
                ? null
                : (value) => setState(() => _tab = value),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.add_circle_outline_rounded),
                selectedIcon: Icon(
                  Icons.add_circle_rounded,
                  color: Palette.violet,
                ),
                label: 'Crear',
              ),
              NavigationDestination(
                icon: Icon(Icons.collections_bookmark_outlined),
                selectedIcon: Icon(
                  Icons.collections_bookmark_rounded,
                  color: Palette.violet,
                ),
                label: 'Mis stickers',
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _create() => ListView(
    padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
    children: [
      const SectionLabel('DE TU FEED A TUS CHATS'),
      const SizedBox(height: 10),
      const Text(
        'Ese GIF merece\nser un sticker.',
        style: TextStyle(
          fontSize: 36,
          height: 1.08,
          fontWeight: FontWeight.w800,
          letterSpacing: -1.5,
        ),
      ),
      const SizedBox(height: 22),
      Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: Palette.taupe,
          borderRadius: BorderRadius.circular(26),
        ),
        child: Row(
          children: [
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SectionLabel('PEQUEÑAS REACCIONES', color: Palette.ink),
                  SizedBox(height: 12),
                  Text(
                    'Mucho que decir.\nSin escribir nada.',
                    style: TextStyle(
                      fontSize: 21,
                      height: 1.25,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: 16),
                  Row(
                    children: [
                      Icon(Icons.gif_box_outlined, size: 22),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 10),
                        child: Icon(Icons.arrow_right_alt_rounded, size: 22),
                      ),
                      Icon(Icons.emoji_emotions_outlined, size: 22),
                    ],
                  ),
                ],
              ),
            ),
            LayoutBuilder(
              builder: (context, constraints) => StickerIllustration(
                size: MediaQuery.sizeOf(context).width < 360 ? 84 : 112,
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 24),
      const Text(
        'Empieza con una imagen o GIF',
        style: TextStyle(
          fontSize: 19,
          fontWeight: FontWeight.w700,
          letterSpacing: -.4,
        ),
      ),
      const SizedBox(height: 6),
      const Text(
        'Pega uno o varios enlaces, uno por línea.',
        style: TextStyle(fontSize: 13, height: 1.5, color: Palette.muted),
      ),
      const SizedBox(height: 14),
      TextField(
        controller: _link,
        enabled: !_busy,
        keyboardType: TextInputType.multiline,
        textInputAction: TextInputAction.newline,
        minLines: 1,
        maxLines: 4,
        autocorrect: false,
        onChanged: (_) => setState(() => _error = null),
        decoration: InputDecoration(
          hintText: 'https://x.com/…',
          labelText: 'Enlaces de X o de archivos',
          prefixIcon: const Icon(Icons.link_rounded, size: 21),
          suffixIcon: IconButton(
            tooltip: 'Añadir enlaces del portapapeles',
            onPressed: _busy
                ? null
                : () async {
                    try {
                      final data = await Clipboard.getData(
                        Clipboard.kTextPlain,
                      );
                      if (mounted) {
                        final pasted = data?.text?.trim() ?? '';
                        if (pasted.isNotEmpty) {
                          _link.text = [
                            _link.text.trim(),
                            pasted,
                          ].where((text) => text.isNotEmpty).join('\n');
                          _link.selection = TextSelection.collapsed(
                            offset: _link.text.length,
                          );
                        }
                        setState(() => _error = null);
                      }
                    } catch (_) {
                      if (mounted) {
                        _message(
                          'No pudimos acceder al portapapeles. Pega el enlace manualmente.',
                        );
                      }
                    }
                  },
            icon: const Icon(Icons.content_paste_rounded, size: 20),
          ),
        ),
      ),
      if (_error != null)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Semantics(liveRegion: true, child: Notice(_error!)),
        ),
      const SizedBox(height: 12),
      FilledButton.icon(
        onPressed: _busy ? null : _fromLink,
        icon: _busy
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.arrow_forward_rounded, size: 21),
        label: Text(
          _busy
              ? _progress
              : _link.text.trim().split(RegExp(r'\s+')).length > 1
              ? 'Crear stickers de los enlaces'
              : 'Continuar con enlace',
        ),
      ),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        onPressed: _busy ? null : () => _import(),
        icon: const Icon(Icons.folder_open_rounded, size: 21),
        label: const Text('Importar imagen, GIF o video'),
      ),
      const SizedBox(height: 14),
      const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.phonelink_lock_outlined, size: 15, color: Palette.muted),
          SizedBox(width: 7),
          Flexible(
            child: Text(
              'Se convierte aquí. Se queda contigo.',
              style: TextStyle(fontSize: 12, color: Palette.muted),
            ),
          ),
        ],
      ),
    ],
  );

  Widget _collection() {
    final packs = _library!.packs;
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
      children: [
        const SectionLabel('TU COLECCIÓN'),
        const SizedBox(height: 10),
        const Text(
          'Reacciones muy tuyas.',
          style: TextStyle(
            fontSize: 32,
            height: 1.1,
            fontWeight: FontWeight.w800,
            letterSpacing: -1,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          packs.isEmpty
              ? 'Tus próximos favoritos viven aquí.'
              : '${packs.length} ${packs.length == 1 ? 'paquete' : 'paquetes'} · Guardados en tu teléfono',
          style: const TextStyle(color: Palette.muted),
        ),
        const SizedBox(height: 28),
        if (packs.isEmpty)
          Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: Palette.taupe.withValues(alpha: .17),
              borderRadius: BorderRadius.circular(28),
            ),
            child: Column(
              children: [
                const StickerIllustration(size: 144),
                const SizedBox(height: 24),
                const Text(
                  'Tu primer sticker\nes el comienzo.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Crea un paquete con al menos 3 stickers\ny llévalo a WhatsApp.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Palette.muted, height: 1.5),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () => setState(() => _tab = 0),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Crear mi primer sticker'),
                ),
              ],
            ),
          ),
        for (final pack in packs)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: _PackCard(
              pack: pack,
              library: _library!,
              onTap: () async {
                await Navigator.push<void>(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        PackScreen(packId: pack.id, library: _library!),
                  ),
                );
                if (mounted) setState(() {});
              },
            ),
          ),
      ],
    );
  }
}

class _HelpStep extends StatelessWidget {
  const _HelpStep(this.number, this.title, this.detail);
  final String number, title, detail;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 24),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          number,
          style: const TextStyle(
            color: Palette.violet,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                detail,
                style: const TextStyle(color: Palette.muted, height: 1.5),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _PackCard extends StatelessWidget {
  const _PackCard({
    required this.pack,
    required this.library,
    required this.onTap,
  });
  final StickerPack pack;
  final StickerLibrary library;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
    color: Palette.paper,
    borderRadius: BorderRadius.circular(24),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    pack.name,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const Icon(Icons.arrow_forward_rounded, size: 20),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '${pack.stickers.length}/30 ${pack.isAnimated ? 'animados' : 'de imágenes'} · ${pack.canExport ? 'Listo para WhatsApp' : 'Faltan ${3 - pack.stickers.length} para compartir'}',
              style: const TextStyle(fontSize: 12, color: Palette.muted),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                for (final sticker in pack.stickers.take(3))
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: AspectRatio(
                        aspectRatio: 1,
                        child: StickerImage(library.stickerFile(pack, sticker)),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class StickerImage extends StatelessWidget {
  const StickerImage(this.file, {super.key, this.fit = BoxFit.contain});
  final File file;
  final BoxFit fit;
  @override
  Widget build(BuildContext context) => Image.file(
    file,
    fit: fit,
    gaplessPlayback: true,
    errorBuilder: (_, error, stack) => const Center(
      child: Icon(Icons.broken_image_outlined, color: Palette.muted),
    ),
  );
}

class PackScreen extends StatefulWidget {
  const PackScreen({super.key, required this.packId, required this.library});
  final String packId;
  final StickerLibrary library;
  @override
  State<PackScreen> createState() => _PackScreenState();
}

class _PackScreenState extends State<PackScreen> {
  bool _busy = false;
  String? _error;
  Future<void> _export(StickerPack pack) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.library.export(pack);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Confirma el paquete en WhatsApp.')),
        );
      }
    } catch (error) {
      if (mounted) setState(() => _error = friendlyError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _inspect(StickerPack pack, Sticker sticker) async {
    final remove = await showModalBottomSheet<bool>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 220,
                child: StickerImage(widget.library.stickerFile(pack, sticker)),
              ),
              const SizedBox(height: 16),
              Text(
                '${(sticker.durationMs / 1000).toStringAsFixed(1)} s · ${(sticker.bytes / 1024).ceil()} KB · 512 × 512',
                style: const TextStyle(color: Palette.muted),
              ),
              const SizedBox(height: 16),
              TextButton.icon(
                onPressed: () => Navigator.pop(context, true),
                icon: const Icon(Icons.delete_outline_rounded),
                label: const Text('Eliminar de mi colección'),
              ),
            ],
          ),
        ),
      ),
    );
    if (remove != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.library.removeSticker(pack, sticker);
      if (!mounted) return;
      if (!widget.library.packs.any((p) => p.id == widget.packId)) {
        Navigator.pop(context);
        return;
      }
      setState(() {});
    } catch (error) {
      if (mounted) setState(() => _error = friendlyError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pack = widget.library.packs
        .where((p) => p.id == widget.packId)
        .firstOrNull;
    if (pack == null) return const Scaffold(body: SizedBox.shrink());
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        appBar: AppBar(title: Text(pack.name)),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                SectionLabel('${pack.stickers.length} DE 30 STICKERS'),
                const SizedBox(height: 20),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: pack.stickers.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                  ),
                  itemBuilder: (_, index) => Material(
                    color: Palette.paper,
                    borderRadius: BorderRadius.circular(20),
                    child: InkWell(
                      onTap: _busy
                          ? null
                          : () => _inspect(pack, pack.stickers[index]),
                      borderRadius: BorderRadius.circular(20),
                      child: Semantics(
                        label: 'Ver sticker ${index + 1}',
                        button: true,
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: StickerImage(
                            widget.library.stickerFile(
                              pack,
                              pack.stickers[index],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                if (!pack.canExport)
                  Notice(
                    'Añade ${3 - pack.stickers.length} ${pack.stickers.length == 2 ? 'sticker más' : 'stickers más'} a este paquete para llevarlo a WhatsApp.',
                  ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Notice(_error!),
                  ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _busy || !pack.canExport
                      ? null
                      : () => _export(pack),
                  icon: const Icon(Icons.chat_bubble_outline_rounded),
                  label: Text(
                    _busy ? 'Preparando paquete…' : 'Añadir a WhatsApp',
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'WhatsApp te pedirá confirmar la importación del paquete.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Palette.muted,
                    fontSize: 12,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
