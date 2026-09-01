// Writing the `import` a generated file needs to name a type.
//
// Split out of `accessor_scan.dart` when the component-bit table (#18) turned
// out to need the same answer for one name - `GeneratedComponentBits`, which
// `goo2d_physics_box2d` reaches through `package:goo2d/goo2d.dart` because it
// depends on `goo2d` and not on `good`. One resolver, so the two generated
// files in a package cannot disagree about how that package spells an import.

import 'package:good_tool/src/engine_packages.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

// good_cli's `lib/src` is private by convention and this reaches into it, for
// the reason `accessor_scan.dart` states beside its own copy of this line.
// ignore: implementation_imports
import 'package:good_cli/src/generate/struct_scan.dart';

/// The package whose `lib/` holds [file].
EnginePackage? packageOf(String file, Map<String, EnginePackage> byLibDir) {
  final full = p.normalize(p.absolute(file));
  for (final entry in byLibDir.entries) {
    if (p.isWithin(entry.key, full)) return entry.value;
  }
  return null;
}

String posix(String path) => p.split(path).join('/');

/// Where each top-level name in the repository is declared.
///
/// A name two libraries both declare is left out rather than picked between.
/// This pass resolves nothing, so it cannot tell which one a column's type
/// annotation meant, and writing an import for the wrong one produces a
/// generated file that compiles against the wrong type.
Map<String, String> declaredIn(ScanSources sources) {
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
class ResolvedImport {
  const ResolvedImport.ok(this.imports) : problem = null;
  const ResolvedImport.problem(this.problem) : imports = const <String>{};

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
class Imports {
  Imports({
    required Map<String, String> declaredIn,
    required Map<String, EnginePackage> byLibDir,
    required Map<String, ScannedUnit> units,
    required List<EnginePackage> packages,
  }) : this._(declaredIn, byLibDir, units, <String, EnginePackage>{
         for (final package in packages) package.name: package,
       });

  Imports._(this.declaredIn, this._byLibDir, this._units, this._byName);


  final Map<String, String> declaredIn;
  final Map<String, EnginePackage> _byLibDir;
  final Map<String, ScannedUnit> _units;
  final Map<String, EnginePackage> _byName;

  /// Each package's entry-library namespace, walked once per package.
  final Map<String, Map<String, String>> _namespaces =
      <String, Map<String, String>>{};

  /// The `package:` URIs [type] needs, or why [into] cannot name it.
  ResolvedImport importsFor(String type, EnginePackage into) {
    final imports = <String>{};
    for (final match in RegExp(r'[A-Za-z_$][A-Za-z0-9_$]*').allMatches(type)) {
      final name = match.group(0)!;
      if (coreTypes.contains(name)) continue;
      final resolved = importFor(name, into);
      if (resolved.problem != null) return resolved;
      imports.addAll(resolved.imports);
    }
    return ResolvedImport.ok(imports);
  }

  /// The one import [into] would write to name [name].
  ResolvedImport importFor(String name, EnginePackage into) {
    final file = declaredIn[name];
    if (file == null) {
      return ResolvedImport.problem(
        '$name is not declared in any package this pass reads, or is declared '
        'in more than one, so no import can be written for it',
      );
    }
    final owner = packageOf(file, _byLibDir);
    if (owner == null) {
      return ResolvedImport.problem('$name is declared outside any package lib/');
    }
    if (owner.name == into.name) {
      return ResolvedImport.ok(<String>{
        'package:${owner.name}/${posix(p.relative(file, from: owner.libDir))}',
      });
    }
    // The declaring package first, because naming where something comes from is
    // the clearest import to read, then whatever else `into` depends on - which
    // is what covers a re-export. Either way it has to be a *direct* dependency
    // or the import names a package the pubspec does not.
    for (final candidate in <String>[owner.name, ...into.dependencies]) {
      if (!into.dependencies.contains(candidate)) continue;
      if (!_exportsName(candidate, name)) continue;
      return ResolvedImport.ok(<String>{'package:$candidate/$candidate.dart'});
    }
    return ResolvedImport.problem(
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
const Set<String> coreTypes = <String>{
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
