import 'dart:convert';
import 'dart:io';
import '../models/document.dart';

String serialize(FredesDoc d) {
  d.updatedAt = DateTime.now().toUtc();
  return const JsonEncoder.withIndent('  ').convert(d.toJson());
}

FredesDoc parse(String text) {
  final obj = jsonDecode(text);
  if (obj is! Map<String, dynamic>) {
    throw const FormatException('Top-level JSON must be an object.');
  }
  return FredesDoc.fromJson(obj);
}

Future<FredesDoc> readFile(String path) async {
  final s = await File(path).readAsString();
  return parse(s);
}

Future<void> writeFile(String path, FredesDoc d) async {
  await File(path).writeAsString(serialize(d));
}
