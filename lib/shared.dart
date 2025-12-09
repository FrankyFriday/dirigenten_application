// lib/shared.dart
import 'dart:io';
import 'package:path_provider/path_provider.dart';

class ReceivedPiece {
  final String name;
  final String path;
  final DateTime receivedAt;
  ReceivedPiece({required this.name, required this.path, required this.receivedAt});
}

Future<Directory> appDocumentsDir() async => await getApplicationDocumentsDirectory();

Future<File> saveBytesAsFile(List<int> bytes, String filename) async {
  final dir = await appDocumentsDir();
  final file = File('${dir.path}/$filename');
  await file.writeAsBytes(bytes, flush: true);
  return file;
}
