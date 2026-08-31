import 'dart:io';

import 'package:good_tool/src/accessor_scan.dart';
import 'package:good_tool/src/engine_packages.dart';
import 'package:meta/meta.dart';

/// One file the tool would write, and what it would hold.
@immutable
class GeneratedFile {
  const GeneratedFile({required this.file, required this.contents});

  final File file;
  final String contents;

  /// Whether what is on disk already matches [contents].
  ///
  /// Read as bytes and compared as text, so a checkout that normalised line
  /// endings does not read as a stale file. Git is configured to write CRLF in
  /// this repository's working copies, and `--check` comparing raw bytes would
  /// then fail on every file on Windows and pass on Linux.
  bool get isCurrent =>
      file.existsSync() &&
      _normalise(file.readAsStringSync()) == _normalise(contents);

  static String _normalise(String text) => text.replaceAll('\r\n', '\n');
}

/// The files [scan] would have this repository carry.
///
/// One per package that has any component with a column, and none for a package
/// that has none - a file holding no extension would be an import in a barrel
/// pointing at nothing.
List<GeneratedFile> accessorFiles(
  AccessorScan scan,
  List<EnginePackage> packages,
) {
  final byName = <String, EnginePackage>{
    for (final package in packages) package.name: package,
  };
  final files = <GeneratedFile>[];
  scan.byPackage.forEach((name, extensions) {
    final package = byName[name];
    if (package == null) return;
    files.add(
      GeneratedFile(
        file: package.accessorFile,
        contents: emitAccessors(extensions, package: name),
      ),
    );
  });
  files.sort((a, b) => a.file.path.compareTo(b.file.path));
  return files;
}

/// `lib/src/accessors.g.dart` - a property per column, on the accessor.
///
/// Committed, so this is read in a diff by people rather than only by a
/// compiler. Everything about the shape follows from that: the imports are
/// sorted, the extensions are ordered by where their component is declared, and
/// each property keeps the order its column was declared in. A regeneration
/// that reordered nothing semantically would still be noise in a review.
String emitAccessors(
  List<AccessorExtension> extensions, {
  required String package,
}) {
  final imports = <String>{
    for (final extension in extensions) ...extension.imports,
  }.toList()..sort();

  final buffer = StringBuffer()
    ..writeln('// GENERATED - do not edit.')
    ..writeln('//')
    ..writeln('// Regenerate with `dart run good_tool` from')
    ..writeln('// packages/good_tool, and commit what changes.')
    ..writeln('// `dart run good_tool --check` is what CI runs; it fails if')
    ..writeln('// this file is not what the generator would write. To change a')
    ..writeln('// property, change the column it is generated from.')
    ..writeln('//')
    ..writeln('// A property here is for code touching **one** entity:')
    ..writeln('//')
    ..writeln('//   entity<Transform2D>().offsetX = 10.0;')
    ..writeln('//')
    ..writeln('// A system walking many entities resolves the component once')
    ..writeln('// per group and indexes the column instead. `component`')
    ..writeln('// re-resolves on every access, so three property lines are')
    ..writeln('// three archetype lookups - noise for one entity, and the')
    ..writeln('// thing to avoid inside a loop over thousands. See *A property')
    ..writeln('// is for one entity, a column is for many* in the design rules.')
    ..writeln('//')
    ..writeln('// Every read below is of the published snapshot, the same as')
    ..writeln('// `column[entity]`. Nothing here answers "what did I write')
    ..writeln('// earlier in this tick" - that is `column.readPending(entity)`,')
    ..writeln('// and it is reached by indexing the column.')
    ..writeln();
  for (final import in imports) {
    buffer.writeln("import '$import';");
  }
  buffer.writeln();

  for (var i = 0; i < extensions.length; i++) {
    final extension = extensions[i];
    if (i > 0) buffer.writeln();
    buffer
      ..writeln(
        '/// ${extension.component}\'s columns, one property each - for code',
      )
      ..writeln('/// touching **one** entity.')
      ..writeln('///')
      ..writeln('/// A system walking many resolves the component once per')
      ..writeln('/// group and indexes the column instead. Every read here is')
      ..writeln('/// of the published snapshot.')
      ..writeln(
        'extension ${extension.extensionName} '
        'on Accessor<${extension.component}> {',
      );
    for (var j = 0; j < extension.properties.length; j++) {
      final property = extension.properties[j];
      if (j > 0) buffer.writeln();
      final setter =
          '  set ${property.name}(${property.type} newValue) => '
          'component.${property.column}[entity] = newValue;';
      buffer
        ..writeln(
          '  /// `${property.column}` on this entity, from the published '
          'snapshot.',
        )
        ..writeln('  ///')
        ..writeln('  /// One entity. A system walking many indexes')
        ..writeln('  /// `component.${property.column}` instead.')
        ..writeln(
          '  ${property.type} get ${property.name} => '
          'component.${property.column}[entity];',
        )
        // Wrapped only when it has to be. `dart format` is not run over a
        // generated file, so the width is this emitter's to keep.
        ..writeln(
          setter.length <= 80
              ? setter
              : '  set ${property.name}(${property.type} newValue) =>\n'
                    '      component.${property.column}[entity] = newValue;',
        );
    }
    buffer.writeln('}');
  }
  return buffer.toString();
}

/// Every package whose entry library does not export its generated file.
///
/// The `export` line is hand-written, once, and reviewed like any other line of
/// the package's public surface - `goo2d_ffi_box2d` does the same for
/// `box2d.g.dart`. A generator editing a hand-written barrel is a generator
/// that can lose somebody's edit.
///
/// The cost of that choice is that a new engine package could get a generated
/// file nothing exports, and every property in it would be unreachable with
/// nothing failing. So it is reported here and `--check` fails on it, which is
/// the same treatment a stale file gets.
List<EnginePackage> missingExports(
  List<GeneratedFile> files,
  List<EnginePackage> packages,
) {
  final generated = <String>{for (final file in files) file.file.path};
  return <EnginePackage>[
    for (final package in packages)
      if (generated.contains(package.accessorFile.path) &&
          !_exports(package)) package,
  ];
}

bool _exports(EnginePackage package) {
  final barrel = package.barrel;
  if (!barrel.existsSync()) return false;
  return barrel.readAsStringSync().contains(package.accessorExport);
}
