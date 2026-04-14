# Fredes

**Free, open-source, offline-first vector design tool — built in Flutter for native desktop performance.**

Like Figma, but the file lives on your disk, the app runs without an internet connection, and the source is yours. Native Skia rendering via Flutter — no Electron, no Chromium, no janky web view.

## Two operating modes

1. **Local (offline-first)** — every canvas is a `.fredes` file on your filesystem. Plain JSON, open spec ([FORMAT.md](./FORMAT.md)), diff-friendly, version-controllable. No account, no telemetry, no lock-in.
2. **Cloud sync** — opt-in real-time multi-user collaboration over plain WebSocket. Server-agnostic — any broadcast WS works.

## Features (v0.1)

- Vector tools: select, pan, rectangle, ellipse, line, freehand pen, text
- Inline text editing
- Multi-select, drag-to-move, color picker
- Layers panel: reorder, hide, lock, rename
- Properties panel: position, size, rotation, opacity, fill, stroke, corner radius, font
- Page background color
- Undo/redo (100 steps)
- Open/save `.fredes` files
- Export to **SVG** (open standard)
- Two modes: Local and Cloud Sync
- Keyboard shortcuts (V/H/R/O/L/P/T, Ctrl+Z/Y/D/S/O/N, Delete, Ctrl+=/-/0)
- Native menu bar (File / Edit / View / Mode / Help)

## Build

See [HANDOFF.md](./HANDOFF.md) for the complete Windows build recipe. TL;DR:

```powershell
flutter pub get
flutter build windows --release
# Output: build\windows\x64\runner\Release\fredes.exe
```

For Linux:

```bash
sudo apt install clang cmake ninja-build libgtk-3-dev
flutter build linux --release
# Output: build/linux/x64/release/bundle/fredes
```

## File format

Plain UTF-8 JSON. See [FORMAT.md](./FORMAT.md) — the spec is CC0 (public domain). Any tool can read or write it.

## Tech stack

- **Flutter 3.24+** with Material 3 dark theme
- **dart:ui CustomPainter** for canvas (GPU-accelerated Skia)
- **ChangeNotifier** for state (no Riverpod/Bloc — keeps deps minimal)
- **`file_selector`** for native file dialogs
- **`web_socket_channel`** for cloud sync transport
- **`uuid`** for node IDs

## License

MIT.
