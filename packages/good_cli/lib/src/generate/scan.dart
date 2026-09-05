// The pre-`ClassBody` AST - `MixinDeclaration.name`,
// `ExtensionTypeDeclaration.representation`, `NamedCompilationUnitMember` - is
// deprecated in analyzer 10, and only some of it has a replacement there.
// `ClassDeclaration` and `EnumDeclaration` have gained `namePart`;
// `MixinDeclaration` has not - probed against 10.2.0, "The getter 'namePart'
// isn't defined for the type 'MixinDeclaration'". Every component in this
// repository is a mixin, so writing the new spelling for classes and the old
// one for mixins would read two ASTs to answer one question. The migration is
// the analyzer 11 bump, which drops the old names in the release that finishes
// the new ones - see good_tool/pubspec.yaml and #348.
//
// The one member of it this file does *not* use is `.members`, and that is a
// defect and not a deprecation: see `_members`.
// ignore_for_file: deprecated_member_use

// One pass over a set of `lib/` directories, and every question the generators
// ask answered off the result of it.
//
// This replaces five separate scanners that each walked their own trees and
// disagreed with each other about how to read them. Two of them lived here,
// three in `good_tool`, and between them they held three parsers, two answers
// to "does this file honour `primary-constructors`", and one pair that resolved
// where the other parsed. #348 was a file that failed to parse in three of them
// and could not fail in the fourth, and nothing in either package could have
// noticed the split.
//
// So: one walk, one parser, one model. [readSources] reads; everything below it
// is a pure function of what it read, and adding a sixth question costs a
// function rather than a sixth walk.
//
// # Why it resolves
//
// The scan asks the analyzer what a field *is* and keys on the answer.
// `final hp = Field.float64();` holds a `DataPointer<double>` because the
// element model says so, not because a pattern here recognised `Field.float64`
// as a dotted static.
//
// What that replaced was three layers of expression matching, each one added
// after a declaration had gone missing: a dotted static, then a builder chain,
// then a bare constructor call. Every layer had a fourth shape behind it, and
// the fourth was a cascade. `Track.of<double>(0)..hashCode` is a
// `CascadeExpression`; the chain walk followed `MethodInvocation` alone, so it
// read an empty chain and the field was neither collected, nor refused, nor
// listed anywhere. Silence is the one outcome this design exists to prevent,
// and a rule derived from the shape of an expression never stops producing it.
//
// # What resolution costs, and what it demands back
//
// Roughly twenty times the walk. Parsing alone read this repository's files at
// about 7ms each; resolving them takes tens of seconds, and `good build` runs
// `good generate` every time, so it is paid on every build rather than on a
// tool run somebody chose to make.
//
// It also demands a resolved checkout, which is what made it too expensive to
// be wrong about. `package:good/good.dart` resolves through a
// `.dart_tool/package_config.json`; without one, every column in this
// repository comes back `InvalidType` and nothing throws - the run finds no
// declarations, reports success, and `--check` calls every committed file
// stale, which run without `--check` deletes every generated accessor and lays
// out every row wrong.
//
// So an unresolved read is refused rather than answered.
// [ScanSources.unresolvedUris] carries every URI the analyzer could not find
// and [unresolvedUriMessage] names them; a mode that reports a count asks for
// them first, because "no declarations" and "I could not read the engine" are
// otherwise the same sentence.
//
// A file in the read set may sit outside every context the collection built -
// an engine package installed in the pub cache carries no `.dart_tool/` of its
// own. Those resolve through the context of the directory the walk was asked
// about, which is the one whose package config names them; see [readSources].
//
// The language version and its experiments are still pinned here rather than
// inherited, and #348 is still the reason - see [scanFeatureSet], which now
// overrides each context's feature set instead of feeding `parseString`. A
// file that still does not parse lands in [ScanSources.unparsed], so a caller
// fails the run rather than reporting a clean pass over a tree it read a
// fraction of.

import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context.dart';
import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/diagnostic/diagnostic.dart';
import 'package:analyzer/error/error.dart';
// The two things the public `AnalysisContextCollection` factory has no
// parameter for: which feature set a context analyses with, and the type it
// is handed as. See [scanFeatureSet] for why this walk has to say.
// ignore: implementation_imports
import 'package:analyzer/src/dart/analysis/analysis_context_collection.dart';
// ignore: implementation_imports
import 'package:analyzer/src/dart/analysis/analysis_options.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';

import 'package:good_cli/src/generate/assets.dart';
import 'package:good_cli/src/generate/engine_dependency.dart';

/// The language every file in the walk is analysed as.
///
/// Pinned rather than read out of each package's `analysis_options.yaml`, and
/// that is not the choice it looks like. An `enable-experiment:` entry for a
/// feature with no experimental release version - `primary-constructors` is
/// one - takes effect only for a library whose language version is *exactly*
/// the analyzer's own (`restrictEnableFlagsToVersion`, `version ==
/// sdkLanguageVersion`). `analyzer` 10.2.0's is **3.12.0** and every package
/// here declares `sdk: ^3.13.0`, so the entry those files already carry is
/// dropped and three of them fail to parse. `flutter analyze` does not see it,
/// because it runs the analyzer built into the SDK, whose version matches.
///
/// Measured against this repository at the analyzer constraint in
/// `good_cli/pubspec.yaml`: `collider.dart`, `render_2d.dart` and
/// `effector.dart`, six `experiment_not_enabled` between them and no other
/// diagnostic. That is the same #348 shape as before - a file the run reads a
/// fraction of - reached by a different route.
///
/// So the version is named here, and raising it is the deliberate edit made
/// when the repository starts using something newer. It goes away when the
/// analyzer constraint moves to a release whose own version is the one these
/// pubspecs ask for.
final FeatureSet scanFeatureSet = FeatureSet.fromEnableFlags2(
  sdkLanguageVersion: Version(3, 13, 0),
  flags: const <String>['primary-constructors', 'dot-shorthands'],
);

// ---------------------------------------------------------------------------
// The model
// ---------------------------------------------------------------------------

/// One `export` directive, with whatever its combinators let through.
@immutable
class ScannedExport {
  const ScannedExport({
    required this.uri,
    required this.shown,
    required this.hidden,
  });

  final String uri;
  final Set<String> shown;
  final Set<String> hidden;
}

/// One `import` directive, with whatever its combinators let through.
///
/// Held apart from [ScannedExport] because the two answer different
/// questions. An export decides what a library *publishes*, which is what
/// `Imports` walks to write a generated import; an import decides what a
/// library can *name*, which is what [LibraryScopes] walks to resolve a
/// written one.
@immutable
class ScannedImport {
  const ScannedImport({
    required this.uri,
    required this.prefix,
    required this.shown,
    required this.hidden,
  });

  final String uri;

  /// The `as p` name, or null.
  ///
  /// Recorded so a prefixed import can be left out of a scope. Its names are
  /// reachable only as `p.Name`, and every name this scan resolves is written
  /// bare - a supertype, a field's value type - so counting them would let a
  /// library name something it cannot.
  final String? prefix;

  final Set<String> shown;
  final Set<String> hidden;
}

/// One field or top-level variable, and what the analyzer says it holds.
///
/// [valueType] is the whole of the answer to "is this a declaration", and it
/// is the analyzer's, not this walk's: `final hp = Field.float64();` and
/// `late final DataPointer<double> hp = ...;` reach it the same way, and so
/// does a typedef, a builder chain and a cascade. Nothing here reads the
/// initialiser's spelling to decide what the field is.
///
/// Two things are still read off the initialiser, and neither of them is a
/// type. [isBareConstruction] is what the `@sub` rule is about - how the line
/// reads to a person - and [readsFields] is what a `late` initialiser touches
/// on the way to its value, which is what closes a `LateInitializationError`
/// ring.
@immutable
class ScannedField {
  const ScannedField({
    required this.name,
    required this.valueType,
    required this.valueTypeProblem,
    required this.annotations,
    required this.isStatic,
    required this.isLate,
    required this.hasInitializer,
    required this.isBareConstruction,
    required this.readsFields,
  });

  final String name;

  /// The type the analyzer says the field holds - `InitialPointer<double>`,
  /// `Query`, `Stopwatch` - or null where it could not name one.
  ///
  /// Null is the loud answer and not a quiet one. It means the element model
  /// came back with `InvalidType` or with nothing at all, which in practice
  /// means the file's imports did not resolve - and a field whose type is
  /// unknown is reported rather than being called "not a declaration". See
  /// [ScanSources.unresolvedUris] for the run-level half of the same fact.
  final String? valueType;

  /// What the analyzer said about this declaration when it could not type it,
  /// or null when it could.
  ///
  /// Its own diagnostics rather than a sentence written here. The walk knows
  /// only that the type is unknown; the analyzer knows that `withEverything`
  /// is not a method on `QueryBuilder`, or that `package:good/good.dart` was
  /// not found - and those are two entirely different edits by the person
  /// reading the report. Everything overlapping the declaration, so a chain
  /// that stops half way names the link it stopped at.
  final String? valueTypeProblem;

  /// The annotations written on it, in source order, each as it was written -
  /// `system`, `LoadBefore(PhysicsSystem)`.
  ///
  /// Whole source and not just the name: an annotation the scan carries into
  /// generated output has to be re-emitted, arguments included, and a name
  /// alone cannot say what `@LoadBefore(PhysicsSystem)` meant. [annotationName]
  /// takes the head back off when only that is wanted.
  final List<String> annotations;

  final bool isStatic;

  /// Whether it is written `late`.
  ///
  /// A `late` field with an initialiser is allowed and is how a declaration
  /// reaches `this`; a `late` field without one is the half of a double
  /// declaration this walk can see. So this is read together with
  /// [hasInitializer] and never on its own - see `scanDeclarations`.
  final bool isLate;

  /// Whether it has an initialiser at its declaration.
  ///
  /// A `late final X x;` with no initialiser is filled in from somewhere the
  /// declaration does not say - a `describeX` body, a constructor. This walk
  /// deliberately does not go looking for the other half; one half is enough
  /// to refuse.
  final bool hasInitializer;

  /// Whether the initialiser is, at its head, a call to an unnamed
  /// constructor - `Barrel()`, `Barrel()..tune()`.
  ///
  /// The head after cascades, chained calls and property accesses are peeled
  /// off, because `Turret().tuned()` still reads as a constructor call to
  /// whoever wrote the line and the marker rule is about how the line reads.
  /// A named constructor is not one: `Entity.pack(...)` is dotted, and a
  /// dotted head says what it is where it is written.
  ///
  /// Resolved and not guessed. `Barrel()` parses as a `MethodInvocation` and
  /// only becomes an `InstanceCreationExpression` once the analyzer has said
  /// that `Barrel` is a class, which is why a parse could never tell it from
  /// a call to a top-level function without a table of class names.
  final bool isBareConstruction;

  /// The names of the owning class's own instance fields this field's
  /// initialiser reads.
  ///
  /// Only a `late` initialiser can have any - a plain field initialiser
  /// cannot reach `this` at all - and a ring in them is a
  /// `LateInitializationError` that names nothing at run time.
  final Set<String> readsFields;

  bool get isPrivate => name.startsWith('_');
}

/// The head of an annotation as it was written - `LoadBefore` out of
/// `LoadBefore(PhysicsSystem)`, `system` out of `system`.
String annotationName(String annotation) {
  final open = annotation.indexOf('(');
  final head = open < 0 ? annotation : annotation.substring(0, open);
  final dot = head.indexOf('.');
  return (dot < 0 ? head : head.substring(0, dot)).trim();
}

/// One method, reduced to what the generators ask about.
@immutable
class ScannedMethod {
  const ScannedMethod({
    required this.name,
    required this.isStatic,
    required this.annotations,
    required this.isEmptyBody,
    required this.callsSuper,
    required this.registeredTypes,
  });

  final String name;
  final bool isStatic;

  /// The names of the annotations written on it - `override`, `mustCallSuper`.
  final Set<String> annotations;

  /// Whether it has no body at all, or one holding no statements.
  ///
  /// What separates `void describeAssets(AssetDescriptor descriptor) {}` - a
  /// base declaration that does nothing and has nothing to chain to - from an
  /// override that does something and drops the chain.
  final bool isEmptyBody;

  /// Whether the body calls `super.<name>(...)`.
  final bool callsSuper;

  /// The `T`s of every `<descriptor>.has<T>()` in the body, where
  /// `<descriptor>` is this method's own first parameter.
  ///
  /// Restricted to that receiver on purpose. `hierarchy.dart` writes
  /// `child.has<Child>()` and `ancestor.has<Child>()` as ordinary runtime
  /// tests, and a scan that counted every `has<T>()` it saw would assign a
  /// component bit for each of them.
  final List<String> registeredTypes;
}

/// One class, mixin, enum or extension type, as it is written.
@immutable
class ScannedType {
  const ScannedType({
    required this.name,
    required this.path,
    required this.typeParameters,
    required this.supertypes,
    required this.superclass,
    required this.mixins,
    required this.isAbstract,
    required this.fields,
    required this.methods,
    required this.referencedNames,
    required this.assetIdentifiers,
    required this.representationName,
  });

  final String name;

  /// Its own type parameter names, in order, and empty when it has none.
  ///
  /// What separates `_OneOff<T>` from `_OneOff` at the one place it matters:
  /// a generated table keyed by the type literal `_OneOff` holds
  /// `_OneOff<EntityStruct>`, and an instance's `runtimeType` is
  /// `_OneOff<Barrel>`, so the two never compare equal. See
  /// `DeclarationCollector.generic`.
  final List<String> typeParameters;

  /// The file it is declared in, normalised and absolute.
  final String path;

  /// Every name in its `extends`, `on`, `with` and `implements` clauses.
  ///
  /// Flattened into one list because the question asked of it is only ever
  /// "does `Component` sit above this", and all four clauses carry that
  /// upwards. [superclass] and [mixins] are those same names again, kept
  /// apart, for the one question that does distinguish them.
  final List<String> supertypes;

  /// The name written in `extends`, or null.
  ///
  /// Held apart from [supertypes] because construction order is not a set.
  /// Dart runs a class's own field initialisers first, then each mixin
  /// application's - last in the `with` clause first - then the superclass's,
  /// recursively; `collectDeclarations` has to hand a class's declarations
  /// over in exactly that order, because that order is the row layout. See
  /// `_SceneDescriptor`'s doc in `good`.
  ///
  /// A mixin's `on` clause is not this. It constrains what the mixin may be
  /// applied to, and the type named there is initialised by the applying
  /// class's own chain rather than by the mixin - which is why
  /// `mixin WorldTransform2D on Component` contributes its own fields and
  /// none of `Component`'s.
  final String? superclass;

  /// The names written in the `with` clause, in the order they are written.
  ///
  /// Written order and not construction order: reversing it is the reader's
  /// job, and doing it here would leave a list whose name says one thing and
  /// whose contents say another.
  final List<String> mixins;

  /// Whether nothing can ever be an instance of exactly this.
  ///
  /// True for `abstract` and `sealed` classes and for every `mixin`, which is
  /// the same question as "can this be a `runtimeType`". A collector is
  /// looked up by one, so a table holding an entry for `Transform2D` would
  /// hold a line nothing can reach.
  final bool isAbstract;

  final List<ScannedField> fields;
  final Map<String, ScannedMethod> methods;

  /// Every identifier written anywhere in the declaration.
  ///
  /// What answers "does this scene mention that prefab" without resolving
  /// anything - see [scanScenes].
  final Set<String> referencedNames;

  /// The names in every `Textures.x` and `Audios.x` written in the body.
  final Set<String> assetIdentifiers;

  /// An extension type's representation field name, or null.
  final String? representationName;

  /// The member names an extension on this type would lose to.
  Set<String> get memberNames => <String>{
    for (final field in fields) field.name,
    ...methods.keys,
    ?representationName,
  };
}

/// One parsed file, and the facts every generator reads off it.
@immutable
class ScannedUnit {
  const ScannedUnit({
    required this.path,
    required this.declaredNames,
    required this.imports,
    required this.exports,
    required this.types,
    required this.variables,
  });

  /// The file, normalised and absolute.
  final String path;

  /// Every top-level name it declares.
  final Set<String> declaredNames;

  /// Its `import` directives, in the order they are written.
  ///
  /// What a name written in this file is allowed to mean. `_Quad` is declared
  /// in three files under `goo2d/test`, so which one a line naming it means is
  /// settled by what that line's own library imported and by nothing else.
  final List<ScannedImport> imports;

  final List<ScannedExport> exports;
  final List<ScannedType> types;

  /// Its top-level variables, read the same way a field is.
  ///
  /// Recorded because a declaration held by one is refused, and refusing it
  /// needs the same three facts a field's refusal does - the written type, the
  /// factory that produced the value, and whether it is `late`. A top-level
  /// variable is `late` whether or not the word is written: Dart initialises
  /// every one of them lazily, so the first read is what runs the initialiser,
  /// and that is a different moment on every isolate.
  final List<ScannedField> variables;
}

/// Everything one walk read.
@immutable
class ScanSources {
  const ScanSources({
    required this.units,
    required this.unparsed,
    required this.unresolvedUris,
  });

  /// Keyed by normalised absolute path.
  final Map<String, ScannedUnit> units;

  /// Every file the parser reported a diagnostic on, as an absolute path.
  ///
  /// Carried rather than thrown, because the caller decides what a file it
  /// could not read means. It means the run checked less than it was pointed
  /// at, and the mode that has one exits on it - see #348 for what reporting it
  /// as a warning cost.
  final List<String> unparsed;

  /// Every directive URI the analyzer could not find, keyed by the file that
  /// writes it, as normalised absolute paths.
  ///
  /// This is the loud half of resolving. A file whose `package:good/good.dart`
  /// does not resolve still parses, still declares its classes, and answers
  /// `InvalidType` for every field in it - so the walk reads the whole tree,
  /// finds no declaration anywhere, and reports a clean run over nothing. That
  /// failure is silent by construction and cannot be caught downstream: an
  /// empty answer and a correct answer are the same shape.
  ///
  /// So it is carried here, and a mode that reports a count says this first;
  /// see [unresolvedUriMessage] and [ScanSources.resolves].
  final Map<String, List<String>> unresolvedUris;

  /// Whether every file the walk read resolved.
  bool get resolves => unresolvedUris.isEmpty;

  /// Every type declared anywhere in the walk, keyed by name.
  ///
  /// A name two files both declare keeps the first in path order. Only the
  /// supertype walk goes through this map; every other pass holds the
  /// [ScannedType] it found in the unit it found it in, so an ambiguous name
  /// cannot send a column to the wrong component.
  Map<String, ScannedType> get typesByName {
    final byName = <String, ScannedType>{};
    final paths = units.keys.toList()..sort();
    for (final path in paths) {
      for (final type in units[path]!.types) {
        byName.putIfAbsent(type.name, () => type);
      }
    }
    return byName;
  }
}

/// The file one directive URI names, or null where this walk cannot say.
///
/// [libDirs] maps a package name to that package's `lib/`. A `dart:` URI, a
/// relative one climbing out of the trees read, and a `package:` URI naming
/// something not in [libDirs] all answer null - the walk did not read them, so
/// anything it said about the names in them would be made up.
String? resolveDirectiveUri(
  String uri, {
  required String from,
  required Map<String, String> libDirs,
}) {
  if (uri.startsWith('package:')) {
    final rest = uri.substring('package:'.length);
    final slash = rest.indexOf('/');
    if (slash <= 0) return null;
    final lib = libDirs[rest.substring(0, slash)];
    if (lib == null) return null;
    return p.normalize(p.join(lib, rest.substring(slash + 1)));
  }
  if (uri.contains(':')) return null;
  return p.normalize(p.join(p.dirname(from), uri));
}

/// What one library resolves a written name to, laid over the map a pass
/// already walks with.
///
/// # Two questions that look alike
///
/// **A name written in a file** means whatever that file declared or imported.
/// `_Quad` is declared in three files under `goo2d/test` and one of them is a
/// struct, so a map keyed by name alone answers with whichever came first in
/// path order and the other two libraries get somebody else's class.
///
/// **A supertype two links up** is reached from a library that never imported
/// it. `A extends B` in one file and `B extends C` in another says nothing
/// about `C` being in scope where `A` is written, and it does not have to be.
///
/// So this is a layer and not an answer. Narrowing a pass to one library's
/// imports gets the first question right and loses the top of every chain;
/// what [over] does is keep the pass's own map underneath for the second
/// question and let the library's own view win the first.
///
/// # What the library's own view holds
///
/// Its own types, then everything its `import` directives reach - followed
/// through `export`, and through those libraries' own imports in turn. Wider
/// than Dart's scope at that last step, on purpose: what the walk wants here
/// is a superclass chain, and a fixture's crosses libraries the bottom of it
/// never imported. Narrow where it counts - a library that reaches nothing of
/// another gets nothing of it, so one file's `_Scene` is never flattened
/// through another file's mixins.
///
/// A prefixed import contributes nothing. Its names are reachable only as
/// `p.Name`, and every name resolved off this is written bare.
class LibraryScopes {
  LibraryScopes(ScanSources sources) : _units = sources.units;

  final Map<String, ScannedUnit> _units;
  final Map<String, Map<String, ScannedType>> _scopes =
      <String, Map<String, ScannedType>>{};
  final Map<String, Map<String, ScannedType>> _namespaces =
      <String, Map<String, ScannedType>>{};
  final Map<String, Set<String>> _closures = <String, Set<String>>{};
  Map<String, String>? _libDirs;

  /// The types the library at [path] can name, its own winning.
  Map<String, ScannedType> scopeOf(String path) =>
      _scopes.putIfAbsent(path, () {
        final scope = <String, ScannedType>{};
        final reached = <String>{};
        _reach(path, scope, reached);
        _closures[path] = reached;
        return scope;
      });

  /// Every library the one at [path] reaches, itself included.
  ///
  /// The same walk [scopeOf] makes, answered as files rather than as names -
  /// which is what says *whose* generated table a fixture part has to name. A
  /// package's pubspec cannot say it: `goo2d` does not depend on
  /// `goo2d_physics_box2d` and a fixture under `goo2d/example` imports it
  /// anyway.
  ///
  /// Holds a path the walk resolved and did not read - a generated file left
  /// out of it, say. It still names the package it is in, which is the only
  /// thing asked of it here.
  Set<String> closureOf(String path) {
    scopeOf(path);
    return _closures[path]!;
  }

  /// Every package a library in [path]'s closure imports and this walk read
  /// no `lib/` for.
  ///
  /// The names a name could have come from, for a pass that has a name it
  /// could not resolve and nothing else to say about it. It is a candidate
  /// list and not an answer - an import carries no promise about which of
  /// its names a line meant - but it is the list the caller is looking at,
  /// and the alternative is reporting a bare identifier that nobody can act
  /// on.
  ///
  /// A prefixed import is in it, unlike in [scopeOf]. There the question is
  /// what a bare name may mean and a prefixed import answers nothing; here it
  /// is which package went unread, and one imported behind a prefix went
  /// unread just the same.
  Set<String> unreadPackagesOf(String path) {
    final unread = <String>{};
    for (final file in closureOf(path)) {
      for (final import in _units[file]?.imports ?? const <ScannedImport>[]) {
        if (!import.uri.startsWith('package:')) continue;
        final rest = import.uri.substring('package:'.length);
        final slash = rest.indexOf('/');
        if (slash <= 0) continue;
        final name = rest.substring(0, slash);
        if (_packageLibDirs.containsKey(name)) continue;
        unread.add(name);
      }
    }
    return unread;
  }

  /// [scopeOf] over [base], for a pass that has to keep its own map.
  ///
  /// [base] itself comes back where the library disagrees with it about
  /// nothing, which is every file declaring no name a second library declares
  /// too - nearly all of them, and the reason this is not a copy per file.
  Map<String, ScannedType> over(Map<String, ScannedType> base, String path) {
    final scope = scopeOf(path);
    for (final entry in scope.entries) {
      if (identical(base[entry.key], entry.value)) continue;
      return <String, ScannedType>{...base, ...scope};
    }
    return base;
  }

  void _reach(String path, Map<String, ScannedType> into, Set<String> seen) {
    if (!seen.add(path)) return;
    final unit = _units[path];
    if (unit == null) return;
    for (final entry in _namespaceOf(path).entries) {
      into.putIfAbsent(entry.key, () => entry.value);
    }
    for (final import in unit.imports) {
      if (import.prefix != null) continue;
      final target = resolveDirectiveUri(
        import.uri,
        from: path,
        libDirs: _packageLibDirs,
      );
      if (target == null) continue;
      if (import.shown.isEmpty && import.hidden.isEmpty) {
        _reach(target, into, seen);
        continue;
      }
      final nested = <String, ScannedType>{};
      _reach(target, nested, seen);
      nested.forEach((name, type) {
        if (import.shown.isNotEmpty && !import.shown.contains(name)) return;
        if (import.hidden.contains(name)) return;
        into.putIfAbsent(name, () => type);
      });
    }
  }

  /// What the library at [path] declares, plus what its exports let through.
  Map<String, ScannedType> _namespaceOf(String path) =>
      _namespaces.putIfAbsent(path, () {
        final namespace = <String, ScannedType>{};
        _collectExports(path, namespace, <String>{});
        return namespace;
      });

  void _collectExports(
    String path,
    Map<String, ScannedType> into,
    Set<String> seen,
  ) {
    if (!seen.add(path)) return;
    final unit = _units[path];
    if (unit == null) return;
    for (final type in unit.types) {
      into.putIfAbsent(type.name, () => type);
    }
    for (final export in unit.exports) {
      final target = resolveDirectiveUri(
        export.uri,
        from: path,
        libDirs: _packageLibDirs,
      );
      if (target == null) continue;
      final nested = <String, ScannedType>{};
      _collectExports(target, nested, seen);
      nested.forEach((name, type) {
        if (export.shown.isNotEmpty && !export.shown.contains(name)) return;
        if (export.hidden.contains(name)) return;
        into.putIfAbsent(name, () => type);
      });
    }
  }

  /// Every package whose `lib/` the walk read, to that directory.
  ///
  /// Off the pubspec beside each `lib/` a scanned file sits under, rather than
  /// off a package list handed in: `goo2d/example` is a package of its own,
  /// its files name each other `package:goo2d_example/...`, and it is a
  /// fixture root rather than anything the tool generates into.
  Map<String, String> get _packageLibDirs =>
      _libDirs ??= _readPackageLibDirs(_units.keys);
}

Map<String, String> _readPackageLibDirs(Iterable<String> paths) {
  final byName = <String, String>{};
  final examined = <String>{};
  for (final path in paths) {
    var dir = p.dirname(path);
    while (true) {
      final parent = p.dirname(dir);
      if (parent == dir) break;
      if (p.basename(dir) == 'lib' && examined.add(dir)) {
        final facts = readPubspecFacts(File(p.join(parent, 'pubspec.yaml')));
        final name = facts?.name;
        if (name != null) byName.putIfAbsent(name, () => dir);
      }
      dir = parent;
    }
  }
  return byName;
}

// ---------------------------------------------------------------------------
// The walk
// ---------------------------------------------------------------------------

/// Parses every `.dart` file under the roots and records what is in it.
///
/// [rootOverride] names the directories to walk. Without it the walk is [dir]'s
/// own `lib/` plus the `lib/` of every engine package [dir] resolves - which is
/// what a scan of somebody's *project* wants, since `Component` and `Field` are
/// declared in `good` and a project read on its own would find no components at
/// all. A project that has never been resolved contributes only its own `lib/`,
/// and that is enough for every check that reads names rather than types.
///
/// Engine packages, not every resolved package, for the reason `enginePackages`
/// gives about the same choice: `flutter` alone is more source than everything
/// else put together, `sky_engine` holds a file this parser cannot read, and
/// none of it declares a component. Measured over `goo2d/example`, widening it
/// to everything resolved adds one unparsed file and nothing else.
///
/// [exclude] drops individual files. A generator must not read its own output:
/// `accessors.g.dart` is an ordinary hand-written extension on the next run, so
/// a run that read it reported every property it would write as colliding with
/// itself.
Future<ScanSources> readSources(
  Directory dir, {
  List<String>? rootOverride,
  Set<String> exclude = const <String>{},
}) async {
  final home = p.normalize(p.absolute(dir.path));
  final roots = <String>[];
  if (rootOverride != null) {
    for (final root in rootOverride) {
      roots.add(p.normalize(p.absolute(root)));
    }
  } else {
    roots.add(p.normalize(p.absolute(p.join(dir.path, 'lib'))));
    final resolved = resolvedPackages(dir);
    final engine = EngineDependencies(
      roots: <String, Directory>{
        for (final package in resolved.values) package.name: package.root,
      },
    );
    for (final package in resolved.values) {
      if (!engine.contains(package.name)) continue;
      final lib = p.normalize(p.absolute(package.lib));
      if (Directory(lib).existsSync()) roots.add(lib);
    }
  }
  final skip = <String>{
    for (final path in exclude) p.normalize(p.absolute(path)),
  };

  final files = <String>[];
  for (final root in <String>{...roots}) {
    final directory = Directory(root);
    if (!directory.existsSync()) continue;
    // Links are listed and never followed. `goo2d/example/windows/flutter/
    // ephemeral/.plugin_symlinks/` links back to packages this walk already
    // reads, so following it reads those packages a second time under a path
    // that is inside nobody's package config - every file of them unresolved,
    // and the run refused over source it had already read correctly.
    final found = <String>[
      for (final entry in directory.listSync(
        recursive: true,
        followLinks: false,
      ))
        if (entry is File && entry.path.endsWith('.dart'))
          p.normalize(p.absolute(entry.path)),
    ]..sort();
    files.addAll(found);
  }

  final collection = AnalysisContextCollectionImpl(
    includedPaths: _includedPaths(home, roots),
    updateAnalysisOptions4: ({required AnalysisOptionsImpl analysisOptions}) {
      analysisOptions.contextFeatures = scanFeatureSet;
    },
  );
  final units = <String, ScannedUnit>{};
  final unparsed = <String>[];
  final unresolvedUris = <String, List<String>>{};
  try {
    final fallback = collection.contextFor(home);
    for (final path in files) {
      if (skip.contains(path)) continue;
      if (units.containsKey(path)) continue;
      // A package the walk reads that no context covers - an engine package
      // installed in the pub cache, which carries no `.dart_tool/` of its own
      // and so is nobody's context root. The directory this walk was asked
      // about is the one whose package config names it, so its context is the
      // one that can resolve the file.
      final AnalysisContext context = _contextFor(collection, path, fallback);
      final resolved = await context.currentSession.getResolvedUnit(path);
      if (resolved is! ResolvedUnitResult) {
        unparsed.add(path);
        continue;
      }
      // Syntactic alone, because a semantic error is what an unresolved
      // package produces by the hundred and it says nothing about whether the
      // file was read. #348 is a file the parser gave up on, and that is this.
      final syntactic = resolved.diagnostics.where(
        (diagnostic) =>
            diagnostic.diagnosticCode.type == DiagnosticType.SYNTACTIC_ERROR,
      );
      if (syntactic.isNotEmpty) {
        unparsed.add(path);
        continue;
      }
      final missing = _missingImports(resolved);
      if (missing.isNotEmpty) unresolvedUris[path] = missing;
      units[path] = _readUnit(path, resolved.unit, resolved.diagnostics);
    }
  } finally {
    await collection.dispose();
  }
  return ScanSources(
    units: units,
    unparsed: unparsed,
    unresolvedUris: unresolvedUris,
  );
}

/// The context that reads [path], or [fallback] where none of them covers it.
AnalysisContext _contextFor(
  AnalysisContextCollection collection,
  String path,
  AnalysisContext fallback,
) {
  try {
    return collection.contextFor(path);
  } on StateError {
    return fallback;
  }
}

/// The directories an [AnalysisContextCollection] is opened over.
///
/// [home] always, because it is the directory whose package config resolves
/// whatever the walk reads from outside the trees it was given. Each root's
/// own package as well, but only where that package carries a
/// `.dart_tool/package_config.json`: a directory without one becomes a context
/// that resolves nothing, and every file under it would then answer
/// `InvalidType` while a context that *could* have read it sat unused.
///
/// Nested paths are dropped rather than passed through. The collection groups
/// included paths into contexts by walking up for a package, so two paths
/// inside one package are one context said twice.
List<String> _includedPaths(String home, List<String> roots) {
  final included = <String>{home};
  for (final root in roots) {
    final package = _packageRootOf(root);
    if (package == null) continue;
    if (!File(
      p.join(package, '.dart_tool', 'package_config.json'),
    ).existsSync()) {
      continue;
    }
    included.add(package);
  }
  final sorted = included.toList()..sort();
  return <String>[
    for (final path in sorted)
      if (!sorted.any(
        (other) => other != path && p.isWithin(other, path),
      ))
        path,
  ];
}

/// The nearest directory at or above [from] holding a `pubspec.yaml`.
String? _packageRootOf(String from) {
  var dir = from;
  while (true) {
    if (File(p.join(dir, 'pubspec.yaml')).existsSync()) return dir;
    final parent = p.dirname(dir);
    if (parent == dir) return null;
    dir = parent;
  }
}

/// The URIs [resolved]'s `import` and `export` directives name and the
/// analyzer could not find.
///
/// Imports and exports only, and the exclusion is the point. A `part` this
/// walk cannot find is ordinarily one it is about to **write**: `--tests`
/// reads a fixture library whose generated part is the thing the run
/// produces, so counting those would refuse every new fixture at the run that
/// was going to create it. A missing part leaves the names *it* declares
/// undefined and types the rest of the library as usual, so a declaration
/// caught by it is reported by name with the analyzer's own reason - loud, and
/// in the right place.
///
/// An import that does not resolve is the other thing entirely. It leaves
/// every field in the file typed `InvalidType`, so nothing is a declaration,
/// nothing is refused, and the run writes that as the answer.
///
/// Found through the diagnostic's offset rather than through the directive's
/// own resolution, because a directive naming a URI the analyzer never found
/// carries no element to ask.
List<String> _missingImports(ResolvedUnitResult resolved) {
  final directives = <Directive>[
    for (final directive in resolved.unit.directives)
      if (directive is ImportDirective || directive is ExportDirective)
        directive,
  ];
  if (directives.isEmpty) return const <String>[];
  final missing = <String>[];
  for (final diagnostic in resolved.diagnostics) {
    if (!_missingUriCodes.contains(diagnostic.diagnosticCode.name)) continue;
    final within = directives.any(
      (directive) =>
          diagnostic.offset >= directive.offset &&
          diagnostic.offset < directive.end,
    );
    if (!within) continue;
    missing.add(_quotedUri(diagnostic.message));
  }
  return missing;
}

/// The diagnostics that mean "this directive names a file the analyzer cannot
/// find", which is what an unresolved package looks like from inside a file.
const Set<String> _missingUriCodes = <String>{
  'uri_does_not_exist',
  'uri_has_not_been_generated',
};

/// The URI out of a `Target of URI doesn't exist: 'package:good/good.dart'.`
///
/// The message and not the directive, because a diagnostic carries no node and
/// re-walking the unit to find the directive at an offset would be a second
/// answer to a question the message already answers. A message that stops
/// quoting its URI falls back to the whole message, which still names it.
///
/// The **last** pair of quotes, because the sentence has an apostrophe in it:
/// reading from the first quote answers `t exist: `, which is what this
/// printed the first time it ran.
String _quotedUri(String message) {
  final close = message.lastIndexOf("'");
  if (close <= 0) return message;
  final open = message.lastIndexOf("'", close - 1);
  if (open < 0) return message;
  return message.substring(open + 1, close);
}

/// What to say about a walk that could not resolve what it read.
///
/// Names the URIs and the files, because the fix is a `pub get` in a package
/// the caller has to be able to find. It never says how many declarations were
/// found: the whole point is that the number would be a lie.
String unresolvedUriMessage(
  ScanSources sources,
  String Function(String path) display,
) {
  final buffer = StringBuffer();
  buffer.writeln(
    'The analyzer could not find every import in the source it read, so what '
    'each field holds is unknown and no declaration in these files can be '
    'read:',
  );
  final paths = sources.unresolvedUris.keys.toList()..sort();
  final uris = <String>{
    for (final path in paths) ...sources.unresolvedUris[path]!,
  }.toList()..sort();
  for (final uri in uris) {
    buffer.writeln('  $uri');
  }
  buffer.writeln();
  buffer.writeln(
    'First seen in ${display(paths.first)}, and in '
    '${paths.length} file(s) altogether.',
  );
  buffer.writeln();
  buffer.write(
    'Run `flutter pub get` (or `dart pub get`) in the package that writes '
    'them and try again. This is refused rather than reported, because an '
    'unresolved import leaves every field in the file typed `InvalidType` - '
    'the run would find no columns, no queries and no events, write that as '
    'the answer, and every generated accessor would be deleted by the write '
    'that followed.',
  );
  return buffer.toString();
}

ScannedUnit _readUnit(
  String path,
  CompilationUnit unit,
  List<Diagnostic> diagnostics,
) {
  final declaredNames = <String>{};
  final imports = <ScannedImport>[];
  final exports = <ScannedExport>[];
  final types = <ScannedType>[];
  final variables = <ScannedField>[];

  for (final directive in unit.directives) {
    if (directive is! NamespaceDirective) continue;
    final uri = directive.uri.stringValue;
    if (uri == null) continue;
    final shown = <String>{};
    final hidden = <String>{};
    for (final combinator in directive.combinators) {
      if (combinator is ShowCombinator) {
        shown.addAll(combinator.shownNames.map((name) => name.name));
      } else if (combinator is HideCombinator) {
        hidden.addAll(combinator.hiddenNames.map((name) => name.name));
      }
    }
    if (directive is ExportDirective) {
      exports.add(ScannedExport(uri: uri, shown: shown, hidden: hidden));
    } else if (directive is ImportDirective) {
      imports.add(
        ScannedImport(
          uri: uri,
          prefix: directive.prefix?.name,
          shown: shown,
          hidden: hidden,
        ),
      );
    }
  }

  for (final declaration in unit.declarations) {
    if (declaration is NamedCompilationUnitMember) {
      declaredNames.add(declaration.name.lexeme);
    } else if (declaration is ExtensionDeclaration) {
      final name = declaration.name;
      if (name != null) declaredNames.add(name.lexeme);
    } else if (declaration is TopLevelVariableDeclaration) {
      final annotations = <String>[
        for (final annotation in declaration.metadata)
          annotation.toSource().substring(1),
      ];
      for (final variable in declaration.variables.variables) {
        declaredNames.add(variable.name.lexeme);
        variables.add(
          _readVariable(
            variable,
            annotations: annotations,
            isStatic: true,
            isLate: true,
            diagnostics: diagnostics,
          ),
        );
      }
    }

    final scanned = _readType(path, declaration, diagnostics);
    if (scanned != null) types.add(scanned);
  }

  return ScannedUnit(
    path: path,
    declaredNames: declaredNames,
    imports: imports,
    exports: exports,
    types: types,
    variables: variables,
  );
}

ScannedType? _readType(
  String path,
  CompilationUnitMember declaration,
  List<Diagnostic> diagnostics,
) {
  final String name;
  final typeParameters = <String>[];
  final supertypes = <String>[];
  final mixins = <String>[];
  String? superclass;
  var isAbstract = false;
  final List<ClassMember> members;
  String? representation;

  void addTypeParameters(TypeParameterList? list) {
    for (final parameter in list?.typeParameters ?? const <TypeParameter>[]) {
      typeParameters.add(parameter.name.lexeme);
    }
  }

  void addAll(Iterable<NamedType> named) {
    for (final type in named) {
      supertypes.add(type.name.lexeme);
    }
  }

  void addMixins(Iterable<NamedType> named) {
    for (final type in named) {
      mixins.add(type.name.lexeme);
    }
  }

  if (declaration is ClassDeclaration) {
    name = declaration.name.lexeme;
    addTypeParameters(declaration.typeParameters);
    isAbstract =
        declaration.abstractKeyword != null ||
        declaration.sealedKeyword != null;
    final extendsClause = declaration.extendsClause;
    if (extendsClause != null) {
      superclass = extendsClause.superclass.name.lexeme;
      addAll(<NamedType>[extendsClause.superclass]);
    }
    addMixins(declaration.withClause?.mixinTypes ?? const <NamedType>[]);
    addAll(declaration.withClause?.mixinTypes ?? const <NamedType>[]);
    addAll(declaration.implementsClause?.interfaces ?? const <NamedType>[]);
    members = _members(declaration.body);
  } else if (declaration is MixinDeclaration) {
    name = declaration.name.lexeme;
    addTypeParameters(declaration.typeParameters);
    isAbstract = true;
    addAll(declaration.onClause?.superclassConstraints ?? const <NamedType>[]);
    addAll(declaration.implementsClause?.interfaces ?? const <NamedType>[]);
    members = _members(declaration.body);
  } else if (declaration is EnumDeclaration) {
    name = declaration.name.lexeme;
    addTypeParameters(declaration.typeParameters);
    addMixins(declaration.withClause?.mixinTypes ?? const <NamedType>[]);
    addAll(declaration.withClause?.mixinTypes ?? const <NamedType>[]);
    addAll(declaration.implementsClause?.interfaces ?? const <NamedType>[]);
    // An `EnumBody` and not a `ClassBody`, and an enum always has a block, so
    // there is no empty case for [_members] to guard against here.
    members = declaration.body.members;
  } else if (declaration is ExtensionTypeDeclaration) {
    name = declaration.name.lexeme;
    addTypeParameters(declaration.typeParameters);
    addAll(declaration.implementsClause?.interfaces ?? const <NamedType>[]);
    members = _members(declaration.body);
    representation = declaration.representation.fieldName.lexeme;
  } else {
    return null;
  }

  final fields = <ScannedField>[];
  final methods = <String, ScannedMethod>{};
  for (final member in members) {
    if (member is FieldDeclaration) {
      final annotations = <String>[
        for (final annotation in member.metadata)
          annotation.toSource().substring(1),
      ];
      for (final variable in member.fields.variables) {
        fields.add(
          _readVariable(
            variable,
            annotations: annotations,
            isStatic: member.isStatic,
            isLate: member.fields.lateKeyword != null,
            diagnostics: diagnostics,
          ),
        );
      }
    } else if (member is MethodDeclaration) {
      final method = _readMethod(member);
      methods[method.name] = method;
    }
  }

  final referenced = <String>{};
  final assets = <String>{};
  declaration.accept(_ReferenceCollector(referenced, assets));

  return ScannedType(
    name: name,
    path: path,
    typeParameters: typeParameters,
    supertypes: supertypes,
    superclass: superclass,
    mixins: mixins,
    isAbstract: isAbstract,
    fields: fields,
    methods: methods,
    referencedNames: referenced,
    assetIdentifiers: assets,
    representationName: representation,
  );
}

/// The members of a declaration body, or none for a declaration without one.
///
/// Through `body` and not `.members`, and that is not a style choice.
/// `ClassDeclaration.members` in analyzer 10.2.0 is `(body as
/// BlockClassBodyImpl).members`, and a primary-constructor class written
/// `class Sprite({final int width});` - no braces, a semicolon - has an
/// `EmptyClassBody`. The cast throws, so the walk dies on the file rather than
/// skipping it. Measured on exactly that source.
List<ClassMember> _members(ClassBody body) =>
    body is BlockClassBody ? body.members : const <ClassMember>[];

/// Whether [expression] is, at its head, a call to an unnamed constructor.
///
/// Walks down the targets rather than matching a shape, because the shapes a
/// head can be wearing are open-ended: `Barrel()`, `Barrel()..tune()`,
/// `Barrel().tuned()`, `(Barrel())` all read as a constructor call to whoever
/// wrote the line, and each one of them was a separate patch when this was a
/// pattern match. What stops the walk is a node with no target left, and the
/// answer is whether that node is an `InstanceCreationExpression` the analyzer
/// resolved with no constructor name on it.
bool _isBareConstruction(Expression? expression) {
  var current = expression;
  while (true) {
    switch (current) {
      case ParenthesizedExpression():
        current = current.expression;
      case CascadeExpression():
        current = current.target;
      case MethodInvocation(target: final target?):
        current = target;
      case PropertyAccess(target: final target?):
        current = target;
      case InstanceCreationExpression():
        return current.constructorName.name == null;
      case _:
        return false;
    }
  }
}

/// The owning class's own instance fields [expression] reads.
///
/// Off the element model and not off the names written, so `b` in
/// `late final a = b;` is here because the analyzer says it is this class's
/// field, and `b` in `late final a = other.b;` is not. Only a `late`
/// initialiser can read one at all - an ordinary field initialiser cannot
/// reach `this` - which is why this is only ever asked about a `late` field.
Set<String> _readFieldReads(Expression? expression) {
  if (expression == null) return const <String>{};
  final names = <String>{};
  expression.accept(_FieldReadCollector(names));
  return names;
}

/// What the analyzer reported over [variable]'s own source range.
///
/// Errors alone, deduplicated, in the order they were reported. A warning or a
/// lint says nothing about why a type could not be worked out, and a run that
/// quoted them would bury the one line that does.
String? _whyUntyped(VariableDeclaration variable, List<Diagnostic> diagnostics) {
  final said = <String>{};
  for (final diagnostic in diagnostics) {
    if (diagnostic.diagnosticCode.severity != DiagnosticSeverity.ERROR) {
      continue;
    }
    if (diagnostic.offset < variable.offset) continue;
    if (diagnostic.offset >= variable.end) continue;
    said.add(diagnostic.message);
  }
  if (said.isEmpty) return null;
  return said.join(' ');
}

class _FieldReadCollector extends RecursiveAstVisitor<void> {
  _FieldReadCollector(this._names);

  final Set<String> _names;

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    final element = node.element;
    if (element is PropertyAccessorElement && !element.isStatic) {
      _names.add(node.name);
    } else if (element is FieldElement && !element.isStatic) {
      _names.add(node.name);
    }
    super.visitSimpleIdentifier(node);
  }
}

ScannedField _readVariable(
  VariableDeclaration variable, {
  required List<String> annotations,
  required bool isStatic,
  required bool isLate,
  required List<Diagnostic> diagnostics,
}) {
  final initializer = variable.initializer;
  final type = variable.declaredFragment?.element.type;
  final unknown = type == null || type is InvalidType;
  return ScannedField(
    name: variable.name.lexeme,
    // Null for `InvalidType` and for a fragment the resolution never
    // produced, which are the same fact wearing two shapes: the analyzer
    // could not say what this field holds. It is never flattened into a name
    // here, because `InvalidType`'s display string is `InvalidType` and a
    // walk keyed on names would take it for a class somebody wrote.
    valueType: unknown ? null : type.getDisplayString(),
    valueTypeProblem: unknown ? _whyUntyped(variable, diagnostics) : null,
    annotations: annotations,
    isStatic: isStatic,
    isLate: isLate,
    hasInitializer: initializer != null,
    isBareConstruction: _isBareConstruction(initializer),
    readsFields: isLate ? _readFieldReads(initializer) : const <String>{},
  );
}

ScannedMethod _readMethod(MethodDeclaration member) {
  final name = member.name.lexeme;
  // The first parameter's name and nothing else about the signature. A
  // `describeX` body's `<descriptor>.has<T>()` calls are read off that
  // receiver; the written types went with `columnValueType`'s expression
  // matching, which is the only thing that ever asked for them.
  String? receiver;
  for (final parameter
      in member.parameters?.parameters ?? const <FormalParameter>[]) {
    receiver = parameter.name?.lexeme;
    if (receiver != null) break;
  }
  final visitor = _MethodBodyVisitor(name: name, receiver: receiver);
  member.body.accept(visitor);
  return ScannedMethod(
    name: name,
    isStatic: member.isStatic,
    annotations: <String>{
      for (final annotation in member.metadata) annotation.name.name,
    },
    isEmptyBody: _isEmptyBody(member.body),
    callsSuper: visitor.callsSuper,
    registeredTypes: visitor.registeredTypes,
  );
}

bool _isEmptyBody(FunctionBody body) {
  if (body is EmptyFunctionBody) return true;
  if (body is BlockFunctionBody) return body.block.statements.isEmpty;
  return false;
}

class _MethodBodyVisitor extends RecursiveAstVisitor<void> {
  _MethodBodyVisitor({required this.name, required this.receiver});

  final String name;
  final String? receiver;
  bool callsSuper = false;
  final List<String> registeredTypes = <String>[];

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final target = node.target;
    if (target is SuperExpression && node.methodName.name == name) {
      callsSuper = true;
    }
    if (node.methodName.name == 'has' &&
        receiver != null &&
        target is SimpleIdentifier &&
        target.name == receiver) {
      final arguments = node.typeArguments?.arguments;
      if (arguments != null && arguments.length == 1) {
        registeredTypes.add(arguments.single.toSource());
      }
    }
    super.visitMethodInvocation(node);
  }
}

class _ReferenceCollector extends RecursiveAstVisitor<void> {
  _ReferenceCollector(this.names, this.assets);

  final Set<String> names;
  final Set<String> assets;

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    names.add(node.name);
    super.visitSimpleIdentifier(node);
  }

  @override
  void visitNamedType(NamedType node) {
    names.add(node.name.lexeme);
    super.visitNamedType(node);
  }

  @override
  void visitPrefixedIdentifier(PrefixedIdentifier node) {
    if (node.prefix.name == 'Textures' || node.prefix.name == 'Audios') {
      assets.add(node.identifier.name);
    }
    super.visitPrefixedIdentifier(node);
  }

  @override
  void visitPropertyAccess(PropertyAccess node) {
    final target = node.target;
    if (target is SimpleIdentifier &&
        (target.name == 'Textures' || target.name == 'Audios')) {
      assets.add(node.propertyName.name);
    }
    super.visitPropertyAccess(node);
  }
}

// ---------------------------------------------------------------------------
// Shared derivations
// ---------------------------------------------------------------------------

/// The names a column's value is held behind.
///
/// All three are `DataPointer`s: `InitialPointer` adds the declared default and
/// `PackedPointer` adds the representation, and a generated property reads and
/// writes all three the same way.
const Set<String> pointerRoots = <String>{
  'DataPointer',
  'InitialPointer',
  'PackedPointer',
};

/// The array column, which is a separate root and not a [pointerRoots] at all.
///
/// `data.dart` says so where it is declared: "a `DataArrayPointer` is not a
/// `DataPointer`". It is named here rather than left out so a scan meeting one
/// says what it is skipping instead of not noticing it - `Text2D`'s
/// `textCodeUnits` is one, and a pass matching only on `DataPointer` drops it
/// with nothing anywhere saying so.
const String arrayPointerRoot = 'DataArrayPointer';

/// A generic type as it was written, split into head and arguments.
@immutable
class TypeSource {
  const TypeSource(this.name, this.arguments, {required this.isNullable});

  final String name;
  final List<String> arguments;

  /// Whether a trailing `?` was taken off [name] to get here.
  ///
  /// The record that it was, so the split is lossless: `parse('Entity?')` and
  /// `parse('Entity')` are otherwise the same answer.
  final bool isNullable;

  /// `DataPointer<CameraView?>` into `DataPointer` and `['CameraView?']`.
  ///
  /// Returns null for anything that is not a plain named type - a function
  /// type, a record, a `dynamic`.
  static TypeSource? parse(String source) {
    var text = source.trim();
    var nullable = false;
    if (text.endsWith('?')) {
      nullable = true;
      text = text.substring(0, text.length - 1).trim();
    }
    final open = text.indexOf('<');
    if (open < 0) {
      if (!_namePattern.hasMatch(text)) return null;
      return TypeSource(text, const <String>[], isNullable: nullable);
    }
    if (!text.endsWith('>')) return null;
    final name = text.substring(0, open).trim();
    if (!_namePattern.hasMatch(name)) return null;
    final arguments = <String>[];
    final buffer = StringBuffer();
    var depth = 0;
    for (final rune in text.substring(open + 1, text.length - 1).runes) {
      final character = String.fromCharCode(rune);
      if (character == '<' || character == '(') depth++;
      if (character == '>' || character == ')') depth--;
      if (character == ',' && depth == 0) {
        arguments.add(buffer.toString().trim());
        buffer.clear();
        continue;
      }
      buffer.write(character);
    }
    final tail = buffer.toString().trim();
    if (tail.isNotEmpty) arguments.add(tail);
    return TypeSource(name, arguments, isNullable: nullable);
  }
}

final RegExp _namePattern = RegExp(r'^[_$a-zA-Z][_$a-zA-Z0-9]*$');

/// What one field turned out to be: a column of [valueType], or not one.
@immutable
class ColumnResolution {
  const ColumnResolution.column(this.valueType) : problem = null;
  const ColumnResolution.problem(this.problem) : valueType = null;

  /// The type one entity's value is read and written as - `double`,
  /// `CameraView?`.
  final String? valueType;

  /// Why this is a column that cannot become a property, or null.
  final String? problem;
}

/// Whether [field] declares a column, and what its value type is.
///
/// One question, asked of the field's own type.
///
/// ```dart
/// final transformOffsetX = Field.float64();   // double
/// late final DataPointer<CameraView?> view = ...;   // CameraView?
/// ```
///
/// Both reach it the same way, because the analyzer resolved both.
///
/// What it used to be was the factory's declared return type read out of the
/// parse, with the type argument filled in from the call where the return type
/// left one standing - two ways of inferring an `E`, a report for anything
/// that was neither, and nothing at all for a builder chain. The analyzer does
/// all of that already and is right about the cases the two ways were not
/// written for.
///
/// Returns null when the field is not a column at all, which is most of them.
ColumnResolution? columnValueType(ScannedField field) {
  final declared = field.valueType;
  if (declared == null) return null;
  final parsed = TypeSource.parse(declared);
  if (parsed == null) return null;
  return _fromPointer(parsed);
}

ColumnResolution? _fromPointer(TypeSource parsed) {
  if (parsed.name == arrayPointerRoot) {
    return const ColumnResolution.problem(
      'it is a $arrayPointerRoot - an array column holds a run of values at '
      'each entity, and one property reading it would have to pick an index',
    );
  }
  if (!pointerRoots.contains(parsed.name)) return null;
  if (parsed.arguments.length != 1) return null;
  return ColumnResolution.column(parsed.arguments.single);
}

/// The property name a column gets on the accessor.
///
/// A published component prefixes its columns with its own name, because a
/// column lands in the row of whatever mixes the component in and two mixins
/// both declaring `speed` is a defect the engine cannot see - `Field`'s own
/// comment says so, and it is #58. That prefix is right in the row and
/// redundant on the accessor, where the receiver already says which component
/// this is: `entity<Transform2D>().transformOffsetX` says it twice.
///
/// So the component's own name comes off when the column starts with it, and
/// the column is left alone when it does not. The dimension suffix comes off
/// first - `Transform2D` prefixes its columns `transform`, not `transform2D`.
/// `WorldTransform2D.worldX` and `RigidBody2D.bodyHandle` are the other case:
/// neither starts with its component's whole name, so both keep what they have.
String propertyNameFor(String component, String column) {
  final base = component.replaceFirst(RegExp(r'\d+[Dd]$'), '');
  if (base.isEmpty) return column;
  final prefix = base[0].toLowerCase() + base.substring(1);
  if (!column.startsWith(prefix) || column.length <= prefix.length) {
    return column;
  }
  final rest = column.substring(prefix.length);
  final head = rest[0];
  if (head.toUpperCase() != head || head.toLowerCase() == head) return column;
  return head.toLowerCase() + rest.substring(1);
}

/// Whether [name] has [root] anywhere above it.
///
/// Walks the names written in `extends`, `on`, `with` and `implements`, which
/// is what makes `mixin Collider2D on MultiComponent` a component. Nothing here
/// resolves, so the chain is followed by name through everything the walk read,
/// and a name the walk never saw stops it - which is why a project scanned
/// without its engine dependencies finds only the components that name
/// `Component` directly, and finds those correctly.
bool isSubtypeOf(
  String name,
  String root,
  Map<String, ScannedType> typesByName, {
  Set<String>? seen,
}) {
  if (name == root) return true;
  final visited = seen ?? <String>{};
  if (!visited.add(name)) return false;
  final type = typesByName[name];
  if (type == null) return false;
  for (final supertype in type.supertypes) {
    if (isSubtypeOf(supertype, root, typesByName, seen: visited)) return true;
  }
  return false;
}

/// The members `int` has, which an extension property would silently lose to.
///
/// `Accessor<T>` implements `Entity`, which implements `int`, and an extension
/// member never wins against one the receiver's own type declares. So a column
/// whose property name is `sign` or `round` generates a property that compiles
/// and is never reached, and every read of it answers about the entity handle
/// instead of about the column.
///
/// Written out because nothing in the walk reads `dart:core`. `Accessor`'s and
/// `Entity`'s own members are not here - those are read off the parse, so they
/// cannot go stale when either gains a member.
const Set<String> intMembers = <String>{
  'abs',
  'bitLength',
  'ceil',
  'ceilToDouble',
  'clamp',
  'compareTo',
  'floor',
  'floorToDouble',
  'gcd',
  'hashCode',
  'isEven',
  'isFinite',
  'isInfinite',
  'isNaN',
  'isNegative',
  'isOdd',
  'modInverse',
  'modPow',
  'noSuchMethod',
  'remainder',
  'round',
  'roundToDouble',
  'runtimeType',
  'sign',
  'toDouble',
  'toInt',
  'toRadixString',
  'toSigned',
  'toString',
  'toStringAsExponential',
  'toStringAsFixed',
  'toStringAsPrecision',
  'toUnsigned',
  'truncate',
  'truncateToDouble',
};

// ---------------------------------------------------------------------------
// Declarations
// ---------------------------------------------------------------------------

/// The marker a class carries to be scanned at all - see `Scannable` in
/// `good/lib/src/scannable.dart`.
const String scannableRoot = 'Scannable';

/// The marker a *value* carries for a field holding it to be a declaration.
///
/// `DataPointer`, `DataArrayPointer` and `Query` implement it today. Nothing
/// here holds a list of those names: the test is the supertype walk through
/// what was read, so a fourth root marked in `good` is found by this pass
/// without an edit here, and a name this walk never saw is simply not one.
const String scannableFieldRoot = 'ScannableField';

/// The marker an annotation carries to be written into generated output.
const String scannableAnnotationRoot = 'ScannableAnnotation';

/// Every name that can be written as a marker annotation on a declaration.
///
/// Two kinds, and a pass holding only the first finds nothing. `@LoadBefore(X)`
/// names the class directly, so the supertype walk answers it. `@sub` names a
/// **const variable** - `const Sub sub = Sub._();` - and `typesByName['sub']`
/// is null, because `sub` is not a type. So the variable's written type is what
/// gets walked, and the variable's own name is what goes in the set.
///
/// A set of names rather than a test run per annotation, because the answer is
/// the same for every field in the repository and the walk that produces it is
/// over every unit.
Set<String> scannableAnnotationNames(ScanSources sources) {
  final typesByName = sources.typesByName;
  final names = <String>{};
  final paths = sources.units.keys.toList()..sort();
  for (final path in paths) {
    final unit = sources.units[path]!;
    for (final type in unit.types) {
      if (isSubtypeOf(type.name, scannableAnnotationRoot, typesByName)) {
        names.add(type.name);
      }
    }
    for (final variable in unit.variables) {
      // The variable's own type, whether or not it is written. `const Sub sub
      // = Sub._();` and `const sub = Sub._();` are one marker declared two
      // ways, and a walk reading the annotation alone found the first and
      // called the second an ordinary constant.
      final declared = variable.valueType;
      if (declared == null) continue;
      final parsed = TypeSource.parse(declared);
      if (parsed == null) continue;
      if (isSubtypeOf(parsed.name, scannableAnnotationRoot, typesByName)) {
        names.add(variable.name);
      }
    }
  }
  return names;
}

/// What a field holds, or why the walk cannot say.
///
/// Null - the return of [resolveValueType] rather than a state of this class -
/// is the quiet answer, and it now means one thing only: the analyzer named a
/// type and it is not one this walk read. `final clock = Stopwatch();` is
/// that. It is quiet because there is nothing to say: the field is not a
/// declaration and nobody was mistaken about it.
///
/// [problem] is the answer that is **not** allowed to be quiet. The analyzer
/// could not name the field's type at all, which in practice means the file's
/// imports did not resolve - and a field whose type is unknown is exactly the
/// one that would otherwise disappear from every list without a line anywhere.
@immutable
class ValueTypeResolution {
  const ValueTypeResolution.type(String this.type) : problem = null;
  const ValueTypeResolution.problem(String this.problem) : type = null;

  /// The type of the value the field holds - `InitialPointer<double>`.
  final String? type;

  /// Why the walk cannot name what the field holds, or null.
  final String? problem;
}

/// The type of the value [field] holds, as the analyzer resolved it.
///
/// One question and one answer. A written annotation, a dotted static, a
/// builder chain, a typedef, a cascade and a bare constructor call all reach
/// it the same way, because none of them is read: the field's own resolved
/// type is.
///
/// ```dart
/// final hp = Field.float64();                          // InitialPointer<double>
/// final roots = Query.where().withAll(A).build();      // Query
/// final q3 = Track.of<double>(0)..hashCode;            // Track<double>
/// late final TextureAsset tex = Asset.of(k);           // Asset<Texture>
/// ```
///
/// Every one of those was a separate patch, and the last two were a miss and a
/// silence. What decides whether the field is a declaration is only ever the
/// head of the type, and [isDeclarationField] takes it from here.
///
/// # What is still not enough for an emitter
///
/// A type argument that is a type parameter stays one: a field on
/// `class Holder<T>` declared `DataPointer<T>` answers `DataPointer<T>`,
/// because that is what it is. A caller that has to write the type out has to
/// say what it does with a `T`.
String? declaredValueType(ScannedField field) =>
    resolveValueType(field)?.type;

/// [declaredValueType], with the reason kept when there is one.
ValueTypeResolution? resolveValueType(ScannedField field) {
  final declared = field.valueType;
  if (declared != null) return ValueTypeResolution.type(declared);
  final why = field.valueTypeProblem;
  return ValueTypeResolution.problem(
    why == null
        ? 'the analyzer could not say what this field holds, and reported '
              'nothing about the line. A field whose type is unknown is '
              'neither collected nor listed as uncollectable, so it is said '
              'out loud instead'
        : 'the analyzer could not say what this field holds: $why A field '
              'whose type is unknown is neither collected nor listed as '
              'uncollectable, so it is said out loud instead',
  );
}

/// Whether [field] holds a declaration - a value marked [scannableFieldRoot].
///
/// By the head of the type alone. `DataPointer<CameraView?>` and
/// `InitialPointer<double>` are both declarations and their arguments have
/// nothing to do with it: the marker is on the value's own type, not on what
/// it wraps.
///
/// # A nullable handle is a reference to somebody else's column
///
/// `DataPointer<CameraView?>` is a declaration whose *value* may be absent.
/// `DataPointer<Entity?>?` - the handle itself nullable - is not a declaration
/// at all, because a column cannot be declared conditionally: there is no
/// shape in which a class declares half a column and holds null instead. What
/// a nullable handle holds is a column somebody else declared, bound
/// afterwards, and `Child._declaredIn` (`good/lib/src/data/hierarchy.dart`) is
/// one - a column on the *parent's* archetype, handed over by
/// `bindDeclaration` at registration and null until then.
///
/// Found by this check reporting it, which is the outcome to want from a rule
/// derived off a type: the type said declaration, the field is a binding, and
/// the difference is written in the nullability rather than in a comment.
bool isDeclarationField(
  ScannedField field,
  Map<String, ScannedType> typesByName,
) {
  final declared = declaredValueType(field);
  if (declared == null) return false;
  final parsed = TypeSource.parse(declared);
  if (parsed == null || parsed.isNullable) return false;
  return isSubtypeOf(parsed.name, scannableFieldRoot, typesByName);
}

/// Whether a generated collector reads [field] back off a constructed
/// instance.
///
/// The rule the owner settled: **shape tells, or annotation tells.** A
/// declaration written as a dotted static says so where it is written, and a
/// bare constructor call does not, so a bare one carries a marker:
///
/// ```dart
/// final hp   = Field.float64();   // collected, no marker
/// @sub  final enemy = Enemy();    // collected, the marker says so
/// final spare = Enemy();          // not collected, and legal
/// ```
///
/// The last line is why this decides at build time and reports rather than
/// refuses. Holding a spare instance of a declarable type is ordinary code -
/// the whole reason a marker exists is that the two shapes are told apart -
/// so what happens to it is that it is named, in
/// [DeclarationScan.unmarked], and left out of the collector.
///
/// The marker rule survives resolution and always would have. Resolution
/// proves `Enemy()` is a [scannableFieldRoot]; it cannot say whether the field
/// is a declared child or a spare, and that distinction is the whole reason
/// the marker exists. What resolution *does* fix is the test for "bare
/// constructor call" - see [ScannedField.isBareConstruction], which a
/// `final spare = Barrel()..tune();` used to walk straight past into the
/// collector.
///
/// [markers] is [scannableAnnotationNames] over the same walk.
bool isCollectedDeclarationField(
  ScannedField field,
  Map<String, ScannedType> typesByName,
  Set<String> markers,
) {
  if (!isDeclarationField(field, typesByName)) return false;
  if (!field.isBareConstruction) return true;
  return field.annotations.any(
    (annotation) => markers.contains(annotationName(annotation)),
  );
}

/// One declaration a scanned class holds, as codegen and a collector need it.
///
/// Both halves of "two artifacts, not one" are here: [name] and [valueType]
/// are what an emitter reads and what a runtime value cannot carry - a
/// `DataPointer` has no `name` member, and `CameraView?` is not recoverable
/// from a `Type` - and [annotations] are what a generated const table holds.
@immutable
class ScannedDeclaration {
  const ScannedDeclaration({
    required this.owner,
    required this.name,
    required this.valueType,
    required this.annotations,
    required this.isPrivate,
    required this.isCollected,
  });

  /// The class that writes the field - `Transform2D`, not whichever class
  /// applies it.
  ///
  /// Carried because a flattened list holds declarations from several
  /// classes at once and an emitter has to be able to say where each came
  /// from; see [flattenedDeclarations].
  final String owner;

  /// The Dart field name - `cameraView`, `transformOffsetX`.
  final String name;

  /// The type of the value it holds, exactly as [declaredValueType] found it.
  final String valueType;

  /// The annotations written on it that carry into generated output.
  ///
  /// Only the ones marked [scannableAnnotationRoot]. Every other annotation
  /// on the field - `override`, `internal`, `pragma` - is read here and
  /// dropped, rather than serialised into a table that ships.
  final List<String> annotations;

  final bool isPrivate;

  /// Whether the generator writes it into a collector - see
  /// [isCollectedDeclarationField].
  ///
  /// False is a bare constructor call with no marker on it, and it is carried
  /// here rather than filtered out at the walk because two passes want
  /// different answers. A collector wants the fields that are declarations; the
  /// cycle check wants every field whose initialiser *constructs* one, marker
  /// or not, because `final spare = Turret();` inside `Turret` recurses in
  /// Dart before anything of this engine's is reached.
  final bool isCollected;
}

/// One scanned class and the declarations it holds, in declaration order.
@immutable
class ScannedDeclarer {
  const ScannedDeclarer({
    required this.type,
    required this.path,
    required this.declarations,
  });

  /// The class - `Camera`, `Transform2D`, `Player`.
  final String type;

  /// The file it is declared in, normalised and absolute.
  final String path;

  final List<ScannedDeclaration> declarations;
}

/// One declaration this engine will not accept, and why.
@immutable
class DeclarationRefusal {
  const DeclarationRefusal({
    required this.owner,
    required this.field,
    required this.path,
    required this.reason,
  });

  /// The class holding it, or the file name when it is a top-level variable.
  final String owner;

  final String field;

  /// The file it is written in, normalised and absolute.
  final String path;

  final String reason;
}

/// Every scanned class's declarations, and every one that is refused.
@immutable
class DeclarationScan {
  const DeclarationScan({
    required this.declarers,
    required this.refusals,
    required this.unresolved,
    required this.cycles,
    required this.uncollectable,
    required this.unmarked,
  });

  /// Classes holding at least one declaration, in path order.
  final List<ScannedDeclarer> declarers;

  /// What refuses a run - see [declarationRefusalMessage].
  final List<DeclarationRefusal> refusals;

  /// Fields whose initialiser this walk could see into and could not finish -
  /// see [unresolvedInitializerMessage].
  ///
  /// A separate list from [refusals] because it is a separate statement about
  /// a separate thing. A refusal says the source is written a way this engine
  /// does not accept and names the edit. This says the *walk* stopped: it read
  /// the class the call is made on, found no member to follow, and so cannot
  /// say what the field holds. Whether that field was a declaration is exactly
  /// what is unknown, so it is reported instead of being answered either way.
  final List<DeclarationRefusal> unresolved;

  /// Rings a declaration waits on itself round - see
  /// [declarationCycleMessage].
  ///
  /// Two shapes, and neither leaves a run anything to report from.
  ///
  /// A declared child is an ordinary field holding an ordinary constructor
  /// call, so a struct that declares itself, directly or round a ring, builds
  /// one of itself while building itself. That does not terminate, and nothing
  /// of this engine's is on the recursion, so what a run produces is Dart's
  /// own `StackOverflowError` with no ring named.
  ///
  /// A ring of `late` initialisers - `late final a = b; late final b = a;` -
  /// compiles and throws `LateInitializationError` at the first touch, naming
  /// one field and nothing about the ring. The collector's read *is* that
  /// first touch, so the throw arrives at boot.
  ///
  /// Each ring is a fact about the source, so this is where it can be named.
  final List<DeclarationRefusal> cycles;

  /// Declarations that are accepted and that a collector cannot read, keyed
  /// `Class.field`, to why.
  ///
  /// Private ones, and today that is all of them. A collector is generated
  /// into another library and a private field is `undefined_getter` there, so
  /// these contribute nothing to a collect pass - which is exactly the shape
  /// this engine keeps being bitten by, and exactly why it is listed rather
  /// than swallowed.
  ///
  /// It is not a refusal: whether a private column becomes public, and every
  /// one that does generates a public accessor property, is a call for whoever
  /// owns the package - and a check that decided it by refusing would be
  /// making it.
  ///
  /// The count this list produces is a fact about the *scan* and not only
  /// about the source, which is why it moved twice while the scan did. A walk
  /// that read one call put it at twenty-two: the seventeen mixin cache
  /// columns plus the five queries written `Query.all(...)`. The other six
  /// were written `Query.where()...build()`, and a walk that stopped at the
  /// first call could not name them - so they were not listed here, not
  /// commented into the generated file, and not anywhere else either.
  final Map<String, String> uncollectable;

  /// Fields holding a declaration that nothing at the line says is one, keyed
  /// `Class.field`, to why - the third thing a field can end up being.
  ///
  /// A bare constructor call with no marker on it. The type is a
  /// [scannableFieldRoot], so the *scanner* knows what it is; the reader does
  /// not, and `final spare = Enemy();` is spelled exactly like a field holding
  /// an ordinary object.
  ///
  /// Reported and never refused, which is the difference between this and
  /// [refusals]. A refusal says the source is written a way this engine does
  /// not accept. This says the field is legal and is not collected: holding a
  /// spare of a declarable type is ordinary code, and the marker exists so
  /// that shape and the declaring one can be told apart at all. Refusing here
  /// would delete the shape the marker was introduced to make writable.
  final Map<String, String> unmarked;

  int get declarationCount {
    var count = 0;
    for (final declarer in declarers) {
      count += declarer.declarations.length;
    }
    return count;
  }
}

/// Every declaration in [sources], and what is wrong with the ones that are.
///
/// # What is refused, and why none of it is a style rule
///
/// **No initialiser, `late` or not.**
/// `late final DataPointer<CameraView?> cameraView;` filled in from a
/// `describeStruct` body is one declaration written twice, and the second half
/// runs at a moment nothing at the declaration says. It is also what a
/// collector trips over first: a collect pass reads declarations off a freshly
/// constructed instance, and an unassigned `late final` throws there instead
/// of yielding anything. Without the word it is the same field with the
/// deferral unstated.
///
/// **A `late` field *with* an initialiser is allowed, and is how a declaration
/// reaches `this`.** A `late` initialiser runs on first touch, after
/// construction, so `Effector(region)` can name the field beside it and
/// `Asset.of(key)` can read a constructor argument. The collector's read *is*
/// that first touch and Dart memoises the result, so collect and gameplay see
/// one object. The rule the `late` ban was carrying is the double declaration,
/// and a `late final x = ...` is not one: it is written once, in the place
/// that declares it.
///
/// Two things follow from running an initialiser later rather than never. An
/// initialiser that throws now throws during collect, where the stack names
/// the field rather than a hook. And a ring of them -
/// `late final a = b; late final b = a;` - is a `LateInitializationError` that
/// names nothing at run time, so it is refused here, the way a prefab ring is;
/// see [DeclarationScan.cycles].
///
/// # What is reported and not refused
///
/// A bare constructor call with no marker - `final spare = Enemy();`. It is
/// legal, it declares nothing, and it lands in [DeclarationScan.unmarked]; see
/// [isCollectedDeclarationField].
///
/// **`static`, and a top-level variable.** Both initialise lazily - the first
/// read runs the initialiser - so the value lands on whichever owner happens
/// to be under construction at that moment. A top-level variable is refused
/// whether or not `late` is written, because Dart makes every one of them
/// lazy regardless.
///
/// # What it does not look at
///
/// The other half of a double declaration - the `x = descriptor.has(...)`
/// statement in a hook body. It is not needed: the field alone says the
/// declaration is deferred, and a rule that had to find both halves would
/// pass whenever the assignment moved somewhere this pass does not read.
///
/// # What it reads, and what that costs
///
/// Only what a class writes itself. A mixin's declarations belong to the
/// mixin, and are refused where the mixin is written rather than once per
/// class that applies it - so one bad declaration is one line of output, not
/// one per user of it.
DeclarationScan scanDeclarations(ScanSources sources) {
  final typesByName = sources.typesByName;
  final scopes = LibraryScopes(sources);
  final declarers = <ScannedDeclarer>[];
  final refusals = <DeclarationRefusal>[];
  final unresolved = <DeclarationRefusal>[];
  final uncollectable = <String, String>{};
  final unmarked = <String, String>{};
  final markers = scannableAnnotationNames(sources);

  final lateRings = <DeclarationRefusal>[];

  final paths = sources.units.keys.toList()..sort();
  for (final path in paths) {
    final unit = sources.units[path]!;
    // What this library means by a name it writes. `_Quad` names a struct in
    // one fixture and a plain class in two others, and a report resolving it
    // through one map keyed by name answered with whichever came first in
    // path order - so the declaration holding the struct was neither counted
    // nor named anywhere. A silent undercount here is worse than a missing
    // one: this is the report the decision to convert a package is read off.
    final scope = scopes.over(typesByName, path);
    for (final variable in unit.variables) {
      if (!isDeclarationField(variable, scope)) continue;
      refusals.add(
        DeclarationRefusal(
          owner: p.split(path).last,
          field: variable.name,
          path: path,
          reason:
              'a top-level variable holds it. Dart initialises one lazily, so '
              'the declaration runs on the first read - whenever that is - '
              'instead of while the class that owns it is being built. Move '
              'it onto a field of the class it belongs to',
        ),
      );
    }
    for (final type in unit.types) {
      if (!isSubtypeOf(type.name, scannableRoot, scope)) continue;
      lateRings.addAll(_lateInitializerRings(type, path, scope));
      final declarations = <ScannedDeclaration>[];
      for (final field in type.fields) {
        // Before the declaration test, because the declaration test is what
        // cannot be answered. A field the analyzer could not type is reported
        // whatever it turns out to hold: going quiet here is how a declaration
        // disappears from every list at once.
        final resolution = resolveValueType(field);
        if (resolution != null && resolution.problem != null) {
          unresolved.add(
            DeclarationRefusal(
              owner: type.name,
              field: field.name,
              path: path,
              reason: resolution.problem!,
            ),
          );
          continue;
        }
        if (!isDeclarationField(field, scope)) continue;
        final valueType = resolution!.type!;
        if (field.isStatic) {
          refusals.add(
            DeclarationRefusal(
              owner: type.name,
              field: field.name,
              path: path,
              reason:
                  'a static field holds it, and a static initialises lazily. '
                  'The declaration would run on the first read and land on '
                  'whichever instance is under construction then, which is '
                  'one instance in a process that has many. Make it an '
                  'instance field',
            ),
          );
          continue;
        }
        if (!field.hasInitializer) {
          refusals.add(
            DeclarationRefusal(
              owner: type.name,
              field: field.name,
              path: path,
              reason: field.isLate
                  ? 'it is late and has no initialiser, so the value is '
                        'assigned somewhere else - a describe pass, a '
                        'constructor body - and the declaration is written '
                        'twice. A collect pass reads declarations off a '
                        'freshly constructed instance and finds this one '
                        'unassigned. Give the field its initialiser'
                  : 'it has no initialiser, so whatever assigns it does so '
                        'somewhere the declaration does not say. Give the '
                        'field its initialiser',
            ),
          );
          continue;
        }
        if (!isCollectedDeclarationField(field, scope, markers)) {
          unmarked['${type.name}.${field.name}'] =
              'a bare constructor call holds it and nothing at the line says '
              'it declares anything - `$valueType()` is spelled the way a '
              'field holding an ordinary object is. Write `@sub` on it to '
              'declare it, or leave it as it is if it is a spare';
          continue;
        }
        if (field.isPrivate) {
          uncollectable['${type.name}.${field.name}'] =
              'it is private, and a collector is generated into another '
              'library - a private field is not reachable from one, and user '
              'code is never edited to add a part directive';
        }
        declarations.add(
          ScannedDeclaration(
            owner: type.name,
            name: field.name,
            valueType: valueType,
            annotations: <String>[
              for (final annotation in field.annotations)
                if (markers.contains(annotationName(annotation))) annotation,
            ],
            isPrivate: field.isPrivate,
            isCollected: true,
          ),
        );
      }
      if (declarations.isEmpty) continue;
      declarers.add(
        ScannedDeclarer(
          type: type.name,
          path: path,
          declarations: declarations,
        ),
      );
    }
  }

  return DeclarationScan(
    declarers: declarers,
    refusals: refusals,
    unresolved: unresolved,
    cycles: <DeclarationRefusal>[
      ...lateRings,
      ..._declarationCycles(sources, typesByName, markers),
    ],
    uncollectable: uncollectable,
    unmarked: unmarked,
  );
}

/// Every ring of `late` fields whose initialisers read each other.
///
/// `late final a = b; late final b = a;` compiles, and the first touch of
/// either throws `LateInitializationError: Field 'a' has not been initialized`
/// - a message that names one field and nothing about the ring, from a stack
/// with no engine frame on it. A collector's read *is* that first touch, so a
/// ring among a scanned class's own fields is a boot that dies with nothing to
/// go on. The ring is a fact about the source, so this is where it can be
/// named, and it is the same trade [_declarationCycles] makes for prefabs.
///
/// Reported only where the ring contains a declaration. Two `late` fields of
/// a scanned class that hold ordinary objects and read each other are a bug in
/// somebody's code, and one nothing here is collecting - refusing it would be
/// this tool deciding what a class may hold.
///
/// The reads come off the element model ([ScannedField.readsFields]), so
/// `late final a = b;` counts and `late final a = other.b;` does not.
List<DeclarationRefusal> _lateInitializerRings(
  ScannedType type,
  String path,
  Map<String, ScannedType> typesByName,
) {
  final deferred = <String, ScannedField>{
    for (final field in type.fields)
      if (field.isLate && field.hasInitializer && !field.isStatic)
        field.name: field,
  };
  if (deferred.length < 2) return const <DeclarationRefusal>[];

  final found = <DeclarationRefusal>[];
  final reported = <String>{};
  final state = <String, int>{};
  final stack = <String>[];

  void walk(String name) {
    state[name] = 1;
    stack.add(name);
    for (final read in deferred[name]!.readsFields) {
      if (!deferred.containsKey(read)) continue;
      final seen = state[read] ?? 0;
      if (seen == 0) {
        walk(read);
      } else if (seen == 1) {
        final ring = stack.sublist(stack.indexOf(read))..add(read);
        if (!ring.any(
          (field) => isDeclarationField(deferred[field]!, typesByName),
        )) {
          continue;
        }
        final key = (ring.toList()..sort()).join(',');
        if (!reported.add(key)) continue;
        found.add(
          DeclarationRefusal(
            owner: type.name,
            field: ring.first,
            path: path,
            reason:
                'its initialiser reads `${ring[1]}`, and that closes a ring: '
                '${ring.join(' -> ')}. Every one of them is late, so each is '
                'waiting on the next and the first read of any of them throws '
                'LateInitializationError naming one field and nothing about '
                'the ring. A collector reads declarations off a constructed '
                'instance, so that read is the boot. Break the ring',
          ),
        );
      }
    }
    stack.removeLast();
    state[name] = 2;
  }

  final names = deferred.keys.toList()..sort();
  for (final name in names) {
    if ((state[name] ?? 0) == 0) walk(name);
  }
  return found;
}

/// Every ring of structs that build each other while being built.
///
/// The edge is "an instance of X holds a declaration whose value is an
/// instance of Y", read off [flattenedDeclarations] so a field a mixin writes
/// counts for every class applying it. A ring in that graph is a constructor
/// that calls itself round the loop.
///
/// Restricted to [entityStructRoot] values, which is the whole of what can
/// close one: every other declaration value is a handle its factory built and
/// handed back, and a handle holds no declarations of its own.
List<DeclarationRefusal> _declarationCycles(
  ScanSources sources,
  Map<String, ScannedType> typesByName,
  Set<String> markers,
) {
  final found = <DeclarationRefusal>[];
  final reported = <String>{};
  final paths = sources.units.keys.toList()..sort();
  for (final path in paths) {
    for (final type in sources.units[path]!.types) {
      if (!isSubtypeOf(type.name, entityStructRoot, typesByName)) continue;
      final ring = _ringFrom(type.name, typesByName, markers);
      if (ring == null) continue;
      final closing = ring.last;
      // The types the ring passes through, which is what names it. Read off
      // the walk rather than off each declaration's owner, because a field a
      // mixin writes is owned by the mixin and the ring goes through the
      // class applying it.
      final through = <String>[
        type.name,
        for (final step in ring) TypeSource.parse(step.valueType)!.name,
      ];
      final ringFrom = through.sublist(through.indexOf(through.last));
      // Keyed on the ring itself, so one ring is one line however many of its
      // members the walk starts from - three, for a ring of three.
      final key = (ringFrom.toSet().toList()..sort()).join(',');
      if (!reported.add(key)) continue;
      final owner = typesByName[closing.owner];
      found.add(
        DeclarationRefusal(
          owner: closing.owner,
          field: closing.name,
          path: owner?.path ?? path,
          reason:
              'it declares ${closing.valueType}, and that closes a ring: '
              '${ringFrom.join(' -> ')}. Each of those builds the next one in '
              'its own field initialiser, so constructing any of them does '
              'not terminate. A struct that owns a variable number of the '
              'same thing spawns them with '
              '`scene.addEntity(prefab, parent: ...)` instead, where the '
              'count is a decision and not a declaration',
        ),
      );
    }
  }
  return found;
}

/// The declarations leading from [name] back to something already on the
/// path, or null when nothing does.
///
/// Depth first over the graph [_declarationCycles] describes, carrying the
/// declarations walked through so the caller can name the ring rather than
/// just report that there is one.
///
/// Every constructed child is an edge, marked or not. `@sub` decides whether
/// a field is *collected*; it decides nothing about whether Dart builds the
/// object, and it is the building that does not terminate.
List<ScannedDeclaration>? _ringFrom(
  String name,
  Map<String, ScannedType> typesByName,
  Set<String> markers, {
  List<String>? path,
  List<ScannedDeclaration>? walked,
}) {
  final onPath = path ?? <String>[];
  final steps = walked ?? <ScannedDeclaration>[];
  final type = typesByName[name];
  if (type == null) return null;
  onPath.add(name);
  for (final declaration in flattenedDeclarations(
    type,
    typesByName,
    markers: markers,
  )) {
    final parsed = TypeSource.parse(declaration.valueType);
    if (parsed == null) continue;
    if (!isSubtypeOf(parsed.name, entityStructRoot, typesByName)) continue;
    steps.add(declaration);
    if (onPath.contains(parsed.name)) {
      onPath.removeLast();
      return steps;
    }
    final deeper = _ringFrom(
      parsed.name,
      typesByName,
      markers,
      path: onPath,
      walked: steps,
    );
    if (deeper != null) {
      onPath.removeLast();
      return deeper;
    }
    steps.removeLast();
  }
  onPath.removeLast();
  return null;
}

/// Every declaration an instance of [type] holds, in the order its
/// initialisers would have run.
///
/// The order is the whole of what this exists for, and it is not the order
/// the names come out of a supertype walk in. Dart runs a class's own
/// instance field initialisers first, then each mixin application's - a
/// mixin application *is* a superclass, so the **last** name in the `with`
/// clause runs first - then the superclass's, the same way, all the way up.
/// Verified rather than assumed: the fixture in
/// `good_tool/test/good_tool_test.dart` builds that shape and reads back the
/// order Dart actually used.
///
/// That order is a row layout. `_SceneDescriptor` hands what
/// `collectDeclarations` returns to `ArchetypeDataDescriptor.declare`, which
/// reserves in the order it is given - so this walk is what decides where
/// every column of every archetype sits, and a walk that visited the mixins
/// the other way round would silently lay every row out differently.
///
/// # What is not walked
///
/// A mixin's `on` clause. It constrains what the mixin may be applied to,
/// and the type it names is initialised by the applying class's own chain -
/// so `mixin WorldTransform2D on Component` contributes its own six columns
/// and nothing of `Component`'s, and a walk that followed `on` would hand
/// `Component`'s over once per mixin that names it.
///
/// An `implements` clause, for the same reason and more obviously: it
/// carries no fields at all.
///
/// A name this walk never read stops it. A class extending something from a
/// package that was not read holds whatever it holds, and this reports what
/// it can see rather than guessing - which is why `good_tool` reads a
/// package's engine dependencies even when it writes into only one of them.
/// What comes back then is a shorter list, and a shorter list is a different
/// row rather than a smaller answer, so [unresolvedSupertypes] answers this
/// same walk with the names that stopped it - what a caller about to write a
/// file refuses on.
///
/// # What is in it that a collector does not write
///
/// Every field whose *type* is a declaration, including the bare-constructor
/// ones with no marker on them. Each carries
/// [ScannedDeclaration.isCollected], and a caller emitting a collector filters
/// on it. The cycle walk deliberately does not: an unmarked child is still
/// constructed, so it still closes a ring.
List<ScannedDeclaration> flattenedDeclarations(
  ScannedType type,
  Map<String, ScannedType> typesByName, {
  required Set<String> markers,
  Set<String>? seen,
}) {
  final visited = seen ?? <String>{};
  if (!visited.add(type.name)) return const <ScannedDeclaration>[];
  final flattened = <ScannedDeclaration>[
    for (final field in type.fields)
      if (!field.isStatic && isDeclarationField(field, typesByName))
        ScannedDeclaration(
          owner: type.name,
          name: field.name,
          valueType: declaredValueType(field)!,
          annotations: <String>[
            for (final annotation in field.annotations)
              if (markers.contains(annotationName(annotation))) annotation,
          ],
          isPrivate: field.isPrivate,
          isCollected: isCollectedDeclarationField(field, typesByName, markers),
        ),
  ];
  for (final mixin in type.mixins.reversed) {
    final applied = typesByName[mixin];
    if (applied == null) continue;
    flattened.addAll(
      flattenedDeclarations(
        applied,
        typesByName,
        markers: markers,
        seen: visited,
      ),
    );
  }
  final superclass = type.superclass;
  if (superclass != null) {
    final above = typesByName[superclass];
    if (above != null) {
      flattened.addAll(
        flattenedDeclarations(
          above,
          typesByName,
          markers: markers,
          seen: visited,
        ),
      );
    }
  }
  return flattened;
}

/// Every name in [type]'s construction chain that [typesByName] does not hold.
///
/// The walk [flattenedDeclarations] makes, answered as the names that stopped
/// it. That one skips a supertype it cannot resolve and hands back what it
/// could see, so a class whose mixin is written in a package the run never
/// read gets a shorter list, in the same order, with nothing said. That list
/// is a row layout: the short one is not a smaller answer to the same
/// question, it is a different archetype.
///
/// The same clauses and no others, which is why it is written out here rather
/// than read off [ScannedType.supertypes]. An `implements` clause carries no
/// fields and a mixin's `on` clause is initialised by the applying class, so
/// neither can shorten a row and neither belongs in this list.
///
/// Nothing is decided here. Whether an unresolved name is a package the run
/// should have been pointed at depends on where it was pointed, and only the
/// caller knows that.
List<String> unresolvedSupertypes(
  ScannedType type,
  Map<String, ScannedType> typesByName, {
  Set<String>? seen,
}) {
  final visited = seen ?? <String>{};
  if (!visited.add(type.name)) return const <String>[];
  final missing = <String>[];
  for (final mixin in type.mixins.reversed) {
    final applied = typesByName[mixin];
    if (applied == null) {
      missing.add(mixin);
      continue;
    }
    missing.addAll(unresolvedSupertypes(applied, typesByName, seen: visited));
  }
  final superclass = type.superclass;
  if (superclass != null) {
    final above = typesByName[superclass];
    if (above == null) {
      missing.add(superclass);
    } else {
      missing.addAll(unresolvedSupertypes(above, typesByName, seen: visited));
    }
  }
  return missing;
}

/// What a run refusing over a deferred declaration says.
///
/// [display] names the file the way the caller names files - a package-
/// relative path from `good_tool`, a project-relative one from `good`.
String declarationRefusalMessage(
  DeclarationScan scan,
  String Function(String path) display,
) {
  final lines = StringBuffer()
    ..writeln('A declaration is not held by the field that declares it:')
    ..writeln();
  for (final refusal in scan.refusals) {
    lines.writeln(
      '  ${display(refusal.path)}: ${refusal.owner}.${refusal.field} - '
      '${refusal.reason}',
    );
  }
  lines
    ..writeln()
    ..writeln(
      'A declaration is a field with its value on it, and the line that '
      'declares it is the line that says so. Every shape above splits that in '
      'two: one half names the field, and the other runs at a moment nothing '
      'at the declaration mentions, on whichever owner happens to be under '
      'construction when it does.',
    );
  return lines.toString();
}

/// What a run refusing over a ring of structs says.
///
/// [display] names files the way [declarationRefusalMessage]'s does.
String declarationCycleMessage(
  DeclarationScan scan,
  String Function(String path) display,
) {
  final lines = StringBuffer()
    ..writeln('A declaration waits on itself, round a ring:')
    ..writeln();
  for (final refusal in scan.cycles) {
    lines.writeln(
      '  ${display(refusal.path)}: ${refusal.owner}.${refusal.field} - '
      '${refusal.reason}',
    );
  }
  lines
    ..writeln()
    ..writeln(
      'Two shapes reach this, and neither has a moment in a run to be caught '
      'in. A declared child is a field holding an ordinary constructor call, '
      'so a ring of them is a constructor that calls itself, and what a run '
      'produces is a StackOverflowError naming nothing. A ring of `late` '
      'initialisers is a LateInitializationError naming one field and nothing '
      'about the ring, thrown at the first touch - which is the collector. '
      'Each ring is a fact about the source, so it is named here instead.',
    );
  return lines.toString();
}

/// What a run stopping over a field it could not type says.
///
/// [display] names files the way [declarationRefusalMessage]'s does.
String unresolvedInitializerMessage(
  DeclarationScan scan,
  String Function(String path) display,
) {
  final lines = StringBuffer()
    ..writeln('A field on a scanned class has no type the analyzer could name:')
    ..writeln();
  for (final refusal in scan.unresolved) {
    lines.writeln(
      '  ${display(refusal.path)}: ${refusal.owner}.${refusal.field} - '
      '${refusal.reason}',
    );
  }
  lines
    ..writeln()
    ..writeln(
      'Each of these is a field on a class this run does scan, and what it '
      'holds decides whether it is a declaration. So an unknown type is said '
      'rather than answered: a field guessed to be no declaration is left out '
      'of the collector, out of the row, and out of the uncollectable list, '
      'with nothing anywhere to read. The reason beside each one is the '
      "analyzer's own, because the edit that fixes it is different every "
      'time - a member that is not there, a package that did not resolve.',
    );
  return lines.toString();
}

// ---------------------------------------------------------------------------
// What `good generate` refuses over
// ---------------------------------------------------------------------------

/// The kernel type every component sits under.
const String componentRoot = 'Component';

/// The kernel type every prefab sits under.
const String entityStructRoot = 'EntityStruct';

/// The kernel type every scene sits under.
const String sceneStructRoot = 'SceneStruct';

/// One column hidden by another of the same name, and where both are.
@immutable
class ShadowedField {
  const ShadowedField({
    required this.owner,
    required this.ownerFile,
    required this.later,
    required this.earlier,
    required this.field,
  });

  /// The class that applies both mixins.
  final String owner;
  final String ownerFile;

  /// The mixin applied later, whose column wins.
  final String later;

  /// The mixin applied earlier, whose column is unreachable.
  final String earlier;

  final String field;
}

/// One `describeX` override that does not chain.
@immutable
class MissingSuper {
  const MissingSuper({
    required this.owner,
    required this.ownerFile,
    required this.method,
  });

  final String owner;
  final String ownerFile;
  final String method;
}

/// What the project-level refusals found.
@immutable
class StructRuleScan {
  const StructRuleScan({
    required this.shadowed,
    required this.missingSuper,
    required this.unresolved,
    required this.unparsed,
  });

  final List<ShadowedField> shadowed;
  final List<MissingSuper> missingSuper;

  /// Every mixin named by a project class that this pass never read, to why.
  ///
  /// Reported rather than swallowed: a project whose engine dependencies are
  /// not resolved yet compares only what it can see, and a run that said
  /// nothing about the rest would read as "your components are fine".
  final Map<String, String> unresolved;

  final List<String> unparsed;
}

/// The two things a project is refused over before anything is generated.
///
/// Both are silent at run time and neither has a symptom anybody would connect
/// to its cause. Two mixins declaring one column name cost a column in every
/// row and send reads to whichever won; a `describeX` override that drops the
/// chain cuts off every mixin applied before it, so those contribute no columns
/// and no query bit, with nothing said anywhere.
///
/// Only the project's own `lib/` is judged. Its engine dependencies are read -
/// a project mixin can shadow `Transform2D.transformOffsetX`, and finding that
/// means reading `goo2d` - but they are never reported on: the engine's own
/// base declarations are `describeX` methods with empty bodies and nothing
/// above them to chain to, and a project build is not the place to raise a
/// defect in a package the project only depends on.
///
/// The chain check asks about components and scenes and nothing else, because
/// those are the types whose `describeX` methods chain. It is not "every
/// `describeX` override must call super": `TimelineStruct.describeAnimation`
/// is **abstract**, so an override of it has no implementation above it and
/// calling super would not compile. It is written that way in `goo2d`'s own
/// example, and a rule keyed on the name alone reports it - measured, before
/// this line was here.
Future<StructRuleScan> scanStructRules(Directory project) async {
  final sources = await readSources(project);
  final typesByName = sources.typesByName;
  final own = p.normalize(p.absolute(p.join(project.path, 'lib')));

  final shadowed = <ShadowedField>[];
  final missingSuper = <MissingSuper>[];
  final unresolved = <String, String>{};

  final paths = sources.units.keys.toList()..sort();
  for (final path in paths) {
    if (!p.isWithin(own, path)) continue;
    final file = p.split(p.relative(path, from: project.path)).join('/');
    for (final type in sources.units[path]!.types) {
      _checkShadowing(
        type,
        file,
        typesByName,
        into: shadowed,
        unresolved: unresolved,
      );
      if (!isSubtypeOf(type.name, componentRoot, typesByName) &&
          !isSubtypeOf(type.name, sceneStructRoot, typesByName)) {
        continue;
      }
      for (final method in type.methods.values) {
        if (!method.name.startsWith('describe')) continue;
        if (method.isStatic || method.isEmptyBody) continue;
        if (!method.annotations.contains('override')) continue;
        if (method.callsSuper) continue;
        missingSuper.add(
          MissingSuper(owner: type.name, ownerFile: file, method: method.name),
        );
      }
    }
  }

  return StructRuleScan(
    shadowed: shadowed,
    missingSuper: missingSuper,
    unresolved: unresolved,
    unparsed: sources.unparsed,
  );
}

/// Walks one class's mixins in application order and reports the collisions.
///
/// In application order because that is the order Dart resolves them in: the
/// last mixin declaring a name is the one every read reaches, and the field
/// underneath it is still allocated, paid for in every row, and unreachable.
///
/// It compares *field names*, and does not first establish that a field is a
/// column. It cannot: `good generate` runs on a project that may never have
/// resolved, so `Field.float64` can be a call on a name this walk never read,
/// and requiring a value type would make the check pass on exactly the project
/// it exists for. Two mixins on one prefab declaring one name is the defect
/// whether or not this pass can say what the field holds.
///
/// A private name is compared only against declarations in the same file. A
/// private field is library-scoped, so `_cached` on two mixins in two files is
/// two different names and shadows nothing.
void _checkShadowing(
  ScannedType type,
  String file,
  Map<String, ScannedType> typesByName, {
  required List<ShadowedField> into,
  required Map<String, String> unresolved,
}) {
  final seen = <String, ScannedType>{};
  for (final supertype in type.supertypes) {
    final applied = typesByName[supertype];
    if (applied == null) {
      unresolved[supertype] =
          'not declared in anything this pass read, so its fields could not be '
          'compared with ${type.name}\'s other mixins';
      continue;
    }
    if (!isSubtypeOf(supertype, componentRoot, typesByName)) continue;
    for (final field in applied.fields) {
      if (field.isStatic) continue;
      final earlier = seen[field.name];
      if (earlier == null) {
        seen[field.name] = applied;
        continue;
      }
      if (earlier.name == applied.name) continue;
      if (field.isPrivate && earlier.path != applied.path) continue;
      into.add(
        ShadowedField(
          owner: type.name,
          ownerFile: file,
          later: applied.name,
          earlier: earlier.name,
          field: field.name,
        ),
      );
    }
  }
}

/// What a run refusing over a shadowed field says.
String shadowedFieldsMessage(StructRuleScan scan) {
  final lines = StringBuffer()
    ..writeln('A field is hidden by another of the same name:')
    ..writeln();
  for (final entry in scan.shadowed) {
    lines.writeln(
      '  ${entry.ownerFile}: ${entry.owner} applies ${entry.later} after '
      '${entry.earlier}, and ${entry.later}.${entry.field} shadows '
      '${entry.earlier}.${entry.field}',
    );
  }
  lines
    ..writeln()
    ..writeln(
      'Both are allocated, so every row of the archetype pays for both, and '
      'every read and write reaches the later one. Nothing at run time says '
      'so. Prefix each component\'s columns with its own name, the way '
      'Transform2D prefixes transformOffsetX.',
    );
  return lines.toString();
}

/// What a run refusing over a broken `describeX` chain says.
String missingSuperMessage(StructRuleScan scan) {
  final lines = StringBuffer()
    ..writeln('A describe pass does not chain:')
    ..writeln();
  for (final entry in scan.missingSuper) {
    lines.writeln(
      '  ${entry.ownerFile}: ${entry.owner}.${entry.method} does not call '
      'super.${entry.method}()',
    );
  }
  lines
    ..writeln()
    ..writeln(
      'Each describe pass is chained through the mixins applied to a prefab, '
      'so an override that does not call super cuts off every mixin applied '
      'before it: those contribute no columns and no query bit, and nothing at '
      'run time reports it.',
    );
  return lines.toString();
}

// ---------------------------------------------------------------------------
// Which scene needs which asset
// ---------------------------------------------------------------------------

/// Which assets each scene reaches, for chunk grouping.
@immutable
class SceneUsage {
  const SceneUsage({
    required this.byScene,
    required this.unresolved,
    required this.unparsed,
  });

  /// Asset paths, keyed by the scene class that reaches them.
  final Map<String, Set<String>> byScene;

  /// Every asset this pass could not attribute to a scene, to why.
  ///
  /// These go in the shared chunk. A wrong attribution ships a chunk without
  /// an asset a scene needs, so anything not established is left unattributed
  /// rather than guessed at - `planPack` groups by directory when this comes
  /// back empty, and puts the leftovers in the chunk every scene loads.
  final Map<String, String> unresolved;

  final List<String> unparsed;
}

/// Which scene reaches which asset, read out of the project's own `lib/`.
///
/// A scene reaches an asset through the prefabs it declares: the scene names
/// `Player`, `Player` names `Textures.playerIdle`, and `Textures.playerIdle` is
/// an entry in [assets]. So this walks the project's types, keeps the ones that
/// are scenes and the ones that are prefabs, and follows the names one writes
/// about the other - transitively, because a prefab declares child prefabs.
///
/// It follows *names written in the body*, not resolved references. A scene
/// that mentions `Player` anywhere is taken to reach `Player`, which over-
/// attributes rather than under-attributes: an asset in one chunk too many
/// costs bytes, and one missing from the chunk a scene loads is a game that
/// fails at its first asset load. The same reason [unresolved] exists.
Future<SceneUsage> scanScenes(Directory project, AssetScan assets) async {
  final sources = await readSources(project);
  final typesByName = sources.typesByName;
  final own = p.normalize(p.absolute(p.join(project.path, 'lib')));

  final pathByIdentifier = <String, String>{
    for (final asset in assets.textures) asset.identifier: asset.path,
    for (final asset in assets.audio) asset.identifier: asset.path,
  };

  final scenes = <ScannedType>[];
  final projectTypes = <String, ScannedType>{};
  final paths = sources.units.keys.toList()..sort();
  for (final path in paths) {
    if (!p.isWithin(own, path)) continue;
    for (final type in sources.units[path]!.types) {
      projectTypes[type.name] = type;
      // Not the root itself. `isSubtypeOf(x, x)` is true, so a project that
      // declares its own `SceneStruct` - a fixture, a fork - would otherwise
      // get a chunk named after the abstract base that loads nothing.
      if (type.name != sceneStructRoot &&
          isSubtypeOf(type.name, sceneStructRoot, typesByName)) {
        scenes.add(type);
      }
    }
  }

  final byScene = <String, Set<String>>{};
  final attributed = <String>{};
  for (final scene in scenes) {
    final reached = <String>{};
    final seen = <String>{};
    _walkReferences(scene, projectTypes, typesByName, seen, reached);
    final chunk = <String>{};
    for (final identifier in reached) {
      final path = pathByIdentifier[identifier];
      if (path == null) continue;
      chunk.add(path);
      attributed.add(identifier);
    }
    byScene[scene.name] = chunk;
  }

  final unresolved = <String, String>{};
  for (final entry in pathByIdentifier.entries) {
    if (attributed.contains(entry.key)) continue;
    unresolved[entry.key] =
        'nothing this pass read reaches it from a $sceneStructRoot, so it goes '
        'in the shared chunk';
  }

  return SceneUsage(
    byScene: byScene,
    unresolved: unresolved,
    unparsed: sources.unparsed,
  );
}

/// Collects the asset identifiers [type] names, and those of what it names.
void _walkReferences(
  ScannedType type,
  Map<String, ScannedType> projectTypes,
  Map<String, ScannedType> typesByName,
  Set<String> seen,
  Set<String> into,
) {
  if (!seen.add(type.name)) return;
  into.addAll(type.assetIdentifiers);
  for (final name in type.referencedNames) {
    final referenced = projectTypes[name];
    if (referenced == null) continue;
    if (!isSubtypeOf(name, entityStructRoot, typesByName) &&
        !isSubtypeOf(name, componentRoot, typesByName)) {
      continue;
    }
    _walkReferences(referenced, projectTypes, typesByName, seen, into);
  }
}
