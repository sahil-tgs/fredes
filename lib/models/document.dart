import 'package:uuid/uuid.dart';
import 'nodes.dart';

const _uuid = Uuid();

class FredesPage {
  String id;
  String name;
  String background; // hex
  List<FredesNode> nodes;

  FredesPage({String? id, this.name = 'Page 1', this.background = '#2A2A2A', List<FredesNode>? nodes})
      : id = id ?? _uuid.v4(),
        nodes = nodes ?? [];

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'background': background,
        'nodes': nodes.map((n) => n.toJson()).toList(),
      };

  factory FredesPage.fromJson(Map<String, dynamic> j) => FredesPage(
        id: j['id'] as String,
        name: j['name'] as String? ?? 'Page',
        background: j['background'] as String? ?? '#2A2A2A',
        nodes: ((j['nodes'] as List?) ?? const [])
            .map((e) => FredesNode.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class FredesDoc {
  String name;
  DateTime createdAt;
  DateTime updatedAt;
  String app;
  List<FredesPage> pages;

  FredesDoc({
    this.name = 'Untitled',
    DateTime? createdAt,
    DateTime? updatedAt,
    this.app = 'Fredes 0.1.0 (Flutter)',
    List<FredesPage>? pages,
  })  : createdAt = createdAt ?? DateTime.now().toUtc(),
        updatedAt = updatedAt ?? DateTime.now().toUtc(),
        pages = pages ?? [FredesPage()];

  Map<String, dynamic> toJson() => {
        'format': 'fredes',
        'version': '1.0',
        'meta': {
          'name': name,
          'createdAt': createdAt.toIso8601String(),
          'updatedAt': updatedAt.toIso8601String(),
          'app': app,
        },
        'pages': pages.map((p) => p.toJson()).toList(),
      };

  factory FredesDoc.fromJson(Map<String, dynamic> j) {
    // Accept the legacy 'freegma' discriminator so .freegma files authored
    // before the rename still open. New files are always written as 'fredes'.
    final fmt = j['format'];
    if (fmt != 'fredes' && fmt != 'freegma') {
      throw StateError('Not a Fredes document (format=$fmt).');
    }
    final meta = (j['meta'] as Map?)?.cast<String, dynamic>() ?? const {};
    return FredesDoc(
      name: meta['name'] as String? ?? 'Untitled',
      createdAt: DateTime.tryParse(meta['createdAt'] as String? ?? '') ?? DateTime.now().toUtc(),
      updatedAt: DateTime.tryParse(meta['updatedAt'] as String? ?? '') ?? DateTime.now().toUtc(),
      app: meta['app'] as String? ?? 'unknown',
      pages: ((j['pages'] as List?) ?? const [])
          .map((e) => FredesPage.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

enum Tool { select, hand, frame, rect, ellipse, line, pen, text }

enum AppMode { local, cloud }
