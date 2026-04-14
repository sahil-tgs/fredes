import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/nodes.dart';
import '../state/doc_controller.dart';

class LayersPanel extends StatefulWidget {
  final DocController doc;
  const LayersPanel({super.key, required this.doc});

  @override
  State<LayersPanel> createState() => _LayersPanelState();
}

class _LayersPanelState extends State<LayersPanel> {
  final Set<String> _collapsed = {};
  /// Id of the layer whose name is currently being edited inline. Only one
  /// at a time. Null when no rename is in progress.
  String? _renamingLayer;

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
                        itemCount: rows.length,
                        itemBuilder: (ctx, i) => _buildRow(rows[i]),
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
    return Container(
      decoration: BoxDecoration(
        color: selected ? const Color(0x553B82F6) : Colors.transparent,
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

/// Tiny color picker (preset swatches + hex). No deps.
Future<Color?> showColorPicker(BuildContext context, Color initial) async {
  final controller = TextEditingController(text: '#${initial.value.toRadixString(16).padLeft(8, '0').substring(2)}');
  Color current = initial;
  const swatches = <int>[
    0xFF000000, 0xFF111111, 0xFF374151, 0xFF6B7280, 0xFF9CA3AF, 0xFFD1D5DB, 0xFFF3F4F6, 0xFFFFFFFF,
    0xFFEF4444, 0xFFF97316, 0xFFEAB308, 0xFF22C55E, 0xFF14B8A6, 0xFF3B82F6, 0xFF8B5CF6, 0xFFEC4899,
  ];
  return showDialog<Color>(
    context: context,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
      return AlertDialog(
        backgroundColor: const Color(0xFF252525),
        title: const Text('Color', style: TextStyle(color: Colors.white)),
        content: SizedBox(
          width: 260,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final c in swatches)
                GestureDetector(
                  onTap: () => setS(() {
                    current = Color(c);
                    controller.text = '#${c.toRadixString(16).padLeft(8, '0').substring(2)}';
                  }),
                  child: Container(
                    width: 24, height: 24,
                    decoration: BoxDecoration(color: Color(c), borderRadius: BorderRadius.circular(3), border: Border.all(color: Colors.white24)),
                  ),
                )
            ]),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(labelText: 'Hex', labelStyle: TextStyle(color: Colors.white70)),
              onChanged: (v) {
                try {
                  current = hexToColor(v);
                  setS(() {});
                } catch (_) {}
              },
            ),
            const SizedBox(height: 8),
            Row(children: [
              Container(width: 24, height: 24, color: current),
              const SizedBox(width: 8),
              Text('#${current.value.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}',
                  style: const TextStyle(color: Colors.white70)),
            ]),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, current), child: const Text('Apply')),
        ],
      );
    }),
  );
}
