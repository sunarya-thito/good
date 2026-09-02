/// A fixture project's dependency graph, written the way a `pub get` leaves
/// one.
///
/// `enginePackageOf` decides which package the generated files import by
/// reading each direct dependency's own pubspec, and it finds those pubspecs
/// through `.dart_tool/package_config.json` (#309). A fixture whose pubspec
/// names a dependency and whose package config does not resolve it is an
/// unresolved project, and the answer there is the kernel - so a test about
/// which renderer wins has to hand the generator a graph to walk.
library;

import 'dart:io';

/// Writes a stub package under `<dir>/.packages/<name>` for each entry in
/// [packages] and points [dir]'s package config at all of them.
///
/// The value of an entry is that package's own `dependencies:`. That is the
/// whole of what the engine test reads out of a package, so a stub with a
/// pubspec and an empty `lib/` stands in for a real one: `goo2d: ['good']` is
/// a renderer, and `google_fonts: ['flutter']` is not.
///
/// [at] names packages that resolve to a directory that already exists,
/// rather than to a stub written here. That is a `path:` dependency after a
/// `pub get`, and the generated bundle is the one that needs it: what
/// `enginePackageOf` asks of a candidate is whether its directory carries the
/// marker file, and no stub carries one.
void resolvePackages(
  Directory dir,
  Map<String, List<String>> packages, {
  Map<String, Directory> at = const <String, Directory>{},
}) {
  final entries = <String>[];
  at.forEach((name, root) {
    entries.add(
      '    { "name": "$name", "rootUri": "${root.absolute.uri}", '
      '"packageUri": "lib/" }',
    );
  });
  packages.forEach((name, dependencies) {
    final root = Directory('${dir.path}/.packages/$name');
    Directory('${root.path}/lib').createSync(recursive: true);
    File('${root.path}/pubspec.yaml').writeAsStringSync(
      'name: $name\n'
      'dependencies:\n'
      '${dependencies.map((d) => '  $d: any\n').join()}',
    );
    entries.add(
      '    { "name": "$name", "rootUri": "../.packages/$name", '
      '"packageUri": "lib/" }',
    );
  });
  File('${dir.path}/.dart_tool/package_config.json')
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(
      '{\n'
      '  "configVersion": 2,\n'
      '  "packages": [\n'
      '${entries.join(',\n')}\n'
      '  ]\n'
      '}\n',
    );
}
