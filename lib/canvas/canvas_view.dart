import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/document.dart';
import '../models/nodes.dart';
import '../state/doc_controller.dart';
import 'painter.dart';

class CanvasView extends StatefulWidget {
  final DocController doc;
  const CanvasView({super.key, required this.doc});

  @override
  State<CanvasView> createState() => _CanvasViewState();
}

class _CanvasViewState extends State<CanvasView> {
  FredesNode? _drawing;
  Offset? _panStartLocal;           // Hand tool drag (left-click)
  Offset? _middlePanStart;          // Middle-click anywhere → pan
  Offset? _moveStart;               // page-space drag origin when moving selection
  Map<String, Offset>? _moveOriginalPos;
  String? _editingTextId;
  Size _viewport = Size.zero;

  // Right-click marquee selection (page-space)
  Offset? _marqueeStartPage;
  Offset? _marqueeEndPage;

  // Resize-by-handle state
  String? _resizeHandle;          // tl,t,tr,l,r,bl,b,br
  String? _resizeNodeId;
  Rect? _resizeOriginalAbsRect;   // absolute-page-space rect at drag start
  Offset? _resizeOriginalLocalXY; // node's own x,y at drag start

  final TextEditingController _textCtrl = TextEditingController();
  final FocusNode _textFocus = FocusNode();

  DocController get c => widget.doc;

  Offset _toPage(Offset screenLocal) => (screenLocal - c.pan) / c.zoom;

  @override
  void initState() {
    super.initState();
    c.addListener(_listener);
    // Escape cancels inline text editing without committing. Registered on
    // the focus node itself so it only fires while the text field has focus
    // — no separate KeyboardListener that could steal focus.
    _textFocus.onKeyEvent = (node, event) {
      if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape) {
        _textFocus.unfocus();
        setState(() => _editingTextId = null);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    };
  }
  @override
  void dispose() {
    c.removeListener(_listener);
    _textCtrl.dispose();
    _textFocus.dispose();
    super.dispose();
  }
  void _listener() => setState(() {});

  // ── raw pointer handlers (middle-click pan + right-click marquee) ───
  void _onPointerDown(PointerDownEvent e) {
    if (e.buttons == kMiddleMouseButton) {
      _middlePanStart = e.localPosition - c.pan;
      return;
    }
    if (e.buttons == kSecondaryMouseButton) {
      final pt = _toPage(e.localPosition);
      setState(() {
        _marqueeStartPage = pt;
        _marqueeEndPage = pt;
      });
      return;
    }
  }

  void _onPointerMove(PointerMoveEvent e) {
    if (_middlePanStart != null && e.buttons == kMiddleMouseButton) {
      c.setPan(e.localPosition - _middlePanStart!);
      return;
    }
    if (_marqueeStartPage != null && e.buttons == kSecondaryMouseButton) {
      setState(() => _marqueeEndPage = _toPage(e.localPosition));
      return;
    }
  }

  void _onPointerUp(PointerUpEvent e) {
    if (_middlePanStart != null) {
      _middlePanStart = null;
      return;
    }
    if (_marqueeStartPage != null && _marqueeEndPage != null) {
      _commitMarquee();
      setState(() {
        _marqueeStartPage = null;
        _marqueeEndPage = null;
      });
    }
  }

  void _commitMarquee() {
    final a = _marqueeStartPage!;
    final b = _marqueeEndPage!;
    final rect = Rect.fromPoints(a, b);
    // Only select top-level page nodes whose absolute bounds intersect.
    final hits = <String>[];
    for (final n in c.activePage.nodes) {
      final abs = n.localBounds.translate(n.x, n.y);
      if (abs.overlaps(rect) || rect.contains(abs.topLeft) || abs.contains(rect.topLeft)) {
        hits.add(n.id);
      }
    }
    final additive = HardwareKeyboard.instance.isShiftPressed;
    if (additive) {
      final next = {...c.selection, ...hits};
      c.setSelection(next);
    } else {
      c.setSelection(hits);
    }
  }

  // ── gesture handlers (left-click only) ──────────────────────────────
  void _onPanStart(DragStartDetails d) {
    final pt = _toPage(d.localPosition);

    if (c.tool == Tool.hand) {
      _panStartLocal = d.localPosition - c.pan;
      return;
    }

    if (c.tool == Tool.select) {
      // Check resize handles on the currently-selected single node first —
      // they're painted on top of the node itself so must beat hit-testing.
      final handleHit = _pickResizeHandle(pt);
      if (handleHit != null) {
        final n = c.findNode(handleHit.$1)!;
        final parentAbs = c.absoluteOriginOf(handleHit.$1) ?? Offset.zero;
        _resizeHandle = handleHit.$2;
        _resizeNodeId = handleHit.$1;
        _resizeOriginalAbsRect = Rect.fromLTWH(parentAbs.dx + n.x, parentAbs.dy + n.y, n.width, n.height);
        _resizeOriginalLocalXY = Offset(n.x, n.y);
        c.pushHistory();
        return;
      }
      final hit = c.hitTest(pt);
      if (hit != null) {
        if (!c.selection.contains(hit.node.id)) {
          c.toggleSelection(hit.node.id);
        }
        _moveStart = pt;
        _moveOriginalPos = {
          for (final id in c.selection)
            if (c.findNode(id) != null) id: Offset(c.findNode(id)!.x, c.findNode(id)!.y),
        };
        c.pushHistory();
      } else {
        // Empty-area left-click drag also starts a marquee.
        c.clearSelection();
        setState(() {
          _marqueeStartPage = pt;
          _marqueeEndPage = pt;
        });
      }
      return;
    }

    if (c.tool == Tool.text) {
      final n = FredesNode(type: NodeType.text, x: pt.dx, y: pt.dy, width: 220, height: 32);
      c.addNodePageSpace(n, pt);
      _startEditingText(n);
      c.setTool(Tool.select);
      return;
    }

    FredesNode? n;
    switch (c.tool) {
      case Tool.frame:
        n = FredesNode(type: NodeType.frame, x: pt.dx, y: pt.dy, width: 1, height: 1, fill: const Color(0xFFFFFFFF));
        break;
      case Tool.rect:
        n = FredesNode(type: NodeType.rect, x: pt.dx, y: pt.dy, width: 1, height: 1);
        break;
      case Tool.ellipse:
        n = FredesNode(type: NodeType.ellipse, x: pt.dx, y: pt.dy, width: 1, height: 1);
        break;
      case Tool.line:
        n = FredesNode(type: NodeType.line, points: [pt, pt], strokeWidth: 2, stroke: const Color(0xFF111111));
        break;
      case Tool.pen:
        n = FredesNode(type: NodeType.path, points: [pt], strokeWidth: 2, stroke: const Color(0xFF111111), fill: const Color(0x00000000));
        break;
      default:
        n = null;
    }
    if (n != null) setState(() => _drawing = n);
  }

  void _onPanUpdate(DragUpdateDetails d) {
    final pt = _toPage(d.localPosition);

    if (c.tool == Tool.hand && _panStartLocal != null) {
      c.setPan(d.localPosition - _panStartLocal!);
      return;
    }

    if (_resizeHandle != null) {
      _applyResize(pt);
      return;
    }

    if (_moveStart != null && _moveOriginalPos != null) {
      final delta = pt - _moveStart!;
      for (final id in c.selection) {
        final n = c.findNode(id);
        if (n == null) continue;
        final orig = _moveOriginalPos![id]!;
        n.x = orig.dx + delta.dx;
        n.y = orig.dy + delta.dy;
      }
      c.touch();
      return;
    }

    if (_marqueeStartPage != null) {
      setState(() => _marqueeEndPage = pt);
      return;
    }

    if (_drawing == null) return;
    setState(() {
      final n = _drawing!;
      if (n.type == NodeType.rect || n.type == NodeType.ellipse || n.type == NodeType.frame) {
        n.width = pt.dx - n.x;
        n.height = pt.dy - n.y;
      } else if (n.type == NodeType.line) {
        n.points = [n.points.first, pt];
      } else if (n.type == NodeType.path) {
        n.points = [...n.points, pt];
      }
    });
  }

  void _onPanEnd(DragEndDetails d) {
    _panStartLocal = null;
    _moveStart = null;
    _moveOriginalPos = null;
    if (_resizeHandle != null) {
      _resizeHandle = null;
      _resizeNodeId = null;
      _resizeOriginalAbsRect = null;
      _resizeOriginalLocalXY = null;
      return;
    }

    if (_marqueeStartPage != null && _marqueeEndPage != null) {
      _commitMarquee();
      setState(() {
        _marqueeStartPage = null;
        _marqueeEndPage = null;
      });
      return;
    }

    if (_drawing == null) return;
    final n = _drawing!;
    if (n.type == NodeType.rect || n.type == NodeType.ellipse || n.type == NodeType.frame) {
      if (n.width < 0) { n.x += n.width; n.width = -n.width; }
      if (n.height < 0) { n.y += n.height; n.height = -n.height; }
      if (n.width < 2 && n.height < 2) { n.width = 160; n.height = 120; }
    }
    final origin = Offset(n.x, n.y);
    c.addNodePageSpace(n, origin);
    setState(() => _drawing = null);
    c.setTool(Tool.select);
  }

  void _onTapDown(TapDownDetails d) {
    if (c.tool != Tool.select) return;
    final pt = _toPage(d.localPosition);
    final hit = c.hitTest(pt);
    final shift = HardwareKeyboard.instance.isShiftPressed;
    if (hit != null) {
      c.toggleSelection(hit.node.id, additive: shift);
    } else if (!shift) {
      c.clearSelection();
    }
  }

  void _onDoubleTap() {
    if (c.selection.length != 1) return;
    final id = c.selection.first;
    final n = c.findNode(id);
    if (n != null && n.type == NodeType.text) _startEditingText(n);
  }

  void _onScroll(PointerScrollEvent e) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final localPos = box.globalToLocal(e.position);
    final old = c.zoom;
    final factor = e.scrollDelta.dy < 0 ? 1.1 : 1 / 1.1;
    final newZoom = (old * factor).clamp(0.05, 16.0);
    final mp = (localPos - c.pan) / old;
    c.setPan(localPos - mp * newZoom);
    c.setZoom(newZoom);
  }

  /// Only these node types expose a width/height the handles can drive.
  bool _canResize(NodeType t) =>
      t == NodeType.rect || t == NodeType.ellipse || t == NodeType.text || t == NodeType.frame;

  /// If `page` falls inside one of the 8 selection handles of a currently
  /// selected, single resizable node, return (nodeId, handleName). Handle hit
  /// zone is measured in *screen* pixels so it stays consistent across zoom.
  (String, String)? _pickResizeHandle(Offset page) {
    if (c.selection.length != 1) return null;
    final id = c.selection.first;
    final n = c.findNode(id);
    if (n == null || !_canResize(n.type)) return null;
    final parentAbs = c.absoluteOriginOf(id) ?? Offset.zero;
    final x = parentAbs.dx + n.x, y = parentAbs.dy + n.y;
    final w = n.width, h = n.height;
    final cx = x + w / 2, cy = y + h / 2;
    final handles = <String, Offset>{
      'tl': Offset(x, y),       't': Offset(cx, y),     'tr': Offset(x + w, y),
      'l':  Offset(x, cy),                              'r':  Offset(x + w, cy),
      'bl': Offset(x, y + h),   'b': Offset(cx, y + h), 'br': Offset(x + w, y + h),
    };
    final hitSize = 12 / c.zoom; // generous hit zone in page units
    for (final entry in handles.entries) {
      if ((entry.value - page).distance <= hitSize) return (id, entry.key);
    }
    return null;
  }

  void _applyResize(Offset pagePt) {
    final orig = _resizeOriginalAbsRect!;
    final origLocal = _resizeOriginalLocalXY!;
    final id = _resizeNodeId!;
    final h = _resizeHandle!;
    double left = orig.left, top = orig.top, right = orig.right, bottom = orig.bottom;
    if (h.contains('l')) left = pagePt.dx;
    if (h.contains('r')) right = pagePt.dx;
    if (h.contains('t')) top = pagePt.dy;
    if (h.contains('b')) bottom = pagePt.dy;
    // Normalize — allow dragging a handle past its opposite edge to flip.
    if (right < left) { final tmp = right; right = left; left = tmp; }
    if (bottom < top) { final tmp = bottom; bottom = top; top = tmp; }
    final newAbs = Rect.fromLTRB(left, top, right, bottom);
    final delta = newAbs.topLeft - orig.topLeft;
    c.updateNode(id, (m) {
      m.x = origLocal.dx + delta.dx;
      m.y = origLocal.dy + delta.dy;
      m.width = math.max(1, newAbs.width);
      m.height = math.max(1, newAbs.height);
    });
  }

  void _startEditingText(FredesNode n) {
    setState(() {
      _editingTextId = n.id;
      _textCtrl.text = n.text;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _textFocus.requestFocus();
      // Pre-select the placeholder so typing replaces it and a single
      // Backspace clears the whole placeholder — matches Figma's behaviour.
      _textCtrl.selection = TextSelection(baseOffset: 0, extentOffset: _textCtrl.text.length);
    });
  }

  void _commitTextEdit() {
    final id = _editingTextId;
    if (id == null) return;
    // Release focus *before* we tear down the overlay so the root Focus can
    // re-assume ownership — otherwise no widget holds focus and keyboard
    // shortcuts (including zoom) silently stop working.
    _textFocus.unfocus();
    final trimmed = _textCtrl.text.trim();
    if (trimmed.isEmpty) {
      // Clean up empty text nodes rather than leaving invisible stubs.
      c.setSelection([id]);
      c.deleteSelected();
    } else {
      c.updateNode(id, (n) { n.text = _textCtrl.text; }, history: true);
    }
    setState(() => _editingTextId = null);
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: _cursorFor(c.tool),
      child: LayoutBuilder(builder: (ctx, box) {
        _viewport = Size(box.maxWidth, box.maxHeight);
        final marqueeRect = (_marqueeStartPage != null && _marqueeEndPage != null)
            ? Rect.fromPoints(_marqueeStartPage!, _marqueeEndPage!)
            : null;
        return ClipRect(
          child: Listener(
            onPointerDown: _onPointerDown,
            onPointerMove: _onPointerMove,
            onPointerUp: _onPointerUp,
            onPointerSignal: (e) { if (e is PointerScrollEvent) _onScroll(e); },
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: _onTapDown,
              onDoubleTap: _onDoubleTap,
              onPanStart: _onPanStart,
              onPanUpdate: _onPanUpdate,
              onPanEnd: _onPanEnd,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Transform(
                      transform: Matrix4.identity()
                        ..translate(c.pan.dx, c.pan.dy)
                        ..scale(c.zoom),
                      child: CustomPaint(
                        painter: FredesPainter(
                          viewportScreen: _viewport,
                          pan: c.pan,
                          zoom: c.zoom,
                          page: c.activePage,
                          selection: c.selection,
                          drawingPreview: _drawing,
                          marqueePage: marqueeRect,
                          hideNodeId: _editingTextId,
                        ),
                        size: Size.infinite,
                      ),
                    ),
                  ),
                  if (_editingTextId != null) _buildTextEditor(),
                ],
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildTextEditor() {
    final id = _editingTextId!;
    final n = c.findNode(id);
    if (n == null) return const SizedBox.shrink();
    final parentAbs = c.absoluteOriginOf(id) ?? Offset.zero;
    final abs = parentAbs + Offset(n.x, n.y);
    final screenPos = abs * c.zoom + c.pan;
    final w = (n.width * c.zoom).clamp(60.0, double.infinity);
    final h = (n.height * c.zoom).clamp(20.0, double.infinity);

    // Edit overlay is transparent so the background stays visible; the
    // TextField inherits the node's typography so what the user sees while
    // editing is a near-pixel-perfect preview of the final render.
    return Positioned(
      left: screenPos.dx,
      top: screenPos.dy,
      width: w,
      height: h,
      child: Align(
        alignment: _flutterAlign(n.verticalAlign, n.align),
        child: TextField(
          controller: _textCtrl,
          focusNode: _textFocus,
          maxLines: null,
          textAlign: _textAlign(n.align),
          cursorColor: n.fill,
          onSubmitted: (_) => _commitTextEdit(),
          onEditingComplete: _commitTextEdit,
          onTapOutside: (_) => _commitTextEdit(),
          style: TextStyle(
            color: n.fill,
            fontSize: n.fontSize * c.zoom,
            fontFamily: n.fontFamily,
            fontWeight: _wt(n.fontWeight),
            fontStyle: n.italic ? FontStyle.italic : FontStyle.normal,
            letterSpacing: n.letterSpacing * c.zoom,
            height: n.lineHeight,
            decoration: _decoration(n.decoration),
            decorationColor: n.fill,
          ),
          decoration: const InputDecoration(
            isDense: true,
            filled: false,
            fillColor: Colors.transparent,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ),
    );
  }
}

TextAlign _textAlign(String a) {
  switch (a) {
    case 'center': return TextAlign.center;
    case 'right': return TextAlign.right;
    case 'justify': return TextAlign.justify;
    default: return TextAlign.left;
  }
}

AlignmentGeometry _flutterAlign(String vertical, String horizontal) {
  final ax = horizontal == 'center' ? 0.0 : (horizontal == 'right' ? 1.0 : -1.0);
  final ay = vertical == 'middle' ? 0.0 : (vertical == 'bottom' ? 1.0 : -1.0);
  return Alignment(ax, ay);
}

TextDecoration _decoration(String d) {
  switch (d) {
    case 'underline': return TextDecoration.underline;
    case 'line-through': return TextDecoration.lineThrough;
    default: return TextDecoration.none;
  }
}

MouseCursor _cursorFor(Tool t) {
  switch (t) {
    case Tool.hand: return SystemMouseCursors.grab;
    case Tool.select: return SystemMouseCursors.basic;
    default: return SystemMouseCursors.precise;
  }
}

FontWeight _wt(int w) {
  const map = {
    300: FontWeight.w300, 400: FontWeight.w400, 500: FontWeight.w500,
    600: FontWeight.w600, 700: FontWeight.w700, 800: FontWeight.w800,
  };
  return map[w] ?? FontWeight.w400;
}
