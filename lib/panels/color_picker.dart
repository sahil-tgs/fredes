import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Recently-used colors, most-recent-first. In-memory only — intentionally
/// not persisted yet; will survive across picker opens within a session.
final List<Color> _recentColors = <Color>[];
const int _kMaxRecent = 18;

/// Open the Fredes color picker. Returns the picked color, or `null` if the
/// user cancels. The dialog defaults to the Basic tab; the user can flip to
/// the Advanced (Photoshop-style) view.
Future<Color?> showColorPicker(BuildContext context, Color initial) {
  return showDialog<Color>(
    context: context,
    barrierColor: Colors.black54,
    builder: (ctx) => _FredesColorPickerDialog(initial: initial),
  );
}

class _FredesColorPickerDialog extends StatefulWidget {
  final Color initial;
  const _FredesColorPickerDialog({required this.initial});
  @override
  State<_FredesColorPickerDialog> createState() => _FredesColorPickerDialogState();
}

class _FredesColorPickerDialogState extends State<_FredesColorPickerDialog>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  late HSVColor _hsv;
  late Color _original;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _original = widget.initial;
    _hsv = HSVColor.fromColor(widget.initial);
  }

  @override
  void dispose() { _tab.dispose(); super.dispose(); }

  Color get _color => _hsv.toColor();

  void _setColor(Color c) {
    setState(() => _hsv = HSVColor.fromColor(c));
  }

  void _apply() {
    final picked = _color;
    // Push to recents, dedup by RGB only.
    final rgbKey = picked.value & 0x00FFFFFF;
    _recentColors.removeWhere((c) => (c.value & 0x00FFFFFF) == rgbKey);
    _recentColors.insert(0, picked);
    if (_recentColors.length > _kMaxRecent) _recentColors.length = _kMaxRecent;
    Navigator.of(context).pop(picked);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF1F1F1F),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: SizedBox(
        width: 340,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header: tabs + current-vs-original preview
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
              child: Row(children: [
                const Text('Color',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
                const Spacer(),
                _PreviewSwatches(current: _color, original: _original,
                    onRevert: () => _setColor(_original)),
              ]),
            ),
            const SizedBox(height: 8),
            TabBar(
              controller: _tab,
              indicatorColor: const Color(0xFF3B82F6),
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white54,
              labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
              tabs: const [Tab(text: 'Basic'), Tab(text: 'Advanced')],
            ),
            SizedBox(
              height: 430,
              child: TabBarView(
                controller: _tab,
                children: [
                  _BasicView(color: _color, onChanged: _setColor),
                  _AdvancedView(hsv: _hsv, onChanged: (h) => setState(() => _hsv = h)),
                ],
              ),
            ),
            // Recents + buttons
            if (_recentColors.isNotEmpty) _RecentsRow(onPick: _setColor),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
              child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
                ),
                const SizedBox(width: 6),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF3B82F6)),
                  onPressed: _apply,
                  child: const Text('Apply'),
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Preview swatches ────────────────────────────────────────────────────

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
            width: 24, height: 24,
            decoration: BoxDecoration(
              color: original,
              border: Border.all(color: const Color(0xFF3A3A3A)),
              borderRadius: const BorderRadius.horizontal(left: Radius.circular(4)),
            ),
          ),
        ),
      ),
      Container(
        width: 24, height: 24,
        decoration: BoxDecoration(
          color: current,
          border: Border.all(color: const Color(0xFF3A3A3A)),
          borderRadius: const BorderRadius.horizontal(right: Radius.circular(4)),
        ),
      ),
    ]);
  }
}

// ── Recents ─────────────────────────────────────────────────────────────

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

// ── Basic view ──────────────────────────────────────────────────────────

class _BasicView extends StatelessWidget {
  final Color color;
  final ValueChanged<Color> onChanged;
  const _BasicView({required this.color, required this.onChanged});

  /// Curated palette — 9 hue ramps (5 steps each) + a 6-step grey ramp.
  /// Designed to be visually useful at a glance without overwhelming.
  static final List<List<int>> _rows = [
    // Greys
    [0xFF000000, 0xFF1F1F1F, 0xFF3A3A3A, 0xFF5A5A5A, 0xFF8A8A8A, 0xFFBABABA, 0xFFE4E4E4, 0xFFFFFFFF],
    // Red
    [0xFF7F1D1D, 0xFFB91C1C, 0xFFDC2626, 0xFFEF4444, 0xFFF87171, 0xFFFCA5A5, 0xFFFECACA, 0xFFFEE2E2],
    // Orange
    [0xFF7C2D12, 0xFFC2410C, 0xFFEA580C, 0xFFF97316, 0xFFFB923C, 0xFFFDBA74, 0xFFFED7AA, 0xFFFFEDD5],
    // Yellow
    [0xFF713F12, 0xFFA16207, 0xFFCA8A04, 0xFFEAB308, 0xFFFACC15, 0xFFFDE047, 0xFFFEF08A, 0xFFFEF9C3],
    // Green
    [0xFF14532D, 0xFF15803D, 0xFF16A34A, 0xFF22C55E, 0xFF4ADE80, 0xFF86EFAC, 0xFFBBF7D0, 0xFFDCFCE7],
    // Teal
    [0xFF134E4A, 0xFF0F766E, 0xFF0D9488, 0xFF14B8A6, 0xFF2DD4BF, 0xFF5EEAD4, 0xFF99F6E4, 0xFFCCFBF1],
    // Blue
    [0xFF1E3A8A, 0xFF1D4ED8, 0xFF2563EB, 0xFF3B82F6, 0xFF60A5FA, 0xFF93C5FD, 0xFFBFDBFE, 0xFFDBEAFE],
    // Purple
    [0xFF4C1D95, 0xFF6D28D9, 0xFF7C3AED, 0xFF8B5CF6, 0xFFA78BFA, 0xFFC4B5FD, 0xFFDDD6FE, 0xFFEDE9FE],
    // Pink
    [0xFF831843, 0xFFBE185D, 0xFFDB2777, 0xFFEC4899, 0xFFF472B6, 0xFFF9A8D4, 0xFFFBCFE8, 0xFFFCE7F3],
  ];

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // Swatch grid
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
        const SizedBox(height: 12),
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
        // SV square — choose saturation (x) and value (y) at fixed hue.
        _SaturationValueBox(
          hsv: hsv,
          onChanged: onChanged,
        ),
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
              // Hue-coloured base + white→colour (saturation) horizontal
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
              // Black gradient (value) vertical, overlayed
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
              // Cursor ring at current (s, v)
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

// ── Inputs ──────────────────────────────────────────────────────────────

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
      if (parsed != null) {
        widget.onChanged(Color(0xFF000000 | parsed));
        return;
      }
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

/// Three-up int inputs (used for RGB and HSV).
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

