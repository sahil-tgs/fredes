import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Recently-used colors, most-recent-first. In-memory only — intentionally
/// not persisted yet; will survive across picker opens within a session.
final List<Color> _recentColors = <Color>[];
const int _kMaxRecent = 18;

/// Figma-style floating color picker.
///
/// Spawned via an [OverlayEntry] so it sits **above** the app chrome but not
/// as a modal — the user can click other swatches, keep editing text, etc.
/// The panel anchors itself next to the widget identified by [triggerContext]
/// (the tapped swatch) and can be dragged by its title bar.
///
/// Updates are **live**: every change in the picker fires [onChanged] so the
/// canvas repaints instantly. [onClosed] fires once when the panel is
/// dismissed (tap-outside, Esc, or the close button).
///
/// There is only one picker open at a time; opening a new one automatically
/// closes any previous instance.
OverlayEntry? _currentEntry;

void openColorPicker({
  required BuildContext context,
  required BuildContext triggerContext,
  required Color initial,
  required ValueChanged<Color> onChanged,
  VoidCallback? onClosed,
}) {
  // Close any existing picker first.
  _currentEntry?.remove();
  _currentEntry = null;

  final overlay = Overlay.of(context, rootOverlay: true);
  final anchor = _anchorFor(triggerContext, overlay.context);

  late OverlayEntry entry;
  entry = OverlayEntry(builder: (ctx) {
    return _FloatingColorPicker(
      initial: initial,
      startOffset: anchor,
      onChanged: onChanged,
      onClose: () {
        entry.remove();
        if (_currentEntry == entry) _currentEntry = null;
        onClosed?.call();
      },
    );
  });
  _currentEntry = entry;
  overlay.insert(entry);
}

/// Compute an initial offset for the floating picker:
/// * Left of the trigger, by default (the triggers live in the right panel),
///   so the picker doesn't cover the thing you're editing.
/// * If there isn't enough room to the left, fall back to the right.
/// * Vertically aligned with the trigger's top; clamped inside the overlay.
Offset _anchorFor(BuildContext triggerContext, BuildContext overlayContext) {
  const panelWidth = _FloatingColorPicker.width;
  const gap = 8.0;

  final triggerBox = triggerContext.findRenderObject() as RenderBox?;
  final overlayBox = overlayContext.findRenderObject() as RenderBox?;
  if (triggerBox == null || overlayBox == null) {
    return const Offset(100, 100);
  }
  final topLeft = triggerBox.localToGlobal(Offset.zero, ancestor: overlayBox);
  final triggerSize = triggerBox.size;
  final overlaySize = overlayBox.size;

  // Prefer placing the panel to the left of the trigger.
  double x = topLeft.dx - panelWidth - gap;
  if (x < 8) {
    // Not enough room on the left → place on the right.
    x = topLeft.dx + triggerSize.width + gap;
  }
  // Keep the panel fully on-screen.
  x = x.clamp(8.0, (overlaySize.width - panelWidth - 8).clamp(8.0, double.infinity));

  const estimatedHeight = 520.0;
  double y = topLeft.dy;
  y = y.clamp(8.0, (overlaySize.height - estimatedHeight - 8).clamp(8.0, double.infinity));
  return Offset(x, y);
}

class _FloatingColorPicker extends StatefulWidget {
  static const double width = 320;

  final Color initial;
  final Offset startOffset;
  final ValueChanged<Color> onChanged;
  final VoidCallback onClose;

  const _FloatingColorPicker({
    required this.initial,
    required this.startOffset,
    required this.onChanged,
    required this.onClose,
  });

  @override
  State<_FloatingColorPicker> createState() => _FloatingColorPickerState();
}

class _FloatingColorPickerState extends State<_FloatingColorPicker>
    with SingleTickerProviderStateMixin {
  late Offset _offset;
  late TabController _tab;
  late HSVColor _hsv;
  late Color _original;
  final FocusNode _focus = FocusNode(debugLabel: 'color-picker');

  @override
  void initState() {
    super.initState();
    _offset = widget.startOffset;
    _tab = TabController(length: 2, vsync: this);
    _original = widget.initial;
    _hsv = HSVColor.fromColor(widget.initial);
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _tab.dispose();
    _focus.dispose();
    super.dispose();
  }

  Color get _color => _hsv.toColor();

  void _setColor(Color c) {
    setState(() => _hsv = HSVColor.fromColor(c));
    _pushRecent(c);
    widget.onChanged(c);
  }

  void _setHsv(HSVColor h) {
    setState(() => _hsv = h);
    widget.onChanged(h.toColor());
  }

  void _pushRecent(Color c) {
    final rgb = c.value & 0x00FFFFFF;
    _recentColors.removeWhere((x) => (x.value & 0x00FFFFFF) == rgb);
    _recentColors.insert(0, c);
    if (_recentColors.length > _kMaxRecent) _recentColors.length = _kMaxRecent;
  }

  void _dragHeader(DragUpdateDetails d) {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
    final overlaySize = overlay?.size ?? MediaQuery.of(context).size;
    setState(() {
      _offset = Offset(
        (_offset.dx + d.delta.dx).clamp(8.0, overlaySize.width - _FloatingColorPicker.width - 8),
        (_offset.dy + d.delta.dy).clamp(8.0, overlaySize.height - 200.0),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    // Stack: transparent full-screen layer (to swallow outside taps and close
    // the picker), plus the panel itself positioned at _offset.
    return Stack(children: [
      // Invisible tap-to-dismiss barrier. We deliberately do NOT use
      // `ModalBarrier` — that would steal *all* input and make the rest of
      // the app unresponsive. This layer only reacts to pointer events that
      // reach it (i.e. clicks truly outside the panel).
      Positioned.fill(
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: widget.onClose,
        ),
      ),
      Positioned(
        left: _offset.dx,
        top: _offset.dy,
        width: _FloatingColorPicker.width,
        child: KeyboardListener(
          focusNode: _focus,
          onKeyEvent: (e) {
            if (e is KeyDownEvent && e.logicalKey == LogicalKeyboardKey.escape) {
              widget.onClose();
            }
          },
          child: Material(
            elevation: 14,
            color: const Color(0xFF1F1F1F),
            borderRadius: BorderRadius.circular(10),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _header(),
                  TabBar(
                    controller: _tab,
                    indicatorColor: const Color(0xFF3B82F6),
                    labelColor: Colors.white,
                    unselectedLabelColor: Colors.white54,
                    labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                    tabs: const [Tab(text: 'Basic'), Tab(text: 'Advanced')],
                  ),
                  SizedBox(
                    height: 390,
                    child: TabBarView(
                      controller: _tab,
                      children: [
                        _BasicView(color: _color, onChanged: _setColor),
                        _AdvancedView(hsv: _hsv, onChanged: _setHsv),
                      ],
                    ),
                  ),
                  if (_recentColors.isNotEmpty) _RecentsRow(onPick: _setColor),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        ),
      ),
    ]);
  }

  /// Draggable title row. The user grabs here to reposition the panel.
  Widget _header() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanUpdate: _dragHeader,
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: const BoxDecoration(
          color: Color(0xFF1A1A1A),
          border: Border(bottom: BorderSide(color: Color(0xFF2D2D2D))),
        ),
        child: Row(children: [
          const Icon(Icons.drag_indicator, size: 16, color: Colors.white38),
          const SizedBox(width: 4),
          const Text('Color',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
          const Spacer(),
          _PreviewSwatches(
            current: _color,
            original: _original,
            onRevert: () {
              widget.onChanged(_original);
              setState(() => _hsv = HSVColor.fromColor(_original));
            },
          ),
          const SizedBox(width: 8),
          InkResponse(
            onTap: widget.onClose,
            radius: 14,
            child: const Icon(Icons.close, size: 16, color: Colors.white70),
          ),
        ]),
      ),
    );
  }
}

// ── Preview swatches ───────────────────────────────────────────────────

class _PreviewSwatches extends StatelessWidget {
  final Color current;
  final Color original;
  final VoidCallback onRevert;
  const _PreviewSwatches({required this.current, required this.original, required this.onRevert});
  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Tooltip(
        message: 'Revert to original',
        child: GestureDetector(
          onTap: onRevert,
          child: Container(
            width: 22, height: 22,
            decoration: BoxDecoration(
              color: original,
              border: Border.all(color: const Color(0xFF3A3A3A)),
              borderRadius: const BorderRadius.horizontal(left: Radius.circular(3)),
            ),
          ),
        ),
      ),
      Container(
        width: 22, height: 22,
        decoration: BoxDecoration(
          color: current,
          border: Border.all(color: const Color(0xFF3A3A3A)),
          borderRadius: const BorderRadius.horizontal(right: Radius.circular(3)),
        ),
      ),
    ]);
  }
}

// ── Recents ────────────────────────────────────────────────────────────

class _RecentsRow extends StatelessWidget {
  final ValueChanged<Color> onPick;
  const _RecentsRow({required this.onPick});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('RECENT',
            style: TextStyle(color: Colors.white38, fontSize: 10, letterSpacing: 0.6)),
        const SizedBox(height: 4),
        Wrap(spacing: 4, runSpacing: 4, children: [
          for (final c in _recentColors)
            GestureDetector(
              onTap: () => onPick(c),
              child: Container(
                width: 18, height: 18,
                decoration: BoxDecoration(
                  color: c,
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(color: Colors.white24),
                ),
              ),
            ),
        ]),
      ]),
    );
  }
}

// ── Basic view ─────────────────────────────────────────────────────────

class _BasicView extends StatelessWidget {
  final Color color;
  final ValueChanged<Color> onChanged;
  const _BasicView({required this.color, required this.onChanged});

  static final List<List<int>> _rows = [
    [0xFF000000, 0xFF1F1F1F, 0xFF3A3A3A, 0xFF5A5A5A, 0xFF8A8A8A, 0xFFBABABA, 0xFFE4E4E4, 0xFFFFFFFF],
    [0xFF7F1D1D, 0xFFB91C1C, 0xFFDC2626, 0xFFEF4444, 0xFFF87171, 0xFFFCA5A5, 0xFFFECACA, 0xFFFEE2E2],
    [0xFF7C2D12, 0xFFC2410C, 0xFFEA580C, 0xFFF97316, 0xFFFB923C, 0xFFFDBA74, 0xFFFED7AA, 0xFFFFEDD5],
    [0xFF713F12, 0xFFA16207, 0xFFCA8A04, 0xFFEAB308, 0xFFFACC15, 0xFFFDE047, 0xFFFEF08A, 0xFFFEF9C3],
    [0xFF14532D, 0xFF15803D, 0xFF16A34A, 0xFF22C55E, 0xFF4ADE80, 0xFF86EFAC, 0xFFBBF7D0, 0xFFDCFCE7],
    [0xFF134E4A, 0xFF0F766E, 0xFF0D9488, 0xFF14B8A6, 0xFF2DD4BF, 0xFF5EEAD4, 0xFF99F6E4, 0xFFCCFBF1],
    [0xFF1E3A8A, 0xFF1D4ED8, 0xFF2563EB, 0xFF3B82F6, 0xFF60A5FA, 0xFF93C5FD, 0xFFBFDBFE, 0xFFDBEAFE],
    [0xFF4C1D95, 0xFF6D28D9, 0xFF7C3AED, 0xFF8B5CF6, 0xFFA78BFA, 0xFFC4B5FD, 0xFFDDD6FE, 0xFFEDE9FE],
    [0xFF831843, 0xFFBE185D, 0xFFDB2777, 0xFFEC4899, 0xFFF472B6, 0xFFF9A8D4, 0xFFFBCFE8, 0xFFFCE7F3],
  ];

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final row in _rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(children: [
              for (final v in row)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: _SwatchTile(
                      color: Color(v),
                      active: (v & 0x00FFFFFF) == (color.value & 0x00FFFFFF),
                      onTap: () => onChanged(Color(v)),
                    ),
                  ),
                ),
            ]),
          ),
        const SizedBox(height: 10),
        _HexField(color: color, onChanged: onChanged),
      ]),
    );
  }
}

class _SwatchTile extends StatelessWidget {
  final Color color;
  final bool active;
  final VoidCallback onTap;
  const _SwatchTile({required this.color, required this.active, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: active ? Colors.white : const Color(0xFF3A3A3A),
              width: active ? 2 : 1,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Advanced view ──────────────────────────────────────────────────────

class _AdvancedView extends StatelessWidget {
  final HSVColor hsv;
  final ValueChanged<HSVColor> onChanged;
  const _AdvancedView({required this.hsv, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _SaturationValueBox(hsv: hsv, onChanged: onChanged),
        const SizedBox(height: 10),
        _HueSlider(hsv: hsv, onChanged: onChanged),
        const SizedBox(height: 12),
        _HexField(color: hsv.toColor(), onChanged: (c) => onChanged(HSVColor.fromColor(c))),
        const SizedBox(height: 8),
        _RgbInputs(color: hsv.toColor(), onChanged: (c) => onChanged(HSVColor.fromColor(c))),
        const SizedBox(height: 8),
        _HsvInputs(hsv: hsv, onChanged: onChanged),
      ]),
    );
  }
}

class _SaturationValueBox extends StatelessWidget {
  final HSVColor hsv;
  final ValueChanged<HSVColor> onChanged;
  const _SaturationValueBox({required this.hsv, required this.onChanged});

  void _onPan(Offset localPos, Size size) {
    final s = (localPos.dx / size.width).clamp(0.0, 1.0);
    final v = (1 - localPos.dy / size.height).clamp(0.0, 1.0);
    onChanged(hsv.withSaturation(s).withValue(v));
  }

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1.3,
      child: LayoutBuilder(builder: (ctx, box) {
        final size = Size(box.maxWidth, box.maxHeight);
        return GestureDetector(
          onPanStart: (d) => _onPan(d.localPosition, size),
          onPanUpdate: (d) => _onPan(d.localPosition, size),
          onTapDown: (d) => _onPan(d.localPosition, size),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Stack(children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [Colors.white, HSVColor.fromAHSV(1, hsv.hue, 1, 1).toColor()],
                    ),
                  ),
                ),
              ),
              const Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Colors.black],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: hsv.saturation * size.width - 8,
                top: (1 - hsv.value) * size.height - 8,
                child: Container(
                  width: 16, height: 16,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 3)],
                  ),
                ),
              ),
            ]),
          ),
        );
      }),
    );
  }
}

class _HueSlider extends StatelessWidget {
  final HSVColor hsv;
  final ValueChanged<HSVColor> onChanged;
  const _HueSlider({required this.hsv, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (ctx, box) {
      final w = box.maxWidth;
      return GestureDetector(
        onPanStart: (d) => _set(d.localPosition, w),
        onPanUpdate: (d) => _set(d.localPosition, w),
        onTapDown: (d) => _set(d.localPosition, w),
        child: SizedBox(
          height: 18,
          child: Stack(children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(9),
              child: const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Color(0xFFFF0000), Color(0xFFFFFF00), Color(0xFF00FF00),
                      Color(0xFF00FFFF), Color(0xFF0000FF), Color(0xFFFF00FF),
                      Color(0xFFFF0000),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              left: (hsv.hue / 360.0) * w - 7,
              top: 0, bottom: 0,
              child: Container(
                width: 14,
                decoration: BoxDecoration(
                  shape: BoxShape.rectangle,
                  color: Colors.transparent,
                  border: Border.all(color: Colors.white, width: 2),
                  borderRadius: BorderRadius.circular(4),
                  boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 2)],
                ),
              ),
            ),
          ]),
        ),
      );
    });
  }

  void _set(Offset localPos, double width) {
    final h = (localPos.dx / width).clamp(0.0, 1.0) * 360;
    onChanged(hsv.withHue(h));
  }
}

// ── Inputs ─────────────────────────────────────────────────────────────

class _HexField extends StatefulWidget {
  final Color color;
  final ValueChanged<Color> onChanged;
  const _HexField({required this.color, required this.onChanged});
  @override
  State<_HexField> createState() => _HexFieldState();
}

class _HexFieldState extends State<_HexField> {
  late TextEditingController _c;
  @override
  void initState() { super.initState(); _c = TextEditingController(text: _hex(widget.color)); }
  @override
  void didUpdateWidget(covariant _HexField old) {
    super.didUpdateWidget(old);
    if (old.color != widget.color) {
      final h = _hex(widget.color);
      if (_c.text.toUpperCase() != h.toUpperCase()) _c.text = h;
    }
  }
  @override
  void dispose() { _c.dispose(); super.dispose(); }
  String _hex(Color c) =>
      '#${(c.value & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
  void _commit() {
    final v = _c.text.replaceAll('#', '').trim();
    if (v.length == 6) {
      final parsed = int.tryParse(v, radix: 16);
      if (parsed != null) { widget.onChanged(Color(0xFF000000 | parsed)); return; }
    }
    _c.text = _hex(widget.color);
  }
  @override
  Widget build(BuildContext context) {
    return Row(children: [
      const SizedBox(
        width: 44,
        child: Text('HEX',
            style: TextStyle(color: Colors.white54, fontSize: 11, letterSpacing: 0.5)),
      ),
      Expanded(
        child: SizedBox(
          height: 30,
          child: TextField(
            controller: _c,
            onSubmitted: (_) => _commit(),
            onTapOutside: (_) => _commit(),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9a-fA-F#]')),
              LengthLimitingTextInputFormatter(7),
            ],
            style: const TextStyle(color: Colors.white, fontSize: 12, fontFamily: 'monospace'),
            decoration: const InputDecoration(
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              filled: true,
              fillColor: Color(0xFF0E0E0E),
              border: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF3A3A3A))),
              enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF3A3A3A))),
            ),
          ),
        ),
      ),
    ]);
  }
}

class _TripletInputs extends StatelessWidget {
  final List<({String label, int value, int min, int max, ValueChanged<int> onChanged})> items;
  const _TripletInputs({required this.items});
  @override
  Widget build(BuildContext context) {
    return Row(children: [
      for (var i = 0; i < items.length; i++) ...[
        if (i > 0) const SizedBox(width: 6),
        Expanded(child: _IntField(
          label: items[i].label,
          value: items[i].value,
          min: items[i].min,
          max: items[i].max,
          onChanged: items[i].onChanged,
        )),
      ],
    ]);
  }
}

class _IntField extends StatefulWidget {
  final String label;
  final int value, min, max;
  final ValueChanged<int> onChanged;
  const _IntField({required this.label, required this.value, required this.min, required this.max, required this.onChanged});
  @override
  State<_IntField> createState() => _IntFieldState();
}

class _IntFieldState extends State<_IntField> {
  late TextEditingController _c;
  @override
  void initState() { super.initState(); _c = TextEditingController(text: widget.value.toString()); }
  @override
  void didUpdateWidget(covariant _IntField old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value && _c.text != widget.value.toString()) {
      _c.text = widget.value.toString();
    }
  }
  @override
  void dispose() { _c.dispose(); super.dispose(); }
  void _commit() {
    final v = int.tryParse(_c.text);
    if (v == null) { _c.text = widget.value.toString(); return; }
    final clamped = v.clamp(widget.min, widget.max);
    widget.onChanged(clamped);
    if (clamped != v) _c.text = clamped.toString();
  }
  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(widget.label,
          style: const TextStyle(color: Colors.white54, fontSize: 10, letterSpacing: 0.5)),
      const SizedBox(height: 2),
      SizedBox(
        height: 28,
        child: TextField(
          controller: _c,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onSubmitted: (_) => _commit(),
          onTapOutside: (_) => _commit(),
          style: const TextStyle(color: Colors.white, fontSize: 12),
          decoration: const InputDecoration(
            isDense: true,
            contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            filled: true,
            fillColor: Color(0xFF0E0E0E),
            border: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF3A3A3A))),
            enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF3A3A3A))),
          ),
        ),
      ),
    ]);
  }
}

class _RgbInputs extends StatelessWidget {
  final Color color;
  final ValueChanged<Color> onChanged;
  const _RgbInputs({required this.color, required this.onChanged});
  @override
  Widget build(BuildContext context) {
    return _TripletInputs(items: [
      (label: 'R', value: color.red, min: 0, max: 255,
          onChanged: (v) => onChanged(Color.fromARGB(255, v, color.green, color.blue))),
      (label: 'G', value: color.green, min: 0, max: 255,
          onChanged: (v) => onChanged(Color.fromARGB(255, color.red, v, color.blue))),
      (label: 'B', value: color.blue, min: 0, max: 255,
          onChanged: (v) => onChanged(Color.fromARGB(255, color.red, color.green, v))),
    ]);
  }
}

class _HsvInputs extends StatelessWidget {
  final HSVColor hsv;
  final ValueChanged<HSVColor> onChanged;
  const _HsvInputs({required this.hsv, required this.onChanged});
  @override
  Widget build(BuildContext context) {
    return _TripletInputs(items: [
      (label: 'H', value: hsv.hue.round(), min: 0, max: 360,
          onChanged: (v) => onChanged(hsv.withHue(v.toDouble().clamp(0, 360)))),
      (label: 'S', value: (hsv.saturation * 100).round(), min: 0, max: 100,
          onChanged: (v) => onChanged(hsv.withSaturation((v / 100).clamp(0, 1)))),
      (label: 'V', value: (hsv.value * 100).round(), min: 0, max: 100,
          onChanged: (v) => onChanged(hsv.withValue((v / 100).clamp(0, 1)))),
    ]);
  }
}
