# `.fredes` File Format Specification — v1.0

A `.fredes` file is a UTF-8 encoded **JSON** document. It is intentionally
human-readable, diff-friendly, and free of binary chunks. Any tool can read
or write it. The spec is dedicated to the public domain (CC0).

## Top-level

```json
{
  "format": "fredes",
  "version": "1.0",
  "meta": {
    "name": "My Design",
    "createdAt": "2026-04-14T10:00:00.000Z",
    "updatedAt": "2026-04-14T10:00:00.000Z",
    "app": "Fredes 0.1.0 (Flutter)"
  },
  "pages": [Page, ...]
}
```

Any unknown field at any level **must be preserved on round-trip**. This
keeps the format extensible by third-party tools.

## `Page`

```json
{
  "id": "uuid",
  "name": "Page 1",
  "background": "#ffffff",
  "nodes": [Node, ...]
}
```

## `Node` (common fields)

```json
{
  "id": "uuid",
  "type": "frame" | "group" | "rect" | "ellipse" | "text" | "line" | "path",
  "name": "Layer name",
  "x": 0, "y": 0,
  "rotation": 0,
  "opacity": 1,
  "visible": true,
  "locked": false
}
```

### `frame` (container)
Adds: `width`, `height`, `fill`, `stroke`, `strokeWidth`, `cornerRadius`,
`clipContent`, `children: [Node, ...]`. Frames are the primary artboards —
like Figma frames. Children are positioned in the frame's local coordinate
space. If `clipContent` is true, content outside the frame's rect is clipped
(both at render time and in SVG export).

### `group` (container)
Adds: `children: [Node, ...]`. No visual rendering; used purely to tie
related layers together. Group's `x`/`y` offsets its children.

### `rect`
Adds: `width`, `height`, `fill`, `stroke`, `strokeWidth`, `cornerRadius`.

### `ellipse`
Adds: `width`, `height`, `fill`, `stroke`, `strokeWidth`. Drawn inscribed
into the bounding box (cx = x + w/2, cy = y + h/2, rx = w/2, ry = h/2).

### `text`
Adds: `text`, `fontSize`, `fontFamily`, `fontWeight`, `fill`, `width`,
`height`, `align` (`"left" | "center" | "right"`).

### `line`
Adds: `points: [x1, y1, x2, y2]`, `stroke`, `strokeWidth`. Note `x` and `y`
are typically `0` for lines; positions live entirely in `points`.

### `path`
Adds: `points: [x1, y1, x2, y2, ...]` (flat array), `stroke`, `strokeWidth`,
`fill`, `closed`. Renders as a polyline; if `closed`, the last vertex
connects to the first.

## Coordinate system

Origin at top-left, +X right, +Y down. Rotation in degrees, clockwise around
the node's local origin (`(x + width/2, y + height/2)` for box nodes,
`(x, y)` for line/path).

## Color encoding

`fill` and `stroke` are 6-digit hex strings: `"#RRGGBB"`. Alpha is
expressed via the node's `opacity` (0..1). Rationale: human-readable, no
endianness ambiguity.

## Versioning

`version` is bumped only on breaking changes. Forward-compatible additions
(new optional fields, new node types) are added without a version bump but
**must be ignored** by older readers (preserve via the unknown-field rule).

## Cloud sync wire format

When connected via Cloud Sync mode (Mode 2), Fredes sends and receives:

```json
{ "type": "hello", "room": "<room-id>" }
{ "type": "snapshot", "doc": <FredesDoc> }
```

The "snapshot" message wraps the entire document. Convergence is
last-write-wins. Servers are expected to broadcast received messages to
all other peers in the same room.

## License of this spec

CC0 — public domain. Build whatever you want on top of it.
