import 'package:path/path.dart' as p;

import 'package:good_tool/src/accessor_emit.dart';
import 'package:good_tool/src/scan.dart';

/// A part beside every test or example library that declares a fixture.
///
/// One file per library and not one per package, because what makes this
/// reachable at all is being a `part of` the library it reads: a fixture is
/// private, and a private class can only be named from inside the library
/// that declares it.
List<GeneratedFile> fixtureFiles(FixtureScan scan) => <GeneratedFile>[
  for (final library in scan.libraries)
    GeneratedFile(
      file: library.generated,
      contents: emitFixtureDeclarations(library),
    ),
];

/// `<library>.g.dart` - one collector per fixture the library declares, the
/// table they are looked up in, and the call that installs it.
///
/// # Why it is a part and `declarations.g.dart` is not
///
/// A collector casts to the class it reads and the table names that class, so
/// both have to be able to spell it. A fixture is `_Level`, and Dart privacy
/// is per library - so the only file that can spell it is one inside that
/// library. A part is that, and it costs the library one directive.
///
/// The rule this does not break is that user code is never edited to add a
/// `part`. A test in this repository is not user code, and the alternative
/// for it was renaming several hundred fixtures.
///
/// # Why the install is a call and not something that happens
///
/// Dart runs nothing on import, so a table installs itself at no point. The
/// library's `main` calls [installName], which is one line at the top of a
/// function that is already there, and the failure when it is missing names
/// the class it could not collect.
///
/// A library with no `main` gets no installer, only the table. It is entered
/// by constructing a game, and a constructor cannot install anything the
/// game isolate will see: `Isolate.spawn` sends the game as a deep copy, so
/// nothing but `Game.declarations` - a getter, re-evaluated over there - is
/// read on the copy that boots. Such a library names [FixtureLibrary.tableName]
/// from its own getter, and an installer beside it would be a function nothing
/// can correctly call.
String emitFixtureDeclarations(FixtureLibrary library) {
  final buffer = StringBuffer()
    ..writeln('// GENERATED - do not edit.')
    ..writeln('//')
    ..writeln('// Regenerate with `dart run good_tool --tests` from')
    ..writeln('// packages/good_tool, and commit what changes.')
    ..writeln('// `dart run good_tool --tests --check` is what CI runs; it')
    ..writeln('// fails if this file is not what the generator would write.')
    ..writeln('//')
    ..writeln('// One function per fixture this library declares. It is a')
    ..writeln('// part of that library because a fixture is private, and a')
    ..writeln('// private class can only be named from inside the library')
    ..writeln('// that declares it.')
    ..writeln('//')
    ..writeln('// The order inside each list is the order the fields would')
    ..writeln('// have been initialised in, which is the field order of every')
    ..writeln('// row of that archetype.')
    ..writeln('//')
    ..writeln('// A commented-out line is a declaration a mixin from a')
    ..writeln("// package's lib/ holds privately. That is another library,")
    ..writeln('// so nothing here can read it - it keeps its place so that')
    ..writeln('// what the row is missing, and where, is visible.');
  if (library.collectors.any((collector) => collector.isGeneric)) {
    buffer
      ..writeln('//')
      ..writeln('// A generic fixture also gets an `is` test. Nothing at run')
      ..writeln('// time can take the type arguments off a `Type`, so the')
      ..writeln('// literal in the table below never equals an instance\'s')
      ..writeln('// `runtimeType` - the test is what matches the two.');
  }
  buffer
    ..writeln("part of '${p.basename(library.path)}';")
    ..writeln();

  for (final collector in library.collectors) {
    buffer.writeln(
      'List<$scannableFieldType> ${collector.functionName}(Object object) {',
    );
    buffer.writeln(
      collector.fields.any((field) => !field.isPrivate)
          ? '  final owner = object as ${collector.type};'
          : '  object as ${collector.type};',
    );
    if (collector.fields.isEmpty) {
      buffer
        ..writeln('  return const <$scannableFieldType>[];')
        ..writeln('}')
        ..writeln();
      continue;
    }
    buffer.writeln('  return <$scannableFieldType>[');
    for (final field in collector.fields) {
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

  for (final collector in library.collectors) {
    if (!collector.isGeneric) continue;
    // A generic class is keyed by nothing a lookup can present: the literal
    // in the table below is `_OneOff<EntityStruct>` and an instance's
    // `runtimeType` is `_OneOff<_Level>`, and a `Type` cannot have its
    // arguments taken off at run time. So the test the run cannot make is
    // written here instead. Bare, no type arguments, so it is true of every
    // instantiation.
    buffer
      ..writeln(
        '/// Whether an object is a ${collector.type}, whatever its type '
        'arguments are.',
      )
      ..writeln(
        'bool ${collector.matcherName}(Object object) => '
        'object is ${collector.type};',
      )
      ..writeln();
  }

  buffer
    ..writeln('/// Every fixture this library declares, and how to read one.')
    ..writeln('///');
  if (library.tables.length == 1 &&
      library.tables.single.name == library.package.name) {
    buffer
      ..writeln("/// It carries the package's own generated table as a")
      ..writeln(
        '/// dependency, so installing this installs the collectors for',
      )
      ..writeln('/// the engine classes a fixture is built on as well.');
  } else {
    // Two shapes, one sentence, because the old text said only the first
    // and the second is now reachable: `joints.dart` sits in `goo2d`, which
    // does have a table, and names `goo2d_physics_box2d`'s because that is
    // what it imports.
    buffer
      ..writeln('/// It carries the generated tables this library imports,')
      ..writeln('/// so installing this installs the collectors for the')
      ..writeln('/// engine classes a fixture is built on as well. Not this')
      ..writeln("/// package's own: either it has none, or one of these")
      ..writeln('/// already names it.');
  }
  buffer
    ..writeln(
      'const $generatedDeclarationsType ${library.tableName} =',
    )
    ..writeln('    $generatedDeclarationsType(')
    ..writeln("      package: '${library.tableKey}',")
    ..writeln('      collectors: <$declarationCollectorType>[');
  for (final collector in library.collectors) {
    if (!collector.isGeneric) {
      buffer.writeln(
        '        $declarationCollectorType(${collector.type}, '
        '${collector.functionName}),',
      );
      continue;
    }
    final line =
        '        $declarationCollectorType.generic(${collector.type}, '
        '${collector.functionName}, ${collector.matcherName}),';
    // Wrapped only when it has to be, the way the accessor emitter wraps a
    // setter. `dart format` is not run over a generated file.
    buffer.writeln(
      line.length <= 80
          ? line
          : '        $declarationCollectorType.generic(\n'
                '          ${collector.type},\n'
                '          ${collector.functionName},\n'
                '          ${collector.matcherName},\n'
                '        ),',
    );
  }
  buffer
    ..writeln('      ],')
    ..writeln('      dependencies: <$generatedDeclarationsType>[');
  for (final table in library.tables) {
    buffer.writeln('        ${table.declarationsName},');
  }
  buffer
    ..writeln('      ],')
    ..writeln('    );');
  // Only where something can call it - see the doc above.
  if (!library.hasMain) return buffer.toString();
  buffer
    ..writeln()
    ..writeln('/// Installs [${library.tableName}].')
    ..writeln('///')
    ..writeln("/// Called first thing in this library's `main`. Nothing runs")
    ..writeln('/// on import in Dart, so a table that is never installed is a')
    ..writeln('/// table nothing has - and the first registration says so by')
    ..writeln('/// naming the class it could not collect.')
    ..writeln('void $installName() => DeclarationRegistry.installGenerated(')
    ..writeln(
      '  const <$generatedDeclarationsType>[${library.tableName}],',
    )
    ..writeln(');');
  return buffer.toString();
}

/// What a fixture library with a `main` calls to install its table.
///
/// The same name in every one of them, so the line at the top of a `main`
/// reads identically wherever it is - and private, because a part shares the
/// library's privacy and nothing outside calls it.
const String installName = '_installDeclarations';

/// What a run stopping over a supertype it read no source for says.
///
/// [display] names files the way the caller names files, exactly as
/// `declarationRefusalMessage`'s does.
///
/// The packages are named last and once, rather than beside each line: a
/// narrow run over one package reports the same missing package for every
/// fixture built on it, and the thing to do about all of them is one `--dir`.
String unreachableSupertypeMessage(
  FixtureScan scan,
  String Function(String path) display,
) {
  final lines = StringBuffer()
    ..writeln('A fixture is built on a supertype this run read no source for:')
    ..writeln();
  for (final missing in scan.unreachable) {
    lines.writeln(
      '  ${display(missing.path)}: ${missing.type} is built on '
      '${missing.supertype}',
    );
  }
  final packages = <String>{
    for (final missing in scan.unreachable) ...missing.packages,
  }.toList()..sort();
  lines
    ..writeln()
    ..writeln(
      packages.isEmpty
          ? 'Nothing those libraries import went unread, so the name is '
                'declared in no package this run was pointed at and in none '
                'they reach. Check the spelling before widening the run.'
          : 'Those libraries import ${packages.join(', ')}, which no --dir '
                'named. A fixture reaches a package its own package does not '
                'depend on - the dependency runs the other way - so widening '
                'the run to what the targets depend on never gets there.',
    )
    ..writeln()
    ..writeln(
      'The list a collector hands back is the order every row of that '
      'archetype is laid out in, so a supertype the walk cannot follow is not '
      'a shorter answer to the same question - it is every column below it '
      'gone from the row, in a file that is committed and that the next '
      'narrow --check reads as current. Nothing is written.',
    );
  return lines.toString();
}

/// Every fixture library whose own file does not carry its `part` directive.
///
/// Hand-written and reported rather than inserted, exactly as the barrel
/// exports are. Without the directive the generated file is not compiled at
/// all, so the collectors exist on disk and not in the program.
List<FixtureLibrary> missingPartDirectives(List<FixtureLibrary> libraries) =>
    <FixtureLibrary>[
      for (final library in libraries)
        if (!_carriesPart(library)) library,
    ];

bool _carriesPart(FixtureLibrary library) {
  final file = library.file;
  if (!file.existsSync()) return false;
  return file.readAsStringSync().contains(library.partDirective);
}
