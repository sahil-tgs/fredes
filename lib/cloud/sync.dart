import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/document.dart';
import '../state/doc_controller.dart';

/// Cloud sync (Mode 2).
///
/// We use a tiny "snapshot broadcast" protocol over a plain WebSocket so the
/// server is just `bunx websocketd` or any echo/broadcast server. The protocol:
///
///   {"type":"snapshot","doc":<FredesDoc.toJson()>}
///   {"type":"hello","room":"<room>"}
///
/// Last-write-wins. This intentionally trades CRDT correctness for simplicity
/// — Yjs has no production Dart port. The wire format is documented in
/// FORMAT.md so any tool can implement a sync server.
class CloudSync {
  final DocController doc;
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _sub;
  Timer? _debounce;
  String? _lastSent;
  bool _suppress = false;

  CloudSync(this.doc);

  Future<void> connect(String url, {String room = 'fredes-default'}) async {
    await disconnect();
    try {
      final ch = WebSocketChannel.connect(Uri.parse(url));
      _channel = ch;
      _sub = ch.stream.listen(_onMessage, onDone: _onClosed, onError: (_) => _onClosed());
      ch.sink.add(jsonEncode({'type': 'hello', 'room': room}));
      doc.setCloudConnected(true);
      doc.addListener(_onLocalChange);
      // Push initial snapshot so peers can hydrate
      _send(force: true);
    } catch (_) {
      doc.setCloudConnected(false);
    }
  }

  Future<void> disconnect() async {
    doc.removeListener(_onLocalChange);
    _debounce?.cancel();
    _debounce = null;
    await _sub?.cancel();
    _sub = null;
    await _channel?.sink.close();
    _channel = null;
    _lastSent = null;
    doc.setCloudConnected(false);
  }

  void _onLocalChange() {
    if (_suppress) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 150), _send);
  }

  void _send({bool force = false}) {
    final ch = _channel;
    if (ch == null) return;
    final json = jsonEncode(doc.doc.toJson());
    if (!force && json == _lastSent) return;
    _lastSent = json;
    ch.sink.add(jsonEncode({'type': 'snapshot', 'doc': jsonDecode(json)}));
  }

  void _onMessage(dynamic raw) {
    try {
      final s = raw is String ? raw : utf8.decode(raw as List<int>);
      final msg = jsonDecode(s) as Map<String, dynamic>;
      if (msg['type'] != 'snapshot') return;
      final remote = msg['doc'] as Map<String, dynamic>;
      final remoteJson = jsonEncode(remote);
      if (remoteJson == _lastSent) return;
      _suppress = true;
      try {
        doc.replaceDocFromRemote(FredesDoc.fromJson(remote));
        _lastSent = remoteJson;
      } finally {
        _suppress = false;
      }
    } catch (_) {/* ignore malformed */}
  }

  void _onClosed() {
    doc.setCloudConnected(false);
    _channel = null;
  }
}
