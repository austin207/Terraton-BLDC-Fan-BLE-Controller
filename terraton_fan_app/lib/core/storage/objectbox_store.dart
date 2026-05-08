// lib/core/storage/objectbox_store.dart
import 'package:objectbox/objectbox.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:terraton_fan_app/objectbox.g.dart' as ob;

Store? _store;

Future<Store> initObjectBox() async {
  if (_store != null) return _store!;
  final dir = await getApplicationDocumentsDirectory();
  _store = await ob.openStore(directory: p.join(dir.path, 'terraton-ob'));
  return _store!;
}

Store get store {
  if (_store == null) {
    throw StateError('Call initObjectBox() before accessing store.');
  }
  return _store!;
}
