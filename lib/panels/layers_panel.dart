import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/nodes.dart';
import '../state/doc_controller.dart';
// Re-export so existing `import '...layers_panel.dart' show showColorPicker;`
// callers continue to work after the picker was extracted.
export 'color_picker.dart' show showColorPicker;

class LayersPanel extends StatefulWidget {
  final DocController doc;
  const LayersPanel({super.key, required this.doc});

  @override
  State<LayersPanel> createState() => _LayersPanelState();
}

/// Which part of a row the user is hovering while dragging. Drives the blue
/// drop-indicator line and decides whether the drop nests or re-orders.
enum _DropZone { before, into, after }

class _LayersPanelState extends State<LayersPanel> {
  final Set<String> _collapsed = {};
  /// Id of the layer whose name is currently being edited inline. Only one
  /// at a time. Null when no rename is in progress.
  String? _renamingLayer;

  /// While a layer drag is in flight we track which target row+zone the
  /// cursor is currently over, so we can paint the right drop indicator.
  String? _hoverTargetId;
  _DropZone? _hoverZone;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.doc,
      builder: (ctx, _) {
        final page = widget.doc.activePage;
        final rows = <_Row>[];
        _flatten(page.nodes.reversed.toList(), 0, rows);
        return Container(
          width: 240,
          decoration: const BoxDecoration(
            color: Color(0xFF252525),
            border: Border(right: BorderSide(color: Color(0xFF3A3A3A))),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _PagesSection(doc: widget.doc),
              const _SectionTitle('Layers'),
              Expanded(
                child: rows.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: Text('No layers yet — pick a tool (F for Frame, R/O/L/P/T) and draw.',
                            style: TextStyle(color: Colors.white38, fontStyle: FontStyle.italic)),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        // +1 for the trailing root drop zone.
                        itemCount: rows.length + 1,
                        itemBuilder: (ctx, i) {
                          if (i == rows.length) return _buildRootDropZone();
                          return _buildRow(rows[i]);
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Depth-first flatten, but skip children of collapsed containers.
  void _flatten(List<FredesNode> nodes, int depth, List<_Row> out) {
    for (final n in nodes) {
      out.add(_Row(node: n, depth: depth));
      if (isContainer(n.type) && !_collapsed.contains(n.id)) {
        _flatten(n.children.reversed.toList(), depth + 1, out);
      }
    }
  }

  Widget _buildRow(_Row row) {
    final n = row.node;
    final doc = widget.doc;
    final selected = doc.selection.contains(n.id);
    final container = isContainer(n.type);
    final collapsed = _collapsed.contains(n.id);
    final isHoverTarget = _hoverTargetId == n.id;
    final zoneInto = isHoverTarget && _hoverZone == _DropZone.into;
    final zoneBefore = isHoverTarget && _hoverZone == _DropZone.before;
    final zoneAfter = isHoverTarget && _hoverZone == _DropZone.after;

    final core = Container(
      // Row background: blue fill when nesting into a container, subtler
      // selection tint otherwise.
      decoration: BoxDecoration(
        color: zoneInto
            ? const Color(0x883B82F6)
            : (selected ? const Color(0x553B82F6) : Colors.transparent),
        borderRadius: BorderRadius.circular(4),
      ),
      margin: const EdgeInsets.symmetric(vertical: 1),
      child: InkWell(
        borderRadius: BorderRadius.circular(4),
        onTap: () => doc.toggleSelection(n.id),
        child: Padding(
          padding: EdgeInsets.only(left: 6 + row.depth * 12.0, right: 6, top: 4, bottom: 4),
          child: Row(children: [
            SizedBox(
              width: 14,
              child: container
                  ? InkWell(
                      onTap: () => setState(() {
                        if (collapsed) { _collapsed.remove(n.id); } else { _collapsed.add(n.id); }
                      }),
                      child: Text(collapsed ? '▸' : '▾', style: const TextStyle(color: Colors.white54, fontSize: 10)),
                    )
                  : const SizedBox.shrink(),
            ),
            _IconBtn(glyph: n.visible ? '👁' : '✕', onTap: () => doc.updateNode(n.id, (m) => m.visible = !m.visible)),
            _IconBtn(glyph: n.locked ? '🔒' : '🔓', onTap: () => doc.updateNode(n.id, (m) => m.locked = !m.locked)),
            SizedBox(width: 16, child: Center(child: Text(_glyph(n.type), style: const TextStyle(color: Colors.white54)))),
            const SizedBox(width: 4),
            Expanded(
              child: _renamingLayer == n.id
                  ? _InlineRename(
                      initial: n.name,
                      onCommit: (v) {
                        doc.updateNode(n.id, (m) => m.name = v);
                        setState(() => _renamingLayer = null);
                      },
                      onCancel: () => setState(() => _renamingLayer = null),
                    )
                  : GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onDoubleTap: () => setState(() => _renamingLayer = n.id),
                      onSecondaryTapDown: (d) => _showLayerMenu(d.globalPosition, n.id),
                      child: Text(
                        n.name,
                        style: const TextStyle(color: Colors.white, fontSize: 12),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
            ),
            _IconBtn(glyph: '↑', onTap: () => doc.reorder(n.id, 'forward')),
            _IconBtn(glyph: '↓', onTap: () => doc.reorder(n.id, 'backward')),
          ]),
        ),
      ),
    );

    // Composite: Draggable source + three stacked drop zones (before, into,
    // after). Horizontal blue lines show insertion points; blue row-fill
    // shows "nest into container".
    final draggableCore = Draggable<String>(
      data: n.id,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: _dragFeedback(n),
      childWhenDragging: Opacity(opacity: 0.35, child: core),
      onDragEnd: (_) => setState(() {
        _hoverTargetId = null;
        _hoverZone = null;
      }),
      child: core,
    );

    return Stack(children: [
      draggableCore,
      // Drop-target zones laid over the row. Each is a thin slice that
      // decides its zone kind. `onMove` updates the indicator so the user
      // sees live feedback.
      Positioned.fill(
        child: Column(children: [
          _zoneTarget(n.id, row.node, _DropZone.before, flex: 1),
          _zoneTarget(n.id, row.node, _DropZone.into,   flex: 2),
          _zoneTarget(n.id, row.node, _DropZone.after,  flex: 1),
        ]),
      ),
      // Thin blue indicator lines for "before" / "after".
      if (zoneBefore)
        const Positioned(top: 0, left: 4, right: 4, child: IgnorePointer(child: _DropLine())),
      if (zoneAfter)
        const Positioned(bottom: 0, left: 4, right: 4, child: IgnorePointer(child: _DropLine())),
    ]);
  }

  /// Drop target for one of the three zones on a row. Accepts the dragged
  /// node id and calls [_handleDrop] on commit.
  Widget _zoneTarget(String targetId, FredesNode targetNode, _DropZone zone, {required int flex}) {
    return Expanded(
      flex: flex,
      child: DragTarget<String>(
        onWillAcceptWithDetails: (details) {
          final dragged = details.data;
          if (dragged == targetId) return false;
          // Forbid drops that would create a cycle (dragging a parent into
          // its own descendant).
          if (widget.doc.findNode(dragged) != null &&
              _containsDescendant(dragged, targetId)) return false;
          // "Into" only makes sense for containers.
          if (zone == _DropZone.into && !isContainer(targetNode.type)) return false;
          setState(() {
            _hoverTargetId = targetId;
            _hoverZone = zone;
          });
          return true;
        },
        onLeave: (_) => setState(() {
          if (_hoverTargetId == targetId && _hoverZone == zone) {
            _hoverTargetId = null;
            _hoverZone = null;
          }
        }),
        onAcceptWithDetails: (details) {
          _handleDrop(details.data, targetId, zone);
          setState(() { _hoverTargetId = null; _hoverZone = null; });
        },
        builder: (ctx, _, __) => const SizedBox.expand(),
      ),
    );
  }

  /// Did [ancestorId]'s node-tree contain [candidateId] as a descendant?
  /// Prevents dropping a frame/group into itself or its children.
  bool _containsDescendant(String ancestorId, String candidateId) {
    final anc = widget.doc.findNode(ancestorId);
    if (anc == null || !isContainer(anc.type)) return false;
    for (final c in anc.children) {
      if (c.id == candidateId) return true;
      if (_containsDescendant(c.id, candidateId)) return true;
    }
    return false;
  }

  /// Translate a (drop-target, zone) pair to a controller reparent call.
  void _handleDrop(String draggedId, String targetId, _DropZone zone) {
    final doc = widget.doc;
    final target = doc.findNode(targetId);
    if (target == null) return;

    if (zone == _DropZone.into && isContainer(target.type)) {
      // Nest as the top-most child (children list paints last-→-first, so
      // appending puts the dropped layer on top visually).
      doc.reparent(draggedId, toParentId: targetId, index: target.children.length);
      return;
    }

    // Sibling placement: find the target's parent + target's index there.
    // The flattened list is rendered **reversed** (back-to-front → top row
    // is the top-most sibling), so "before the row" in UI terms means
    // "after the target in the children list", and vice-versa.
    final parent = _parentOf(targetId);
    final siblings = parent == null ? doc.activePage.nodes : parent.children;
    final idx = siblings.indexWhere((n) => n.id == targetId);
    if (idx < 0) return;

    int insertAt;
    if (zone == _DropZone.before) {
      insertAt = idx + 1;             // visually above = later in list
    } else {
      insertAt = idx;                 // visually below = earlier in list
    }
    doc.reparent(draggedId, toParentId: parent?.id, index: insertAt);
  }

  /// Walks the tree to find the parent node of [childId]. Returns null if
  /// the child is at the root.
  FredesNode? _parentOf(String childId) {
    FredesNode? found;
    void walk(List<FredesNode> nodes, FredesNode? parent) {
      for (final n in nodes) {
        if (n.id == childId) { found = parent; return; }
        if (isContainer(n.type)) walk(n.children, n);
        if (found != null) return;
      }
    }
    walk(widget.doc.activePage.nodes, null);
    return found;
  }

  /// Small labelled "pill" shown under the cursor while dragging a layer.
  Widget _dragFeedback(FredesNode n) {
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFF3B82F6),
          borderRadius: BorderRadius.circular(4),
          boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 6, offset: Offset(0, 2))],
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(_glyph(n.type), style: const TextStyle(color: Colors.white)),
          const SizedBox(width: 6),
          Text(n.name, style: const TextStyle(color: Colors.white, fontSize: 12)),
        ]),
      ),
    );
  }

  /// Drop zone at the bottom of the layers list → always "move to root as
  /// topmost sibling".
  Widget _buildRootDropZone() {
    return DragTarget<String>(
      onWillAcceptWithDetails: (d) {
        setState(() { _hoverTargetId = '__root__'; _hoverZone = _DropZone.into; });
        return d.data != '__root__';
      },
      onLeave: (_) => setState(() {
        if (_hoverTargetId == '__root__') { _hoverTargetId = null; _hoverZone = null; }
      }),
      onAcceptWithDetails: (d) {
        // Insert at the very top of the root page (index 0 paints back-most,
        // but visually in the panel it'll land at the bottom; use the full
        // length so it becomes the top-most root layer instead).
        widget.doc.reparent(d.data, toParentId: null, index: widget.doc.activePage.nodes.length);
        setState(() { _hoverTargetId = null; _hoverZone = null; });
      },
      builder: (ctx, _, __) {
        final active = _hoverTargetId == '__root__';
        return Container(
          height: 44,
          margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
          decoration: BoxDecoration(
            color: active ? const Color(0x883B82F6) : Colors.transparent,
            border: Border.all(
              color: active ? const Color(0xFF3B82F6) : const Color(0xFF3A3A3A),
              style: BorderStyle.solid,
            ),
            borderRadius: BorderRadius.circular(4),
          ),
          alignment: Alignment.center,
          child: Text(
            active ? 'Drop to move to root' : 'Drag here to move to root',
            style: TextStyle(
              color: active ? Colors.white : Colors.white38,
              fontSize: 11,
              fontStyle: FontStyle.italic,
            ),
          ),
        );
      },
    );
  }

  void _showLayerMenu(Offset pos, String id) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final choice = await showMenu<String>(
      context: context,
      color: const Color(0xFF252525),
      position: RelativeRect.fromRect(pos & const Size(1, 1), Offset.zero & overlay.size),
      items: const [
        PopupMenuItem<String>(value: 'rename', child: Text('Rename', style: TextStyle(color: Colors.white))),
        PopupMenuItem<String>(value: 'delete', child: Text('Delete', style: TextStyle(color: Colors.white))),
      ],
    );
    if (choice == 'rename') setState(() => _renamingLayer = id);
    if (choice == 'delete') {
      widget.doc.setSelection([id]);
      widget.doc.deleteSelected();
    }
  }

  static String _glyph(NodeType t) => switch (t) {
        NodeType.frame => '🖽',
        NodeType.group => '⧈',
        NodeType.rect => '▭',
        NodeType.ellipse => '◯',
        NodeType.text => 'T',
        NodeType.line => '／',
        NodeType.path => '✎',
      };
}

class _Row {
  final FredesNode node;
  final int depth;
  _Row({required this.node, required this.depth});
}

class _PagesSection extends StatefulWidget {
  final DocController doc;
  const _PagesSection({required this.doc});
  @override
  State<_PagesSection> createState() => _PagesSectionState();
}

class _PagesSectionState extends State<_PagesSection> {
  String? _renaming;

  @override
  Widget build(BuildContext context) {
    final doc = widget.doc;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 6),
          child: Row(children: [
            const Expanded(
              child: Text('PAGES',
                  style: TextStyle(color: Colors.white54, fontWeight: FontWeight.w600, letterSpacing: 0.6, fontSize: 11)),
            ),
            Tooltip(
              message: 'Add page',
              child: InkWell(
                borderRadius: BorderRadius.circular(3),
                onTap: () => doc.addPage(),
                child: const Padding(
                  padding: EdgeInsets.all(2),
                  child: Icon(Icons.add, size: 16, color: Colors.white70),
                ),
              ),
            ),
          ]),
        ),
        for (final p in doc.doc.pages)
          _pageRow(p.id, p.name, p.id == doc.activePageId),
      ],
    );
  }

  Widget _pageRow(String id, String name, bool active) {
    final doc = widget.doc;
    final renaming = _renaming == id;
    return GestureDetector(
      onSecondaryTapDown: (d) => _showMenu(d.globalPosition, id),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: active ? const Color(0x553B82F6) : const Color(0xFF2D2D2D),
          borderRadius: BorderRadius.circular(4),
        ),
        child: InkWell(
          onTap: () => doc.setActivePageId(id),
          onDoubleTap: () => setState(() => _renaming = id),
          child: Row(children: [
            const Icon(Icons.description, size: 13, color: Colors.white54),
            const SizedBox(width: 6),
            Expanded(
              child: renaming
                  ? _InlineRename(
                      initial: name,
                      onCommit: (v) {
                        doc.renamePage(id, v);
                        setState(() => _renaming = null);
                      },
                      onCancel: () => setState(() => _renaming = null),
                    )
                  : Text(name, style: const TextStyle(color: Colors.white), overflow: TextOverflow.ellipsis),
            ),
          ]),
        ),
      ),
    );
  }

  void _showMenu(Offset pos, String id) async {
    final doc = widget.doc;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final choice = await showMenu<String>(
      context: context,
      color: const Color(0xFF252525),
      position: RelativeRect.fromRect(pos & const Size(1, 1), Offset.zero & overlay.size),
      items: [
        const PopupMenuItem<String>(value: 'rename', child: Text('Rename', style: TextStyle(color: Colors.white))),
        PopupMenuItem<String>(
          value: 'delete',
          enabled: doc.doc.pages.length > 1,
          child: const Text('Delete', style: TextStyle(color: Colors.white)),
        ),
      ],
    );
    if (choice == 'rename') setState(() => _renaming = id);
    if (choice == 'delete') doc.deletePage(id);
  }
}

class _InlineRename extends StatefulWidget {
  final String initial;
  final ValueChanged<String> onCommit;
  final VoidCallback onCancel;
  const _InlineRename({required this.initial, required this.onCommit, required this.onCancel});
  @override
  State<_InlineRename> createState() => _InlineRenameState();
}

class _InlineRenameState extends State<_InlineRename> {
  late TextEditingController _c;
  late final FocusNode _f;
  @override
  void initState() {
    super.initState();
    _c = TextEditingController(text: widget.initial);
    _f = FocusNode();
    // Escape cancels the rename without persisting changes. Registered on
    // the focus node so it only fires while this field has focus.
    _f.onKeyEvent = (node, event) {
      if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape) {
        _f.unfocus();
        widget.onCancel();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    };
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _f.requestFocus();
      _c.selection = TextSelection(baseOffset: 0, extentOffset: _c.text.length);
    });
  }
  @override
  void dispose() { _c.dispose(); _f.dispose(); super.dispose(); }
  void _commit() {
    // Order matters: unfocus *first* so the parent rebuild that removes this
    // widget tree doesn't strand the focus node, then deliver the value.
    _f.unfocus();
    widget.onCommit(_c.text);
  }
  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _c,
      focusNode: _f,
      autofocus: true,
      onSubmitted: (_) => _commit(),
      onEditingComplete: _commit,
      onTapOutside: (_) => _commit(),
      style: const TextStyle(color: Colors.white, fontSize: 12),
      decoration: const InputDecoration(
        isDense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        border: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF3B82F6))),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
        child: Text(text.toUpperCase(),
            style: const TextStyle(color: Colors.white54, fontWeight: FontWeight.w600, letterSpacing: 0.6, fontSize: 11)),
      );
}

class _IconBtn extends StatelessWidget {
  final String glyph;
  final VoidCallback onTap;
  const _IconBtn({required this.glyph, required this.onTap});
  @override
  Widget build(BuildContext context) => SizedBox(
        width: 22, height: 22,
        child: InkWell(
          borderRadius: BorderRadius.circular(3),
          onTap: onTap,
          child: Center(child: Text(glyph, style: const TextStyle(color: Colors.white60, fontSize: 11))),
        ),
      );
}

/// Thin horizontal line drawn between rows to indicate a "sibling insertion"
/// drop target during a layer drag.
class _DropLine extends StatelessWidget {
  const _DropLine();
  @override
  Widget build(BuildContext context) => Container(
        height: 2,
        decoration: BoxDecoration(
          color: const Color(0xFF3B82F6),
          borderRadius: BorderRadius.circular(1),
        ),
      );
}

// Color picker moved to color_picker.dart. Re-exported below for callers
// that already import it from this file.

