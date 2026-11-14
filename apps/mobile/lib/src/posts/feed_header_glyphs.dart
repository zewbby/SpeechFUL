import 'package:flutter/material.dart';

import '../design_system/telegram_theme.dart';

/// Keeps the header's icon footprint without adding a surrounding frame.
class FeedHeaderTile extends StatelessWidget {
  const FeedHeaderTile({super.key, required this.child, this.size = 40});
  final Widget child;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: Center(child: child),
  );
}

class FeedHeaderSearchGlyph extends StatelessWidget {
  const FeedHeaderSearchGlyph({super.key});
  @override
  Widget build(BuildContext context) => CustomPaint(
    size: const Size(24, 24),
    painter: _FeedHeaderGlyphPainter(
      HhTelegramPalette.of(context).accent,
      false,
    ),
  );
}

class FeedHeaderAvatarGlyph extends StatelessWidget {
  const FeedHeaderAvatarGlyph({super.key});
  @override
  Widget build(BuildContext context) => CustomPaint(
    size: const Size(24, 24),
    painter: _FeedHeaderGlyphPainter(
      HhTelegramPalette.of(context).accent,
      true,
    ),
  );
}

class _FeedHeaderGlyphPainter extends CustomPainter {
  const _FeedHeaderGlyphPainter(this.color, this.avatar);
  final Color color;
  final bool avatar;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    if (avatar) {
      canvas.drawCircle(const Offset(12, 12), 10, stroke);
      canvas.drawCircle(const Offset(12, 9), 2.7, stroke);
      final shoulders = Path()
        ..moveTo(7.2, 17.5)
        ..cubicTo(7.6, 15.1, 9.3, 13.8, 12, 13.8)
        ..cubicTo(14.7, 13.8, 16.4, 15.1, 16.8, 17.5);
      canvas.drawPath(shoulders, stroke);
    } else {
      canvas.drawCircle(const Offset(10, 10), 6, stroke);
      canvas.drawLine(const Offset(14.5, 14.5), const Offset(20, 20), stroke);
    }
  }

  @override
  bool shouldRepaint(_FeedHeaderGlyphPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.avatar != avatar;
}
