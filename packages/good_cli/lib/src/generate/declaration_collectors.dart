// Which classes get a generated declaration collector, and what each one reads.
//
// One of the two questions asked off `scan.dart`'s walk that produce a
// committed artifact. It lives here rather than in `good_tool` because there
// are two callers and there must be one answer: `good_tool` writes the table
// for each engine package in this repository, and `good generate` writes the
// one for a user's own project (#313). A project's classes are the classes
// `Game.declarations` cannot do without - a prefab, a scene and a state are
// what the person wrote - so a second implementation over there would be the
// generator that disagrees about what is current.

import 'package:good_cli/src/generate/engine_package.dart';
import 'package:good_cli/src/generate/imports.dart';
import 'package:good_cli/src/generate/scan.dart';
import 'package:meta/meta.dart';

/// The type a generated table is an instance of.
const String generatedDeclarationsType = 'GeneratedDeclarations';

/// The type one entry of that table is.
const String declarationCollectorType = 'DeclarationCollector';

/// The bound every collected value carries, and the element type of the list
/// a collector hands back.
const String scannableFieldType = 'ScannableField';

/// One declaration a collector would read, in the position it holds.
///
/// A private one is here too, and that is the point of the class. It is not
/// dropped from the list and mentioned in a log somewhere else: it keeps its
/// place among the fields that surround it, so the generated file can say
/// where the hole is rather than only that there is one.
@immutable
class CollectedDeclaration {
  const CollectedDeclaration({
    required this.owner,
    required this.name,
    required this.isPrivate,
  });

  /// The class that writes the field - `WorldTransform2D`, not whichever
  /// class applies it.
  final String owner;

  /// The Dart field name.
  final String name;

  /// Whether it is private, and so unreachable from the generated file.
  final bool isPrivate;
}

/// One class's collector: what it reads, and off what.
@immutable
class DeclarationCollectorEntry {
  const DeclarationCollectorEntry({
    required this.type,
    required this.package,
    required this.path,
    required this.imports,
    required this.fields,
    required this.isGeneric,
  });

  /// The class it reads - `GameRenderer2D`.
  final String type;

  /// Whether the class takes type parameters, and so needs the type test
  /// `DeclarationCollector.generic` is given.
  final bool isGeneric;

  /// The package whose table it goes in.
  final String package;

  /// The file the class is declared in, normalised and absolute.
  final String path;

  /// Every `package:` URI the generated file needs for this entry.
  final Set<String> imports;

  /// Every declaration an instance holds, in the order its initialisers
  /// would have run - see [flattenedDeclarations]. Private ones included,
  /// keeping their place.
  final List<CollectedDeclaration> fields;

  /// Whether any of [fields] can actually be read.
  ///
  /// False leaves a collector that hands back an empty list, which is a
  /// truthful answer to "what can be read off this" and a false one to "what
  /// does this declare". Nothing in this repository is such a class - every
  /// `Scannable` root declares at least one public dispatcher - and a run
  /// that produced one would be worth stopping over rather than emitting.
  bool get hasReadableField => fields.any((field) => !field.isPrivate);

  /// `_gameRenderer2D`, the collector function's name.
  ///
  /// Private, because nothing names it but the table three lines below it.
  String get functionName => '_${type[0].toLowerCase()}${type.substring(1)}';

  /// `_is$GameRenderer2D`, the type test's name, written only when
  /// [isGeneric].
  ///
  /// A `$` for the reason `AccessorExtension.extensionName` has one: it
  /// cannot appear in a class name, so this can never land on the same name
  /// as some other class's [functionName].
  String get matcherName => '_is\$$type';
}

/// Every collector one run would write, and what it left out.
@immutable
class DeclarationCollectorScan {
  const DeclarationCollectorScan({
    required this.byPackage,
    required this.entries,
    required this.skipped,
  });

  /// Entries keyed by the package they are written into, in table order.
  final Map<String, List<DeclarationCollectorEntry>> byPackage;

  /// Every entry, over every package read.
  final List<DeclarationCollectorEntry> entries;

  /// Every declaration that reached no collector, keyed `Class.field`, to
  /// why.
  ///
  /// Reported under `--verbose` and not fatal, for the reason
  /// `DeclarationScan.uncollectable` gives: today every one of them is a
  /// private field, and whether the engine's own cache columns become public
  /// is an open call that a generator refusing would be making. What is *not*
  /// left to the reader is whether the omission is visible - each one is
  /// written into the generated file beside the fields that did reach it.
  final Map<String, String> skipped;
}

/// Every class in [packages] that can be a `runtimeType`, whether or not it
/// declares anything.
///
/// # Why a class that declares nothing is in it
///
/// Because `collectDeclarations` throws on a miss, and that throw is only
/// worth anything if a miss means one thing. Leaving out the classes that
/// declare nothing made it mean two - never scanned, or scanned and empty -
/// and `final class StepOnceCommand extends SignalCommand {}` is the second,
/// registered like every other command and absent from the table. So an
/// entry is written for every one of them, holding an empty list.
///
/// # Why abstract classes and mixins are not in it
///
/// A collector is looked up by `object.runtimeType`, and nothing is ever an
/// instance of exactly `Transform2D` or exactly `EntityStruct`. An entry for
/// one would be a line in a committed file that nothing can reach. What
/// carries a mixin's columns is the entry of each class that applies it,
/// which holds them flattened in place.
///
/// # The order everything comes out in
///
/// Entries by where the class is declared - file path, then name within a
/// file - exactly as the accessor extensions are, and for the same reason:
/// the file is committed and read in a diff. The *fields* inside an entry are
/// in construction order, which is the one order here that is load-bearing
/// rather than tidy.
DeclarationCollectorScan scanDeclarationCollectors({
  required List<EnginePackage> packages,
  ScanSources? sources,
}) {
  final read = sources ?? readPackageSources(packages);
  final byLibDir = <String, EnginePackage>{
    for (final package in packages) package.libDir: package,
  };
  final imports = Imports(
    declaredIn: declaredIn(read),
    byLibDir: byLibDir,
    units: read.units,
    packages: packages,
  );
  final typesByName = read.typesByName;
  final markers = scannableAnnotationNames(read);

  final entries = <DeclarationCollectorEntry>[];
  final skipped = <String, String>{};

  final paths = read.units.keys.toList()..sort();
  for (final path in paths) {
    final owner = packageOf(path, byLibDir);
    if (owner == null) continue;
    final types = read.units[path]!.types.toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    for (final type in types) {
      if (type.isAbstract) continue;
      if (!isSubtypeOf(type.name, scannableRoot, typesByName)) continue;
      // No `if (declarations.isEmpty) continue` here, and that omission is
      // the whole of what makes the miss in `collectDeclarations` mean one
      // thing. A class that declares nothing still gets an entry, holding an
      // empty list. Without it, `final class StepOnceCommand extends
      // SignalCommand {}` - which declares nothing and is registered like
      // every other command - reached a table that had no line for it, and
      // the throw meant for "this class was never scanned" fired on a class
      // that was scanned and had nothing to say.
      final declarations = flattenedDeclarations(
        type,
        typesByName,
        markers: markers,
      );
      if (type.name.startsWith('_')) {
        // The same wall a private field runs into, one level up: this file is
        // another library, so it cannot name the class either - not to cast
        // to it and not to key the table by it. Skipped rather than emitted
        // half-written, because a collector that cannot name its own class
        // does not compile.
        skipped[type.name] =
            'the class is private, and this file is another library - it can '
            'neither cast to it nor name it in the table. Nothing can collect '
            'declarations off it, so `collectDeclarations` throws when one is '
            'registered. Give the class a public name, marked @internal if it '
            'is not part of the package API';
        continue;
      }

      final fields = <CollectedDeclaration>[];
      for (final declaration in declarations) {
        // Not a hole in the row, so not a commented-out line either. A bare
        // constructor call with no `@sub` on it declares nothing at all -
        // no column is reserved for it and none is missing - and writing a
        // placeholder here would say a column went astray. What names it is
        // `--declarations`.
        if (!declaration.isCollected) continue;
        if (declaration.isPrivate) {
          skipped['${declaration.owner}.${declaration.name}'] =
              'it is private, and this file is a different library from the '
              'one that declares it - a collector reading it would not '
              'compile, and user code is never edited to add a part '
              'directive';
        }
        fields.add(
          CollectedDeclaration(
            owner: declaration.owner,
            name: declaration.name,
            isPrivate: declaration.isPrivate,
          ),
        );
      }

      final resolved = imports.importFor(type.name, owner);
      final field = imports.importFor(scannableFieldType, owner);
      if (resolved.problem != null || field.problem != null) {
        skipped[type.name] = resolved.problem ?? field.problem!;
        continue;
      }
      entries.add(
        DeclarationCollectorEntry(
          type: type.name,
          package: owner.name,
          path: path,
          imports: <String>{...resolved.imports, ...field.imports},
          fields: fields,
          isGeneric: type.typeParameters.isNotEmpty,
        ),
      );
    }
  }

  final byPackage = <String, List<DeclarationCollectorEntry>>{};
  for (final entry in entries) {
    byPackage
        .putIfAbsent(entry.package, () => <DeclarationCollectorEntry>[])
        .add(entry);
  }
  return DeclarationCollectorScan(
    byPackage: byPackage,
    entries: entries,
    skipped: skipped,
  );
}
