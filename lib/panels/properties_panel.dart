import 'package:flutter/material.dart';
import '../models/document.dart';
import '../models/nodes.dart';
import '../state/doc_controller.dart';
import 'color_picker.dart';

class _PageNameRow extends StatefulWidget {
  final String initial;
  final ValueChanged<String> onCommit;
  const _PageNameRow({super.key, required this.initial, required this.onCommit});
  @override
  State<_PageNameRow> createState() => _PageNameRowState();
}

class _PageNameRowState extends State<_PageNameRow> {
  late TextEditingController _c;
  @override
  void initState() { super.initState(); _c = TextEditingController(text: widget.initial); }
  @override
  void dispose() { _c.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [
        const SizedBox(width: 56, child: Text('Name', style: TextStyle(color: Colors.white54, fontSize: 11))),
        Expanded(
          child: SizedBox(
            height: 28,
            child: TextField(
              controller: _c,
              onSubmitted: widget.onCommit,
              onTapOutside: (_) => widget.onCommit(_c.text),
              style: const TextStyle(color: Colors.white, fontSize: 12),
              decoration: const InputDecoration(
                isDense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                filled: true,
                fillColor: Color(0xFF1E1E1E),
                border: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF3A3A3A))),
                enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF3A3A3A))),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

class PropertiesPanel extends StatelessWidget {
  final DocController doc;
  const PropertiesPanel({super.key, required this.doc});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: doc,
      builder: (ctx, _) {
        final selected = doc.activePage.nodes.where((n) => doc.selection.contains(n.id)).toList();
        final node = selected.length == 1 ? selected.first : null;
        return Container(
          width: 280,
          decoration: const BoxDecoration(
            color: Color(0xFF252525),
            border: Border(left: BorderSide(color: Color(0xFF3A3A3A))),
          ),
          child: ListView(
            padding: const EdgeInsets.all(8),
            children: [
              const _Title('Properties'),
              if (node == null) ..._pageProps(context, doc),
              if (node != null) ..._propsForNode(context, doc, node),
              const SizedBox(height: 12),
              const _Title('Mode'),
              _ModeSection(doc: doc),
            ],
          ),
        );
      },
    );
  }

  List<Widget> _pageProps(BuildContext ctx, DocController doc) {
    final p = doc.activePage;
    return [
      _Section('Page', [
        _PageNameRow(
          key: ValueKey('page-name-${p.id}'),
          initial: p.name,
          onCommit: (v) => doc.renamePage(p.id, v),
        ),
        _ColorRow(
          label: 'Background',
          color: hexToColor(p.background),
          onChanged: (c) => doc.setPageBackground(colorToHex(c)),
        ),
      ]),
    ];
  }

  List<Widget> _propsForNode(BuildContext ctx, DocController doc, FredesNode n) {
    final widgets = <Widget>[
      _Section('Position', [
        _NumRow(label: 'X', value: n.x, onCommit: (v) => doc.updateNode(n.id, (m) => m.x = v, history: true)),
        _NumRow(label: 'Y', value: n.y, onCommit: (v) => doc.updateNode(n.id, (m) => m.y = v, history: true)),
        _NumRow(label: 'Rotate', value: n.rotation, onCommit: (v) => doc.updateNode(n.id, (m) => m.rotation = v, history: true)),
        _NumRow(label: 'Opacity', value: n.opacity, step: 0.05, min: 0, max: 1, onCommit: (v) => doc.updateNode(n.id, (m) => m.opacity = v.clamp(0, 1), history: true)),
      ]),
    ];

    if (n.type == NodeType.rect || n.type == NodeType.ellipse || n.type == NodeType.text || n.type == NodeType.frame) {
      widgets.add(_Section('Size', [
        _NumRow(label: 'W', value: n.width, onCommit: (v) => doc.updateNode(n.id, (m) => m.width = v.clamp(1, double.infinity), history: true)),
        _NumRow(label: 'H', value: n.height, onCommit: (v) => doc.updateNode(n.id, (m) => m.height = v.clamp(1, double.infinity), history: true)),
      ]));
    }

    // Text has its own "Typography" section (with color), so skip the generic Fill for it.
    if (n.type == NodeType.rect || n.type == NodeType.ellipse || n.type == NodeType.path || n.type == NodeType.frame) {
      widgets.add(_Section('Fill', [
        _ColorRow(label: 'Color', color: n.fill, onChanged: (c) => doc.updateNode(n.id, (m) => m.fill = c, history: true)),
      ]));
    }

    if (n.type == NodeType.text) {
      widgets.add(_TypographySection(node: n, doc: doc));
    }

    if (n.type == NodeType.rect || n.type == NodeType.frame) {
      widgets.add(_Section('Corner', [
        _NumRow(label: 'Radius', value: n.cornerRadius, onCommit: (v) => doc.updateNode(n.id, (m) => m.cornerRadius = v.clamp(0, double.infinity), history: true)),
      ]));
    }

    if (n.type == NodeType.frame) {
      widgets.add(_Section('Frame', [
        _ToggleRow(
          label: 'Clip',
          value: n.clipContent,
          onChanged: (v) => doc.updateNode(n.id, (m) => m.clipContent = v, history: true),
        ),
      ]));
    }

    if (n.type != NodeType.text && n.type != NodeType.group) {
      widgets.add(_Section('Stroke', [
        _ColorRow(label: 'Color', color: n.stroke, onChanged: (c) => doc.updateNode(n.id, (m) => m.stroke = c, history: true)),
        _NumRow(label: 'Width', value: n.strokeWidth, onCommit: (v) => doc.updateNode(n.id, (m) => m.strokeWidth = v.clamp(0, double.infinity), history: true)),
      ]));
    }

    return widgets;
  }
}

class _Title extends StatelessWidget {
  final String text;
  const _Title(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 6, 0, 4),
        child: Text(text.toUpperCase(),
            style: const TextStyle(color: Colors.white54, fontWeight: FontWeight.w600, letterSpacing: 0.6, fontSize: 11)),
      );
}

class _Section extends StatelessWidget {
  final String title;
  final List<Widget> rows;
  const _Section(this.title, this.rows);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title.toUpperCase(),
              style: const TextStyle(color: Colors.white38, fontSize: 10, letterSpacing: 0.5)),
          const SizedBox(height: 4),
          ...rows,
        ]),
      );
}

class _NumRow extends StatefulWidget {
  final String label;
  final double value;
  final ValueChanged<double> onCommit;
  final double step;
  final double? min, max;
  const _NumRow({required this.label, required this.value, required this.onCommit, this.step = 1, this.min, this.max});
  @override
  State<_NumRow> createState() => _NumRowState();
}

class _NumRowState extends State<_NumRow> {
  late TextEditingController _c;
  @override
  void initState() { super.initState(); _c = TextEditingController(text: _fmt(widget.value)); }
  @override
  void didUpdateWidget(covariant _NumRow old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value && _c.text != _fmt(widget.value)) _c.text = _fmt(widget.value);
  }
  @override
  void dispose() { _c.dispose(); super.dispose(); }
  String _fmt(double v) => v.toStringAsFixed(v.truncateToDouble() == v ? 0 : 2);
  void _commit() {
    final v = double.tryParse(_c.text);
    if (v != null) {
      widget.onCommit(v);
    } else {
      _c.text = _fmt(widget.value);
    }
  }
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [
        SizedBox(width: 56, child: Text(widget.label, style: const TextStyle(color: Colors.white54, fontSize: 11))),
        Expanded(
          child: SizedBox(
            height: 28,
            child: TextField(
              controller: _c,
              onSubmitted: (_) => _commit(),
              onTapOutside: (_) => _commit(),
              keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
              style: const TextStyle(color: Colors.white, fontSize: 12),
              decoration: const InputDecoration(
                isDense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                filled: true,
                fillColor: Color(0xFF1E1E1E),
                border: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF3A3A3A))),
                enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF3A3A3A))),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

/// Figma-inspired Typography section. All controls mutate the node via the
/// supplied [DocController] with history entries batched per edit.
class _TypographySection extends StatelessWidget {
  final FredesNode node;
  final DocController doc;
  const _TypographySection({required this.node, required this.doc});

  static const _fontFamilies = <String>[
    'Inter',
    'Roboto',
    'Arial',
    'Helvetica',
    'Times New Roman',
    'Georgia',
    'Courier New',
    'Verdana',
    'Tahoma',
    'Comic Sans MS',
  ];
  // Common weights + friendly names.
  static const _weights = <int, String>{
    100: 'Thin',
    200: 'ExtraLight',
    300: 'Light',
    400: 'Regular',
    500: 'Medium',
    600: 'SemiBold',
    700: 'Bold',
    800: 'ExtraBold',
    900: 'Black',
  };

  void _mut(void Function(FredesNode) f) => doc.updateNode(node.id, f, history: true);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 6),
          child: Text('TYPOGRAPHY',
              style: TextStyle(color: Colors.white38, fontSize: 10, letterSpacing: 0.5)),
        ),
        _FillRow(node: node, doc: doc),
        const SizedBox(height: 6),
        // Font family
        _FamilyDropdown(
          value: node.fontFamily,
          families: _fontFamilies,
          onChanged: (v) => _mut((m) => m.fontFamily = v),
        ),
        const SizedBox(height: 4),
        Row(children: [
          Expanded(
            flex: 3,
            child: _WeightDropdown(
              value: node.fontWeight,
              weights: _weights,
              onChanged: (v) => _mut((m) => m.fontWeight = v),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            flex: 2,
            child: _NumField(
              value: node.fontSize,
              onCommit: (v) => _mut((m) => m.fontSize = (v ?? m.fontSize).clamp(4, 999)),
            ),
          ),
        ]),
        const SizedBox(height: 4),
        Row(children: [
          Expanded(
            child: _NumField(
              prefix: 'H',
              tooltip: 'Line height (× font size) — blank for auto',
              value: node.lineHeight,
              allowNull: true,
              onCommit: (v) => _mut((m) => m.lineHeight = v),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: _NumField(
              prefix: 'S',
              tooltip: 'Letter spacing (px)',
              value: node.letterSpacing,
              onCommit: (v) => _mut((m) => m.letterSpacing = v ?? 0),
            ),
          ),
        ]),
        const SizedBox(height: 6),
        // Horizontal alignment
        _IconRow<String>(
          value: node.align,
          onChanged: (v) => _mut((m) => m.align = v),
          items: const [
            ('left', Icons.format_align_left, 'Left'),
            ('center', Icons.format_align_center, 'Center'),
            ('right', Icons.format_align_right, 'Right'),
            ('justify', Icons.format_align_justify, 'Justify'),
          ],
        ),
        const SizedBox(height: 4),
        // Vertical alignment
        _IconRow<String>(
          value: node.verticalAlign,
          onChanged: (v) => _mut((m) => m.verticalAlign = v),
          items: const [
            ('top', Icons.vertical_align_top, 'Top'),
            ('middle', Icons.vertical_align_center, 'Middle'),
            ('bottom', Icons.vertical_align_bottom, 'Bottom'),
          ],
        ),
        const SizedBox(height: 4),
        // Decoration & style toggles
        Row(children: [
          _ToggleIcon(
            icon: Icons.format_italic,
            tooltip: 'Italic',
            active: node.italic,
            onTap: () => _mut((m) => m.italic = !m.italic),
          ),
          const SizedBox(width: 4),
          _ToggleIcon(
            icon: Icons.format_underline,
            tooltip: 'Underline',
            active: node.decoration == 'underline',
            onTap: () => _mut((m) => m.decoration = (m.decoration == 'underline') ? 'none' : 'underline'),
          ),
          const SizedBox(width: 4),
          _ToggleIcon(
            icon: Icons.strikethrough_s,
            tooltip: 'Strikethrough',
            active: node.decoration == 'line-through',
            onTap: () => _mut((m) => m.decoration = (m.decoration == 'line-through') ? 'none' : 'line-through'),
          ),
        ]),
        const SizedBox(height: 4),
        // Letter case
        _IconRow<String>(
          value: node.letterCase,
          onChanged: (v) => _mut((m) => m.letterCase = v),
          items: const [
            ('original', Icons.text_fields, 'Original'),
            ('upper', Icons.abc, 'UPPER'),
            ('lower', Icons.text_decrease, 'lower'),
            ('title', Icons.title, 'Title'),
          ],
        ),
      ]),
    );
  }
}

class _FillRow extends StatelessWidget {
  final FredesNode node;
  final DocController doc;
  const _FillRow({required this.node, required this.doc});
  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Builder(builder: (triggerCtx) {
        return GestureDetector(
          onTap: () {
            bool historyPushed = false;
            openColorPicker(
              context: context,
              triggerContext: triggerCtx,
              initial: node.fill,
              onChanged: (c) {
                // Only one undo entry per picker *session*, regardless of how
                // many live adjustments the user makes.
                if (!historyPushed) {
                  doc.pushHistory();
                  historyPushed = true;
                }
                doc.updateNode(node.id, (m) => m.fill = c);
              },
            );
          },
          child: Container(
            width: 26, height: 26,
            decoration: BoxDecoration(
              color: node.fill,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: const Color(0xFF3A3A3A)),
            ),
          ),
        );
      }),
      const SizedBox(width: 6),
      Expanded(
        child: Text(
          '#${node.fill.value.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}',
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
      ),
    ]);
  }
}

class _FamilyDropdown extends StatelessWidget {
  final String value;
  final List<String> families;
  final ValueChanged<String> onChanged;
  const _FamilyDropdown({required this.value, required this.families, required this.onChanged});
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: const Color(0xFF3A3A3A)),
      ),
      child: DropdownButton<String>(
        value: families.contains(value) ? value : families.first,
        isExpanded: true,
        isDense: true,
        underline: const SizedBox.shrink(),
        dropdownColor: const Color(0xFF1E1E1E),
        style: const TextStyle(color: Colors.white, fontSize: 12),
        icon: const Icon(Icons.keyboard_arrow_down, size: 16, color: Colors.white54),
        items: [
          for (final f in families)
            DropdownMenuItem(value: f, child: Text(f, style: TextStyle(fontFamily: f))),
        ],
        onChanged: (v) { if (v != null) onChanged(v); },
      ),
    );
  }
}

class _WeightDropdown extends StatelessWidget {
  final int value;
  final Map<int, String> weights;
  final ValueChanged<int> onChanged;
  const _WeightDropdown({required this.value, required this.weights, required this.onChanged});
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: const Color(0xFF3A3A3A)),
      ),
      child: DropdownButton<int>(
        value: weights.containsKey(value) ? value : 400,
        isExpanded: true,
        isDense: true,
        underline: const SizedBox.shrink(),
        dropdownColor: const Color(0xFF1E1E1E),
        style: const TextStyle(color: Colors.white, fontSize: 12),
        icon: const Icon(Icons.keyboard_arrow_down, size: 16, color: Colors.white54),
        items: [
          for (final e in weights.entries)
            DropdownMenuItem(value: e.key, child: Text(e.value)),
        ],
        onChanged: (v) { if (v != null) onChanged(v); },
      ),
    );
  }
}

class _NumField extends StatefulWidget {
  final double? value;
  final ValueChanged<double?> onCommit;
  final String? prefix;
  final String? tooltip;
  final bool allowNull;
  const _NumField({
    required this.value,
    required this.onCommit,
    this.prefix,
    this.tooltip,
    this.allowNull = false,
  });
  @override
  State<_NumField> createState() => _NumFieldState();
}

class _NumFieldState extends State<_NumField> {
  late TextEditingController _c;
  @override
  void initState() { super.initState(); _c = TextEditingController(text: _fmt(widget.value)); }
  @override
  void didUpdateWidget(covariant _NumField old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value && _c.text != _fmt(widget.value)) _c.text = _fmt(widget.value);
  }
  @override
  void dispose() { _c.dispose(); super.dispose(); }
  String _fmt(double? v) {
    if (v == null) return widget.allowNull ? '' : '0';
    return v.truncateToDouble() == v ? v.toStringAsFixed(0) : v.toStringAsFixed(2);
  }
  void _commit() {
    final t = _c.text.trim();
    if (t.isEmpty && widget.allowNull) { widget.onCommit(null); return; }
    final v = double.tryParse(t);
    if (v != null) {
      widget.onCommit(v);
    } else {
      _c.text = _fmt(widget.value);
    }
  }
  @override
  Widget build(BuildContext context) {
    final field = SizedBox(
      height: 30,
      child: TextField(
        controller: _c,
        onSubmitted: (_) => _commit(),
        onTapOutside: (_) => _commit(),
        keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
        style: const TextStyle(color: Colors.white, fontSize: 12),
        decoration: InputDecoration(
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          filled: true,
          fillColor: const Color(0xFF1E1E1E),
          prefixText: widget.prefix == null ? null : '${widget.prefix}  ',
          prefixStyle: const TextStyle(color: Colors.white38, fontSize: 11),
          border: const OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF3A3A3A))),
          enabledBorder: const OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF3A3A3A))),
          hintText: widget.allowNull ? 'Auto' : null,
          hintStyle: const TextStyle(color: Colors.white24, fontSize: 11),
        ),
      ),
    );
    return widget.tooltip == null ? field : Tooltip(message: widget.tooltip!, child: field);
  }
}

class _IconRow<T> extends StatelessWidget {
  final T value;
  final ValueChanged<T> onChanged;
  final List<(T, IconData, String)> items;
  const _IconRow({required this.value, required this.onChanged, required this.items});
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: const Color(0xFF3A3A3A)),
      ),
      padding: const EdgeInsets.all(2),
      child: Row(children: [
        for (final item in items)
          Expanded(
            child: Tooltip(
              message: item.$3,
              child: InkWell(
                borderRadius: BorderRadius.circular(3),
                onTap: () => onChanged(item.$1),
                child: Container(
                  height: 26,
                  decoration: BoxDecoration(
                    color: item.$1 == value ? const Color(0xFF3B82F6) : Colors.transparent,
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Icon(item.$2, size: 16,
                      color: item.$1 == value ? Colors.white : Colors.white70),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}

class _ToggleIcon extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool active;
  final VoidCallback onTap;
  const _ToggleIcon({required this.icon, required this.tooltip, required this.active, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(4),
        onTap: onTap,
        child: Container(
          width: 30, height: 30,
          decoration: BoxDecoration(
            color: active ? const Color(0xFF3B82F6) : const Color(0xFF1E1E1E),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: const Color(0xFF3A3A3A)),
          ),
          child: Icon(icon, size: 16, color: active ? Colors.white : Colors.white70),
        ),
      ),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _ToggleRow({required this.label, required this.value, required this.onChanged});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [
        SizedBox(width: 56, child: Text(label, style: const TextStyle(color: Colors.white54, fontSize: 11))),
        Switch(
          value: value,
          onChanged: onChanged,
          activeColor: const Color(0xFF3B82F6),
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ]),
    );
  }
}

class _ColorRow extends StatelessWidget {
  final String label;
  final Color color;
  final ValueChanged<Color> onChanged;
  const _ColorRow({required this.label, required this.color, required this.onChanged});
  @override
  Widget build(BuildContext context) {
    final hex = '#${color.value.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [
        SizedBox(width: 56, child: Text(label, style: const TextStyle(color: Colors.white54, fontSize: 11))),
        Builder(builder: (triggerCtx) {
          return GestureDetector(
            onTap: () {
              openColorPicker(
                context: context,
                triggerContext: triggerCtx,
                initial: color,
                onChanged: onChanged,
              );
            },
            child: Container(
              width: 26, height: 26,
              decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4), border: Border.all(color: const Color(0xFF3A3A3A))),
            ),
          );
        }),
        const SizedBox(width: 6),
        Expanded(child: Text(hex, style: const TextStyle(color: Colors.white70, fontSize: 12))),
      ]),
    );
  }
}

class _ModeSection extends StatefulWidget {
  final DocController doc;
  const _ModeSection({required this.doc});
  @override
  State<_ModeSection> createState() => _ModeSectionState();
}

class _ModeSectionState extends State<_ModeSection> {
  late TextEditingController _url;
  @override
  void initState() { super.initState(); _url = TextEditingController(text: widget.doc.cloudUrl); }
  @override
  void dispose() { _url.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    final doc = widget.doc;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        RadioListTile<AppMode>(
          dense: true, contentPadding: EdgeInsets.zero,
          activeColor: const Color(0xFF3B82F6),
          value: AppMode.local, groupValue: doc.mode,
          title: const Text('Local (offline-first)', style: TextStyle(color: Colors.white)),
          onChanged: (v) => doc.setMode(v!),
        ),
        RadioListTile<AppMode>(
          dense: true, contentPadding: EdgeInsets.zero,
          activeColor: const Color(0xFF3B82F6),
          value: AppMode.cloud, groupValue: doc.mode,
          title: const Text('Cloud sync', style: TextStyle(color: Colors.white)),
          onChanged: (v) => doc.setMode(v!),
        ),
        if (doc.mode == AppMode.cloud) ...[
          const SizedBox(height: 4),
          const Text('Sync server', style: TextStyle(color: Colors.white54, fontSize: 11)),
          const SizedBox(height: 4),
          SizedBox(
            height: 28,
            child: TextField(
              controller: _url,
              onSubmitted: doc.setCloudUrl,
              onTapOutside: (_) => doc.setCloudUrl(_url.text),
              style: const TextStyle(color: Colors.white, fontSize: 12),
              decoration: const InputDecoration(
                isDense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                filled: true,
                fillColor: Color(0xFF1E1E1E),
                border: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF3A3A3A))),
                enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF3A3A3A))),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(doc.cloudConnected ? '● Connected' : '● Disconnected',
              style: TextStyle(color: doc.cloudConnected ? const Color(0xFF22C55E) : Colors.white38, fontSize: 11)),
        ],
      ]),
    );
  }
}
