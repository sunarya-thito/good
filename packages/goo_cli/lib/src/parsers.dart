import 'dart:io';

File parseFile(String path) {
  final file = File(path);
  if (!file.existsSync()) {
    // Note: ArgumentError is caught and handled properly, to show the user a nice error message.
    throw ArgumentError('File not found: $path');
  }
  return file;
}
