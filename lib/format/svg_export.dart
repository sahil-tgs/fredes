import '../models/document.dart';
import '../models/nodes.dart';

String pageToSvg(FredesPage page) {
  // Compute SVG viewBox as the bounding box of top-level nodes (padded), so
  // the export represents the actual content instead of a fixed frame.
  final bounds = _pageBounds(page);
  final vb = bounds ?? const _RectLTWH(0, 0, 1440, 1024);
  final b = StringBuffer();
  b.writeln('<?xml version="1.0" encoding="UTF-8"?>');
  b.writeln('<svg xmlns="http://www.w3.org/2000/svg" width="${vb.width}" height="${vb.height}" '
      'viewBox="${vb.x} ${vb.y} ${vb.width} ${vb.height}">');
  // Workspace backdrop is exported as a solid rect for fidelity.
  b.writeln('<rect x="${vb.x}" y="${vb.y}" width="${vb.width}" height="${vb.height}" fill="${_esc(page.background)}" />');
  for (final n in page.nodes) {
    if (!n.visible) continue;
    b.writeln(_emit(n, 0));
  }
  b.writeln('</svg>');
  return b.toString();
}

_RectLTWH? _pageBounds(FredesPage page) {
  double? minX, minY, maxX, maxY;
  void walk(FredesNode n, double ox, double oy) {
    final origin = ox + n.x;
    final originY = oy + n.y;
    if (isContainer(n.type)) {
      if (n.type == NodeType.frame) {
        minX = (minX ?? origin) < origin ? minX : origin;
        minY = (minY ?? originY) < originY ? minY : originY;
        final rX = origin + n.width, rY = originY + n.height;
        maxX = (maxX ?? rX) > rX ? maxX : rX;
        maxY = (maxY ?? rY) > rY ? maxY : rY;
      }
      for (final c in n.children) {
        walk(c, origin, originY);
      }
      return;
    }
    final lb = n.localBounds;
    final x0 = origin + lb.left, y0 = originY + lb.top;
    final x1 = origin + lb.right, y1 = originY + lb.bottom;
    minX = (minX ?? x0) < x0 ? minX : x0;
    minY = (minY ?? y0) < y0 ? minY : y0;
    maxX = (maxX ?? x1) > x1 ? maxX : x1;
    maxY = (maxY ?? y1) > y1 ? maxY : y1;
  }
  for (final n in page.nodes) {
    if (!n.visible) continue;
    walk(n, 0, 0);
  }
  if (minX == null) return null;
  const pad = 32.0;
  return _RectLTWH(minX! - pad, minY! - pad, (maxX! - minX!) + pad * 2, (maxY! - minY!) + pad * 2);
}

String _emit(FredesNode n, int indent) {
  final pad = '  ' * (indent + 1);
  final tx = 'transform="translate(${n.x},${n.y})${n.rotation != 0 && !isContainer(n.type) ? ' rotate(${n.rotation} ${n.width / 2} ${n.height / 2})' : ''}"';
  final op = n.opacity == 1 ? '' : ' opacity="${n.opacity}"';

  switch (n.type) {
    case NodeType.frame:
      final buf = StringBuffer();
      buf.write('$pad<g $tx$op>\n');
      buf.write('$pad  <rect width="${n.width}" height="${n.height}" rx="${n.cornerRadius}" fill="${_color(n.fill)}" stroke="${_color(n.stroke)}" stroke-width="${n.strokeWidth}" />\n');
      if (n.clipContent) {
        buf.write('$pad  <clipPath id="clip-${n.id}"><rect width="${n.width}" height="${n.height}" rx="${n.cornerRadius}" /></clipPath>\n');
        buf.write('$pad  <g clip-path="url(#clip-${n.id})">\n');
      }
      for (final c in n.children) {
        if (!c.visible) continue;
        buf.write('${_emit(c, indent + 2)}\n');
      }
      if (n.clipContent) buf.write('$pad  </g>\n');
      buf.write('$pad</g>');
      return buf.toString();

    case NodeType.group:
      final buf = StringBuffer('$pad<g $tx$op>\n');
      for (final c in n.children) {
        if (!c.visible) continue;
        buf.write('${_emit(c, indent + 1)}\n');
      }
      buf.write('$pad</g>');
      return buf.toString();

    case NodeType.rect:
      return '$pad<rect $tx$op width="${n.width}" height="${n.height}" rx="${n.cornerRadius}" '
          'fill="${_color(n.fill)}" stroke="${_color(n.stroke)}" stroke-width="${n.strokeWidth}" />';

    case NodeType.ellipse:
      final cx = n.width / 2, cy = n.height / 2;
      return '$pad<ellipse $tx$op cx="$cx" cy="$cy" rx="$cx" ry="$cy" '
          'fill="${_color(n.fill)}" stroke="${_color(n.stroke)}" stroke-width="${n.strokeWidth}" />';

    case NodeType.text:
      final anchor = n.align == 'center' ? 'middle' : (n.align == 'right' ? 'end' : 'start');
      final ax = n.align == 'center' ? n.width / 2 : (n.align == 'right' ? n.width : 0);
      final style = <String>[];
      if (n.italic) style.add('font-style="italic"');
      if (n.letterSpacing != 0) style.add('letter-spacing="${n.letterSpacing}"');
      if (n.decoration == 'underline') style.add('text-decoration="underline"');
      if (n.decoration == 'line-through') style.add('text-decoration="line-through"');
      final txt = applyLetterCase(n.text, n.letterCase);
      return '$pad<text $tx$op x="$ax" y="${n.fontSize}" fill="${_color(n.fill)}" '
          'font-family="${_esc(n.fontFamily)}" font-size="${n.fontSize}" '
          'font-weight="${n.fontWeight}" text-anchor="$anchor"${style.isEmpty ? "" : " ${style.join(" ")}"}>${_esc(txt)}</text>';

    case NodeType.line:
      if (n.points.length < 2) return '';
      final a = n.points[0], b2 = n.points[1];
      return '$pad<line $tx$op x1="${a.dx}" y1="${a.dy}" x2="${b2.dx}" y2="${b2.dy}" '
          'stroke="${_color(n.stroke)}" stroke-width="${n.strokeWidth}" stroke-linecap="round" />';

    case NodeType.path:
      if (n.points.length < 2) return '';
      final d = StringBuffer('M ${n.points.first.dx} ${n.points.first.dy}');
      for (var i = 1; i < n.points.length; i++) {
        d.write(' L ${n.points[i].dx} ${n.points[i].dy}');
      }
      if (n.closed) d.write(' Z');
      final fill = (n.fill.alpha == 0) ? 'none' : _color(n.fill);
      return '$pad<path $tx$op d="$d" stroke="${_color(n.stroke)}" stroke-width="${n.strokeWidth}" '
          'fill="$fill" stroke-linecap="round" stroke-linejoin="round" />';
  }
}

String _color(c) {
  final r = c.red.toRadixString(16).padLeft(2, '0');
  final g = c.green.toRadixString(16).padLeft(2, '0');
  final b = c.blue.toRadixString(16).padLeft(2, '0');
  return '#$r$g$b';
}

String _esc(String s) =>
    s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');

class _RectLTWH {
  final double x, y, width, height;
  const _RectLTWH(this.x, this.y, this.width, this.height);
}
