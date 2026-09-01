import 'package:good_tool/src/accessor_emit.dart';
import 'package:good_tool/src/component_scan.dart';
import 'package:good_tool/src/engine_packages.dart';
import 'package:good_tool/src/imports.dart';

/// The name of the type every generated table is an instance of.
const String generatedComponentBitsType = 'GeneratedComponentBits';

/// The files [scan] would have this repository carry.
///
/// One per package that registers a component type, and none for a package
/// that registers none.
List<GeneratedFile> componentBitsFiles(
  ComponentBitScan scan,
  List<EnginePackage> packages,
  Imports imports,
) {
  final byName = <String, EnginePackage>{
    for (final package in packages) package.name: package,
  };
  final grouped = scan.byPackage;
  final files = <GeneratedFile>[];
  grouped.forEach((name, bits) {
    final package = byName[name];
    if (package == null) return;
    final resolved = imports.importFor(generatedComponentBitsType, package);
    if (resolved.problem != null) return;
    files.add(
      GeneratedFile(
        file: package.componentBitsFile,
        contents: emitComponentBits(
          bits,
          package: package,
          bitsImport: resolved.imports.single,
          dependencies: <EnginePackage>[
            for (final candidate in packages)
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

/// `lib/src/component_bits.g.dart` - this package's component types, in the
/// order their bits are assigned.
///
/// Committed and read in a diff, so the order is pinned and the imports are
/// sorted, for the reason `emitAccessors` gives.
///
/// # Why it holds an order and not an index
///
/// A table that wrote `Transform2D: 12` would fix that 12 against the whole
/// repository, and a game depending on `goo2d` but not `goo3d` would then
/// install a table full of holes - bits nothing can ever use, out of
/// sixty-four. Holding the order instead lets
/// `ComponentTypeRegistry.installGenerated` number whatever set of tables it is
/// actually given, contiguously from zero, and a package's own file stops
/// changing every time some other package gains a component.
String emitComponentBits(
  List<ComponentBit> bits, {
  required EnginePackage package,
  required String bitsImport,
  required List<EnginePackage> dependencies,
}) {
  final imports =
      <String>{
        bitsImport,
        for (final bit in bits) bit.import,
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
    ..writeln('// The order below is the bit order. A game names this table')
    ..writeln('// to `Game.componentBits`, and every type in it is then')
    ..writeln('// numbered before the game declares anything of its own, so')
    ..writeln('// the bits are the same on every machine and a query')
    ..writeln('// signature means the same thing to a peer that receives it.')
    ..writeln('//')
    ..writeln('// A component this tool never read - one in a game\'s own')
    ..writeln('// lib/, or in a package outside this repository - is not here')
    ..writeln('// and does not need to be. It takes the next free bit when it')
    ..writeln('// is first seen, after all of these, so nothing below ever')
    ..writeln('// renumbers because of it.')
    ..writeln();
  for (final import in imports) {
    buffer.writeln("import '$import';");
  }
  buffer
    ..writeln()
    ..writeln("/// Every component type `package:${package.name}` registers,")
    ..writeln('/// in the order their bits are assigned.')
    ..writeln('///')
    ..writeln('/// Pass this to `Game.componentBits` - together with the table')
    ..writeln('/// of every other engine package the game uses - to have these')
    ..writeln('/// types numbered at boot instead of on first sighting.');

  // Wrapped only when it has to be, and wrapped the way `dart format` would -
  // which is not run over a generated file, so the width is this emitter's to
  // keep. `goo2dPhysicsBox2dComponentBits` is the one that does not fit.
  final opening =
      'const $generatedComponentBitsType ${package.componentBitsName} = '
      '$generatedComponentBitsType(';
  final indent = opening.length <= 80 ? '' : '    ';
  if (opening.length <= 80) {
    buffer.writeln(opening);
  } else {
    buffer
      ..writeln(
        'const $generatedComponentBitsType ${package.componentBitsName} =',
      )
      ..writeln('    $generatedComponentBitsType(');
  }
  buffer
    ..writeln("$indent  package: '${package.name}',")
    ..writeln('$indent  types: <Type>[');
  for (final bit in bits) {
    buffer.writeln('$indent    ${bit.type},');
  }
  buffer.writeln('$indent  ],');
  if (dependencies.isNotEmpty) {
    buffer.writeln('$indent  dependencies: <$generatedComponentBitsType>[');
    for (final dependency in dependencies) {
      buffer.writeln('$indent    ${dependency.componentBitsName},');
    }
    buffer.writeln('$indent  ],');
  }
  buffer.writeln(opening.length <= 80 ? ');' : '    );');
  return buffer.toString();
}

/// Every package whose entry library does not export its generated table.
///
/// Hand-written and reported rather than inserted, exactly as the accessor
/// export is - and it matters more here, because this file is named from
/// *outside* the package: a game hands the table to `Game.componentBits`, and
/// a downstream engine package's own table names it as a dependency.
List<EnginePackage> missingComponentBitsExports(
  List<GeneratedFile> files,
  List<EnginePackage> packages,
) {
  final generated = <String>{for (final file in files) file.file.path};
  return <EnginePackage>[
    for (final package in packages)
      if (generated.contains(package.componentBitsFile.path) &&
          !_exports(package)) package,
  ];
}

bool _exports(EnginePackage package) {
  final barrel = package.barrel;
  if (!barrel.existsSync()) return false;
  return barrel.readAsStringSync().contains(package.componentBitsExport);
}
