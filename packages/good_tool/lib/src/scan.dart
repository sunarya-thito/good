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
  });

  /// What it is called on the accessor - `offsetX`.
  final String name;

  /// The value one entity holds - `double`, `CameraView?`.
  final String type;

  /// The field on the component the property reads - `transformOffsetX`.
  final String column;
}

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
        needed.addAll(resolved.imports);
        properties.add(
          AccessorProperty(
            name: property,
            type: valueType,
            column: field.name,
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
