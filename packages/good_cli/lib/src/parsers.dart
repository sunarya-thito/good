import 'dart:io';

/// A file that must already exist.
///
/// Parsers turn one command-line token into a typed value, and are the only
/// thing that knows what a bad value *means*, so they throw [ArgumentError]
/// with a written-out message instead of returning null: the runner catches
/// it and shows the message as-is, so "File not found: ./nope" reaches the
/// user instead of a generic "invalid value for --input-dir".
File parseFile(String path) {
  final file = File(path);
  if (!file.existsSync()) {
    // Note: ArgumentError is caught and handled properly, to show the user a
    // nice error message.
    throw ArgumentError('File not found: $path');
  }
  return file;
}

/// A directory that must already exist.
///
/// Separate from [parseFile] because `File.existsSync` is false for a
/// directory: passing `./assets` to a `File` parser reports "File not found"
/// about something that is right there, which is the most confusing form the
/// error could take.
Directory parseDirectory(String path) {
  final directory = Directory(path);
  if (!directory.existsSync()) {
    throw ArgumentError('Directory not found: $path');
  }
  return directory;
}

/// A path that need not exist yet - an output location.
///
/// Nothing is created here. A parser runs while the command line is being
/// read, and creating a directory as a side effect of *parsing* would leave
/// one behind for a run that went on to fail validation.
Directory parseOutputDirectory(String path) => Directory(path);

/// One of the build flavors a project declares.
///
/// The same shape `good: flavors:` accepts, checked here so a name good could
/// never have written into `flutter: assets:` fails on the command line rather
/// than as a build that bundles nothing and says why three steps later.
String parseFlavorName(String name) {
  if (!RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(name)) {
    throw ArgumentError(
      '"$name" is not a flavor name. A flavor name is letters, digits, '
      'underscores and dashes - it is what `--flavor` takes, and what good '
      'writes into the generated asset entries.',
    );
  }
  return name;
}

/// A project name that can be a directory and a Dart package.
///
/// Both constraints at once, because the name becomes both: lowercase with
/// underscores, no leading digit. Checked here so `good create 2Fast` fails on
/// the command line instead of three steps into scaffolding.
String parsePackageName(String name) {
  if (!RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(name)) {
    throw ArgumentError(
      '"$name" is not a valid package name. Use lowercase letters, digits and '
      'underscores, starting with a letter - "my_game", not "MyGame" or '
      '"2fast".',
    );
  }
  return name;
}
