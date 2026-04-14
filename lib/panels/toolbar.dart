import 'package:flutter/material.dart';
import '../models/document.dart';
import '../state/doc_controller.dart';

class FredesToolbar extends StatelessWidget {
  final DocController doc;
  const FredesToolbar({super.key, required this.doc});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: doc,
      builder: (ctx, _) => Container(
        height: 44,
        decoration: const BoxDecoration(
          color: Color(0xFF252525),
          border: Border(bottom: BorderSide(color: Color(0xFF3A3A3A))),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            const _Brand(),
            const SizedBox(width: 12),
            for (final t in const [
              (Tool.select, 'Select',    '↖', 'V / F'),
              (Tool.hand,   'Pan',       '✋', 'P / H'),
              (Tool.frame,  'Frame',     '🖽', 'A'),
              (Tool.rect,   'Rectangle', '▭', 'R'),
              (Tool.ellipse,'Ellipse',   '◯', 'O'),
              (Tool.line,   'Line',      '／', 'L'),
              (Tool.pen,    'Pen',       '✎', 'N'),
              (Tool.text,   'Text',      'T', 'T'),
            ])
              _ToolButton(
                tool: t.$1,
                label: '${t.$2} (${t.$4})',
                glyph: t.$3,
                active: doc.tool == t.$1,
                onTap: () => doc.setTool(t.$1),
              ),
            const Spacer(),
            _ZoomControls(doc: doc),
            const SizedBox(width: 12),
            _ModePill(doc: doc),
          ],
        ),
      ),
    );
  }
}

class _Brand extends StatelessWidget {
  const _Brand();
  @override
  Widget build(BuildContext context) => const Row(
        children: [
          Text('◆', style: TextStyle(color: Color(0xFF3B82F6), fontSize: 16)),
          SizedBox(width: 6),
          Text('Fredes', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.white)),
          SizedBox(width: 12),
          VerticalDivider(width: 1, thickness: 1, color: Color(0xFF3A3A3A)),
        ],
      );
}

class _ToolButton extends StatelessWidget {
  final Tool tool;
  final String label;
  final String glyph;
  final bool active;
  final VoidCallback onTap;
  const _ToolButton({required this.tool, required this.label, required this.glyph, required this.active, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Material(
          color: active ? const Color(0xFF3B82F6) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          child: InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
              child: Text(glyph, style: TextStyle(color: active ? Colors.white : Colors.white70, fontSize: 14)),
            ),
          ),
        ),
      ),
    );
  }
}

class _ZoomControls extends StatelessWidget {
  final DocController doc;
  const _ZoomControls({required this.doc});
  @override
  Widget build(BuildContext context) {
    final pct = (doc.zoom * 100).round();
    return Row(
      children: [
        _zoomBtn('−', () => doc.setZoom(doc.zoom / 1.2)),
        SizedBox(width: 56, child: Center(child: GestureDetector(
          onTap: () { doc.setZoom(1); doc.setPan(Offset.zero); },
          child: Text('$pct%', style: const TextStyle(color: Colors.white70)),
        ))),
        _zoomBtn('+', () => doc.setZoom(doc.zoom * 1.2)),
      ],
    );
  }
  Widget _zoomBtn(String t, VoidCallback cb) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 2),
    child: SizedBox(
      width: 28, height: 28,
      child: TextButton(
        style: TextButton.styleFrom(
          padding: EdgeInsets.zero,
          minimumSize: const Size(28, 28),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4), side: const BorderSide(color: Color(0xFF3A3A3A))),
          foregroundColor: Colors.white70,
        ),
        onPressed: cb,
        child: Text(t),
      ),
    ),
  );
}

class _ModePill extends StatelessWidget {
  final DocController doc;
  const _ModePill({required this.doc});
  @override
  Widget build(BuildContext context) {
    final isCloud = doc.mode == AppMode.cloud;
    final dot = isCloud ? const Color(0xFF3B82F6) : const Color(0xFF22C55E);
    final label = !isCloud ? 'Local' : (doc.cloudConnected ? 'Cloud' : 'Cloud (offline)');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF2D2D2D),
        border: Border.all(color: const Color(0xFF3A3A3A)),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
      ]),
    );
  }
}
