import 'dart:convert';
import 'dart:ui' show Color, Offset, Rect;
import 'package:flutter/foundation.dart';
import '../models/document.dart';
import '../models/nodes.dart';

class DocController extends ChangeNotifier {
  FredesDoc _doc = FredesDoc();
  String? _filePath;
  bool _dirty = false;
  String _activePageId;
  final Set<String> _selection = {};
  Tool _tool = Tool.select;
  double _zoom = 1.0;
  Offset _pan = Offset.zero;
  AppMode _mode = AppMode.local;
  String _cloudUrl = 'ws://localhost:1234';
  bool _cloudConnected = false;

  // Undo/redo snapshots (JSON of the whole page: nodes include their children).
  final List<String> _history = [];
  final List<String> _future = [];
  static const int _historyLimit = 100;

  DocController() : _activePageId = '' {
    _activePageId = _doc.pages.first.id;
  }

  // ── getters ──────────────────────────────────────────────────────────
  FredesDoc get doc => _doc;
  String? get filePath => _filePath;
  bool get dirty => _dirty;
  String get activePageId => _activePageId;
  FredesPage get activePage => _doc.pages.firstWhere((p) => p.id == _activePageId);
  Set<String> get selection => _selection;
  Tool get tool => _tool;
  double get zoom => _zoom;
  Offset get pan => _pan;
  AppMode get mode => _mode;
  String get cloudUrl => _cloudUrl;
  bool get cloudConnected => _cloudConnected;
  bool get canUndo => _history.isNotEmpty;
  bool get canRedo => _future.isNotEmpty;

  // ── document lifecycle ───────────────────────────────────────────────
  void newDoc() {
    _doc = FredesDoc();
    _activePageId = _doc.pages.first.id;
    _filePath = null;
    _dirty = false;
    _selection.clear();
    _history.clear();
    _future.clear();
    notifyListeners();
  }

  void loadDoc(FredesDoc d, {String? filePath}) {
    _doc = d;
    _activePageId = d.pages.first.id;
    _filePath = filePath;
    _dirty = false;
    _selection.clear();
    _history.clear();
    _future.clear();
    notifyListeners();
  }

  void setFilePath(String? p) { _filePath = p; notifyListeners(); }
  void markSaved() { _dirty = false; notifyListeners(); }

  // ── tool / view ──────────────────────────────────────────────────────
  void setTool(Tool t) { _tool = t; notifyListeners(); }
  void setZoom(double z) { _zoom = z.clamp(0.05, 16.0); notifyListeners(); }
  void setPan(Offset p) { _pan = p; notifyListeners(); }
  void resetView() { _zoom = 1.0; _pan = Offset.zero; notifyListeners(); }

  // ── mode ─────────────────────────────────────────────────────────────
  void setMode(AppMode m) { _mode = m; notifyListeners(); }
  void setCloudUrl(String u) { _cloudUrl = u; notifyListeners(); }
  void setCloudConnected(bool b) { _cloudConnected = b; notifyListeners(); }

  // ── selection ────────────────────────────────────────────────────────
  void clearSelection() { if (_selection.isEmpty) return; _selection.clear(); notifyListeners(); }
  void setSelection(Iterable<String> ids) {
    _selection..clear()..addAll(ids);
    notifyListeners();
  }
  void toggleSelection(String id, {bool additive = false}) {
    if (additive) {
      if (!_selection.add(id)) _selection.remove(id);
    } else {
      _selection..clear()..add(id);
    }
    notifyListeners();
  }

  // ── history ──────────────────────────────────────────────────────────
  void pushHistory() {
    final snap = jsonEncode(activePage.nodes.map((n) => n.toJson()).toList());
    _history.add(snap);
    if (_history.length > _historyLimit) _history.removeAt(0);
    _future.clear();
    _dirty = true;
  }

  void undo() {
    if (_history.isEmpty) return;
    final cur = jsonEncode(activePage.nodes.map((n) => n.toJson()).toList());
    final prev = _history.removeLast();
    _future.add(cur);
    _restorePage(prev);
    _dirty = true;
    notifyListeners();
  }

  void redo() {
    if (_future.isEmpty) return;
    final cur = jsonEncode(activePage.nodes.map((n) => n.toJson()).toList());
    final next = _future.removeLast();
    _history.add(cur);
    _restorePage(next);
    _dirty = true;
    notifyListeners();
  }

  void _restorePage(String snap) {
    final list = (jsonDecode(snap) as List).cast<Map<String, dynamic>>();
    activePage.nodes
      ..clear()
      ..addAll(list.map(FredesNode.fromJson));
    final alive = <String>{};
    _walk(activePage.nodes, (_, n, __) { alive.add(n.id); return false; });
    _selection.removeWhere((id) => !alive.contains(id));
  }

  // ── tree helpers ─────────────────────────────────────────────────────
  /// Walk the node tree. Callback receives (parent-list, node, absolute-offset).
  /// Return true from the callback to stop the walk.
  bool _walk(
    List<FredesNode> siblings,
    bool Function(List<FredesNode> siblings, FredesNode node, Offset absOrigin) cb, {
    Offset origin = Offset.zero,
  }) {
    for (final n in siblings) {
      final absO = origin + Offset(n.x, n.y);
      if (cb(siblings, n, absO)) return true;
      if (isContainer(n.type)) {
        if (_walk(n.children, cb, origin: absO)) return true;
      }
    }
    return false;
  }

  /// Find a node (and its siblings-list + absolute origin) by id.
  ({FredesNode node, List<FredesNode> siblings, Offset absOrigin})? _find(String id) {
    FredesNode? out;
    List<FredesNode>? outSibs;
    Offset outOrigin = Offset.zero;
    _walk(activePage.nodes, (sibs, n, abs) {
      if (n.id == id) { out = n; outSibs = sibs; outOrigin = abs; return true; }
      return false;
    });
    return out == null ? null : (node: out!, siblings: outSibs!, absOrigin: outOrigin);
  }

  FredesNode? findNode(String id) => _find(id)?.node;
  Offset? absoluteOriginOf(String id) {
    final r = _find(id);
    if (r == null) return null;
    // absOrigin from _walk is the node's own origin; subtract the node's own
    // x/y to get the parent's origin so tools can reason in parent space.
    return r.absOrigin - Offset(r.node.x, r.node.y);
  }

  /// Hit-test top-most node at a page-space point. Descends into containers.
  ({FredesNode node, Offset parentOrigin})? hitTest(Offset page) {
    ({FredesNode node, Offset parentOrigin})? hit;
    void search(List<FredesNode> list, Offset origin) {
      for (var i = list.length - 1; i >= 0; i--) {
        final n = list[i];
        if (!n.visible || n.locked) continue;
        final local = page - origin - Offset(n.x, n.y);
        if (isContainer(n.type)) {
          search(n.children, origin + Offset(n.x, n.y));
          if (hit != null) return;
          if (n.type == NodeType.frame) {
            final rect = Rect.fromLTWH(0, 0, n.width, n.height);
            if (rect.contains(local)) { hit = (node: n, parentOrigin: origin); return; }
          }
        } else {
          if (n.localBounds.contains(local)) { hit = (node: n, parentOrigin: origin); return; }
        }
      }
    }
    search(activePage.nodes, Offset.zero);
    return hit;
  }

  /// Find the deepest Frame that fully contains `rect` (in page space). Used
  /// to auto-parent newly drawn nodes. Returns null for root.
  ({FredesNode frame, Offset parentOrigin})? frameAt(Offset page) {
    ({FredesNode frame, Offset parentOrigin})? hit;
    void search(List<FredesNode> list, Offset origin) {
      for (var i = list.length - 1; i >= 0; i--) {
        final n = list[i];
        if (!n.visible || n.locked) continue;
        if (n.type != NodeType.frame) continue;
        final local = page - origin - Offset(n.x, n.y);
        final rect = Rect.fromLTWH(0, 0, n.width, n.height);
        if (rect.contains(local)) {
          // deeper frame wins
          search(n.children, origin + Offset(n.x, n.y));
          if (hit != null) return;
          hit = (frame: n, parentOrigin: origin + Offset(n.x, n.y));
          return;
        }
      }
    }
    search(activePage.nodes, Offset.zero);
    return hit;
  }

  // ── node ops ─────────────────────────────────────────────────────────

  /// Add a node at page-space position. If the node's top-left lies inside a
  /// Frame, the node is auto-parented into that frame (Figma behavior) and
  /// `x`/`y` are converted to frame-local coordinates.
  void addNodePageSpace(FredesNode n, Offset pagePos, {bool select = true}) {
    pushHistory();
    final f = frameAt(pagePos);
    if (f != null) {
      n.x = n.x - f.parentOrigin.dx;
      n.y = n.y - f.parentOrigin.dy;
      // Also shift points for line/path which are in local space
      if (n.type == NodeType.line || n.type == NodeType.path) {
        n.points = n.points.map((p) => p - f.parentOrigin).toList();
      }
      f.frame.children.add(n);
    } else {
      activePage.nodes.add(n);
    }
    if (select) { _selection..clear()..add(n.id); }
    _dirty = true;
    notifyListeners();
  }

  void updateNode(String id, void Function(FredesNode) mutate, {bool history = false}) {
    final r = _find(id);
    if (r == null) return;
    if (history) pushHistory();
    mutate(r.node);
    _dirty = true;
    notifyListeners();
  }

  void updateSelected(void Function(FredesNode) mutate, {bool history = true}) {
    if (_selection.isEmpty) return;
    if (history) pushHistory();
    _walk(activePage.nodes, (_, n, __) { if (_selection.contains(n.id)) mutate(n); return false; });
    _dirty = true;
    notifyListeners();
  }

  void deleteSelected() {
    if (_selection.isEmpty) return;
    pushHistory();
    final toDelete = Set<String>.from(_selection);
    _removeDescendants(activePage.nodes, toDelete);
    _selection.clear();
    _dirty = true;
    notifyListeners();
  }

  void _removeDescendants(List<FredesNode> siblings, Set<String> ids) {
    siblings.removeWhere((n) => ids.contains(n.id));
    for (final n in siblings) {
      if (isContainer(n.type)) _removeDescendants(n.children, ids);
    }
  }

  void duplicateSelected() {
    if (_selection.isEmpty) return;
    pushHistory();
    final ids = _selection.toList();
    final newIds = <String>[];
    for (final id in ids) {
      final r = _find(id);
      if (r == null) continue;
      final clone = r.node.clone()
        ..x = r.node.x + 16
        ..y = r.node.y + 16;
      r.siblings.add(clone);
      newIds.add(clone.id);
    }
    _selection..clear()..addAll(newIds);
    _dirty = true;
    notifyListeners();
  }

  void reorder(String id, String dir) {
    pushHistory();
    final r = _find(id);
    if (r == null) return;
    final list = r.siblings;
    final i = list.indexOf(r.node);
    list.removeAt(i);
    switch (dir) {
      case 'front': list.add(r.node); break;
      case 'back': list.insert(0, r.node); break;
      case 'forward': list.insert((i + 1).clamp(0, list.length), r.node); break;
      case 'backward': list.insert((i - 1).clamp(0, list.length), r.node); break;
      default: list.insert(i, r.node);
    }
    _dirty = true;
    notifyListeners();
  }

  void setPageBackground(String hex) {
    pushHistory();
    activePage.background = hex;
    _dirty = true;
    notifyListeners();
  }

  // ── pages ────────────────────────────────────────────────────────────
  void addPage({String? name}) {
    final idx = _doc.pages.length + 1;
    final p = FredesPage(name: name ?? 'Page $idx');
    _doc.pages.add(p);
    _activePageId = p.id;
    _selection.clear();
    _history.clear();
    _future.clear();
    _dirty = true;
    notifyListeners();
  }

  void setActivePageId(String id) {
    if (!_doc.pages.any((p) => p.id == id)) return;
    _activePageId = id;
    _selection.clear();
    _history.clear();
    _future.clear();
    notifyListeners();
  }

  void renamePage(String id, String name) {
    final p = _doc.pages.firstWhere((p) => p.id == id, orElse: () => _doc.pages.first);
    if (p.name == name) return;
    p.name = name;
    _dirty = true;
    notifyListeners();
  }

  void deletePage(String id) {
    if (_doc.pages.length <= 1) return; // keep at least one
    final idx = _doc.pages.indexWhere((p) => p.id == id);
    if (idx < 0) return;
    _doc.pages.removeAt(idx);
    if (_activePageId == id) {
      _activePageId = _doc.pages[idx.clamp(0, _doc.pages.length - 1)].id;
    }
    _selection.clear();
    _history.clear();
    _future.clear();
    _dirty = true;
    notifyListeners();
  }

  /// Group the current selection into a new Group node, preserving absolute
  /// positions. The group is placed at the sibling list of the first-selected
  /// node's parent, so it lives at the same depth.
  void groupSelected() {
    if (_selection.isEmpty) return;
    pushHistory();
    // Resolve selected nodes with their current absolute origin.
    final entries = <({FredesNode node, List<FredesNode> siblings, Offset absOrigin})>[];
    for (final id in _selection.toList()) {
      final r = _find(id);
      if (r != null) entries.add(r);
    }
    if (entries.isEmpty) return;

    // Union bounding box in page space
    Rect bbox = entries.first.absOrigin.pagesAbsBounds(entries.first.node);
    for (final e in entries.skip(1)) {
      bbox = bbox.expandToInclude(e.absOrigin.pagesAbsBounds(e.node));
    }

    // Parent = first entry's siblings list (top-level or inside same parent).
    final parentSibs = entries.first.siblings;
    // Parent origin = absolute origin of parent list (which is first entry's abs - its own x,y)
    final parentOrigin = entries.first.absOrigin - Offset(entries.first.node.x, entries.first.node.y);

    final group = FredesNode(
      type: NodeType.group,
      x: bbox.left - parentOrigin.dx,
      y: bbox.top - parentOrigin.dy,
    );

    for (final e in entries) {
      e.siblings.remove(e.node);
      // Convert to group-local coords.
      final oldAbs = e.absOrigin; // absolute origin of node's own top-left
      e.node.x = oldAbs.dx - bbox.left;
      e.node.y = oldAbs.dy - bbox.top;
      group.children.add(e.node);
    }
    parentSibs.add(group);
    _selection
      ..clear()
      ..add(group.id);
    _dirty = true;
    notifyListeners();
  }

  /// Ungroup: dissolve selected Group/Frame containers, promoting their
  /// children up one level with preserved absolute positions.
  void ungroupSelected() {
    if (_selection.isEmpty) return;
    pushHistory();
    final newSel = <String>{};
    for (final id in _selection.toList()) {
      final r = _find(id);
      if (r == null || !isContainer(r.node.type)) continue;
      final parent = r.siblings;
      final idx = parent.indexOf(r.node);
      parent.removeAt(idx);
      for (final c in r.node.children) {
        c.x += r.node.x;
        c.y += r.node.y;
        parent.insert(idx, c);
        newSel.add(c.id);
      }
    }
    if (newSel.isNotEmpty) {
      _selection..clear()..addAll(newSel);
    }
    _dirty = true;
    notifyListeners();
  }

  /// Wrap the current selection in a Frame (like pressing F then drag-around,
  /// but as a menu command). Useful on the next milestone — exposed now so
  /// the UI can bind to it.
  void frameSelected() {
    if (_selection.isEmpty) return;
    pushHistory();
    final entries = <({FredesNode node, List<FredesNode> siblings, Offset absOrigin})>[];
    for (final id in _selection.toList()) {
      final r = _find(id);
      if (r != null) entries.add(r);
    }
    if (entries.isEmpty) return;
    Rect bbox = entries.first.absOrigin.pagesAbsBounds(entries.first.node);
    for (final e in entries.skip(1)) {
      bbox = bbox.expandToInclude(e.absOrigin.pagesAbsBounds(e.node));
    }
    final parentSibs = entries.first.siblings;
    final parentOrigin = entries.first.absOrigin - Offset(entries.first.node.x, entries.first.node.y);
    final frame = FredesNode(
      type: NodeType.frame,
      x: bbox.left - parentOrigin.dx,
      y: bbox.top - parentOrigin.dy,
      width: bbox.width,
      height: bbox.height,
      fill: const Color(0xFFFFFFFF),
    );
    for (final e in entries) {
      e.siblings.remove(e.node);
      final oldAbs = e.absOrigin;
      e.node.x = oldAbs.dx - bbox.left;
      e.node.y = oldAbs.dy - bbox.top;
      frame.children.add(e.node);
    }
    parentSibs.add(frame);
    _selection..clear()..add(frame.id);
    _dirty = true;
    notifyListeners();
  }

  /// Move [draggedId] into [toParentId] (null = root of the active page) at
  /// the given child [index] (clamped to the bounds of the target list).
  /// Absolute position is preserved: the moved node's local (x, y) is
  /// rewritten in the new parent's coordinate space.
  ///
  /// No-ops and guards:
  /// * Dropping a node into itself or any of its descendants would create a
  ///   cycle — refused silently.
  /// * Reparenting onto the same spot in the same parent is a no-op.
  bool reparent(String draggedId, {String? toParentId, int index = -1}) {
    final r = _find(draggedId);
    if (r == null) return false;
    if (toParentId == draggedId) return false;
    if (toParentId != null && _isDescendant(r.node, toParentId)) return false;

    // Resolve target list + its absolute origin.
    final List<FredesNode> targetSibs;
    final Offset targetAbsOrigin;
    if (toParentId == null) {
      targetSibs = activePage.nodes;
      targetAbsOrigin = Offset.zero;
    } else {
      final tr = _find(toParentId);
      if (tr == null || !isContainer(tr.node.type)) return false;
      targetSibs = tr.node.children;
      // Absolute origin of a node = origin of its *contents*, which is what
      // we want for reparenting coordinate math.
      targetAbsOrigin = tr.absOrigin;
    }

    final curIdx = r.siblings.indexOf(r.node);
    // Same parent + same index → no-op.
    if (identical(targetSibs, r.siblings)) {
      final clamped = index < 0 ? targetSibs.length - 1 : index.clamp(0, targetSibs.length - 1);
      if (clamped == curIdx) return false;
    }

    pushHistory();

    // Capture absolute top-left of the node *before* removal.
    final draggedAbsTopLeft = r.absOrigin;

    r.siblings.removeAt(curIdx);

    // Adjusting index when we removed from the same list and the removal was
    // before the insertion point shifts it down by one.
    int insertAt = (index < 0) ? targetSibs.length : index;
    if (identical(targetSibs, r.siblings) && curIdx < insertAt) insertAt -= 1;
    insertAt = insertAt.clamp(0, targetSibs.length);

    // Convert absolute top-left to new parent-local coords.
    r.node.x = draggedAbsTopLeft.dx - targetAbsOrigin.dx;
    r.node.y = draggedAbsTopLeft.dy - targetAbsOrigin.dy;

    targetSibs.insert(insertAt, r.node);
    _dirty = true;
    notifyListeners();
    return true;
  }

  bool _isDescendant(FredesNode ancestor, String candidateId) {
    if (!isContainer(ancestor.type)) return false;
    for (final c in ancestor.children) {
      if (c.id == candidateId) return true;
      if (_isDescendant(c, candidateId)) return true;
    }
    return false;
  }

  /// Public re-emit so views can repaint after direct mutations.
  void touch() => notifyListeners();

  /// Bulk replace doc — used by cloud sync to apply remote snapshots.
  void replaceDocFromRemote(FredesDoc d) {
    _doc = d;
    if (!_doc.pages.any((p) => p.id == _activePageId)) {
      _activePageId = _doc.pages.first.id;
    }
    final alive = <String>{};
    _walk(activePage.nodes, (_, n, __) { alive.add(n.id); return false; });
    _selection.removeWhere((id) => !alive.contains(id));
    notifyListeners();
  }
}

extension _OffsetAbs on Offset {
  /// Helper: absolute-space bounds of a node given its absolute origin.
  Rect pagesAbsBounds(FredesNode n) => n.localBounds.translate(dx, dy);
}
