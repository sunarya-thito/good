import 'package:good_tool/src/accessor_emit.dart';
import 'package:good_tool/src/engine_packages.dart';
import 'package:good_tool/src/imports.dart';
import 'package:good_tool/src/scan.dart';

/// The files [scan] would have this repository carry.
///
/// One per package that can instantiate a class holding a declaration, and
/// none for a package that cannot. `good` is the interesting case of the
/// second kind: its six declarers are four abstract roots and two mixins, so
/// nothing is ever an instance of exactly one of them and there is nothing
/// for a table to be keyed by.
///
/// [known] is every package the scan read, where [packages] is the subset
/// being written into - the same split [componentBitsFiles] makes, and for the
/// same reason (#305).
List<GeneratedFile> declarationFiles(
  DeclarationCollectorScan scan,
  List<EnginePackage> packages,
  Imports imports, {
  List<EnginePackage>? known,
}) {
  final available = known ?? packages;
  final byName = <String, EnginePackage>{
    for (final package in packages) package.name: package,
  };
  final grouped = scan.byPackage;
  final files = <GeneratedFile>[];
  grouped.forEach((name, entries) {
    final package = byName[name];
    if (package == null) return;
    final table = imports.importFor(generatedDeclarationsType, package);
    final entry = imports.importFor(declarationCollectorType, package);
    if (table.problem != null || entry.problem != null) return;
    files.add(
      GeneratedFile(
        file: package.declarationsFile,
        contents: emitDeclarations(
          entries,
          package: package,
          tableImports: <String>{...table.imports, ...entry.imports},
          dependencies: <EnginePackage>[
            for (final candidate in available)
              if (candidate.name != package.name &&
                  package.dependencies.contains(candidate.name) &&
                  grouped.containsKey(candidate.name))
                candidate,
          ],
        ),
      ),
    );
  });
  files.sort((a, b) => a.file.path.compareTo(b.file.path));
  return files;
}

/// `lib/src/declarations.g.dart` - one collector per class this package can
/// instantiate, and the table they are looked up in.
///
/// # What a collector is for
///
/// A declaration is a field with its value on it and nothing open around it,
/// so the only record of what a class declared is the fields it holds. Reading
/// them back off needs a class's field list, which is the one thing a run
/// cannot obtain at all - AOT Dart has no reflection - so it is read out of
/// the source here and shipped inside the package. See `collectDeclarations`
/// in `good`.
///
/// # The order inside a collector is the row
///
/// Each list is in construction order: the class's own fields, then each mixin
/// application's with the last name in the `with` clause first, then the
/// superclass's, recursively. `ArchetypeDataDescriptor.declare` reserves in
/// the order it is handed, so this order *is* the field order of every row of
/// that archetype. It is what Dart's own initialisers did while the ambient
/// declaration window still collected them, which is why the layout does not
/// move now that nothing runs at a declaration.
String emitDeclarations(
  List<DeclarationCollectorEntry> entries, {
  required EnginePackage package,
  required Set<String> tableImports,
  required List<EnginePackage> dependencies,
}) {
  final imports =
      <String>{
        ...tableImports,
        for (final entry in entries) ...entry.imports,
        for (final dependency in dependencies)
          'package:${dependency.name}/${dependency.name}.dart',
      }.toList()
        ..sort();

  final buffer = StringBuffer()
    ..writeln('// GENERATED - do not edit.')
    ..writeln('//')
    ..writeln('// Regenerate with `dart run good_tool` from')
    ..writeln('// packages/good_tool, and commit what changes.')
    ..writeln('// `dart run good_tool --check` is what CI runs; it fails if')
    ..writeln('// this file is not what the generator would write.')
    ..writeln('//')
    ..writeln('// One function per class this package can instantiate that')
    ..writeln('// declares anything. A declaration is a field holding its own')
    ..writeln('// value, with nothing open around it, so this is the only')
    ..writeln('// record of what a class declared - and a class\'s field list')
    ..writeln('// is the one thing a running program cannot ask for.')
    ..writeln('//')
    ..writeln('// The order inside each list is the order the fields would')
    ..writeln('// have been initialised in: the class\'s own, then each')
    ..writeln('// mixin\'s with the last name in the `with` clause first,')
    ..writeln('// then the superclass\'s. That order is the field order of')
    ..writeln('// every row of the archetype, so reordering a list here')
    ..writeln('// relays out the entities.')
    ..writeln('//')
    ..writeln('// A commented-out line is a declaration held by a private')
    ..writeln('// field. Dart privacy is per library and this is a different')
    ..writeln('// one, so nothing here can read it - it keeps its place so')
    ..writeln('// that what the row is missing, and where, is visible.')
    ..writeln();
  for (final import in imports) {
    buffer.writeln("import '$import';");
  }
  buffer.writeln();

  for (final entry in entries) {
    buffer.writeln(
      'List<$scannableFieldType> ${entry.functionName}(Object object) {',
    );
    buffer.writeln('  final owner = object as ${entry.type};');
    buffer.writeln('  return <$scannableFieldType>[');
    for (final field in entry.fields) {
      // A private one keeps its place, commented out. Written into the file
      // rather than only into a `--verbose` line: this is the file that lays
      // the row out, so a column missing from it is missing where somebody
      // reading a diff is looking, and it is missing from where it would
      // have been.
      buffer.writeln(
        field.isPrivate
            ? '    // ${field.owner}.${field.name}: private, unreachable.'
            : '    owner.${field.name},',
      );
    }
    buffer
      ..writeln('  ];')
      ..writeln('}')
      ..writeln();
  }

  buffer
    ..writeln(
      "/// Every class `package:${package.name}` can instantiate that holds a",
    )
    ..writeln('/// declaration, and how to read one.')
    ..writeln('///')
    ..writeln('/// Pass this to `Game.declarations` - together with the table')
    ..writeln('/// of every other engine package the game uses, and the one')
    ..writeln('/// generated for the game itself - so a registration can read')
    ..writeln('/// what a constructed object declared.');

  final opening =
      'const $generatedDeclarationsType ${package.declarationsName} = '
      '$generatedDeclarationsType(';
  final indent = opening.length <= 80 ? '' : '    ';
  if (opening.length <= 80) {
    buffer.writeln(opening);
  } else {
    buffer
      ..writeln(
        'const $generatedDeclarationsType ${package.declarationsName} =',
      )
      ..writeln('    $generatedDeclarationsType(');
  }
  buffer
    ..writeln("$indent  package: '${package.name}',")
    ..writeln('$indent  collectors: <$declarationCollectorType>[');
  for (final entry in entries) {
    buffer.writeln(
      '$indent    $declarationCollectorType(${entry.type}, '
      '${entry.functionName}),',
    );
  }
  buffer.writeln('$indent  ],');
  if (dependencies.isNotEmpty) {
    buffer.writeln('$indent  dependencies: <$generatedDeclarationsType>[');
    for (final dependency in dependencies) {
      buffer.writeln('$indent    ${dependency.declarationsName},');
    }
    buffer.writeln('$indent  ],');
  }
  buffer.writeln(opening.length <= 80 ? ');' : '    );');
  return buffer.toString();
}

/// Every package whose entry library does not export its generated table.
///
/// Hand-written and reported rather than inserted, exactly as the other two
/// exports are. It has to be reachable from outside the package: a game names
/// this table to `Game.declarations`, and a downstream package's table names
/// it as a dependency.
List<EnginePackage> missingDeclarationExports(
  List<GeneratedFile> files,
  List<EnginePackage> packages,
) {
  final generated = <String>{for (final file in files) file.file.path};
  return <EnginePackage>[
    for (final package in packages)
      if (generated.contains(package.declarationsFile.path) &&
          !_exports(package))
        package,
  ];
}

bool _exports(EnginePackage package) {
  final barrel = package.barrel;
  if (!barrel.existsSync()) return false;
  return barrel.readAsStringSync().contains(package.declarationsExport);
}
