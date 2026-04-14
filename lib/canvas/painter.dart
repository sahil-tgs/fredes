import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../models/document.dart';
import '../models/nodes.dart';

/// Painter driven by the document's active page. Render order:
///   1. Workspace backdrop (filled solid, then subtle dot grid overlay).
///   2. Nodes, back-to-front, recursively through containers.
///   3. Selection outlines (drawn last on top of everything).
///
/// All coordinates passed into [paint] are already in page-space because the
/// enclosing [Transform] handles pan & zoom.
class FredesPainter extends CustomPainter {
  /// Size of the rendered viewport in **screen** pixels.
  final Size viewportScreen;
  /// Current pan/zoom from the DocController — used so the backdrop can be
  /// drawn as a page-space rectangle that always fills the viewport.
  final Offset pan;
  final double zoom;

  final FredesPage page;
  final Set<String> selection;
  final FredesNode? drawingPreview;
  /// Rubber-band selection rect in **page space**. When non-null, a translucent
  /// blue rectangle is drawn over the canvas.
  final Rect? marqueePage;
  /// If set, the text node with this id is hidden from rendering because the
  /// inline text editor is displaying its content live. Prevents ghosting.
  final String? hideNodeId;

  /// Logical extent of the workspace. Not infinite — very large but bounded.
  static const double workspaceExtent = 100000;

  FredesPainter({
    required this.viewportScreen,
    required this.pan,
    required this.zoom,
    required this.page,
    required this.selection,
    this.drawingPreview,
    this.marqueePage,
    this.hideNodeId,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Visible rect in page coords (screen viewport inverse-transformed).
    final visible = Rect.fromLTWH(
      -pan.dx / zoom,
      -pan.dy / zoom,
      viewportScreen.width / zoom,
      viewportScreen.height / zoom,
    );

    // 1. Workspace backdrop (solid) — just the visible area is enough; we're
    //    clipped by the enclosing ClipRect so drawing a huge rect is fine too.
    canvas.drawRect(visible, Paint()..color = _hex(page.background));

    // 2. Dot grid overlay — every 100 page units, sized so it stays crisp at
    //    any zoom. Skip entirely when zoomed way out (dots become noise).
    if (zoom > 0.25) {
      _paintDotGrid(canvas, visible);
    }

    // 3. Nodes, back-to-front, recursively.
    for (final n in page.nodes) {
      _paintNode(canvas, n);
    }
    if (drawingPreview != null) _paintNode(canvas, drawingPreview!);

    // 4. Selection overlays in world space.
    _paintSelections(canvas, page.nodes, Offset.zero);

    // 5. Marquee rectangle (drawn last so it's always visible).
    if (marqueePage != null) {
      final r = marqueePage!;
      final fill = Paint()..color = const Color(0x333B82F6);
      final border = Paint()
        ..color = const Color(0xFF3B82F6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0 / zoom;
      canvas.drawRect(r, fill);
      canvas.drawRect(r, border);
    }
  }

  void _paintDotGrid(Canvas canvas, Rect visible) {
    const spacing = 100.0;
    // Snap visible bounds down to the nearest grid cell.
    final startX = (visible.left / spacing).floor() * spacing;
    final startY = (visible.top / spacing).floor() * spacing;
    final paint = Paint()..color = const Color(0x22FFFFFF);
    final r = (0.8 / zoom).clamp(0.4, 2.0);
    for (double y = startY; y <= visible.bottom; y += spacing) {
      for (double x = startX; x <= visible.right; x += spacing) {
        canvas.drawCircle(Offset(x, y), r, paint);
      }
    }
  }

  void _paintNode(Canvas canvas, FredesNode n) {
    if (!n.visible) return;
    if (hideNodeId != null && n.id == hideNodeId) return;
    canvas.save();
    canvas.translate(n.x, n.y);
    if (n.rotation != 0 && !isContainer(n.type)) {
      final cx = n.width / 2, cy = n.height / 2;
      canvas.translate(cx, cy);
      canvas.rotate(n.rotation * 3.1415926535 / 180);
      canvas.translate(-cx, -cy);
    }

    switch (n.type) {
      case NodeType.frame:
        final rect = Rect.fromLTWH(0, 0, n.width, n.height);
        // Fill
        final p = Paint()
          ..color = n.fill.withOpacity(n.fill.opacity * n.opacity)
          ..style = PaintingStyle.fill;
        if (n.cornerRadius > 0) {
          canvas.drawRRect(RRect.fromRectAndRadius(rect, Radius.circular(n.cornerRadius)), p);
        } else {
          canvas.drawRect(rect, p);
        }
        // Children (optionally clipped)
        canvas.save();
        if (n.clipContent) {
          if (n.cornerRadius > 0) {
            canvas.clipRRect(RRect.fromRectAndRadius(rect, Radius.circular(n.cornerRadius)));
          } else {
            canvas.clipRect(rect);
          }
        }
        for (final c in n.children) {
          _paintNode(canvas, c);
        }
        canvas.restore();
        // Border (on top of children)
        if (n.strokeWidth > 0) {
          final s = Paint()
            ..color = n.stroke.withOpacity(n.stroke.opacity * n.opacity)
            ..style = PaintingStyle.stroke
            ..strokeWidth = n.strokeWidth;
          if (n.cornerRadius > 0) {
            canvas.drawRRect(RRect.fromRectAndRadius(rect, Radius.circular(n.cornerRadius)), s);
          } else {
            canvas.drawRect(rect, s);
          }
        }
        // Frame name label, drawn just above the frame. Negative y so it
        // lives outside the frame's own rect.
        _paintLabel(canvas, n.name, const Offset(0, -6));
        break;

      case NodeType.group:
        // No own visuals — just paint children.
        for (final c in n.children) {
          _paintNode(canvas, c);
        }
        break;

      case NodeType.rect:
        final p = Paint()
          ..color = n.fill.withOpacity(n.fill.opacity * n.opacity)
          ..style = PaintingStyle.fill;
        final rect = Rect.fromLTWH(0, 0, n.width, n.height);
        if (n.cornerRadius > 0) {
          canvas.drawRRect(RRect.fromRectAndRadius(rect, Radius.circular(n.cornerRadius)), p);
        } else {
          canvas.drawRect(rect, p);
        }
        if (n.strokeWidth > 0) {
          final s = Paint()
            ..color = n.stroke.withOpacity(n.stroke.opacity * n.opacity)
            ..style = PaintingStyle.stroke
            ..strokeWidth = n.strokeWidth;
          if (n.cornerRadius > 0) {
            canvas.drawRRect(RRect.fromRectAndRadius(rect, Radius.circular(n.cornerRadius)), s);
          } else {
            canvas.drawRect(rect, s);
          }
        }
        break;

      case NodeType.ellipse:
        final rect = Rect.fromLTWH(0, 0, n.width, n.height);
        canvas.drawOval(rect, Paint()
          ..color = n.fill.withOpacity(n.fill.opacity * n.opacity)
          ..style = PaintingStyle.fill);
        if (n.strokeWidth > 0) {
          canvas.drawOval(rect, Paint()
            ..color = n.stroke.withOpacity(n.stroke.opacity * n.opacity)
            ..style = PaintingStyle.stroke
            ..strokeWidth = n.strokeWidth);
        }
        break;

      case NodeType.text:
        final tp = TextPainter(
          text: TextSpan(
            text: applyLetterCase(n.text, n.letterCase),
            style: TextStyle(
              color: n.fill.withOpacity(n.fill.opacity * n.opacity),
              fontSize: n.fontSize,
              fontFamily: n.fontFamily,
              fontWeight: _wt(n.fontWeight),
              fontStyle: n.italic ? FontStyle.italic : FontStyle.normal,
              letterSpacing: n.letterSpacing,
              height: n.lineHeight,
              decoration: _decoration(n.decoration),
              decorationColor: n.fill.withOpacity(n.fill.opacity * n.opacity),
            ),
          ),
          textAlign: _align(n.align),
          textDirection: TextDirection.ltr,
        );
        // Lay out with a fixed width (min == max) so `textAlign` has an actual
        // box to align against. With only maxWidth set, the painter collapses
        // to the content's own width and alignment becomes a no-op.
        final w = n.width.clamp(1.0, double.infinity);
        tp.layout(minWidth: w, maxWidth: w);
        // Vertical alignment inside the node's height box.
        double dy = 0;
        if (n.verticalAlign == 'middle') {
          dy = ((n.height - tp.height) / 2).clamp(0, double.infinity);
        } else if (n.verticalAlign == 'bottom') {
          dy = (n.height - tp.height).clamp(0, double.infinity);
        }
        tp.paint(canvas, Offset(0, dy));
        break;

      case NodeType.line:
        if (n.points.length >= 2) {
          final s = Paint()
            ..color = n.stroke.withOpacity(n.stroke.opacity * n.opacity)
            ..style = PaintingStyle.stroke
            ..strokeWidth = n.strokeWidth.clamp(0.5, double.infinity)
            ..strokeCap = StrokeCap.round;
          canvas.drawLine(n.points[0], n.points[1], s);
        }
        break;

      case NodeType.path:
        if (n.points.length >= 2) {
          final path = ui.Path()..moveTo(n.points.first.dx, n.points.first.dy);
          for (var i = 1; i < n.points.length; i++) {
            path.lineTo(n.points[i].dx, n.points[i].dy);
          }
          if (n.closed) path.close();
          if (n.fill.alpha > 0) {
            canvas.drawPath(path, Paint()
              ..color = n.fill.withOpacity(n.fill.opacity * n.opacity)
              ..style = PaintingStyle.fill);
          }
          if (n.strokeWidth > 0) {
            canvas.drawPath(path, Paint()
              ..color = n.stroke.withOpacity(n.stroke.opacity * n.opacity)
              ..style = PaintingStyle.stroke
              ..strokeWidth = n.strokeWidth
              ..strokeCap = StrokeCap.round
              ..strokeJoin = StrokeJoin.round);
          }
        }
        break;
    }
    canvas.restore();
  }

  /// Recursive selection pass. We compute each node's absolute position by
  /// accumulating parent offsets instead of stacking canvas transforms,
  /// because selection boxes must be drawn in an axis-aligned frame.
  void _paintSelections(Canvas canvas, List<FredesNode> nodes, Offset parentOrigin) {
    for (final n in nodes) {
      final origin = parentOrigin + Offset(n.x, n.y);
      if (selection.contains(n.id)) {
        _paintSelectionBox(canvas, n, origin);
      }
      if (isContainer(n.type)) {
        _paintSelections(canvas, n.children, origin);
      }
    }
  }

  void _paintSelectionBox(Canvas canvas, FredesNode n, Offset origin) {
    final localB = n.localBounds;
    final r = Rect.fromLTWH(
      origin.dx + localB.left,
      origin.dy + localB.top,
      localB.width,
      localB.height,
    );
    final p = Paint()
      ..color = const Color(0xFF3B82F6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5 / zoom;
    canvas.drawRect(r, p);
    final handles = [
      r.topLeft, r.topCenter, r.topRight,
      r.centerLeft, r.centerRight,
      r.bottomLeft, r.bottomCenter, r.bottomRight,
    ];
    final hSize = 8 / zoom;
    final hp = Paint()..color = Colors.white;
    final hs = Paint()
      ..color = const Color(0xFF3B82F6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5 / zoom;
    for (final h in handles) {
      final hr = Rect.fromCenter(center: h, width: hSize, height: hSize);
      canvas.drawRect(hr, hp);
      canvas.drawRect(hr, hs);
    }
  }

  void _paintLabel(Canvas canvas, String text, Offset at) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: const Color(0xFFBFBFBF),
          fontSize: 11 / zoom,
          fontWeight: FontWeight.w500,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    tp.layout();
    tp.paint(canvas, Offset(at.dx, at.dy - tp.height));
  }

  @override
  bool shouldRepaint(covariant FredesPainter oldDelegate) => true;
}

FontWeight _wt(int w) {
  const map = {
    100: FontWeight.w100, 200: FontWeight.w200, 300: FontWeight.w300,
    400: FontWeight.w400, 500: FontWeight.w500, 600: FontWeight.w600,
    700: FontWeight.w700, 800: FontWeight.w800, 900: FontWeight.w900,
  };
  return map[w] ?? FontWeight.w400;
}

TextAlign _align(String a) {
  switch (a) {
    case 'center': return TextAlign.center;
    case 'right': return TextAlign.right;
    case 'justify': return TextAlign.justify;
    default: return TextAlign.left;
  }
}

TextDecoration _decoration(String d) {
  switch (d) {
    case 'underline': return TextDecoration.underline;
    case 'line-through': return TextDecoration.lineThrough;
    default: return TextDecoration.none;
  }
}

Color _hex(String hex) {
  var h = hex.replaceAll('#', '');
  if (h.length == 6) h = 'FF$h';
  return Color(int.parse(h, radix: 16));
}
