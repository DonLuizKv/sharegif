import 'package:material_ui/material_ui.dart';

abstract final class Palette {
  static const porcelain = Color(0xFFE4E3DE);
  static const taupe = Color(0xFF8B7E71);
  static const violet = Color(0xFF6B2BFF);
  static const ink = Color(0xFF292620);
  static const muted = Color(0xFF635B53);
  static const paper = Color(0xFFF4F3EF);
  static const line = Color(0xFFC9C4BB);
}

ThemeData appTheme() {
  final base = ThemeData(
    useMaterial3: true,
    fontFamily: 'Roboto',
    colorScheme: ColorScheme.fromSeed(
      seedColor: Palette.violet,
      surface: Palette.porcelain,
    ),
  );
  return base.copyWith(
    scaffoldBackgroundColor: Palette.porcelain,
    colorScheme: base.colorScheme.copyWith(
      primary: Palette.violet,
      onPrimary: Colors.white,
      secondary: Palette.taupe,
      onSurface: Palette.ink,
    ),
    textTheme: base.textTheme.apply(
      bodyColor: Palette.ink,
      displayColor: Palette.ink,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Palette.porcelain,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 56),
        backgroundColor: Palette.violet,
        foregroundColor: Colors.white,
        textStyle: const TextStyle(
          fontFamily: 'Roboto',
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 52),
        foregroundColor: Palette.ink,
        side: const BorderSide(color: Palette.line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Palette.paper,
      hintStyle: const TextStyle(color: Palette.muted, fontSize: 14),
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Palette.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Palette.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Palette.violet, width: 2),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: Palette.ink,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Palette.paper,
      showDragHandle: true,
    ),
    dividerTheme: const DividerThemeData(color: Palette.line, thickness: 1),
  );
}

class StickerMark extends StatelessWidget {
  const StickerMark({super.key, this.size = 40});
  final double size;
  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: Palette.violet,
      borderRadius: BorderRadius.circular(size * 0.3),
    ),
    child: Icon(
      Icons.auto_awesome_rounded,
      color: Colors.white,
      size: size * .55,
    ),
  );
}

class StickerIllustration extends StatelessWidget {
  const StickerIllustration({super.key, this.size = 128});
  final double size;
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox(
      width: size,
      height: size,
      child: Transform.rotate(
        angle: -.13,
        child: CustomPaint(painter: _StickerPainter()),
      ),
    ),
  );
}

class _StickerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 128, size.height / 128);
    final shadow = RRect.fromRectAndRadius(
      const Rect.fromLTWH(17, 21, 98, 98),
      const Radius.circular(28),
    );
    canvas.drawRRect(
      shadow,
      Paint()..color = Palette.ink.withValues(alpha: .12),
    );
    final shape = Path()
      ..moveTo(38, 12)
      ..lineTo(90, 12)
      ..quadraticBezierTo(112, 12, 112, 34)
      ..lineTo(112, 81)
      ..lineTo(81, 112)
      ..lineTo(38, 112)
      ..quadraticBezierTo(12, 112, 12, 86)
      ..lineTo(12, 38)
      ..quadraticBezierTo(12, 12, 38, 12)
      ..close();
    canvas.drawPath(shape, Paint()..color = Palette.paper);
    final fold = Path()
      ..moveTo(81, 112)
      ..lineTo(81, 96)
      ..quadraticBezierTo(81, 81, 96, 81)
      ..lineTo(112, 81)
      ..close();
    canvas.drawPath(fold, Paint()..color = Palette.porcelain);
    final stroke = Paint()
      ..color = Palette.violet
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(const Offset(42, 45), const Offset(42, 54), stroke);
    canvas.drawLine(const Offset(76, 45), const Offset(76, 54), stroke);
    canvas.drawPath(
      Path()
        ..moveTo(39, 70)
        ..quadraticBezierTo(59, 91, 79, 70),
      stroke,
    );
    canvas.drawCircle(
      const Offset(9, 8),
      4,
      Paint()..color = Palette.porcelain,
    );
    canvas.drawLine(
      const Offset(116, 23),
      const Offset(127, 23),
      stroke..strokeWidth = 3,
    );
    canvas.drawLine(const Offset(122, 17), const Offset(122, 29), stroke);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.color = Palette.muted});
  final String text;
  final Color color;
  @override
  Widget build(BuildContext context) => Text(
    text,
    style: TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.7,
      color: color,
    ),
  );
}

class Notice extends StatelessWidget {
  const Notice(this.text, {super.key, this.icon = Icons.info_outline_rounded});
  final String text;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Palette.taupe.withValues(alpha: .12),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: Palette.muted),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 13,
              height: 1.5,
              color: Palette.muted,
            ),
          ),
        ),
      ],
    ),
  );
}
