import 'dart:io';

// good_cli's `lib/src` is private by convention and this reaches into it.
// Deliberate, and the alternative is worse: exporting the parse from
// `good_cli.dart` would make a published package's public API out of it for one
// consumer that is never published and never leaves this repository. Both
// packages are versioned together here, so the coupling costs nothing a rename
// would not immediately show.
// ignore: implementation_imports
import 'package:good_cli/src/generate/struct_scan.dart';
import 'package:good_tool/src/engine_packages.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

/// One property a generated extension declares.
@immutable
class AccessorProperty {
  const AccessorProperty({
    required this.name,
    required this.column,
    required this.type,
    required this.imports,
  });

  /// What the property is called - `offsetX`.
  final String name;

  /// The column it reads and writes - `transformOffsetX`.
  final String column;

  /// What `column[entity]` hands back, written as Dart source.
  final String type;

  /// The `package:` URIs [type] needs, which is empty for a `dart:core` one.
  final Set<String> imports;
}

/// One component's generated extension.
@immutable
class AccessorExtension {
  const AccessorExtension({
    required this.component,
    required this.package,
    required this.componentImport,
    required this.accessorImport,
    required this.sortKey,
    required this.properties,
  });

  /// The component the extension is `on Accessor<...>` of.
  final String component;

  /// The package the extension is generated into - the one declaring
  /// [component].
  final String package;

  /// The `package:` URI of the library declaring [component].
  final String componentImport;

  /// The component's file, relative to its package's `lib/`, in posix form.
  ///
  /// The ordering key, and posix on purpose: this decides the order of a file
  /// that is committed and read in a diff, and a Windows separator would sort
  /// `src/data/camera.dart` differently from `src\data\camera.dart` and
  /// reorder the whole file on the next person's machine.
  final String sortKey;

  /// Its properties, in the order the columns are declared.
  final List<AccessorProperty> properties;

  /// What the extension itself is called.
  ///
  /// `$` is deliberate. The documented way to write an accessor helper by hand
  /// is `extension HealthAccessor on Accessor<Health>` (see `Accessor`'s own
  /// doc), and this repository has five of them, so generating
  /// `Transform2DAccessor` would put generated code in the exact namespace
  /// people are told to write into. A `$` is not legal in a name anybody would
  /// choose and is the marker Dart code generators already use.
  String get extensionName => 'Accessor\$$component';

  /// The `package:` URI of the library declaring `Accessor`.
  ///
  /// Needed by every generated file and by no column: it is in the extension's
  /// own `on` clause, not in any property's type. Resolved rather than written
  /// down, so it follows `Accessor` if that ever moves out of `struct.dart`.
  final String accessorImport;

  /// Every `package:` URI this extension needs.
  Set<String> get imports => <String>{
    accessorImport,
    componentImport,
    for (final property in properties) ...property.imports,
  };
}

/// One column whose property name something else already answers to.
@immutable
class AccessorCollision {
  const AccessorCollision({
    required this.component,
    required this.column,
    required this.property,
    required this.owner,
    required this.file,
  });

  /// The component declaring the column.
  final String component;

  /// The column as declared - `transformSign`.
  final String column;

  /// The property name it would take - `sign`.
  final String property;

  /// What already answers to [property] - `Accessor`, `Entity`, `int`, or a
  /// hand-written extension.
  final String owner;

  /// Where [component] is declared, for the message.
  final String file;
}

/// What one pass over the repository's components produced.
@immutable
class AccessorScan {
  const AccessorScan({
    required this.extensions,
    required this.collisions,
    required this.skipped,
  });

  /// One entry per component that got an extension, ordered by package and then
  /// by where the component is declared.
  final List<AccessorExtension> extensions;

  /// Every column whose property something else would answer to.
  ///
  /// This stops the tool. See [accessorCollisionMessage] for why this one is
  /// not a skip when everything else here is.
  final List<AccessorCollision> collisions;

  /// Every column that got no property and why, as `Component.column -> why`.
  ///
  /// Reported and never fatal, because each of these fails *loudly* at the use
  /// site: no property is generated, so `entity<Text2D>().codeUnits` is *"The
  /// getter 'codeUnits' isn't defined for the type `Accessor<Text2D>`"*. That
  /// is the discrimination this scan turns on - an omission the compiler
  /// catches is safe to make quietly, and one it cannot catch is not.
  final Map<String, String> skipped;

  /// How many properties were generated, across every component.
  int get propertyCount =>
      extensions.fold(0, (sum, e) => sum + e.properties.length);

  /// [extensions] grouped by the package they are written into.
  Map<String, List<AccessorExtension>> get byPackage {
    final grouped = <String, List<AccessorExtension>>{};
    for (final extension in extensions) {
      grouped
          .putIfAbsent(extension.package, () => <AccessorExtension>[])
          .add(extension);
    }
    return grouped;
  }
}

/// Finds every engine column a generated accessor property can be written for.
///
/// # What this is
///
/// #99, generated where #300 put it. `entity<Transform2D>().offsetX = 10.0` for
/// code touching one entity, with the properties shipped **inside** the engine
/// packages rather than regenerated into every project's bundle. A system
/// walking many entities still indexes the column, and
/// `docs/reference/design-rules.md` says which tier a reader is in.
///
/// One extension per component:
///
/// ```dart
/// extension Accessor$Transform2D on Accessor<Transform2D> {
///   double get offsetX => component.transformOffsetX[entity];
///   set offsetX(double v) => component.transformOffsetX[entity] = v;
/// }
/// ```
///
/// Per component and not per prefab, though `Accessor<Player>` is legal -
/// `EntityStruct` implements `Component`. A prefab needs no extension of its
/// own: `Player` mixes in `Transform2D`, so `Accessor<Player>` is a subtype of
/// `Accessor<Transform2D>` and the component's extension already applies to it.
/// Per prefab would emit `offsetX` once per prefab mixing the component in, and
/// every one of those would be a second extension applicable to the same
/// receiver - an ambiguity error at each use site, in return for nothing.
///
/// # Why an extension, and not a table
///
/// An extension resolves statically. A lookup registry would have to be
/// imported, installed onto a static, and installed again past
/// `Isolate.spawn`, because statics are per isolate and the spawn's deep copy
/// does not carry them (`archetype.dart`). Shipping the extensions inside the
/// engine removes the remaining question of who imports what: a user gets them
/// by importing `package:goo2d/goo2d.dart`, which they already do.
///
/// # It needs names and types, never offsets
///
/// This is why it is not blocked by what stopped #18. No scan can produce a
/// byte offset: an offset is the running total of a `declareField` sequence
/// that reads values only available at run time. A property calls through the
/// existing `DataPointer`, so it wants the column's name and its type, and both
/// are written in the source - see `columnValueType` in `good_cli`'s
/// `struct_scan.dart`.
///
/// # What it will not generate for
///
/// A component in a package declaring `publish_to: none`, a private column, an
/// array column, and a column whose value type this pass cannot place in an
/// importable library or whose package the component's own does not depend on.
/// Each of those fails at the use site with *the getter isn't defined*.
///
/// **A user's own component still gets nothing, and this does not solve that.**
/// Engine components are solved by shipping them; a component in a game's own
/// `lib/` is not in this repository and nothing here can reach it. #300 records
/// that as a separate design and so does this.
AccessorScan scanAccessors(
  Directory repoRoot, {
  List<EnginePackage>? packages,
  ScanSources? sources,
}) {
  final targets = packages ?? enginePackages(repoRoot);
  final read =
      sources ??
      readSources(
        repoRoot,
        rootOverride: <String>[for (final target in targets) target.libDir],
        // A generator must not read its own output. What this writes is an
        // `extension ... on Accessor<Transform2D>` inside `packages/goo2d/lib/`,
        // which on the next run is an ordinary hand-written extension declaring
        // `offsetX` - so the second run reported every one of its own
        // properties as colliding with itself. The guard was right and the
        // input was wrong.
        exclude: <String>{
          for (final target in targets) target.accessorFile.path,
        },
      );

  final byLibDir = <String, EnginePackage>{
    for (final target in targets) target.libDir: target,
  };
  final declaredIn = _declaredIn(read);
  final reserved = _reservedNames(read);
  final imports = _Imports(
    declaredIn: declaredIn,
    byLibDir: byLibDir,
    units: read.units,
    packages: targets,
  );

  final extensions = <AccessorExtension>[];
  final collisions = <AccessorCollision>[];
  final skipped = <String, String>{};

  // Sorted before anything is read out of them. What this writes is committed
  // and read in a diff, so an order that came from `Directory.listSync` would
  // make the file's contents a property of the filesystem: two people
  // regenerating would produce two orderings of the same set, and `--check`
  // would fail on whichever machine did not write it.
  final entries = <_Entry>[];
  for (final owners in read.byName.values) {
    for (final owner in owners) {
      if (!owner.isComponentMixin) continue;
      final package = _packageOf(owner.file, byLibDir);
      if (package == null) continue;
      entries.add(
        _Entry(
          owner,
          package,
          _posix(p.relative(owner.file, from: package.libDir)),
        ),
      );
    }
  }
  entries.sort((a, b) {
    final byPackage = a.package.name.compareTo(b.package.name);
    if (byPackage != 0) return byPackage;
    final byPath = a.sortKey.compareTo(b.sortKey);
    return byPath != 0 ? byPath : a.owner.name.compareTo(b.owner.name);
  });

  for (final entry in entries) {
    final component = entry.owner;
    final display = '${entry.package.name}/lib/${entry.sortKey}';
    // `Accessor` is named in every extension's `on` clause and in no column's
    // type, so it is resolved per package here rather than falling out of the
    // per-property walk. Resolved rather than written down, so it follows the
    // day `Accessor` moves out of `struct.dart`.
    final accessor = imports.importFor('Accessor', entry.package);
    final accessorProblem = accessor.problem;
    if (accessorProblem != null) {
      skipped[component.name] =
          'the extension has nothing to be `on` - $accessorProblem';
      continue;
    }
    if (read.byName[component.name]!.length > 1) {
      skipped[component.name] =
          'declared in more than one library, and a parsed scan cannot tell '
          'which one an import would reach';
      continue;
    }
    final handWritten =
        read.accessorExtensions[component.name] ?? const <String>{};

    final properties = <AccessorProperty>[];
    final taken = <String, String>{};
    for (final field in component.fields) {
      final key = '${component.name}.${field.name}';
      if (!field.isColumn) continue;
      if (field.name.startsWith('_')) {
        skipped[key] =
            'private, so nothing outside its own library can reach it';
        continue;
      }
      final type = field.valueType;
      if (type == null) {
        skipped[key] =
            'this pass cannot say what column[entity] returns - an array '
            'column, a type argument nothing spells, or a declaration form it '
            'does not read';
        continue;
      }
      final resolved = imports.importsFor(type, entry.package);
      final problem = resolved.problem;
      if (problem != null) {
        skipped[key] = problem;
        continue;
      }

      final property = accessorPropertyName(component.name, field.name);
      final owner = _shadowedBy(
        property,
        reserved: reserved,
        handWritten: handWritten,
        taken: taken,
        component: component.name,
      );
      if (owner != null) {
        collisions.add(
          AccessorCollision(
            component: component.name,
            column: field.name,
            property: property,
            owner: owner,
            file: display,
          ),
        );
        continue;
      }
      taken[property] = field.name;
      properties.add(
        AccessorProperty(
          name: property,
          column: field.name,
          type: type,
          imports: resolved.imports,
        ),
      );
    }

    if (properties.isEmpty) continue;
    extensions.add(
      AccessorExtension(
        component: component.name,
        package: entry.package.name,
        componentImport: 'package:${entry.package.name}/${entry.sortKey}',
        accessorImport: accessor.imports.single,
        sortKey: entry.sortKey,
        properties: properties,
      ),
    );
  }

  return AccessorScan(
    extensions: extensions,
    collisions: collisions,
    skipped: skipped,
  );
}

/// What already answers to [property], or `null` when nothing does.
///
/// Three sources, and they fail differently. A member of `Accessor`, `Entity`
/// or `int` shadows the property **silently**. A hand-written extension on the
/// same accessor makes the use site ambiguous, which is loud but raised in
/// shipped code far from the column. A second column of the same component
/// stripping to one name would simply not compile. All three are refused,
/// because none of them is a file worth writing.
String? _shadowedBy(
  String property, {
  required Map<String, String> reserved,
  required Set<String> handWritten,
  required Map<String, String> taken,
  required String component,
}) {
  final inherited = reserved[property];
  if (inherited != null) return inherited;
  if (handWritten.contains(property)) {
    return 'a hand-written extension on Accessor<$component>';
  }
  final earlier = taken[property];
  if (earlier != null) return '$component.$earlier';
  return null;
}

/// One component paired with where it will be written.
class _Entry {
  _Entry(this.owner, this.package, this.sortKey);

  final Owner owner;
  final EnginePackage package;

  /// The component's file, relative to its package's `lib/`, in posix form.
  final String sortKey;
}

/// What a column is called on the accessor.
///
/// A column carries its component's prefix - `transformOffsetX` - because two
/// mixins both declaring `x` on one prefab is #58's silent two-column bug.
/// `Accessor<Transform2D>` is its own type with nothing to collide with, so the
/// property drops the prefix and is `offsetX`: shorter and safer at once.
///
/// # The rule, and where it stops
///
/// Derived, not declared, and derived from **this column and its component's
/// name only** - never from what the component's other columns happen to be
/// called. A rule that took the longest prefix its siblings shared would rename
/// every property of a component the day an eleventh column was added to it,
/// and would turn a component declaring `speed` and `spin` into `eed` and `in`.
///
/// So: lower-case the component's name, drop a trailing `2D`/`3D`, and strip
/// that from the column when the column actually starts with it *and* the rest
/// starts a new camel-case word. Everything else is left exactly as declared:
///
///  * `Transform2D.transformOffsetX` -> `offsetX`
///  * `Child.childParent` -> `parent`
///  * `Text2D.textZIndex` -> `zIndex`
///  * `RigidBody2D.bodyType` -> `bodyType`, unchanged - the component is
///    `RigidBody2D` and the prefix is `body`, so nothing here can know they go
///    together. #99's body names this exact case: `bodyHandle` is not
///    `handle`-by-prefix, it just reads that way.
///  * `WorldTransform2D.worldX` -> `worldX`, unchanged, for the same reason.
///
/// Leaving those two alone is the point rather than a shortfall. A rule that
/// guessed would be right about `body` and wrong about the next component, and
/// the property name is public API from the moment it ships.
String accessorPropertyName(String component, String column) {
  for (final prefix in _prefixesOf(component)) {
    if (column.length <= prefix.length) continue;
    if (!column.startsWith(prefix)) continue;
    final rest = column.substring(prefix.length);
    // The boundary test. Without it `parenthood` on a `Parent` would strip to
    // `hood`, which names nothing.
    if (rest[0].toUpperCase() != rest[0]) continue;
    return rest[0].toLowerCase() + rest.substring(1);
  }
  return column;
}

/// The prefixes [component]'s name offers, longest first.
List<String> _prefixesOf(String component) {
  final lower = component[0].toLowerCase() + component.substring(1);
  final bare = lower.replaceFirst(RegExp(r'[23]D$'), '');
  return <String>[lower, if (bare != lower && bare.isNotEmpty) bare];
}

/// The package whose `lib/` holds [file].
EnginePackage? _packageOf(String file, Map<String, EnginePackage> byLibDir) {
  final full = p.normalize(p.absolute(file));
  for (final entry in byLibDir.entries) {
    if (p.isWithin(entry.key, full)) return entry.value;
  }
  return null;
}

String _posix(String path) => p.split(path).join('/');

/// Where each top-level name in the repository is declared.
///
/// A name two libraries both declare is left out rather than picked between.
/// This pass resolves nothing, so it cannot tell which one a column's type
/// annotation meant, and writing an import for the wrong one produces a
/// generated file that compiles against the wrong type.
Map<String, String> _declaredIn(ScanSources sources) {
  final declaredIn = <String, String>{};
  final ambiguous = <String>{};
  sources.units.forEach((path, unit) {
    for (final name in unit.declaredNames) {
      final existing = declaredIn[name];
      if (existing != null && existing != path) ambiguous.add(name);
      declaredIn[name] = path;
    }
  });
  for (final name in ambiguous) {
    declaredIn.remove(name);
  }
  return declaredIn;
}

/// What one column's value type needs imported, or why it cannot be written.
@immutable
class _Resolved {
  const _Resolved.ok(this.imports) : problem = null;
  const _Resolved.problem(this.problem) : imports = const <String>{};

  final Set<String> imports;
  final String? problem;
}

/// Turns a type name into the `import` a given package would write for it.
///
/// # Two spellings, and the engine already picks between them the same way
///
/// A name from the package's **own** `lib/` is imported by file -
/// `package:goo2d/src/data/transform.dart` - because that is what every
/// hand-written file under `goo2d/lib/src` does, and there is nothing private
/// about a package's own `src`.
///
/// A name from **another** package goes through that package's entry library -
/// `package:good/good.dart` - and never through its `src`. `camera.dart` opens
/// with exactly that line. Importing another package's `src` compiles and then
/// trips `implementation_imports`, which `flutter analyze` reports and CI fails
/// on, so a generated file spelled that way would be red in every package it
/// was written into.
///
/// The second spelling only works when the entry library actually exports the
/// name, which is a question about `export` directives and their combinators,
/// so this walks them. That walk is also what answers the case with no direct
/// dependency at all: `goo2d_physics_box2d` needs `Accessor`, which is declared
/// in `good`, and its pubspec names only `goo2d` - which re-exports the kernel.
/// `rigid_body.dart` reaches `Accessor` through `package:goo2d/goo2d.dart`, and
/// so does the file generated beside it.
class _Imports {
  _Imports({
    required Map<String, String> declaredIn,
    required Map<String, EnginePackage> byLibDir,
    required Map<String, ScannedUnit> units,
    required List<EnginePackage> packages,
  }) : this._(declaredIn, byLibDir, units, <String, EnginePackage>{
         for (final package in packages) package.name: package,
       });

  _Imports._(this._declaredIn, this._byLibDir, this._units, this._byName);


  final Map<String, String> _declaredIn;
  final Map<String, EnginePackage> _byLibDir;
  final Map<String, ScannedUnit> _units;
  final Map<String, EnginePackage> _byName;

  /// Each package's entry-library namespace, walked once per package.
  final Map<String, Map<String, String>> _namespaces =
      <String, Map<String, String>>{};

  /// The `package:` URIs [type] needs, or why [into] cannot name it.
  _Resolved importsFor(String type, EnginePackage into) {
    final imports = <String>{};
    for (final match in RegExp(r'[A-Za-z_$][A-Za-z0-9_$]*').allMatches(type)) {
      final name = match.group(0)!;
      if (_coreTypes.contains(name)) continue;
      final resolved = importFor(name, into);
      if (resolved.problem != null) return resolved;
      imports.addAll(resolved.imports);
    }
    return _Resolved.ok(imports);
  }

  /// The one import [into] would write to name [name].
  _Resolved importFor(String name, EnginePackage into) {
    final file = _declaredIn[name];
    if (file == null) {
      return _Resolved.problem(
        '$name is not declared in any package this pass reads, or is declared '
        'in more than one, so no import can be written for it',
      );
    }
    final owner = _packageOf(file, _byLibDir);
    if (owner == null) {
      return _Resolved.problem('$name is declared outside any package lib/');
    }
    if (owner.name == into.name) {
      return _Resolved.ok(<String>{
        'package:${owner.name}/${_posix(p.relative(file, from: owner.libDir))}',
      });
    }
    // The declaring package first, because naming where something comes from is
    // the clearest import to read, then whatever else `into` depends on - which
    // is what covers a re-export. Either way it has to be a *direct* dependency
    // or the import names a package the pubspec does not.
    for (final candidate in <String>[owner.name, ...into.dependencies]) {
      if (!into.dependencies.contains(candidate)) continue;
      if (!_exportsName(candidate, name)) continue;
      return _Resolved.ok(<String>{'package:$candidate/$candidate.dart'});
    }
    return _Resolved.problem(
      '$name is in package:${owner.name}, and nothing ${into.name} depends on '
      'exports it from its entry library',
    );
  }

  /// Whether `package:<package>/<package>.dart` exports [name].
  bool _exportsName(String package, String name) {
    final target = _byName[package];
    if (target == null) return false;
    return _namespaceOf(target).containsKey(name);
  }

  Map<String, String> _namespaceOf(EnginePackage package) =>
      _namespaces.putIfAbsent(package.name, () {
        final into = <String, String>{};
        _collectExports(p.normalize(package.barrel.path), into, <String>{});
        return into;
      });

  /// Adds the namespace of the library at [path] to [into].
  ///
  /// A library's namespace is what it declares plus, for each `export`,
  /// whatever that export lets through - so this walks `export` and stops at
  /// everything else. An `import` is not followed: importing a library does not
  /// re-export it, and following one would claim a generated file can name a
  /// type it cannot.
  void _collectExports(
    String path,
    Map<String, String> into,
    Set<String> seen,
  ) {
    if (!seen.add(path)) return;
    final unit = _units[path];
    if (unit == null) return;
    for (final name in unit.declaredNames) {
      into.putIfAbsent(name, () => path);
    }
    for (final export in unit.exports) {
      final target = _resolveUri(export.uri, from: path);
      if (target == null) continue;
      final nested = <String, String>{};
      _collectExports(target, nested, seen);
      nested.forEach((name, file) {
        if (export.shown.isNotEmpty && !export.shown.contains(name)) return;
        if (export.hidden.contains(name)) return;
        into.putIfAbsent(name, () => file);
      });
    }
  }

  /// Turns one directive URI into a path this pass may have read.
  String? _resolveUri(String uri, {required String from}) {
    if (uri.startsWith('dart:')) return null;
    if (uri.startsWith('package:')) {
      final rest = uri.substring('package:'.length);
      final slash = rest.indexOf('/');
      if (slash <= 0) return null;
      final target = _byName[rest.substring(0, slash)];
      if (target == null) return null;
      return p.normalize(p.join(target.libDir, rest.substring(slash + 1)));
    }
    if (uri.contains(':')) return null;
    return p.normalize(p.join(p.dirname(from), uri));
  }
}

/// The `dart:core` names a column's value type can be spelled with.
const Set<String> _coreTypes = <String>{
  'bool',
  'int',
  'double',
  'num',
  'String',
  'Object',
  'dynamic',
  'void',
  'Never',
  'List',
  'Set',
  'Map',
  'Iterable',
  'Duration',
  'DateTime',
};

/// Every name a generated property would lose to, as name to what declares it.
///
/// # Why this is a failure and every other gap here is not
///
/// A Dart extension member is reachable only where the receiver's own type has
/// no member of that name. `Accessor<T>` implements `Entity`, which implements
/// `int` - so a generated `int get sign` on it is not an error, not a warning,
/// and not reached: `entity<Foo>().sign` compiles, resolves to `int.sign`, and
/// hands back the sign of the entity *handle*. Reading a column would look
/// exactly like reading the handle, and nothing anywhere says so.
///
/// That is the one gap in this pass a compiler cannot catch, so it is the one
/// that stops the tool. An array column, a private field or a type in a package
/// this one does not depend on all fail at the use site with *"The getter isn't
/// defined"*, and a skip is safe there.
///
/// # Where the list comes from
///
/// `Accessor`'s and `Entity`'s own members are read out of the parse, not
/// transcribed. Both are declared in `struct.dart`, which is inside the scanned
/// packages, so this cannot fall behind the day `Entity` gains a member - which
/// a hand-written list would, silently, in exactly the direction that lets a
/// shadowed property through.
///
/// `int`'s members have to be written down: `dart:core` is not scanned and
/// parsing the SDK to find out that `int` has `sign` would be absurd. They are
/// fixed by the platform rather than by this repository, which is what makes
/// the copy safe here and not in the other direction.
Map<String, String> _reservedNames(ScanSources sources) {
  final reserved = <String, String>{};
  for (final name in _intMembers) {
    reserved[name] = 'int';
  }
  for (final name in sources.interfaceMembers['Entity'] ?? const <String>{}) {
    reserved[name] = 'Entity';
  }
  for (final name in sources.interfaceMembers['Accessor'] ?? const <String>{}) {
    reserved[name] = 'Accessor';
  }
  return reserved;
}

/// Every member an `int` has, and so every member an `Entity` has for free.
///
/// `Object`, `num`, `Comparable` and `int` itself. Operators are left out - no
/// field name can be one.
const Set<String> _intMembers = <String>{
  'hashCode',
  'noSuchMethod',
  'runtimeType',
  'toString',
  'abs',
  'ceil',
  'ceilToDouble',
  'clamp',
  'compareTo',
  'floor',
  'floorToDouble',
  'isFinite',
  'isInfinite',
  'isNaN',
  'isNegative',
  'remainder',
  'round',
  'roundToDouble',
  'sign',
  'toDouble',
  'toInt',
  'toStringAsExponential',
  'toStringAsFixed',
  'toStringAsPrecision',
  'truncate',
  'truncateToDouble',
  'bitLength',
  'gcd',
  'isEven',
  'isOdd',
  'modInverse',
  'modPow',
  'toRadixString',
  'toSigned',
  'toUnsigned',
};

/// What `good_tool` prints when a column's property would be shadowed.
String accessorCollisionMessage(AccessorScan scan) {
  final lines = StringBuffer()
    ..writeln(
      'A column would generate an accessor property that something else '
      'already answers to.',
    )
    ..writeln();
  for (final hit in scan.collisions) {
    lines
      ..writeln(
        '  ${hit.component}.${hit.column} would be '
        '${hit.component}.${hit.property}, and ${hit.owner} already has '
        '${hit.property}',
      )
      ..writeln('    ${hit.file}');
  }
  lines
    ..writeln()
    ..writeln(
      'A Dart extension member is reached only where the receiver has no '
      'member of that name, and Accessor implements Entity, which implements '
      'int. A property shadowed that way would compile, never be called, and '
      'every read of it would quietly return something about the entity handle '
      'instead of the column. A property colliding with a hand-written '
      'extension is louder - two applicable extensions declaring one member is '
      'an error at the use site - but it is an error in shipped code, raised '
      'nowhere near the column that caused it.',
    )
    ..writeln()
    ..writeln(
      'Rename the column. The property name follows it, so a column that keeps '
      'its component prefix and does not strip to a member of int is enough.',
    );
  return lines.toString();
}
