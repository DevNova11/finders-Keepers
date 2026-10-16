import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Tiny crash-safe JSON file store used for form drafts and the outbox.
class LocalStore {
  LocalStore._();

  static Future<Directory> dir(String name) async {
    final base = await getApplicationDocumentsDirectory();
    final d = Directory('${base.path}/$name');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  static Future<dynamic> read(String folder, String key) async {
    final f = File('${(await dir(folder)).path}/$key.json');
    if (!await f.exists()) return null;
    try {
      return jsonDecode(await f.readAsString());
    } catch (_) {
      return null;
    }
  }

  static Future<void> write(String folder, String key, Object? value) async {
    final d = await dir(folder);
    final tmp = File('${d.path}/$key.json.tmp');
    await tmp.writeAsString(
      jsonEncode(
        value,
        toEncodable: (o) => o is DateTime ? o.toIso8601String() : o.toString(),
      ),
      flush: true,
    );
    await tmp.rename('${d.path}/$key.json');
  }

  static Future<void> delete(String folder, String key) async {
    final f = File('${(await dir(folder)).path}/$key.json');
    if (await f.exists()) await f.delete();
  }
}
