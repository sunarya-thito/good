// Beside the scan that feeds it, for the reason `declaration_collectors.dart`
// gives: this file is written for each engine package by the repository's own
// generator and for a user's project by `good generate`, and one artifact
// takes one emitter.

import 'package:good_cli/src/generate/declaration_collectors.dart';
import 'package:good_cli/src/generate/engine_package.dart';
import 'package:good_cli/src/generate/imports.dart';

/// The files [scan] would have this repository carry.
///
/// One per package that can instantiate a scanned class, and none for a
/// package that cannot - a package whose scanned types are all abstract roots
/// and mixins has nothing that is ever a `runtimeType`, so there is nothing
/// for a table to be keyed by. What decides an entry is that the class can be
/// instantiated, not that it declares anything: see [scanDeclarationCollectors]
/// for why an empty entry has to be written.
///
/// [known] is every package the scan read, where [packages] is the subset
/// being written into - the same split the component-bit emitter makes, and
/// for the same reason (#305). It is what lets a project's table name
/// `goo2dDeclarations` as a dependency without generating into a copy of
/// `goo2d` in a pub cache.
List<GeneratedFile> declarationFiles(
  DeclarationCollectorScan scan,
  List<EnginePackage> packages,
  Imports imports, {
  required List<String> regenerate,
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
          regenerate: regenerate,
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
/// [regenerate] is the paragraph the banner opens with, one entry per line,
/// without the `// ` - what to run to write this file again.
///
/// Passed in rather than written here because two tools write this file and
/// the sentence differs: the repository's own generator is run from
/// `packages/good_tool` and its output is committed, while a project's is
/// written by `good generate` and rewritten by every build. The rest of the
/// banner is about the file's contents and is the same either way.
String emitDeclarations(
  List<DeclarationCollectorEntry> entries, {
  required EnginePackage package,
  required Set<String> tableImports,
  required List<EnginePackage> dependencies,
  required List<String> regenerate,
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
    ..writeln('//');
  for (final line in regenerate) {
    buffer.writeln('// $line');
  }
  buffer
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
    ..writeln('// that what the row is missing, and where, is visible.');
  if (entries.any((entry) => entry.isGeneric)) {
    buffer
      ..writeln('//')
      ..writeln('// A generic class also gets an `is` test. Nothing at run')
      ..writeln('// time can take the type arguments off a `Type`, so the')
      ..writeln('// literal in the table below never equals an instance\'s')
      ..writeln('// `runtimeType` - the test is what matches the two.');
  }
  buffer.writeln();
  for (final import in imports) {
    buffer.writeln("import '$import';");
  }
  buffer.writeln();

  for (final entry in entries) {
    buffer.writeln(
      'List<$scannableFieldType> ${entry.functionName}(Object object) {',
    );
    // `final owner =` only where something reads it. A class that declares
    // nothing, and one whose declarations are all private, both leave every
    // line below a comment - and a bound name nothing reads does not compile
    // clean. The cast stays either way: it is what makes handing this
    // function the wrong object an error rather than an empty answer.
    buffer.writeln(
      entry.fields.any((field) => !field.isPrivate)
          ? '  final owner = object as ${entry.type};'
          : '  object as ${entry.type};',
    );
    if (entry.fields.isEmpty) {
      // Nothing to lay out and nothing to comment: a const empty list rather
      // than an empty literal spread over two lines.
      buffer
        ..writeln('  return const <$scannableFieldType>[];')
        ..writeln('}')
        ..writeln();
      continue;
    }
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

  for (final entry in entries) {
    if (!entry.isGeneric) continue;
    // A generic class is keyed by nothing a lookup can present: the literal
    // below is `Foo<Bound>` and an instance's `runtimeType` is `Foo<Enemy>`,
    // and a `Type` cannot have its arguments taken off at run time. So the
    // test the run cannot make is written here instead. Bare, no type
    // arguments, so it is true of every instantiation.
    buffer
      ..writeln(
        '/// Whether an object is a ${entry.type}, whatever its type '
        'arguments are.',
      )
      ..writeln(
        'bool ${entry.matcherName}(Object object) => '
        'object is ${entry.type};',
      )
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
    if (!entry.isGeneric) {
      buffer.writeln(
        '$indent    $declarationCollectorType(${entry.type}, '
        '${entry.functionName}),',
      );
      continue;
    }
    final line =
        '$indent    $declarationCollectorType.generic(${entry.type}, '
        '${entry.functionName}, ${entry.matcherName}),';
    // Wrapped only when it has to be, the way the accessor emitter wraps a
    // setter. `dart format` is not run over a generated file.
    buffer.writeln(
      line.length <= 80
          ? line
          : '$indent    $declarationCollectorType.generic(\n'
                '$indent      ${entry.type},\n'
                '$indent      ${entry.functionName},\n'
                '$indent      ${entry.matcherName},\n'
                '$indent    ),',
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
