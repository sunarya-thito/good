// What the two emitters ask of one walk over the packages.
//
// The walk itself is `good_cli`'s `scan.dart` - one parse of one set of trees,
// shared, for the reason stated there. This file holds the two questions that
// only `good_tool` asks, and it is here rather than there because both answers
// need `Imports`, and `Imports` lives in this package.
//
// Neither of these decides anything about a file's contents beyond what it
// found. What refuses a run - a column shadowing a member of `Accessor`, a
// component-bit table too big for a query signature - is reported here and
// acted on by `bin/good_tool.dart`, so a caller that only wants the counts can
// have them without a process exiting underneath it.

import 'dart:io';

import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

import 'package:good_tool/src/engine_packages.dart';
import 'package:good_tool/src/imports.dart';

// good_cli's `lib/src` is private by convention and this reaches into it, for
// the reason `imports.dart` states beside its own copy of this line: one walk
// serves both packages, and two copies of it would be two answers about one
// tree.
// ignore: implementation_imports
import 'package:good_cli/src/generate/scan.dart';

/// The one walk both questions below are answered off.
///
/// Every package read, and its own generated output left out of it - a
/// generator that read `accessors.g.dart` back reported each property it would
/// write as colliding with the copy of itself already on disk. Its own output
/// and only its own: an upstream package's committed file is an ordinary
/// hand-written extension, and a name it already declares on the same component
/// is a real collision.
///
/// `Directory.current` is passed only so [readSources] has somewhere to look
/// for a package config it will not use - the roots are named outright.
ScanSources readPackageSources(List<EnginePackage> packages) => readSources(
  Directory.current,
  rootOverride: <String>[for (final package in packages) package.libDir],
  exclude: <String>{
    for (final package in packages) package.accessorFile.path,
    for (final package in packages) package.componentBitsFile.path,
    for (final package in packages) package.declarationsFile.path,
  },
);

// ---------------------------------------------------------------------------
// Accessor properties
// ---------------------------------------------------------------------------

/// One generated property: `double get offsetX => component.transformOffsetX`.
@immutable
class AccessorProperty {
  const AccessorProperty({
    required this.name,
    required this.type,
    required this.column,
    this.annotations = const <String>[],
  });

  /// What it is called on the accessor - `offsetX`.
  final String name;

  /// The value one entity holds - `double`, `CameraView?`.
  final String type;

  /// The field on the component the property reads - `transformOffsetX`.
  final String column;

  /// The column's annotations that the property inherits - see
  /// [narrowingColumnAnnotations]. Written as they were, `@` included.
  final List<String> annotations;
}

/// The annotations a column hands down to the property generated off it.
///
/// A property is a second name for one column, so an annotation saying who
/// may write the first has to say it about the second - otherwise the
/// generator is what widens the audience, and it does it silently. That is
/// what happened to `WorldTransform2D`'s six change-detection columns: they
/// were made public with `@internal` so a collector in another library could
/// read them, and shipped as undecorated public setters into a cache.
///
/// The test for adding a name here is that leaving it off would make the
/// property reachable where the column is not. `@override` and `@child` fail
/// it - neither says anything about who may name the field - and a
/// documentation annotation fails it too.
///
/// Written without the `@`, the way `annotationName` hands them back.
const Set<String> narrowingColumnAnnotations = <String>{'internal'};

/// The import a carried annotation needs in the generated file.
const String metaImport = 'package:meta/meta.dart';

/// One `extension Accessor$X on Accessor<X>`, and everything it needs.
@immutable
class AccessorExtension {
  const AccessorExtension({
    required this.component,
    required this.package,
    required this.path,
    required this.imports,
    required this.properties,
  });

  /// The component the extension is on - `Transform2D`.
  final String component;

  /// The package whose `lib/` declares it.
  final String package;

  /// The file it is declared in, normalised and absolute.
  final String path;

  /// Every `package:` URI the generated file has to import for this one.
  final Set<String> imports;

  /// The properties, in the order their columns are declared.
  final List<AccessorProperty> properties;

  /// `Accessor$Transform2D`.
  ///
  /// A `$` because it cannot appear in a component name, so no hand-written
  /// extension can collide with a generated one by accident.
  String get extensionName => 'Accessor\$$component';
}

/// A property name a member of `Accessor`, `Entity` or `int` already holds.
@immutable
class AccessorCollision {
  const AccessorCollision({
    required this.component,
    required this.column,
    required this.property,
    required this.owner,
  });

  final String component;
  final String column;
  final String property;

  /// Which type already declares that name.
  final String owner;
}

/// Every accessor extension one run would write, and what it left out.
@immutable
class AccessorScan {
  const AccessorScan({
    required this.byPackage,
    required this.extensions,
    required this.skipped,
    required this.collisions,
  });

  /// Extensions keyed by the package they are written into, sorted within each
  /// package by where the component is declared.
  final Map<String, List<AccessorExtension>> byPackage;

  /// Every extension, over every package read.
  final List<AccessorExtension> extensions;

  /// Every column that got no property, keyed `Component.column`, to why.
  ///
  /// Reported under `--verbose` rather than failing the run: a private cache
  /// column and an array column both belong here, and neither is a mistake.
  /// A column silently absent is what this exists to prevent.
  final Map<String, String> skipped;

  /// Every property name that would be shadowed, which refuses the run.
  final List<AccessorCollision> collisions;

  int get propertyCount {
    var count = 0;
    for (final extension in extensions) {
      count += extension.properties.length;
    }
    return count;
  }
}

/// Every column in [packages], as the property it would become.
///
/// # What counts as a column
///
/// A field on a type with `Component` above it whose value is a `DataPointer`
/// - either because it says so (`late final DataPointer<CameraView?>`) or
/// because the factory that produced it does (`Field.float64()` returns
/// `InitialPointer<double>`, read out of `Field`'s own declaration). See
/// `columnValueType`.
///
/// A `DataArrayPointer` is a column and gets no property: it holds a run of
/// values at each entity, and a property reading one would have to pick an
/// index. It is recorded in [AccessorScan.skipped] saying so, rather than
/// falling through a `DataPointer` test that never mentioned it.
///
/// A private column gets no property either. `Accessor$X` is generated into
/// the package that declares the component, so a private field is reachable -
/// but the property would be public, which makes a cache column part of the
/// published API by accident. `WorldTransform2D` has five of them.
///
/// # The order everything comes out in
///
/// Extensions by where their component is declared - file path, then name
/// within a file. Properties in the order their columns are written. The file
/// is committed and read in a diff, so a regeneration that reordered nothing
/// semantically would still be noise in a review.
AccessorScan scanAccessors({
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
  final reserved = _reservedNames(typesByName);

  final extensions = <AccessorExtension>[];
  final skipped = <String, String>{};
  final collisions = <AccessorCollision>[];

  final paths = read.units.keys.toList()..sort();
  for (final path in paths) {
    final owner = packageOf(path, byLibDir);
    if (owner == null) continue;
    for (final type in read.units[path]!.types) {
      if (!isSubtypeOf(type.name, componentRoot, typesByName)) continue;
      final properties = <AccessorProperty>[];
      final needed = <String>{};
      for (final field in type.fields) {
        if (field.isStatic) continue;
        final column = columnValueType(field, typesByName);
        if (column == null) continue;
        final key = '${type.name}.${field.name}';
        if (column.problem != null) {
          skipped[key] = column.problem!;
          continue;
        }
        if (field.isPrivate) {
          skipped[key] =
              'it is private, and a generated property is public - a column '
              'nothing outside the component should name would become part of '
              'the package\'s API';
          continue;
        }
        final valueType = column.valueType!;
        final resolved = imports.importsFor(valueType, owner);
        if (resolved.problem != null) {
          skipped[key] = resolved.problem!;
          continue;
        }
        final property = propertyNameFor(type.name, field.name);
        final shadowedBy = reserved[property];
        if (shadowedBy != null) {
          collisions.add(
            AccessorCollision(
              component: type.name,
              column: field.name,
              property: property,
              owner: shadowedBy,
            ),
          );
          continue;
        }
        final carried = <String>[
          for (final annotation in field.annotations)
            if (narrowingColumnAnnotations.contains(annotationName(annotation)))
              '@$annotation',
        ];
        needed.addAll(resolved.imports);
        if (carried.isNotEmpty) needed.add(metaImport);
        properties.add(
          AccessorProperty(
            name: property,
            type: valueType,
            column: field.name,
            annotations: carried,
          ),
        );
      }
      if (properties.isEmpty) continue;

      final component = imports.importsFor(type.name, owner);
      final accessor = imports.importFor('Accessor', owner);
      if (component.problem != null || accessor.problem != null) {
        skipped[type.name] = component.problem ?? accessor.problem!;
        continue;
      }
      extensions.add(
        AccessorExtension(
          component: type.name,
          package: owner.name,
          path: path,
          imports: <String>{
            ...needed,
            ...component.imports,
            ...accessor.imports,
          },
          properties: properties,
        ),
      );
    }
  }

  extensions.sort(_byDeclaration);
  final byPackage = <String, List<AccessorExtension>>{};
  for (final extension in extensions) {
    byPackage
        .putIfAbsent(extension.package, () => <AccessorExtension>[])
        .add(extension);
  }
  return AccessorScan(
    byPackage: byPackage,
    extensions: extensions,
    skipped: skipped,
    collisions: collisions,
  );
}

int _byDeclaration(AccessorExtension a, AccessorExtension b) {
  final path = a.path.compareTo(b.path);
  if (path != 0) return path;
  return a.component.compareTo(b.component);
}

/// Every name a generated property would lose to, to the type that holds it.
///
/// `Accessor<T>` implements `Entity`, which implements `int`, and an extension
/// member never wins against one the receiver's own type declares. `Accessor`
/// and `Entity` are read out of the parse so they cannot go stale; `int`'s
/// members are the written-out list in `scan.dart`, because nothing in the
/// walk reads `dart:core`.
Map<String, String> _reservedNames(Map<String, ScannedType> typesByName) {
  final reserved = <String, String>{for (final name in intMembers) name: 'int'};
  for (final owner in const <String>['Entity', 'Accessor']) {
    final type = typesByName[owner];
    if (type == null) continue;
    for (final member in type.memberNames) {
      if (member.startsWith('_')) continue;
      reserved[member] = owner;
    }
  }
  return reserved;
}

/// What a run refusing over a shadowed property name says.
String accessorCollisionMessage(AccessorScan scan) {
  final lines = StringBuffer()
    ..writeln(
      'A column would generate a property that is already a member of '
      'Accessor, Entity or int:',
    )
    ..writeln();
  for (final collision in scan.collisions) {
    lines.writeln(
      '  ${collision.component}.${collision.column} would generate '
      '`${collision.property}` on Accessor<${collision.component}>, and '
      '${collision.owner} already has ${collision.property}',
    );
  }
  lines
    ..writeln()
    ..writeln(
      'An extension member loses to one the receiver\'s own type has, so the '
      'property would compile and never be reached: every read of it would '
      'answer about the entity handle instead of the column, with nothing '
      'said anywhere. This file is committed and shipped, so nothing '
      'downstream would say it either. Rename the column.',
    );
  return lines.toString();
}

// ---------------------------------------------------------------------------
// Component bits
// ---------------------------------------------------------------------------

/// The number of component types one query signature can hold.
///
/// It is one 64-bit word - `ComponentTypeRegistry.maxComponentTypes` in
/// `good/lib/src/archetype.dart`, which is the number that actually governs.
/// This is a second copy of it because nothing here reads the engine at run
/// time, and it is checked against the engine's own value by
/// `good_tool_test.dart`. A table that exactly fills the word has already
/// taken every slot a game had.
const int maxComponentTypes = 64;

/// One component type that gets a bit, and how the table names it.
@immutable
class ComponentBit {
  const ComponentBit({
    required this.type,
    required this.import,
    required this.package,
    required this.path,
  });

  /// The type - `Transform2D`.
  final String type;

  /// The `package:` URI the table imports to name it.
  final String import;

  /// The package whose table it goes in.
  final String package;

  /// The file it is declared in, normalised and absolute.
  final String path;
}

/// Every component type one run would number, and what it left out.
@immutable
class ComponentBitScan {
  const ComponentBitScan({
    required this.byPackage,
    required this.bits,
    required this.skipped,
  });

  /// Bits keyed by the package whose table they go in, in bit order.
  final Map<String, List<ComponentBit>> byPackage;

  /// Every bit over every package read, which is what the ceiling counts.
  final List<ComponentBit> bits;

  /// Every registration that got no bit, keyed `Component`, to why.
  final Map<String, String> skipped;
}

/// Every type a package registers with `component.has<T>()`.
///
/// Registration is what earns a bit, not declaring columns: `Collider2D`,
/// `Renderable2D` and `ScreenTransform2D` all register and declare no column
/// of their own, and a query over any of them still has to mean something.
///
/// Only inside a `describeType`, and only on that method's own descriptor
/// parameter. `hierarchy.dart` writes `child.has<Child>()` and
/// `!ancestor.has<Child>()` as ordinary runtime tests, and counting every
/// `has<T>()` in the tree would assign a bit for each of them.
///
/// The order is the bit order, so it is pinned: by where the type is declared -
/// file path, then name within a file - and never by the order the walk
/// happened to reach the files in. A table that renumbered itself between runs
/// would give two machines two meanings for one query signature.
ComponentBitScan scanComponentBits({
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

  final found = <_Registration>[];
  final skipped = <String, String>{};
  final paths = read.units.keys.toList()..sort();
  for (final path in paths) {
    final owner = packageOf(path, byLibDir);
    if (owner == null) continue;
    for (final type in read.units[path]!.types) {
      final describe = type.methods['describeType'];
      if (describe == null) continue;
      for (final registered in describe.registeredTypes) {
        final parsed = TypeSource.parse(registered);
        if (parsed == null || parsed.arguments.isNotEmpty) {
          skipped[registered] =
              'it is registered as `$registered`, and a table holds a plain '
              'Type';
          continue;
        }
        found.add(
          _Registration(name: parsed.name, package: owner, path: path),
        );
      }
    }
  }

  found.sort((a, b) {
    final package = a.package.name.compareTo(b.package.name);
    if (package != 0) return package;
    final path = a.path.compareTo(b.path);
    if (path != 0) return path;
    return a.name.compareTo(b.name);
  });

  final bits = <ComponentBit>[];
  final seen = <String>{};
  for (final registration in found) {
    if (!seen.add('${registration.package.name}.${registration.name}')) {
      continue;
    }
    final resolved = imports.importFor(registration.name, registration.package);
    if (resolved.problem != null) {
      skipped[registration.name] = resolved.problem!;
      continue;
    }
    bits.add(
      ComponentBit(
        type: registration.name,
        import: resolved.imports.single,
        package: registration.package.name,
        path: registration.path,
      ),
    );
  }

  final byPackage = <String, List<ComponentBit>>{};
  for (final bit in bits) {
    byPackage.putIfAbsent(bit.package, () => <ComponentBit>[]).add(bit);
  }
  return ComponentBitScan(
    byPackage: byPackage,
    bits: bits,
    skipped: skipped,
  );
}

@immutable
class _Registration {
  const _Registration({
    required this.name,
    required this.package,
    required this.path,
  });

  final String name;
  final EnginePackage package;
  final String path;
}

/// What a run refusing over a full component-bit table says.
///
/// It names every type competing for the last bit rather than whichever one
/// happened to arrive last, which is all a registry filling up at run time can
/// say. And it counts the packages alone: a table that exactly fills the word
/// has already taken every slot a game had for its own components.
String componentBitCeilingMessage(ComponentBitScan scan, int max) {
  final lines = StringBuffer()
    ..writeln(
      'The packages read register ${scan.bits.length} component types, and a '
      'query signature holds $max.',
    )
    ..writeln();
  for (var i = max; i < scan.bits.length; i++) {
    final bit = scan.bits[i];
    lines.writeln(
      '  ${bit.package}: ${bit.type} (${p.split(bit.path).last}) has no bit',
    );
  }
  lines
    ..writeln()
    ..writeln(
      'A signature is one 64-bit word. Every type above the line is one a '
      'query cannot ask about, and a game has none left for its own '
      'components. Widening the signature past one word is a change to '
      'ComponentTypeRegistry (see maxComponentTypes); until then, the answer '
      'is fewer component types in the packages this run read.',
    );
  return lines.toString();
}

// ---------------------------------------------------------------------------
// Declaration collectors
// ---------------------------------------------------------------------------

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
  });

  /// The class it reads - `GameRenderer2D`.
  final String type;

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
        // constructor call with no `@child` on it declares nothing at all -
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

// ---------------------------------------------------------------------------
// Fixture collectors
// ---------------------------------------------------------------------------

/// One class declared outside a package's `lib/` that a collector reads.
@immutable
class FixtureCollector {
  const FixtureCollector({
    required this.type,
    required this.functionName,
    required this.fields,
  });

  /// The class it reads - `_Level`, private like most of them.
  final String type;

  /// Every declaration an instance holds, in the order its initialisers
  /// would have run.
  final List<CollectedDeclaration> fields;

  /// The collector function's name - `_collect$Level` for `_Level`.
  ///
  /// The leading underscore of a private fixture is dropped rather than kept,
  /// because `non_constant_identifier_names` reads `_collect$_Level` as not
  /// lower-camel and this file has to analyze clean. Two classes in one
  /// library that differ only by that underscore would land on one name, so
  /// [scanFixtures] appends a `$` until the name is free.
  final String functionName;
}

/// One test or example library, and the collectors it needs.
@immutable
class FixtureLibrary {
  const FixtureLibrary({
    required this.package,
    required this.path,
    required this.collectors,
  });

  /// The package the library belongs to - where its table's key comes from,
  /// and whose generated table it depends on.
  final EnginePackage package;

  /// The library's own file, normalised and absolute.
  final String path;

  /// Its collectors, in the order the classes are declared in.
  final List<FixtureCollector> collectors;

  /// The library itself.
  File get file => File(path);

  /// The part beside it - `archetype_test.g.dart`.
  ///
  /// Not `_test.dart`, so the test runner's own glob does not pick the part
  /// up as a suite with no tests in it.
  File get generated =>
      File('${path.substring(0, path.length - '.dart'.length)}.g.dart');

  /// The line [file] has to carry for [generated] to be compiled at all.
  String get partDirective => "part '${p.basename(generated.path)}';";

  /// What the table is called - `_archetypeTestDeclarations`.
  String get tableName {
    final words = p.basenameWithoutExtension(path).split('_');
    return <String>[
      '_',
      words.first,
      for (final word in words.skip(1))
        if (word.isNotEmpty) word[0].toUpperCase() + word.substring(1),
      'Declarations',
    ].join();
  }

  /// The key the table is installed once under - `good/test/archetype_test.dart`.
  ///
  /// A path rather than a package name, because a package has one `lib/`
  /// table and as many of these as it has files that declare a fixture, and
  /// `DeclarationRegistry` installs a table once per key.
  String get tableKey => package.describe(file);
}

/// [readPackageSources] widened to the trees `--tests` reads.
///
/// The `lib/` of every package read, so the supertype walk can see that
/// `EntityStruct` is a `Scannable` at all, plus the `test/` and `example/` of
/// the packages being written into. Their own generated parts are left out
/// for the reason the three `lib/` files are: a generator that read its own
/// output back would be reading a copy of the answer it is computing.
ScanSources readFixtureSources(
  List<EnginePackage> packages,
  List<EnginePackage> readable,
) {
  final roots = <String>[
    for (final package in readable) package.libDir,
    for (final package in packages)
      for (final root in package.fixtureRoots) root.path,
  ];
  final generated = <String>{
    for (final package in readable) package.accessorFile.path,
    for (final package in readable) package.componentBitsFile.path,
    for (final package in readable) package.declarationsFile.path,
  };
  for (final package in packages) {
    for (final root in package.fixtureRoots) {
      for (final entry in root.listSync(recursive: true)) {
        if (entry is File && entry.path.endsWith('.g.dart')) {
          generated.add(entry.path);
        }
      }
    }
  }
  return readSources(
    Directory.current,
    rootOverride: roots,
    exclude: generated,
  );
}

/// Every fixture library one run would write a part for.
@immutable
class FixtureScan {
  const FixtureScan({required this.libraries, required this.collectorCount});

  /// The libraries, sorted by path.
  final List<FixtureLibrary> libraries;

  /// How many collectors they hold between them.
  final int collectorCount;
}

/// Every class declared under a package's `test/` or `example/` that a
/// collector has to be able to read.
///
/// # Why this is not [scanDeclarationCollectors] pointed somewhere else
///
/// Two things about a fixture are different from a class in a `lib/`, and
/// each of them changes the answer rather than the path.
///
/// **It is almost always private.** 678 of the 737 instantiable scanned
/// classes under this repository's `test/` directories are `_Level`,
/// `_Scene`, `_Game`. A generated library in another file can neither cast to
/// one nor name it in a table, so what is written here is a **part** of the
/// library that declares them - which reaches a private class and a private
/// field the way any other part of that library does. The rule that user code
/// is never edited to add a `part` is about a user's code; a test in this
/// repository is ours.
///
/// **Its name is not unique.** `_Scene` is declared in 23 files here and
/// `_Game` in 17. [ScanSources.typesByName] keeps one of each, so a supertype
/// walk through it would flatten one file's `_Scene` using another file's
/// mixins and hand back a row that belongs to neither. So each library is
/// walked against its own types laid over the `lib/` ones, and nothing from a
/// second test file is ever in scope - which is also what Dart says, since no
/// test file here imports another.
FixtureScan scanFixtures({
  required List<EnginePackage> packages,
  required ScanSources sources,
}) {
  final libTypes = <String, ScannedType>{};
  // Over every unit and not per library: a marker is a const in an engine
  // package's `lib/`, so the set is the same whichever fixture is being
  // walked.
  final markers = scannableAnnotationNames(sources);
  final libDirs = <String>[for (final package in packages) package.libDir];
  final paths = sources.units.keys.toList()..sort();
  for (final path in paths) {
    if (!libDirs.any((lib) => p.isWithin(lib, path))) continue;
    for (final type in sources.units[path]!.types) {
      libTypes.putIfAbsent(type.name, () => type);
    }
  }

  final libraries = <FixtureLibrary>[];
  var collectorCount = 0;
  for (final package in packages) {
    final roots = <String>[
      for (final root in package.fixtureRoots) root.path,
    ];
    if (roots.isEmpty) continue;
    for (final path in paths) {
      if (!roots.any((root) => p.isWithin(root, path))) continue;
      final unit = sources.units[path]!;
      // The library's own types win. A fixture named after something in a
      // `lib/` - and there are several - is the one this file declares.
      final scope = <String, ScannedType>{
        ...libTypes,
        for (final type in unit.types) type.name: type,
      };
      final declaredHere = <String>{for (final type in unit.types) type.name};

      final collectors = <FixtureCollector>[];
      final taken = <String>{};
      for (final type in unit.types) {
        if (type.isAbstract) continue;
        if (!isSubtypeOf(type.name, scannableRoot, scope)) continue;
        var functionName = '_collect\$${type.name.replaceFirst('_', '')}';
        while (!taken.add(functionName)) {
          functionName = '$functionName\$';
        }
        collectors.add(
          FixtureCollector(
            type: type.name,
            functionName: functionName,
            fields: <CollectedDeclaration>[
              for (final declaration in flattenedDeclarations(
                type,
                scope,
                markers: markers,
              ))
                if (declaration.isCollected)
                  CollectedDeclaration(
                    owner: declaration.owner,
                    name: declaration.name,
                    // Private is not the question a part asks. A field this
                    // library declares is reachable however it is named; one a
                    // `lib/` mixin declares privately is not, and that is the
                    // same wall `declarations.g.dart` runs into.
                    isPrivate:
                        declaration.isPrivate &&
                        !declaredHere.contains(declaration.owner),
                  ),
            ],
          ),
        );
      }
      if (collectors.isEmpty) continue;
      collectorCount += collectors.length;
      libraries.add(
        FixtureLibrary(
          package: package,
          path: path,
          collectors: collectors,
        ),
      );
    }
  }
  libraries.sort((a, b) => a.path.compareTo(b.path));
  return FixtureScan(libraries: libraries, collectorCount: collectorCount);
}
