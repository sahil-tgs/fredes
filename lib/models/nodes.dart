import 'dart:ui';
import 'package:uuid/uuid.dart';

const _uuid = Uuid();

enum NodeType { frame, group, rect, ellipse, text, line, path }

bool isContainer(NodeType t) => t == NodeType.frame || t == NodeType.group;

NodeType nodeTypeFromString(String s) {
  return NodeType.values.firstWhere((e) => e.name == s);
}

/// Base class for all canvas nodes. We use a single class with optional fields
/// instead of a deep hierarchy so JSON (de)serialization stays trivial.
///
/// `x`/`y` are **relative to the parent** (root for top-level nodes, or the
/// parent frame/group otherwise). `children` is populated only for container
/// types (`frame`, `group`).
class FredesNode {
  String id;
  NodeType type;
  String name;
  double x;
  double y;
  double rotation;
  double opacity;
  bool visible;
  bool locked;

  // Containers: children are in the container's local coordinate space.
  List<FredesNode> children;

  // rect / ellipse / text / frame
  double width;
  double height;

  // fill / stroke
  Color fill;
  Color stroke;
  double strokeWidth;
  double cornerRadius;

  // frame-only: clip children to bounds
  bool clipContent;

  // text
  String text;
  double fontSize;
  String fontFamily;
  int fontWeight;
  String align;          // left | center | right | justify
  String verticalAlign;  // top | middle | bottom
  double letterSpacing;  // px
  /// Null = "auto" (framework default). Otherwise a multiplier of font size.
  double? lineHeight;
  String decoration;     // none | underline | line-through
  String letterCase;     // original | upper | lower | title
  bool italic;

  // line / path (points are in local space)
  List<Offset> points;
  bool closed;

  FredesNode({
    String? id,
    required this.type,
    String? name,
    this.x = 0,
    this.y = 0,
    this.rotation = 0,
    this.opacity = 1,
    this.visible = true,
    this.locked = false,
    List<FredesNode>? children,
    this.width = 100,
    this.height = 100,
    this.fill = const Color(0xFF9CA3AF),
    this.stroke = const Color(0xFF000000),
    this.strokeWidth = 0,
    this.cornerRadius = 0,
    this.clipContent = true,
    this.text = 'Type something',
    this.fontSize = 24,
    this.fontFamily = 'Inter',
    this.fontWeight = 400,
    this.align = 'left',
    this.verticalAlign = 'top',
    this.letterSpacing = 0,
    this.lineHeight,
    this.decoration = 'none',
    this.letterCase = 'original',
    this.italic = false,
    List<Offset>? points,
    this.closed = false,
  })  : id = id ?? _uuid.v4(),
        name = name ?? _defaultName(type),
        children = children ?? [],
        points = points ?? const [];

  static String _defaultName(NodeType t) {
    switch (t) {
      case NodeType.frame: return 'Frame';
      case NodeType.group: return 'Group';
      case NodeType.rect: return 'Rectangle';
      case NodeType.ellipse: return 'Ellipse';
      case NodeType.text: return 'Text';
      case NodeType.line: return 'Line';
      case NodeType.path: return 'Path';
    }
  }

  FredesNode clone({String? newId}) {
    return FredesNode(
      id: newId ?? _uuid.v4(),
      type: type,
      name: name,
      x: x, y: y, rotation: rotation, opacity: opacity,
      visible: visible, locked: locked,
      children: children.map((c) => c.clone()).toList(),
      width: width, height: height,
      fill: fill, stroke: stroke, strokeWidth: strokeWidth, cornerRadius: cornerRadius,
      clipContent: clipContent,
      text: text, fontSize: fontSize, fontFamily: fontFamily, fontWeight: fontWeight,
      align: align, verticalAlign: verticalAlign,
      letterSpacing: letterSpacing, lineHeight: lineHeight,
      decoration: decoration, letterCase: letterCase, italic: italic,
      points: List<Offset>.from(points),
      closed: closed,
    );
  }

  /// Local-space bounds of the node's *own* geometry (not including children).
  /// For containers this is the frame's box; for groups it's the union of
  /// children's local bounds.
  Rect get localBounds {
    if (type == NodeType.frame || type == NodeType.rect ||
        type == NodeType.ellipse || type == NodeType.text) {
      return Rect.fromLTWH(0, 0, width, height);
    }
    if (type == NodeType.group) {
      if (children.isEmpty) return Rect.zero;
      return children.map((c) => c.localBounds.translate(c.x, c.y)).reduce((a, b) => a.expandToInclude(b));
    }
    if (type == NodeType.line || type == NodeType.path) {
      if (points.isEmpty) return Rect.zero;
      double minX = points.first.dx, minY = points.first.dy;
      double maxX = minX, maxY = minY;
      for (final p in points) {
        if (p.dx < minX) minX = p.dx;
        if (p.dy < minY) minY = p.dy;
        if (p.dx > maxX) maxX = p.dx;
        if (p.dy > maxY) maxY = p.dy;
      }
      return Rect.fromLTRB(minX, minY, maxX, maxY);
    }
    return Rect.zero;
  }

  /// Local-space bounds in the **parent's** coordinate system (adds x,y).
  Rect get bounds => localBounds.translate(x, y);

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{
      'id': id,
      'type': type.name,
      'name': name,
      'x': x, 'y': y,
      'rotation': rotation,
      'opacity': opacity,
      'visible': visible,
      'locked': locked,
    };
    if (type == NodeType.frame) {
      m['width'] = width;
      m['height'] = height;
      m['fill'] = _colorToHex(fill);
      m['stroke'] = _colorToHex(stroke);
      m['strokeWidth'] = strokeWidth;
      m['cornerRadius'] = cornerRadius;
      m['clipContent'] = clipContent;
      m['children'] = children.map((c) => c.toJson()).toList();
    } else if (type == NodeType.group) {
      m['children'] = children.map((c) => c.toJson()).toList();
    } else if (type == NodeType.rect || type == NodeType.ellipse) {
      m['width'] = width;
      m['height'] = height;
      m['fill'] = _colorToHex(fill);
      m['stroke'] = _colorToHex(stroke);
      m['strokeWidth'] = strokeWidth;
      if (type == NodeType.rect) m['cornerRadius'] = cornerRadius;
    } else if (type == NodeType.text) {
      m['width'] = width;
      m['height'] = height;
      m['text'] = text;
      m['fontSize'] = fontSize;
      m['fontFamily'] = fontFamily;
      m['fontWeight'] = fontWeight;
      m['align'] = align;
      m['verticalAlign'] = verticalAlign;
      m['letterSpacing'] = letterSpacing;
      if (lineHeight != null) m['lineHeight'] = lineHeight;
      m['decoration'] = decoration;
      m['letterCase'] = letterCase;
      m['italic'] = italic;
      m['fill'] = _colorToHex(fill);
    } else if (type == NodeType.line || type == NodeType.path) {
      m['stroke'] = _colorToHex(stroke);
      m['strokeWidth'] = strokeWidth;
      m['points'] = points.expand((p) => [p.dx, p.dy]).toList();
      if (type == NodeType.path) {
        m['fill'] = _colorToHex(fill);
        m['closed'] = closed;
      }
    }
    return m;
  }

  factory FredesNode.fromJson(Map<String, dynamic> j) {
    final type = nodeTypeFromString(j['type'] as String);
    final pts = (j['points'] as List?)?.cast<num>().map((e) => e.toDouble()).toList() ?? const <double>[];
    final offsets = <Offset>[];
    for (var i = 0; i + 1 < pts.length; i += 2) {
      offsets.add(Offset(pts[i], pts[i + 1]));
    }
    final kids = ((j['children'] as List?) ?? const [])
        .map((e) => FredesNode.fromJson(e as Map<String, dynamic>))
        .toList();
    final defaultFill = (type == NodeType.frame) ? '#FFFFFF' : '#9CA3AF';
    return FredesNode(
      id: j['id'] as String,
      type: type,
      name: j['name'] as String? ?? _defaultName(type),
      x: (j['x'] as num?)?.toDouble() ?? 0,
      y: (j['y'] as num?)?.toDouble() ?? 0,
      rotation: (j['rotation'] as num?)?.toDouble() ?? 0,
      opacity: (j['opacity'] as num?)?.toDouble() ?? 1,
      visible: j['visible'] as bool? ?? true,
      locked: j['locked'] as bool? ?? false,
      children: kids,
      width: (j['width'] as num?)?.toDouble() ?? 100,
      height: (j['height'] as num?)?.toDouble() ?? 100,
      fill: _hexToColor(j['fill'] as String? ?? defaultFill),
      stroke: _hexToColor(j['stroke'] as String? ?? '#000000'),
      strokeWidth: (j['strokeWidth'] as num?)?.toDouble() ?? 0,
      cornerRadius: (j['cornerRadius'] as num?)?.toDouble() ?? 0,
      clipContent: j['clipContent'] as bool? ?? true,
      text: j['text'] as String? ?? 'Type something',
      fontSize: (j['fontSize'] as num?)?.toDouble() ?? 24,
      fontFamily: j['fontFamily'] as String? ?? 'Inter',
      fontWeight: (j['fontWeight'] as num?)?.toInt() ?? 400,
      align: j['align'] as String? ?? 'left',
      verticalAlign: j['verticalAlign'] as String? ?? 'top',
      letterSpacing: (j['letterSpacing'] as num?)?.toDouble() ?? 0,
      lineHeight: (j['lineHeight'] as num?)?.toDouble(),
      decoration: j['decoration'] as String? ?? 'none',
      letterCase: j['letterCase'] as String? ?? 'original',
      italic: j['italic'] as bool? ?? false,
      points: offsets,
      closed: j['closed'] as bool? ?? false,
    );
  }
}

String _colorToHex(Color c) {
  final r = c.red.toRadixString(16).padLeft(2, '0');
  final g = c.green.toRadixString(16).padLeft(2, '0');
  final b = c.blue.toRadixString(16).padLeft(2, '0');
  return '#$r$g$b';
}

Color _hexToColor(String hex) {
  var h = hex.replaceAll('#', '');
  if (h.length == 3) {
    h = h.split('').map((c) => '$c$c').join();
  }
  if (h.length == 6) h = 'ff$h';
  return Color(int.parse(h, radix: 16));
}

String colorToHex(Color c) => _colorToHex(c);
Color hexToColor(String s) => _hexToColor(s);

/// Apply the Figma-style letter-case transform to a string.
String applyLetterCase(String s, String mode) {
  switch (mode) {
    case 'upper': return s.toUpperCase();
    case 'lower': return s.toLowerCase();
    case 'title':
      return s.split(' ').map((w) {
        if (w.isEmpty) return w;
        return w[0].toUpperCase() + w.substring(1).toLowerCase();
      }).join(' ');
    default: return s;
  }
}
