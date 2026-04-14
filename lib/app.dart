import 'dart:io';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'canvas/canvas_view.dart';
import 'cloud/sync.dart';
import 'format/fredes_io.dart';
import 'format/svg_export.dart';
import 'models/document.dart';
import 'panels/layers_panel.dart';
import 'panels/properties_panel.dart';
import 'panels/toolbar.dart';
import 'state/doc_controller.dart';

class FredesApp extends StatefulWidget {
  const FredesApp({super.key});
  @override
  State<FredesApp> createState() => _FredesAppState();
}

class _FredesAppState extends State<FredesApp> {
  final DocController doc = DocController();
  late final CloudSync cloud = CloudSync(doc);
  final FocusNode _rootFocus = FocusNode(debugLabel: 'fredes-root', skipTraversal: true);

  late final _TextAwareShortcutManager _shortcutManager =
      _TextAwareShortcutManager(shortcuts: _shortcuts());

  @override
  void initState() {
    super.initState();
    doc.addListener(_modeWatcher);
  }

  AppMode? _lastMode;
  String? _lastUrl;
  Future<void> _modeWatcher() async {
    if (doc.mode == _lastMode && doc.cloudUrl == _lastUrl) return;
    _lastMode = doc.mode;
    _lastUrl = doc.cloudUrl;
    if (doc.mode == AppMode.cloud) {
      await cloud.connect(doc.cloudUrl);
    } else {
      await cloud.disconnect();
    }
  }

  @override
  void dispose() {
    doc.removeListener(_modeWatcher);
    cloud.disconnect();
    doc.dispose();
    _rootFocus.dispose();
    super.dispose();
  }

  // ── File ops ─────────────────────────────────────────────────────────
  Future<void> _new() async {
    if (doc.dirty) {
      final ok = await _confirm(context, 'Discard unsaved changes?');
      if (!ok) return;
    }
    doc.newDoc();
  }

  Future<void> _open() async {
    // Accept the legacy .freegma extension so pre-rename files still open.
    const xType = XTypeGroup(label: 'Fredes', extensions: ['fredes', 'freegma', 'json']);
    final f = await openFile(acceptedTypeGroups: [xType]);
    if (f == null) return;
    try {
      final d = await readFile(f.path);
      doc.loadDoc(d, filePath: f.path);
    } catch (e) {
      _toast('Failed to open: $e');
    }
  }

  Future<void> _save() async {
    var path = doc.filePath;
    if (path == null) {
      final loc = await getSaveLocation(
        suggestedName: '${doc.doc.name.isEmpty ? "untitled" : doc.doc.name}.fredes',
        acceptedTypeGroups: const [XTypeGroup(label: 'Fredes', extensions: ['fredes'])],
      );
      if (loc == null) return;
      path = loc.path.endsWith('.fredes') ? loc.path : '${loc.path}.fredes';
      doc.setFilePath(path);
    }
    await writeFile(path, doc.doc);
    doc.markSaved();
    _toast('Saved $path');
  }

  Future<void> _saveAs() async {
    final loc = await getSaveLocation(
      suggestedName: '${doc.doc.name.isEmpty ? "untitled" : doc.doc.name}.fredes',
      acceptedTypeGroups: const [XTypeGroup(label: 'Fredes', extensions: ['fredes'])],
    );
    if (loc == null) return;
    final path = loc.path.endsWith('.fredes') ? loc.path : '${loc.path}.fredes';
    doc.setFilePath(path);
    await writeFile(path, doc.doc);
    doc.markSaved();
    _toast('Saved $path');
  }

  Future<void> _exportSvg() async {
    final loc = await getSaveLocation(
      suggestedName: '${doc.doc.name.isEmpty ? "untitled" : doc.doc.name}.svg',
      acceptedTypeGroups: const [XTypeGroup(label: 'SVG', extensions: ['svg'])],
    );
    if (loc == null) return;
    final path = loc.path.endsWith('.svg') ? loc.path : '${loc.path}.svg';
    await File(path).writeAsString(pageToSvg(doc.activePage));
    _toast('Exported $path');
  }

  // ── helpers ──────────────────────────────────────────────────────────
  void _toast(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(m), duration: const Duration(seconds: 2), backgroundColor: const Color(0xFF1E1E1E),
    ));
  }

  Future<bool> _confirm(BuildContext ctx, String msg) async {
    final r = await showDialog<bool>(
      context: ctx,
      builder: (c) => AlertDialog(
        backgroundColor: const Color(0xFF252525),
        content: Text(msg, style: const TextStyle(color: Colors.white)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(c, true), child: const Text('OK')),
        ],
      ),
    );
    return r == true;
  }

  // ── Shortcuts ────────────────────────────────────────────────────────
  Map<ShortcutActivator, Intent> _shortcuts() => {
        // Tool shortcuts — per user convention:
        //   V or F → Select (merged: "free selection / no tool state")
        //   P or H → Pan
        //   R → Rectangle, O → Ellipse, L → Line, T → Text
        //   A → Frame (artboard), N → Pen (free draw) — reassigned off F/P.
        const SingleActivator(LogicalKeyboardKey.keyV): const _ToolIntent(Tool.select),
        const SingleActivator(LogicalKeyboardKey.keyF): const _ToolIntent(Tool.select),
        const SingleActivator(LogicalKeyboardKey.keyP): const _ToolIntent(Tool.hand),
        const SingleActivator(LogicalKeyboardKey.keyH): const _ToolIntent(Tool.hand),
        const SingleActivator(LogicalKeyboardKey.keyA): const _ToolIntent(Tool.frame),
        const SingleActivator(LogicalKeyboardKey.keyR): const _ToolIntent(Tool.rect),
        const SingleActivator(LogicalKeyboardKey.keyO): const _ToolIntent(Tool.ellipse),
        const SingleActivator(LogicalKeyboardKey.keyL): const _ToolIntent(Tool.line),
        const SingleActivator(LogicalKeyboardKey.keyN): const _ToolIntent(Tool.pen),
        const SingleActivator(LogicalKeyboardKey.keyT): const _ToolIntent(Tool.text),
        const SingleActivator(LogicalKeyboardKey.keyG, control: true): const _GroupIntent(),
        const SingleActivator(LogicalKeyboardKey.keyG, control: true, shift: true): const _UngroupIntent(),
        const SingleActivator(LogicalKeyboardKey.keyZ, control: true): const _UndoIntent(),
        const SingleActivator(LogicalKeyboardKey.keyZ, control: true, shift: true): const _RedoIntent(),
        const SingleActivator(LogicalKeyboardKey.keyY, control: true): const _RedoIntent(),
        const SingleActivator(LogicalKeyboardKey.keyD, control: true): const _DupIntent(),
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): const _SaveIntent(),
        const SingleActivator(LogicalKeyboardKey.keyS, control: true, shift: true): const _SaveAsIntent(),
        const SingleActivator(LogicalKeyboardKey.keyO, control: true): const _OpenIntent(),
        const SingleActivator(LogicalKeyboardKey.keyN, control: true): const _NewIntent(),
        const SingleActivator(LogicalKeyboardKey.delete): const _DelIntent(),
        const SingleActivator(LogicalKeyboardKey.backspace): const _DelIntent(),
        const SingleActivator(LogicalKeyboardKey.equal, control: true): const _ZoomInIntent(),
        const SingleActivator(LogicalKeyboardKey.minus, control: true): const _ZoomOutIntent(),
        const SingleActivator(LogicalKeyboardKey.digit0, control: true): const _ZoomResetIntent(),
      };

  Map<Type, Action<Intent>> _actions() => {
        _ToolIntent: CallbackAction<_ToolIntent>(onInvoke: (i) { doc.setTool(i.tool); return null; }),
        _UndoIntent: CallbackAction<_UndoIntent>(onInvoke: (_) { doc.undo(); return null; }),
        _RedoIntent: CallbackAction<_RedoIntent>(onInvoke: (_) { doc.redo(); return null; }),
        _DupIntent: CallbackAction<_DupIntent>(onInvoke: (_) { doc.duplicateSelected(); return null; }),
        _SaveIntent: CallbackAction<_SaveIntent>(onInvoke: (_) { _save(); return null; }),
        _SaveAsIntent: CallbackAction<_SaveAsIntent>(onInvoke: (_) { _saveAs(); return null; }),
        _OpenIntent: CallbackAction<_OpenIntent>(onInvoke: (_) { _open(); return null; }),
        _NewIntent: CallbackAction<_NewIntent>(onInvoke: (_) { _new(); return null; }),
        _DelIntent: CallbackAction<_DelIntent>(onInvoke: (_) { doc.deleteSelected(); return null; }),
        _GroupIntent: CallbackAction<_GroupIntent>(onInvoke: (_) { doc.groupSelected(); return null; }),
        _UngroupIntent: CallbackAction<_UngroupIntent>(onInvoke: (_) { doc.ungroupSelected(); return null; }),
        _ZoomInIntent: CallbackAction<_ZoomInIntent>(onInvoke: (_) { doc.setZoom(doc.zoom * 1.2); return null; }),
        _ZoomOutIntent: CallbackAction<_ZoomOutIntent>(onInvoke: (_) { doc.setZoom(doc.zoom / 1.2); return null; }),
        _ZoomResetIntent: CallbackAction<_ZoomResetIntent>(onInvoke: (_) { doc.resetView(); return null; }),
      };

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Fredes',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF1E1E1E),
        textTheme: const TextTheme(),
        colorScheme: const ColorScheme.dark(primary: Color(0xFF3B82F6)),
      ),
      home: Shortcuts.manager(
        manager: _shortcutManager,
        child: Actions(
          actions: _actions(),
          child: Focus(
            focusNode: _rootFocus,
            autofocus: true,
            // Whenever a pointer-down happens anywhere in the app frame, pull
            // focus back to the root. Without this, clicking a TextField (or
            // even a dropdown) transfers primary focus away, and after it
            // closes no one re-assumes focus — so keyboard shortcuts
            // silently die. We only snap back when the event didn't land on
            // a text input, so active typing isn't interrupted.
            child: Listener(
              behavior: HitTestBehavior.translucent,
              onPointerDown: (_) {
                // Defer: at pointer-down a TextField hasn't yet claimed
                // focus, so checking _textInputHasFocus() here would race
                // and we'd stomp on text editing. Post-frame the focus has
                // settled — if it landed on a text input we back off, else
                // we restore focus to root so shortcuts keep firing.
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  if (!_TextAwareShortcutManager._textInputHasFocus()) {
                    _rootFocus.requestFocus();
                  }
                });
              },
              child: Scaffold(
                body: Column(
                  children: [
                    Row(children: [
                      _MenuBar(onNew: _new, onOpen: _open, onSave: _save, onSaveAs: _saveAs, onExportSvg: _exportSvg, doc: doc),
                    ]),
                    FredesToolbar(doc: doc),
                    Expanded(
                      child: Row(children: [
                        LayersPanel(doc: doc),
                        Expanded(child: CanvasView(doc: doc)),
                        PropertiesPanel(doc: doc),
                      ]),
                    ),
                    _StatusBar(doc: doc),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A [ShortcutManager] that disables itself entirely whenever an
/// [EditableText] (i.e. any [TextField], inline canvas text editor, etc.)
/// owns the primary focus.
///
/// Why this exists: the default Flutter `Shortcuts` *consumes* a key event
/// the moment one of its activators matches, regardless of what the action
/// returns. So binding `Backspace`/`Delete` at the app root would swallow
/// those keys before any focused text field could process them — leading to
/// bugs where the user can never type backspace into a text field.
///
/// By short-circuiting at the manager level (returning
/// `KeyEventResult.ignored`), we let the key continue to propagate through
/// the focus chain and reach the text field's own internal shortcuts.
class _TextAwareShortcutManager extends ShortcutManager {
  _TextAwareShortcutManager({required super.shortcuts});

  @override
  KeyEventResult handleKeypress(BuildContext context, KeyEvent event) {
    if (_textInputHasFocus()) return KeyEventResult.ignored;
    return super.handleKeypress(context, event);
  }

  static bool _textInputHasFocus() {
    final pf = FocusManager.instance.primaryFocus;
    if (pf == null || !pf.hasPrimaryFocus) return false;
    final ctx = pf.context;
    if (ctx == null) return false;
    if (ctx.widget is EditableText) return true;
    bool found = false;
    ctx.visitAncestorElements((e) {
      if (e.widget is EditableText) { found = true; return false; }
      return true;
    });
    return found;
  }
}

// Intents
class _ToolIntent extends Intent { final Tool tool; const _ToolIntent(this.tool); }
class _UndoIntent extends Intent { const _UndoIntent(); }
class _RedoIntent extends Intent { const _RedoIntent(); }
class _DupIntent extends Intent { const _DupIntent(); }
class _SaveIntent extends Intent { const _SaveIntent(); }
class _SaveAsIntent extends Intent { const _SaveAsIntent(); }
class _OpenIntent extends Intent { const _OpenIntent(); }
class _NewIntent extends Intent { const _NewIntent(); }
class _DelIntent extends Intent { const _DelIntent(); }
class _GroupIntent extends Intent { const _GroupIntent(); }
class _UngroupIntent extends Intent { const _UngroupIntent(); }
class _ZoomInIntent extends Intent { const _ZoomInIntent(); }
class _ZoomOutIntent extends Intent { const _ZoomOutIntent(); }
class _ZoomResetIntent extends Intent { const _ZoomResetIntent(); }

class _MenuBar extends StatelessWidget {
  final VoidCallback onNew, onOpen, onSave, onSaveAs, onExportSvg;
  final DocController doc;
  const _MenuBar({required this.onNew, required this.onOpen, required this.onSave, required this.onSaveAs, required this.onExportSvg, required this.doc});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(color: Color(0xFF1E1E1E), border: Border(bottom: BorderSide(color: Color(0xFF3A3A3A)))),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(children: [
        _menu(context, 'File', [
          _MenuItem('New', 'Ctrl+N', onNew),
          _MenuItem('Open…', 'Ctrl+O', onOpen),
          _MenuItem('Save', 'Ctrl+S', onSave),
          _MenuItem('Save As…', 'Ctrl+Shift+S', onSaveAs),
          _MenuItem('Export SVG…', '', onExportSvg),
        ]),
        _menu(context, 'Edit', [
          _MenuItem('Undo', 'Ctrl+Z', () => doc.undo()),
          _MenuItem('Redo', 'Ctrl+Shift+Z', () => doc.redo()),
          _MenuItem('Duplicate', 'Ctrl+D', () => doc.duplicateSelected()),
          _MenuItem('Delete', 'Del', () => doc.deleteSelected()),
          _MenuItem('Group Selection', 'Ctrl+G', () => doc.groupSelected()),
          _MenuItem('Ungroup', 'Ctrl+Shift+G', () => doc.ungroupSelected()),
          _MenuItem('Frame Selection', '', () => doc.frameSelected()),
        ]),
        _menu(context, 'View', [
          _MenuItem('Zoom In', 'Ctrl+=', () => doc.setZoom(doc.zoom * 1.2)),
          _MenuItem('Zoom Out', 'Ctrl+-', () => doc.setZoom(doc.zoom / 1.2)),
          _MenuItem('Reset Zoom', 'Ctrl+0', () => doc.resetView()),
        ]),
        _menu(context, 'Mode', [
          _MenuItem('Local (offline)', '', () => doc.setMode(AppMode.local)),
          _MenuItem('Cloud Sync',     '', () => doc.setMode(AppMode.cloud)),
        ]),
        _menu(context, 'Help', [
          _MenuItem('About Fredes', '', () => showAboutDialog(
                context: context,
                applicationName: 'Fredes',
                applicationVersion: '0.1.0',
                applicationLegalese: 'Free & open-source design tool. MIT licensed.',
              )),
        ]),
      ]),
    );
  }

  Widget _menu(BuildContext ctx, String label, List<_MenuItem> items) {
    return PopupMenuButton<int>(
      tooltip: label,
      offset: const Offset(0, 28),
      color: const Color(0xFF252525),
      itemBuilder: (_) => [
        for (var i = 0; i < items.length; i++)
          PopupMenuItem<int>(value: i, height: 30, child: Row(children: [
            Expanded(child: Text(items[i].label, style: const TextStyle(color: Colors.white, fontSize: 12))),
            if (items[i].shortcut.isNotEmpty)
              Text(items[i].shortcut, style: const TextStyle(color: Colors.white38, fontSize: 11)),
          ])),
      ],
      onSelected: (i) => items[i].onTap(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
      ),
    );
  }
}

class _MenuItem {
  final String label;
  final String shortcut;
  final VoidCallback onTap;
  _MenuItem(this.label, this.shortcut, this.onTap);
}

class _StatusBar extends StatelessWidget {
  final DocController doc;
  const _StatusBar({required this.doc});
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: doc,
      builder: (_, __) => Container(
        height: 22,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: const BoxDecoration(color: Color(0xFF252525), border: Border(top: BorderSide(color: Color(0xFF3A3A3A)))),
        child: Row(children: [
          Text('Tool: ${doc.tool.name}', style: const TextStyle(color: Colors.white54, fontSize: 11)),
          const SizedBox(width: 16),
          Text('Selection: ${doc.selection.length}', style: const TextStyle(color: Colors.white54, fontSize: 11)),
          const SizedBox(width: 16),
          Expanded(child: Text(doc.filePath ?? 'Unsaved', style: const TextStyle(color: Colors.white54, fontSize: 11), overflow: TextOverflow.ellipsis)),
          Text(doc.dirty ? 'Modified' : 'Clean', style: const TextStyle(color: Colors.white54, fontSize: 11)),
        ]),
      ),
    );
  }
}
