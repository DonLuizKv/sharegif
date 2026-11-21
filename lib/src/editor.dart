import 'dart:math';

import 'package:material_ui/material_ui.dart';

import 'app.dart' show StickerImage;
import 'models.dart';
import 'services.dart';
import 'theme.dart';

class EditorScreen extends StatefulWidget {
  const EditorScreen({
    super.key,
    required this.media,
    required this.service,
    required this.library,
    this.initialPackId,
    this.batchPosition = 1,
    this.batchTotal = 1,
  });
  final ImportedMedia media;
  final MediaService service;
  final StickerLibrary library;
  final String? initialPackId;
  final int batchPosition;
  final int batchTotal;
  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  late RangeValues _range;
  StickerFit _fit = StickerFit.contain;
  bool _busy = false;
  String _progress = '';
  String? _error;
  ConvertedSticker? _converted;
  String? _packId;
  final _name = TextEditingController(text: 'Mis reacciones');

  @override
  void initState() {
    super.initState();
    if (!widget.media.isAnimated) _name.text = 'Mis imágenes';
    _range = RangeValues(0, min(widget.media.duration, 3));
    _packId = widget.library.packs
        .where(
          (p) =>
              p.id == widget.initialPackId &&
              p.stickers.length < 30 &&
              p.isAnimated == widget.media.isAnimated,
        )
        .firstOrNull
        ?.id;
    _packId ??= widget.library.packs
        .where(
          (p) =>
              p.stickers.length < 30 && p.isAnimated == widget.media.isAnimated,
        )
        .firstOrNull
        ?.id;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _convert() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final converted = await widget.service.convert(
        widget.media,
        ConversionOptions(start: _range.start, end: _range.end, fit: _fit),
        (text) {
          if (mounted) setState(() => _progress = text);
        },
      );
      if (mounted) setState(() => _converted = converted);
    } catch (error) {
      if (mounted) setState(() => _error = friendlyError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final pack = await widget.library.save(
        _converted!,
        packId: _packId,
        name: _name.text,
      );
      if (mounted) Navigator.pop(context, pack.id);
    } catch (error) {
      if (mounted) setState(() => _error = friendlyError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _adjustRange(RangeValues next) {
    var start = next.start;
    var end = next.end;
    if (end - start > 10) {
      if (start != _range.start) {
        end = start + 10;
      } else {
        start = end - 10;
      }
    }
    if (end - start < .2) return;
    setState(() {
      _range = RangeValues(start, end);
      _converted = null;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: Scaffold(
      appBar: AppBar(
        title: Text(
          _converted == null ? 'Un último toque' : 'Listo para tu colección',
        ),
        leading: IconButton(
          tooltip: 'Volver',
          onPressed: _busy ? null : () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
            children: [
              if (widget.batchTotal > 1) ...[
                SectionLabel(
                  'STICKER ${widget.batchPosition} DE ${widget.batchTotal}',
                  color: Palette.violet,
                ),
                const SizedBox(height: 12),
              ],
              SectionLabel(
                _converted == null
                    ? '02 / AJUSTA TU STICKER'
                    : '03 / GUÁRDALO EN UN PAQUETE',
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  color: Palette.taupe,
                  borderRadius: BorderRadius.circular(28),
                ),
                child: Column(
                  children: [
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 260),
                      child: AspectRatio(
                        aspectRatio: 1,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: CustomPaint(
                            painter: _CheckerPainter(),
                            child: StickerImage(
                              _converted?.file ?? widget.media.thumbnail,
                              fit:
                                  _converted != null ||
                                      _fit == StickerFit.contain
                                  ? BoxFit.contain
                                  : BoxFit.cover,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _converted == null
                          ? (widget.media.isAnimated
                                ? 'Vista del encuadre · Fotograma inicial'
                                : 'Vista del encuadre')
                          : 'Tu sticker · Así se verá',
                      style: const TextStyle(
                        color: Palette.ink,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              if (_converted == null) ...[
                if (widget.media.isAnimated) ...[
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Elige el momento',
                          style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Text(
                        '${(_range.end - _range.start).toStringAsFixed(1)} s',
                        style: const TextStyle(
                          color: Palette.violet,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Hasta 10 segundos. Un instante suele decirlo todo.',
                    style: TextStyle(
                      color: Palette.muted,
                      fontSize: 13,
                      height: 1.5,
                    ),
                  ),
                  RangeSlider(
                    values: _range,
                    min: 0,
                    max: widget.media.duration,
                    labels: RangeLabels(
                      '${_range.start.toStringAsFixed(1)} s',
                      '${_range.end.toStringAsFixed(1)} s',
                    ),
                    onChanged: _busy ? null : _adjustRange,
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Desde ${_range.start.toStringAsFixed(1)} s'),
                      Text('Hasta ${_range.end.toStringAsFixed(1)} s'),
                    ],
                  ),
                  const SizedBox(height: 24),
                ],
                const Text(
                  'Encuadre',
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                SegmentedButton<StickerFit>(
                  segments: const [
                    ButtonSegment(
                      value: StickerFit.contain,
                      icon: Icon(Icons.fit_screen_rounded),
                      label: Text('Completo'),
                    ),
                    ButtonSegment(
                      value: StickerFit.cover,
                      icon: Icon(Icons.crop_square_rounded),
                      label: Text('Cuadrado'),
                    ),
                  ],
                  selected: {_fit},
                  onSelectionChanged: _busy
                      ? null
                      : (selection) => setState(() => _fit = selection.single),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Completo conserva toda la imagen y añade espacio transparente. Cuadrado recorta desde el centro.',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.5,
                    color: Palette.muted,
                  ),
                ),
              ] else ...[
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (widget.media.isAnimated)
                      Chip(
                        label: Text(
                          '${(_converted!.info.durationMs / 1000).toStringAsFixed(1)} s',
                        ),
                      ),
                    const Chip(label: Text('512 × 512')),
                    Chip(
                      label: Text(
                        widget.media.isAnimated
                            ? 'WebP animado'
                            : 'WebP estático',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                const Text(
                  '¿Dónde lo guardamos?',
                  style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  initialValue: _packId ?? '',
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Paquete'),
                  items: [
                    const DropdownMenuItem(
                      value: '',
                      child: Text('Crear un nuevo paquete'),
                    ),
                    for (final pack in widget.library.packs.where(
                      (p) =>
                          p.stickers.length < 30 &&
                          p.isAnimated == widget.media.isAnimated,
                    ))
                      DropdownMenuItem(
                        value: pack.id,
                        child: Text(
                          '${pack.name} (${pack.stickers.length}/30)',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: _busy
                      ? null
                      : (value) => setState(
                          () => _packId = value == '' ? null : value,
                        ),
                ),
                if (_packId == null) ...[
                  const SizedBox(height: 14),
                  TextField(
                    controller: _name,
                    enabled: !_busy,
                    maxLength: 60,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Nombre del paquete',
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                Notice(
                  '${widget.media.isAnimated ? 'Paquete de animaciones.' : 'Paquete de imágenes.'} Con 3 stickers en tu paquete ya puedes añadirlo a WhatsApp. Puedes seguir completándolo hasta llegar a 30.',
                ),
              ],
              if (_busy) ...[
                const SizedBox(height: 24),
                const LinearProgressIndicator(),
                const SizedBox(height: 12),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    _converted == null ? _progress : 'Guardando tu sticker…',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Palette.muted),
                  ),
                ),
              ],
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 18),
                  child: Semantics(liveRegion: true, child: Notice(_error!)),
                ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _busy
                    ? null
                    : _converted == null
                    ? _convert
                    : _save,
                icon: Icon(
                  _converted == null
                      ? Icons.auto_awesome_rounded
                      : Icons.bookmark_add_outlined,
                ),
                label: Text(
                  _converted == null
                      ? 'Crear sticker'
                      : widget.batchPosition < widget.batchTotal
                      ? 'Guardar y continuar'
                      : 'Guardar sticker',
                ),
              ),
              if (_converted != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: TextButton(
                    onPressed: _busy
                        ? null
                        : () => setState(() {
                            _converted = null;
                            _error = null;
                          }),
                    child: const Text('Volver a ajustar'),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _CheckerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Palette.paper);
    final paint = Paint()..color = Palette.porcelain;
    for (var y = 0; y < size.height / 16; y++) {
      for (var x = 0; x < size.width / 16; x++) {
        if ((x + y).isEven) {
          canvas.drawRect(Rect.fromLTWH(x * 16, y * 16, 16, 16), paint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
