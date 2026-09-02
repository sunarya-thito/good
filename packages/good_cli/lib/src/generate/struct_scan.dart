import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:good_cli/src/generate/engine_dependency.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:analyzer/dart/analysis/features.dart';
import 'package:pub_semver/pub_semver.dart';

/// One column that another declaration hides under the same name.
@immutable
class ShadowedField {
  const ShadowedField({
    required this.field,
    required this.winner,
    required this.winnerFile,
    required this.loser,
    required this.loserFile,
  });

  /// The member name both sides declare.
  final String field;

  /// The declaration whose member the name resolves to - the one later in the
  /// applied order.
  final String winner;

  /// The file [winner] is declared in.
  final String winnerFile;

  /// The declaration whose member is unreachable under [field].
  final String loser;

  /// The file [loser] is declared in.
  final String loserFile;
}

/// One `describeX` override in a component mixin that does not chain.
@immutable
class MissingSuperCall {
  const MissingSuperCall({
    required this.mixin,
    required this.hook,
    required this.file,
  });

  /// The mixin whose override drops the call.
  final String mixin;

  /// Which pass the override drops - `describeStruct` today.
  final String hook;

  final String file;
}

@immutable
class StructScan {
  const StructScan({
    required this.shadowed,
    required this.missingSuper,
    required this.unresolved,
  });

  /// Every collision found, in the order the structs were read.
  final List<ShadowedField> shadowed;

  /// Every component mixin that overrides a declare-time hook and does not
  /// chain to the one below it.
  final List<MissingSuperCall> missingSuper;

  /// Mixins in some struct's applied order this pass could not read, as
  /// `Struct with Mixin -> why`.
  ///
  /// Reported and not treated as clean. A mixin from a package outside the
  /// engine is invisible to a parsed scan, so "no collision found" for that
  /// struct means "none among the parts I could see" - saying so is the
  /// difference between a check you can trust and one that is quiet for two
  /// different reasons.
  final Map<String, String> unresolved;

  /// Whether the scan found nothing that should stop a build. [unresolved] is
  /// reported and does not count - see its own doc.
  bool get isEmpty => shadowed.isEmpty && missingSuper.isEmpty;
}

/// Finds columns that two declarations on one struct declare under one name.
///
/// # What goes wrong without this
///
/// A component is a mixin, so two of them declaring `speed` is not an error in
/// Dart - it is an override. Both field initialisers still run, so both columns
/// are allocated and every row grows by both, and `speed` resolves to whichever
/// declaration comes last in the applied order. The other column is still paid
/// for in every row and no expression can reach it.
///
/// Nothing at run time can report that. `Field.float64()` declares against the
/// descriptor the framework has open and is never told what Dart field holds
/// the result, so `data_layout.dart` tracks no names at all - two mixins each
/// declaring `final x = Field.float64()` reach the engine as two anonymous
/// registrations, which is exactly what two legitimately different columns look
/// like. The name exists in the source and nowhere else, so this is a source
/// scan, and it can say `Velocity.x shadows Transform2D.x` with both files
/// where a throw could only ever have said that a row was bigger than
/// expected.
///
/// # What it reads
///
/// Parsed, not resolved, for the reason `scanScenes` gives: resolution needs
/// every dependency's summary and seconds per run, and the shapes that matter
/// here are syntactic. It reads the project's own `lib/`, plus the engine
/// packages it finds through `.dart_tool/package_config.json` - without those,
/// `Child.childParent` and `Transform2D.transformOffsetX` would be invisible,
/// and those are the collisions a user is likeliest to walk into.
///
/// A name that resolves to two different files is not guessed at. Both land in
/// [StructScan.unresolved], because a build error that fires wrongly is worse
/// than the bug it is looking for.
StructScan scanStructRules(Directory projectDir, {ScanSources? sources}) {
  final read = sources ?? readSources(projectDir);
  final byName = read.byName;
  if (byName.isEmpty && read.roots.isEmpty) {
    return const StructScan(
      shadowed: <ShadowedField>[],
      missingSuper: <MissingSuperCall>[],
      unresolved: <String, String>{},
    );
  }

  final shadowed = <ShadowedField>[];
  final missingSuper = <MissingSuperCall>[];
  final unresolved = <String, String>{};
  for (final owners in byName.values) {
    for (final owner in owners) {
      if (owner.isStruct) {
        _check(owner, byName, shadowed, unresolved, projectDir);
      }
      _checkHooks(owner, byName, missingSuper, unresolved, projectDir);
    }
  }
  return StructScan(
    shadowed: shadowed,
    missingSuper: missingSuper,
    unresolved: unresolved,
  );
}

/// Everything one parse of the project and its engine packages produced.
///
/// Two passes read it, and they are in different packages. [scanStructRules] is
/// looking for defects and runs on a user's project; `scanAccessors` in
/// `good_tool` is looking for columns to generate a property for and runs over
/// this repository. Both need the same declarations marked the same way - which
/// classes are structs, which mixins end up on a `Component` - so the walk and
/// the marking live here once, and only the questions differ.
///
/// Which is why several fields below have no reader inside this package. They
/// describe a declaration rather than answer a question, and the cost of
/// recording them is a walk over tokens already parsed; the alternative is
/// `good_tool` parsing the same trees a second time to ask about the same
/// files.
@immutable
class ScanSources {
  const ScanSources({
    required this.byName,
    required this.units,
    required this.interfaceMembers,
    required this.accessorExtensions,
    required this.packageLibs,
    required this.roots,
  });

  /// Every class and mixin read, by bare name.
  ///
  /// A list rather than one entry: two libraries can each declare a `Velocity`,
  /// and this pass has no resolution to tell which one a `with Velocity` means.
  /// Ambiguity is reported, never picked.
  final Map<String, List<Owner>> byName;

  /// The directives and top-level names of each file read, by normalised path.
  ///
  /// The `export` half is what a barrel walk needs; `declaredNames` is what
  /// answers "which file declares this type", which is how `good_tool` writes
  /// an import for a generated file.
  final Map<String, ScannedUnit> units;

  /// Every member name each named declaration declares, by declaration name -
  /// classes, mixins, enums and extension types alike.
  ///
  /// `Entity` and `Accessor` are extension types, so this is the only place
  /// their members appear; [byName] holds classes and mixins. A declaration
  /// name that two libraries both use has both sets folded together, which
  /// over-reports rather than under-reports, and over-reporting is the safe
  /// direction for the one thing that reads it.
  final Map<String, Set<String>> interfaceMembers;

  /// The members of every hand-written `extension ... on Accessor<T>`, by the
  /// component `T` names.
  ///
  /// `Accessor`'s own doc tells people to put a component's helpers in one of
  /// these, and the engine has five. A generated property sharing a name with
  /// one of them is not silent - two applicable extensions declaring one member
  /// is an ambiguity error at the use site - but it is an error in *shipped*
  /// code, raised nowhere near the column that caused it, so `good_tool`
  /// refuses rather than emitting it.
  ///
  /// Keyed on the exact component named in the type argument. An extension on a
  /// supertype of it applies to the same receiver and is not seen here; that is
  /// a subtype question, and this pass resolves nothing.
  final Map<String, Set<String>> accessorExtensions;

  /// Every package the project's package config named, as package name to the
  /// normalised path of its `lib/`.
  final Map<String, String> packageLibs;

  /// The directories walked - the project's own `lib/`, plus the engine
  /// packages it resolves. Empty when there is nothing to read at all.
  final List<String> roots;
}

/// One file's directives and the top-level names it declares.
@immutable
class ScannedUnit {
  ScannedUnit({
    required this.exports,
    required this.declaredNames,
    required this.exportedNames,
  });

  /// Every `export` this file carries, in source order.
  final List<ScannedExport> exports;

  /// Every top-level name declared here - classes, mixins, enums, extension
  /// types, typedefs, functions and variables.
  final Set<String> declaredNames;

  /// Every name this file re-exports under `export ... show`, which is not the
  /// same question: a `show` list can name something the exported library
  /// declares and this file does not.
  final Set<String> exportedNames;
}

/// One `export` directive: where it points and what it lets through.
@immutable
class ScannedExport {
  const ScannedExport({
    required this.uri,
    required this.shown,
    required this.hidden,
  });

  /// The URI as written - relative, `package:` or `dart:`.
  final String uri;

  /// The `show` list, or empty when there is none. A non-empty list is the
  /// whole of what this directive exports.
  final Set<String> shown;

  /// The `hide` list, or empty when there is none.
  final Set<String> hidden;
}

/// Parses the project and its engine packages once.
///
/// `parseString` on each file, not an `AnalysisContextCollection`. The
/// collection resolves packages, reads every pubspec and builds a context per
/// root before it hands back a syntax tree, and none of that is used here -
/// these passes only ever look at tokens. Against the demo project - 49 engine
/// files plus its own - dropping it took the scan from 826ms to 272ms on a
/// second run and from 563ms to 136ms warm, against 1-7ms for everything
/// `good generate` did before this check existed.
///
/// [rootOverride] replaces the directories walked. `good_tool` passes the
/// `lib/` of every package in this repository, which is not a set any one
/// project's package config describes - a project resolves the engine packages
/// it depends on, and the repository is all of them at once.
///
/// [exclude] drops individual files from the walk, by normalised path. What
/// needs it is a generator reading the tree it writes into: `good_tool` emits
/// an `extension ... on Accessor<Transform2D>`, and on the next run that file
/// is an ordinary part of `packages/goo2d/lib/` declaring a member named
/// `offsetX`. Without this the tool's second run reports its own first run as a
/// collision - measured, on all ten components at once.
ScanSources readSources(
  Directory projectDir, {
  List<String>? rootOverride,
  Set<String> exclude = const <String>{},
}) {
  final roots = rootOverride ?? _scanRoots(projectDir);
  final skip = <String>{for (final path in exclude) p.normalize(path)};
  final byName = <String, List<Owner>>{};
  final units = <String, ScannedUnit>{};
  final interfaceMembers = <String, Set<String>>{};
  final accessorExtensions = <String, Set<String>>{};

  // Which library file each part file belongs to, taken from the `part`
  // directives of the units below. Collected here and applied afterwards,
  // because a part is read before its library as often as not.
  final partOwner = <String, String>{};
  for (final root in roots) {
    for (final file in Directory(root).listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      if (skip.contains(p.normalize(file.path))) continue;
      final CompilationUnit unit;
      try {
        unit = parseString(
          content: file.readAsStringSync(),
          featureSet: _featureSet,
          throwIfDiagnostics: false,
        ).unit;
      } on ArgumentError {
        // Unreadable or not Dart after all. A file this pass cannot parse
        // declares nothing it can compare, and whatever names it held show up
        // as unresolved on the structs that mention them.
        continue;
      }
      _readParts(unit, file.path, partOwner);
      final visitor = _OwnerVisitor(file.path);
      unit.accept(visitor);
      for (final owner in visitor.owners) {
        byName.putIfAbsent(owner.name, () => <Owner>[]).add(owner);
      }
      visitor.members.forEach((declaration, names) {
        interfaceMembers.putIfAbsent(declaration, () => <String>{}).addAll(
          names,
        );
      });
      visitor.accessorExtensions.forEach((component, names) {
        accessorExtensions.putIfAbsent(component, () => <String>{}).addAll(
          names,
        );
      });
      units[p.normalize(file.path)] = _readUnit(unit);
    }
  }

  _markLibraries(byName, partOwner);
  _markStructs(byName);
  _markComponentMixins(byName);

  // A part's declarations belong to its library's namespace, so an `export` of
  // the library reaches them. The engine has no parts today; this is here so
  // the export walk answers for a project that does, rather than quietly
  // deciding one of its components is not exported.
  partOwner.forEach((part, library) {
    final from = units[part];
    final into = units[p.normalize(library)];
    if (from == null || into == null) return;
    into.declaredNames.addAll(from.declaredNames);
  });

  return ScanSources(
    byName: byName,
    units: units,
    interfaceMembers: interfaceMembers,
    accessorExtensions: accessorExtensions,
    packageLibs: _packageLibs(projectDir),
    roots: roots,
  );
}

/// Reads one file's `export` directives and the top-level names it declares.
ScannedUnit _readUnit(CompilationUnit unit) {
  final exports = <ScannedExport>[];
  final exportedNames = <String>{};
  for (final directive in unit.directives) {
    if (directive is! ExportDirective) continue;
    final uri = directive.uri.stringValue;
    if (uri == null) continue;
    final shown = <String>{};
    final hidden = <String>{};
    for (final combinator in directive.combinators) {
      if (combinator is ShowCombinator) {
        for (final name in combinator.shownNames) {
          shown.add(name.name);
        }
      } else if (combinator is HideCombinator) {
        for (final name in combinator.hiddenNames) {
          hidden.add(name.name);
        }
      }
    }
    exportedNames.addAll(shown);
    exports.add(ScannedExport(uri: uri, shown: shown, hidden: hidden));
  }

  final declared = <String>{};
  for (final declaration in unit.declarations) {
    switch (declaration) {
      case NamedCompilationUnitMember(:final name):
        declared.add(name.lexeme);
      case TopLevelVariableDeclaration(:final variables):
        for (final variable in variables.variables) {
          declared.add(variable.name.lexeme);
        }
      default:
        break;
    }
  }
  return ScannedUnit(
    exports: exports,
    declaredNames: declared,
    exportedNames: exportedNames,
  );
}

/// Records each file [unit] claims as a part of itself, keyed by the part.
///
/// The `part` side is read and the `part of` side is not, because only one of
/// them is always a path. `part of` still allows the old dotted library name,
/// which cannot be turned back into a file without resolving; `part` is a URI
/// relative to the file holding it, every time. A `package:` or `dart:` URI is
/// skipped - a part is a file beside its library, and matching one to a scan
/// root would mean resolving package URIs, which this pass does not do.
///
/// What that leaves out is a part whose library is not itself scanned, which
/// keeps the part's own path as its library. That needs a `part` pointing out
/// of the directory the library lives in, and the roots here are whole `lib/`
/// trees, so the library is in the scan whenever the part is.
void _readParts(
  CompilationUnit unit,
  String file,
  Map<String, String> partOwner,
) {
  for (final directive in unit.directives) {
    if (directive is! PartDirective) continue;
    final uri = directive.uri.stringValue;
    if (uri == null || uri.contains(':')) continue;
    partOwner[p.normalize(p.join(p.dirname(file), uri))] = p.normalize(file);
  }
}

/// Points every declaration at the library it belongs to, and not at the file
/// it is written in.
///
/// The two differ exactly when `part` splits one library across several files,
/// and the difference decides a private name: `_dirty` in two libraries is two
/// independent members, `_dirty` in two parts of one library is a genuine
/// collision. [_check] keys on the answer.
///
/// This is the library the language means and not a proxy for it. It comes off
/// the directives of units this pass has already parsed, so it costs a walk
/// over a handful of tokens per file - the element model would give the same
/// answer for the seconds of resolution [scanStructRules] exists to avoid.
void _markLibraries(
  Map<String, List<Owner>> byName,
  Map<String, String> partOwner,
) {
  if (partOwner.isEmpty) return;
  for (final owners in byName.values) {
    for (final owner in owners) {
      // Walked rather than looked up once, because a part may itself have
      // parts. The seen set is for a source that makes a cycle: Dart rejects
      // that, but nothing here resolves, so this has to terminate on its own.
      final seen = <String>{owner.library};
      for (
        var next = partOwner[owner.library];
        next != null && seen.add(next);
        next = partOwner[owner.library]
      ) {
        owner.library = next;
      }
    }
  }
}

/// Decides which classes are laid out as entity rows, so the rest are skipped.
///
/// Without this the pass walks every class in the project and its dependencies,
/// and reports each unreadable supertype it meets. Against the demo project
/// that meant 21 notes about `ChangeNotifier`, `StatefulWidget` and `Iterable` -
/// none of which can declare a column, all of which drown the one line that
/// would matter. A widget is not a struct and is nobody's shadowing risk.
///
/// A class counts when it declares a column of its own, or when it descends
/// from one that does. That second half needs a fixed point: `class Player
/// extends Base` is a struct only once `Base` is known to be one, and the files
/// arrive in no particular order.
void _markStructs(Map<String, List<Owner>> byName) {
  bool declaresColumn(Owner owner) =>
      owner.fields.any((field) => field.isColumn);

  for (final owners in byName.values) {
    for (final owner in owners) {
      owner.isStruct =
          declaresColumn(owner) ||
          _isStructRoot(owner.superName) ||
          owner.mixes.any(_isStructRoot);
    }
  }

  var changed = true;
  while (changed) {
    changed = false;
    for (final owners in byName.values) {
      for (final owner in owners) {
        if (owner.isStruct) continue;
        final parents = <String>[
          if (owner.superName != null) owner.superName!,
          ...owner.mixes,
        ];
        for (final parent in parents) {
          final candidates = byName[parent];
          if (candidates == null) continue;
          if (candidates.any((c) => c.isStruct || declaresColumn(c))) {
            owner.isStruct = true;
            changed = true;
            break;
          }
        }
      }
    }
  }
}

/// Decides which mixins end up applied to a `Component`, and are therefore
/// subject to the chained-hook rule.
///
/// `mixin Transform2D on Component` is the direct case. A mixin constrained to
/// another component mixin - `mixin Aimed on Transform2D` - is one too, and
/// needs a fixed point for the same reason [_markStructs] does: the files
/// arrive in no order, so `Aimed` can only be settled once `Transform2D` is.
void _markComponentMixins(Map<String, List<Owner>> byName) {
  for (final owners in byName.values) {
    for (final owner in owners) {
      owner.isComponentMixin =
          owner.isMixin && owner.onConstraints.any(_isComponentRoot);
    }
  }

  var changed = true;
  while (changed) {
    changed = false;
    for (final owners in byName.values) {
      for (final owner in owners) {
        if (!owner.isMixin || owner.isComponentMixin) continue;
        for (final constraint in owner.onConstraints) {
          final candidates = byName[constraint];
          if (candidates == null) continue;
          if (candidates.any((c) => c.isComponentMixin)) {
            owner.isComponentMixin = true;
            changed = true;
            break;
          }
        }
      }
    }
  }
}

/// The two interfaces a component mixin is constrained to.
bool _isComponentRoot(String name) =>
    name == 'Component' || name == 'MultiComponent';

/// Reports a component mixin whose `describeX` override does not chain.
///
/// # Why a mixin and not a class
///
/// `EntityStruct` and friends carry `@mustCallSuper` on these hooks, and the
/// analyzer enforces it for anything that overrides them - a user's own struct
/// subclass is already covered. It cannot be made to cover a component mixin:
/// `@mustCallSuper` reports only where there is a concrete super implementation
/// to point at, and `Component` declares both hooks with no body. So the
/// annotation is inert exactly where mixins chain, which is the whole of the
/// gap and the reason this is here.
///
/// `describeType` is not in the set any more and needs nothing here: a
/// component declares its type in a field initialiser, which no chain runs
/// through and so none can be left out of.
///
/// A mixin that never overrides a hook is fine and is not mentioned. Only an
/// override that leaves the call out is a defect, and the engine's own eleven
/// component mixins all chain, so this fires on nothing that ships today.
void _checkHooks(
  Owner owner,
  Map<String, List<Owner>> byName,
  List<MissingSuperCall> into,
  Map<String, String> unresolved,
  Directory projectDir,
) {
  // No `isMixin` test: [_markComponentMixins] only ever sets this on a mixin,
  // so asking twice would be a second guard standing in front of the first -
  // and a redundant guard is what lets a test pass while the check it names is
  // switched off.
  if (owner.hooks.isEmpty) return;
  if (!owner.isComponentMixin) {
    // It overrides a declare-time hook but nothing says it is a component. If
    // its constraint is simply something this pass never read, that is worth
    // saying; if it is a mixin on some unrelated type that happens to declare a
    // method by the same name, there is nothing to report and nothing to warn
    // about either.
    final unreadable = owner.onConstraints.where((c) => byName[c] == null);
    for (final constraint in unreadable) {
      unresolved['${owner.name} on $constraint'] =
          'declares ${owner.hooks.map((h) => h.hook).join(', ')} but its '
          'constraint was not read, so whether it is a component mixin is '
          'unknown and its chaining was not checked';
    }
    return;
  }
  for (final hook in owner.hooks) {
    if (hook.callsSuper) continue;
    into.add(
      MissingSuperCall(
        mixin: owner.name,
        hook: hook.hook,
        file: _display(owner.file, projectDir),
      ),
    );
  }
}

/// Whether [name] is one of the types the engine lays rows out from.
bool _isStructRoot(String? name) =>
    name == 'EntityStruct' || name == 'SceneStruct';

/// Walks one struct's applied order and records every name declared twice.
///
/// The order is Dart's own: `class C extends S with A, B` applies S, then A,
/// then B, then C's own members, and each later part overrides the name of an
/// earlier one. So the last declaration of a name wins and every earlier one is
/// what gets reported as hidden.
void _check(
  Owner struct,
  Map<String, List<Owner>> byName,
  List<ShadowedField> shadowed,
  Map<String, String> unresolved,
  Directory projectDir,
) {
  final applied = <Owner>[];
  _linearize(struct, byName, applied, <String>{}, unresolved, struct.name);

  // member -> the declaration that most recently claimed it.
  //
  // Keyed by what the name resolves *as*, which for a `_`-prefixed one is the
  // name together with its library: `Health._dirty` and `Shield._dirty` in two
  // libraries are two independent members, both reachable, and neither hides
  // the other. Dart gives that answer and so must this, or correct code stops
  // a build (#178).
  //
  // Qualifying the key beats testing the two libraries once a collision is
  // found. With `_dirty` declared by A and C in one library and by B in
  // another, applied A, B, C, a name-keyed map holds B by the time C is read,
  // the libraries differ, and the real A/C collision goes unreported.
  final claimed = <String, Owner>{};
  for (final part in applied) {
    for (final field in part.fields) {
      final member = _member(part, field.name);
      final previous = claimed[member];
      if (previous != null && previous != part) {
        // At least one side has to be a column for the row to grow, which is
        // the harm this reports. Two plain fields colliding is ordinary Dart
        // and the author's business.
        if (previous.fields.byName(field.name)!.isColumn || field.isColumn) {
          shadowed.add(
            ShadowedField(
              field: field.name,
              winner: part.name,
              winnerFile: _display(part.file, projectDir),
              loser: previous.name,
              loserFile: _display(previous.file, projectDir),
            ),
          );
        }
      }
      claimed[member] = part;
    }
  }
}

/// What a field name resolves as: a private one only within its library, a
/// public one anywhere.
String _member(Owner owner, String name) =>
    name.startsWith('_') ? '${owner.library}::$name' : name;

/// Appends [owner]'s parts in applied order, base first.
void _linearize(
  Owner owner,
  Map<String, List<Owner>> byName,
  List<Owner> into,
  Set<String> seen,
  Map<String, String> unresolved,
  String rootName,
) {
  if (!seen.add(owner.name)) return;
  final superName = owner.superName;
  if (superName != null && !_isRootType(superName)) {
    _resolveInto(
      superName,
      byName,
      into,
      seen,
      unresolved,
      rootName,
      'extends',
    );
  }
  for (final mixin in owner.mixes) {
    _resolveInto(mixin, byName, into, seen, unresolved, rootName, 'with');
  }
  into.add(owner);
}

void _resolveInto(
  String name,
  Map<String, List<Owner>> byName,
  List<Owner> into,
  Set<String> seen,
  Map<String, String> unresolved,
  String rootName,
  String clause,
) {
  final candidates = byName[name];
  if (candidates == null || candidates.isEmpty) {
    unresolved['$rootName $clause $name'] =
        'not declared in this project or in the engine packages this pass '
        'can see, so its columns were not compared';
    return;
  }
  if (candidates.length > 1) {
    unresolved['$rootName $clause $name'] =
        '${candidates.length} declarations share this name; a parsed scan '
        'cannot tell which one is applied, so it was not compared';
    return;
  }
  _linearize(candidates.single, byName, into, seen, unresolved, rootName);
}

/// The types every struct bottoms out at, which declare no columns of their own
/// and would only ever be reported as unresolved.
bool _isRootType(String name) => const <String>{
  'EntityStruct',
  'SceneStruct',
  'Component',
  'MultiComponent',
  'Object',
}.contains(name);

/// The directories this pass parses: the project's own `lib/`, plus the engine
/// packages it depends on.
///
/// The engine half is what makes the check useful instead of merely correct.
/// The engine's own columns are prefixed (#133) - `Child.childParent`,
/// `Camera.cameraZoom` - so a collision with one is rare, but a third-party
/// component author follows no such rule, and neither does a user who happens
/// to pick the same name. Reading only the project would leave every engine
/// declaration in `unresolved`.
List<String> _scanRoots(Directory projectDir) {
  final roots = <String>[];
  final lib = Directory('${projectDir.path}/lib');
  if (lib.existsSync()) roots.add(p.normalize(p.absolute(lib.path)));

  // Overlap is dropped, and it is not a corner case: a package config lists
  // the project's own package alongside its dependencies, so a project whose
  // name happens to look like an engine one adds its own `lib/` a second time.
  // Every declaration in it then appears twice, every mixin becomes two
  // candidates, and the pass reports the whole project as ambiguous instead of
  // checking it. The demo is called `goo2d_example` and did exactly that.
  for (final path in _enginePackageLibs(projectDir)) {
    final overlaps = roots.any(
      (root) => p.equals(root, path) || p.isWithin(root, path),
    );
    if (!overlaps) roots.add(path);
  }
  return roots;
}

/// The `lib/` of every engine package the project resolves, from its package
/// config.
///
/// Absent before a `pub get`, and that is not an error here: the mixins go to
/// [StructScan.unresolved] and are reported, which is the same answer this pass
/// gives for any other declaration it cannot read.
///
/// Which of them count as engine packages is [EngineDependencies]' question and
/// not a name test (#305). The prefix that used to stand here -
/// `name == 'good' || name.startsWith('goo')` - walked `google_fonts`,
/// `google_sign_in`, `googleapis`, `goodies` and `gooey` on every generate, and
/// missed a third-party component package outright.
List<String> _enginePackageLibs(Directory projectDir) {
  final resolved = resolvedPackages(projectDir);
  final engine = EngineDependencies(
    roots: <String, Directory>{
      for (final entry in resolved.entries) entry.key: entry.value.root,
    },
  );
  return <String>[
    for (final entry in _packageLibs(projectDir).entries)
      if (engine.contains(entry.key)) entry.value,
  ];
}

/// Every package the config names, as package name to the absolute,
/// normalised path of its `lib/`.
///
/// Every package and not only the engine's, because this is also what turns a
/// `package:` URI in an `export` directive into a file - and a barrel is
/// perfectly entitled to re-export something from a package this pass does not
/// walk. Only directories that exist are listed, so a config left over from a
/// deleted dependency drops out here rather than at every use.
Map<String, String> _packageLibs(Directory projectDir) => <String, String>{
  for (final entry in resolvedPackages(projectDir).entries)
    if (Directory(entry.value.lib).existsSync()) entry.key: entry.value.lib,
};

String _display(String file, Directory projectDir) {
  final root = p.normalize(p.absolute(projectDir.path));
  final full = p.normalize(file);
  if (p.isWithin(root, full)) return p.relative(full, from: root);
  // Outside the project - an engine package. The last two segments locate it
  // well enough to open, without an absolute path that is different on every
  // machine.
  final parts = p.split(full);
  return parts.length <= 2 ? full : p.joinAll(parts.sublist(parts.length - 2));
}

/// One field a declaration contributes.
@immutable
class ColumnField {
  const ColumnField(this.name, {required this.isColumn, this.valueType});

  final String name;

  /// Whether this declaration allocates a column - a `Field.*` initialiser,
  /// `EntityStruct.of`, or the `late final DataPointer<...>` shape a
  /// `describeStruct` body fills in.
  final bool isColumn;

  /// What `column[entity]` hands back, written as Dart source, or `null` where
  /// this pass cannot say.
  ///
  /// `null` for three different things, and the caller has to treat them alike
  /// because a parse cannot tell them apart with certainty: a field that is not
  /// a column at all; a column whose value type is a type argument nothing in
  /// the source spells (`Field.heapObject(Foo.new)`); and an array column,
  /// which has no `column[entity]` to hand anything back from - it is read
  /// `get(entity, index)`. `good_tool` generates a property only where this is
  /// set, so all three are skipped the same way.
  ///
  /// This is a *name*, not a resolved type. Whether a generated file can spell
  /// it is a separate question, answered where the file is written.
  final String? valueType;
}

extension on List<ColumnField> {
  ColumnField? byName(String name) {
    for (final field in this) {
      if (field.name == name) return field;
    }
    return null;
  }
}

/// One class or mixin that can contribute fields to a struct.
class Owner {
  Owner(this.name, this.file) : library = p.normalize(file);

  final String name;
  final String file;

  /// The file of the library this declaration is in - its own, unless some
  /// other file claims it with `part`. Set by [_markLibraries], which is also
  /// where the difference between this and [file] matters.
  String library;

  /// Whether entities are laid out from this - a class whose own applied order
  /// is worth checking. Set by [_markStructs] once every file has been read,
  /// because it depends on what the class descends from.
  bool isStruct = false;

  /// Whether this is a mixin that ends up applied to a `Component`, and so is
  /// subject to the chained-hook rule. Set by [_markComponentMixins].
  bool isComponentMixin = false;

  /// True for a `mixin` declaration, false for a `class`.
  bool isMixin = false;

  String? superName;

  /// The `on` clause of a mixin declaration.
  final List<String> onConstraints = <String>[];

  final List<String> mixes = <String>[];
  final List<ColumnField> fields = <ColumnField>[];

  /// The declare-time hooks this declaration overrides with a body.
  final List<HookOverride> hooks = <HookOverride>[];

  /// The `T` of every `Component.type<T>()` field initialiser in this
  /// declaration, in source order.
  ///
  /// These are exactly the types `ComponentTypeRegistry.bitFor` is called
  /// with, which is what `good_tool` writes the generated bit table from
  /// (#18). Read from the initialisers rather than from [isComponentMixin],
  /// because the two sets are not the same: `CollisionListener` is a mixin on
  /// `Component` that declares no type, and giving it a bit would spend a slot
  /// out of sixty-four on a type no signature ever carries.
  ///
  /// A prefab's own type contributes nothing here and cannot: it is
  /// `runtimeType`, the value of an expression, so only the running program
  /// knows it. The framework adds that bit once the prefab is built, and that
  /// is why a prefab's bit stays a run-time assignment however much of this is
  /// generated.
  final List<String> componentTypes = <String>[];
}

/// One `describeX` override, and whether it chains.
@immutable
class HookOverride {
  const HookOverride(this.hook, {required this.callsSuper});

  final String hook;
  final bool callsSuper;
}

/// The declare-time passes a component contributes to, each chained through
/// every mixin on the entity.
///
/// One member, and it stays a set: `describeType` left it in #314 and
/// `describeAssets` in the stage after, both because the thing they declared
/// moved onto a field initialiser, which nothing chains through and so
/// nothing can leave out.
const Set<String> _describeHooks = <String>{'describeStruct'};

/// Looks for `super.<hook>(...)` anywhere in one method body.
///
/// Matched on the AST and not the text, so a mention inside a comment or a
/// string is not a call, and a `super.somethingElse(data)` inside a
/// `describeStruct` body does not count as chaining `describeStruct`.
class _SuperCallVisitor extends RecursiveAstVisitor<void> {
  _SuperCallVisitor(this._hook);

  final String _hook;
  bool found = false;

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.target is SuperExpression && node.methodName.name == _hook) {
      found = true;
    }
    super.visitMethodInvocation(node);
  }
}

/// The `T` of a `Component.type<T>()` field initialiser, or `null` for
/// anything else.
///
/// Matched on the AST: the receiver is the identifier `Component`, the method
/// is `type`, and there is exactly one type argument spelled as a name.
/// Nothing here is resolved, so a name two libraries both declare is left for
/// the caller to reject - the same treatment every other name in this pass
/// gets.
///
/// **This matches on the receiver's name**, exactly as [_isColumn] does and
/// with the same liability: a declaration static added to some other type is
/// invisible here until this is edited, and a spelling that dropped the
/// receiver would have no name to match at all.
String? _componentTypeOf(VariableDeclaration variable) {
  final initializer = variable.initializer;
  if (initializer is! MethodInvocation) return null;
  final target = initializer.target;
  if (target is! SimpleIdentifier || target.name != 'Component') return null;
  if (initializer.methodName.name != 'type') return null;
  final arguments = initializer.typeArguments?.arguments;
  if (arguments == null || arguments.length != 1) return null;
  final argument = arguments.single;
  return argument is NamedType ? argument.name.lexeme : null;
}

/// Collects declarations and the fields they declare.
class _OwnerVisitor extends RecursiveAstVisitor<void> {
  _OwnerVisitor(this._file);

  final String _file;
  final List<Owner> owners = <Owner>[];

  /// Every member name each named declaration in this file declares, by
  /// declaration name.
  ///
  /// Wider than [owners] on purpose: it covers extension types too, and
  /// `Entity` and `Accessor` are both extension types. What reads it is the
  /// collision check in `good_tool`, which has to know every name an accessor
  /// property would lose to - and losing to one is silent, because an
  /// extension member never wins against a member the receiver's own type
  /// already has.
  ///
  /// Kept apart from [owners] rather than folded into it. An extension type is
  /// not a struct and cannot be mixed into one, so adding it to the by-name map
  /// could only ever make a real declaration look ambiguous to
  /// [_resolveInto] - a false build failure on correct code.
  final Map<String, Set<String>> members = <String, Set<String>>{};

  /// The members of each `extension ... on Accessor<T>` in this file, keyed by
  /// the component `T` names.
  final Map<String, Set<String>> accessorExtensions = <String, Set<String>>{};

  @override
  void visitExtensionDeclaration(ExtensionDeclaration node) {
    final onType = node.onClause?.extendedType;
    if (onType is NamedType && onType.name.lexeme == 'Accessor') {
      final arguments = onType.typeArguments?.arguments;
      if (arguments != null && arguments.length == 1) {
        final argument = arguments.single;
        if (argument is NamedType) {
          // The nullable spelling names the same component: `Accessor<Health?>`
          // and `Accessor<Health>` differ in what `component` hands back, not
          // in which extensions apply.
          final component = argument.name.lexeme;
          final into = accessorExtensions.putIfAbsent(
            component,
            () => <String>{},
          );
          for (final member in node.members) {
            switch (member) {
              case MethodDeclaration(:final name):
                into.add(name.lexeme);
              case FieldDeclaration(:final fields):
                for (final variable in fields.variables) {
                  into.add(variable.name.lexeme);
                }
              default:
                break;
            }
          }
        }
      }
    }
    super.visitExtensionDeclaration(node);
  }

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    final superName = node.extendsClause?.superclass.name.lexeme;
    final owner = Owner(node.name.lexeme, _file)..superName = superName;
    for (final type in node.withClause?.mixinTypes ?? const <NamedType>[]) {
      owner.mixes.add(type.name.lexeme);
    }
    _readFields(node.members, owner);
    _readHooks(node.members, owner);
    _readMembers(node.name.lexeme, node.members);
    owners.add(owner);
    super.visitClassDeclaration(node);
  }

  // `ExtensionTypeDeclaration` carries analyzer's `@experimental`, which is
  // about the shape of that AST class and not about the language feature -
  // extension types shipped in Dart 3.3 and `Entity` is one. The pin on
  // analyzer 7.7.1 is what makes taking the warning safe: a version that
  // changed this node would have to be resolved deliberately.
  @override
  // ignore: experimental_member_use
  void visitExtensionTypeDeclaration(ExtensionTypeDeclaration node) {
    _readMembers(node.name.lexeme, node.members);
    // The representation field is a member like any other, and it is the one
    // that matters here: `Accessor`'s is `entity` and `Entity`'s is `value`.
    members[node.name.lexeme]!.add(node.representation.fieldName.lexeme);
    super.visitExtensionTypeDeclaration(node);
  }

  @override
  void visitEnumDeclaration(EnumDeclaration node) {
    _readMembers(node.name.lexeme, node.members);
    super.visitEnumDeclaration(node);
  }

  /// Records every name [members] declares under [declaration].
  void _readMembers(String declaration, List<ClassMember> body) {
    final into = members.putIfAbsent(declaration, () => <String>{});
    for (final member in body) {
      switch (member) {
        case MethodDeclaration(:final name):
          into.add(name.lexeme);
        case FieldDeclaration(:final fields):
          for (final variable in fields.variables) {
            into.add(variable.name.lexeme);
          }
        default:
          break;
      }
    }
  }

  @override
  void visitMixinDeclaration(MixinDeclaration node) {
    final owner = Owner(node.name.lexeme, _file)..isMixin = true;
    for (final type
        in node.onClause?.superclassConstraints ?? const <NamedType>[]) {
      owner.onConstraints.add(type.name.lexeme);
    }
    _readFields(node.members, owner);
    _readHooks(node.members, owner);
    _readMembers(node.name.lexeme, node.members);
    owners.add(owner);
    super.visitMixinDeclaration(node);
  }

  /// Records each declare-time hook this declaration overrides with a body,
  /// and whether that body chains to the one it is overriding.
  ///
  /// A bodiless declaration is skipped. `Component` itself declares all three
  /// with no body, and re-declaring one abstract overrides nothing at run
  /// time - there is no call to leave out.
  void _readHooks(List<ClassMember> members, Owner owner) {
    for (final member in members) {
      if (member is! MethodDeclaration) continue;
      final hook = member.name.lexeme;
      if (!_describeHooks.contains(hook)) continue;
      final body = member.body;
      if (body is EmptyFunctionBody) continue;
      final visitor = _SuperCallVisitor(hook);
      body.accept(visitor);
      owner.hooks.add(HookOverride(hook, callsSuper: visitor.found));
    }
  }

  void _readFields(List<ClassMember> members, Owner owner) {
    for (final member in members) {
      if (member is! FieldDeclaration) continue;
      // An explicit override is somebody stating the intent this checks for,
      // so it is theirs to make.
      if (member.metadata.any((a) => a.name.name == 'override')) continue;
      if (member.isStatic) continue;
      for (final variable in member.fields.variables) {
        owner.fields.add(
          ColumnField(
            variable.name.lexeme,
            isColumn: _isColumn(variable, member.fields.type),
            valueType: columnValueType(variable, member.fields.type),
          ),
        );
        final componentType = _componentTypeOf(variable);
        if (componentType != null) owner.componentTypes.add(componentType);
      }
    }
  }
}

/// The language the engine is written in, spelled out rather than left to
/// `parseString`'s default.
///
/// Without it a column declared as `Field.array(.uint16, 4)` parses to the
/// right AST but reports `EXPERIMENT_NOT_ENABLED`, because the default
/// feature set for a bare `parseString` does not carry `dot-shorthands` on
/// analyzer 7.7.1. This pass sets `throwIfDiagnostics: false` and never reads
/// the diagnostics, so today that costs nothing - but a pass that did read
/// them would see an error on every element-spelled array in the tree.
final FeatureSet _featureSet = FeatureSet.fromEnableFlags2(
  sdkLanguageVersion: Version(3, 13, 0),
  flags: const <String>['dot-shorthands'],
);

/// Whether a field declaration allocates a row column.
///
/// Three shapes, all syntactic. `final speed = Field.float64()` is the one
/// components are written in now. `final barrel = EntityStruct.of(Barrel.new)`
/// takes a column for the child's handle. The third is the older form, a bare
/// `DataPointer` declaration that a `describeStruct` body assigns into, which
/// the engine still supports.
///
/// **The first shape matches on the receiver's name**, so a declaration
/// static added to any type other than `Field` or `EntityStruct` is invisible
/// here until that set is edited. `Field.array(.uint16, 4)` is safe: the dot
/// shorthand is an *argument*, and the receiver is still the identifier
/// `Field`. A spelling that dropped the receiver as well would have no name
/// to match and would fall through this check silently -
/// `test/struct_scan_test.dart` pins both halves.
bool _isColumn(VariableDeclaration variable, TypeAnnotation? declaredType) {
  final initializer = variable.initializer;
  if (initializer is MethodInvocation) {
    final target = initializer.target;
    if (target is SimpleIdentifier) {
      final owner = target.name;
      if (owner == 'Field' || owner == 'EntityStruct') return true;
    }
  }
  if (declaredType is NamedType) {
    const columnTypes = <String>{
      'DataPointer',
      'DataArrayPointer',
      'PackedPointer',
      // `InitialPointer` is what `hasFloat64` and the rest actually return,
      // so a `late final InitialPointer<double> speed;` written in the older
      // form was falling through this check entirely.
      'InitialPointer',
    };
    if (columnTypes.contains(declaredType.name.lexeme)) return true;
  }
  return false;
}

/// What `column[entity]` on this declaration hands back, or `null` where a
/// parse cannot say.
///
/// This is the whole of what a generated accessor property needs, and the
/// reason #99 is not blocked by what stopped #18: a property calls through the
/// existing `DataPointer`, so it wants the column's **type**, never its byte
/// offset. An offset is the running total of a `declareField` sequence that
/// reads values only available at run time; a type is written in the source.
///
/// # Why it is a table and not a rule
///
/// `Field.uint16` yields an `int` and `Field.optUint16` an `int?`, and nothing
/// in the two names says so - the width is in the name and the Dart type is
/// not. Deriving it would mean re-deriving `Field`'s own signatures, which are
/// the fact this is a copy of; the table is that copy made explicit, and
/// [_isColumn]'s note applies here too - **a constructor added to `Field` is
/// invisible until this map is edited**. That failure is safe in one direction
/// only, and it is the right one: an unknown name yields `null`, the property
/// is not generated, and the use site gets *"The getter isn't defined for the
/// type `Accessor<T>`"*. A wrong entry would generate a property that does not
/// compile, which the bundle's own analysis catches on the same run.
///
/// Three shapes deliberately answer `null`:
///
///  * `array`, `arrayOf` and `optArray` return a `DataArrayPointer`, which has
///    no `operator []` at all - an element is read `get(entity, index)`. There
///    is no property to be had, only a method, and that is a different feature.
///  * `packed`, `optPacked`, `heapObject` and `optHeapObject` carry their value
///    type in a type argument. Written explicitly (`Field.heapObject<Sprite>`)
///    it is read below; inferred from a `T Function()` argument it is not
///    spelled anywhere a parse can reach.
///  * `EntityStruct.of` is not a column pointer. It returns the child *prefab*,
///    one object for the whole archetype, and the column is reached by indexing
///    that - so a property on the parent's accessor would be naming the wrong
///    thing entirely.
String? columnValueType(
  VariableDeclaration variable,
  TypeAnnotation? declaredType,
) {
  final initializer = variable.initializer;
  if (initializer is MethodInvocation) {
    final target = initializer.target;
    if (target is SimpleIdentifier && target.name == 'Field') {
      return _fieldValueType(initializer);
    }
    return null;
  }
  // The older form, a bare pointer declaration a `describeStruct` body assigns
  // into. Nothing is inferred here - the type argument is written out.
  if (declaredType is NamedType) {
    const pointers = <String>{
      'DataPointer',
      'InitialPointer',
      'PackedPointer',
    };
    if (!pointers.contains(declaredType.name.lexeme)) return null;
    final arguments = declaredType.typeArguments?.arguments;
    if (arguments == null || arguments.length != 1) return null;
    return arguments.single.toSource();
  }
  return null;
}

/// The value type behind one `Field.<name>(...)` call.
String? _fieldValueType(MethodInvocation initializer) {
  final name = initializer.methodName.name;
  final scalar = _fieldValueTypes[name];
  if (scalar != null) return scalar;

  final typeArguments = initializer.typeArguments?.arguments;
  final explicit = typeArguments != null && typeArguments.length == 1
      ? typeArguments.single.toSource()
      : null;
  switch (name) {
    case 'enumOf':
      // `Field.enumOf(OrcState.values, OrcState.idle)` is how every call in the
      // tree is written, and the type argument is inferred from the first one.
      // `OrcState.values` is a property access on the enum's own name, so the
      // name is right there - but only under that exact spelling. A list held
      // in a variable, or built by a getter, resolves to the same thing and
      // says nothing about which enum it holds, so it answers `null` rather
      // than a guess.
      return explicit ?? _enumOfValues(initializer);
    case 'packed':
    case 'heapObject':
      return explicit;
    case 'optPacked':
    case 'optHeapObject':
      return explicit == null ? null : '$explicit?';
    default:
      return null;
  }
}

/// The enum named by a `<Enum>.values` argument, or `null` for anything else.
String? _enumOfValues(MethodInvocation initializer) {
  final arguments = initializer.argumentList.arguments;
  if (arguments.isEmpty) return null;
  return switch (arguments.first) {
    PrefixedIdentifier(
      prefix: final SimpleIdentifier prefix,
      identifier: SimpleIdentifier(name: 'values'),
    ) =>
      prefix.name,
    _ => null,
  };
}

/// What each `Field` constructor's column hands back, for the ones whose value
/// type is fixed by the constructor alone.
///
/// Transcribed from `Field` in `packages/good/lib/src/data.dart`. See
/// [columnValueType] for why this is a copy and what happens when it falls
/// behind.
const Map<String, String> _fieldValueTypes = <String, String>{
  'boolean': 'bool',
  'uint1': 'int',
  'int1': 'int',
  'uint2': 'int',
  'int2': 'int',
  'uint4': 'int',
  'int4': 'int',
  'uint8': 'int',
  'int8': 'int',
  'uint16': 'int',
  'int16': 'int',
  'uint32': 'int',
  'int32': 'int',
  'uint64': 'int',
  'int64': 'int',
  'float32': 'double',
  'float64': 'double',
  'entity': 'Entity',
  'optUint1': 'int?',
  'optInt1': 'int?',
  'optUint2': 'int?',
  'optInt2': 'int?',
  'optUint4': 'int?',
  'optInt4': 'int?',
  'optUint8': 'int?',
  'optInt8': 'int?',
  'optUint16': 'int?',
  'optInt16': 'int?',
  'optUint32': 'int?',
  'optInt32': 'int?',
  'optUint64': 'int?',
  'optInt64': 'int?',
  'optFloat32': 'double?',
  'optFloat64': 'double?',
  'optEntity': 'Entity?',
};

/// What `good generate` prints when it refuses to proceed.
String shadowedFieldsMessage(StructScan scan) {
  final lines = StringBuffer()
    ..writeln('Two declarations on one struct share a field name.')
    ..writeln();
  for (final hit in scan.shadowed) {
    lines
      ..writeln(
        '  ${hit.winner}.${hit.field} shadows ${hit.loser}.${hit.field}',
      )
      ..writeln('    ${hit.winner}: ${hit.winnerFile}')
      ..writeln('    ${hit.loser}: ${hit.loserFile}');
  }
  lines
    ..writeln()
    ..writeln(
      'A component is a mixin, so this is an override to Dart and not an '
      'error. Both initialisers still run: each row carries both columns, and '
      'the name reaches only the last one applied. Anything written against '
      'the hidden column reads and writes the other one.',
    )
    ..writeln()
    ..writeln(
      'Rename one of them. A component that other people mix in wants a '
      'prefix drawn from its own name, the way Transform2D calls its position '
      'columns transformOffsetX and transformOffsetY.',
    );
  return lines.toString();
}

/// What `good generate` prints when a component mixin stops chaining.
String missingSuperMessage(StructScan scan) {
  final lines = StringBuffer()
    ..writeln(
      'A component mixin overrides a declare-time hook without '
      'chaining it.',
    )
    ..writeln();
  for (final hit in scan.missingSuper) {
    lines
      ..writeln(
        '  ${hit.mixin}.${hit.hook} does not call '
        'super.${hit.hook}()',
      )
      ..writeln('    ${hit.file}');
  }
  lines
    ..writeln()
    ..writeln(
      'Each pass is chained through every mixin on the entity, so the one '
      'that stops calling super cuts off every mixin applied before it. Those '
      'components contribute no columns and no query bit, and the entity is '
      'missing that data with nothing said at run time.',
    )
    ..writeln()
    ..writeln(
      'Add the call as the first statement of the override. Dart cannot '
      'require it here the way it does on a struct subclass: the annotation '
      'that enforces it needs a concrete implementation underneath, and '
      'Component declares these hooks with no body.',
    );
  return lines.toString();
}

/// What it prints for the parts it could not read - a warning, never a
/// failure.
///
/// A struct mixing in a component from some package this pass does not parse is
/// an ordinary thing to do, and failing the build over it would make the check
/// hostile to exactly the third-party components the naming convention exists
/// for. Saying which parts went unread is what keeps a clean run from meaning
/// two different things.
String unreadPartsMessage(StructScan scan) {
  final lines = StringBuffer()
    ..writeln(
      'Some parts of a struct could not be read, and were not '
      'compared for shadowed columns:',
    );
  for (final entry in scan.unresolved.entries) {
    lines.writeln('  ${entry.key} - ${entry.value}');
  }
  return lines.toString();
}
