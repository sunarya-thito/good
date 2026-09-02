import 'dart:io';

import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:good_tool/src/engine_packages.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';

/// One declaration reached from a variable Dart initialises lazily.
@immutable
class DeferredDeclaration {
  const DeferredDeclaration({
    required this.package,
    required this.file,
    required this.line,
    required this.call,
    required this.holder,
    required this.deferral,
  });

  /// The package whose `lib/` holds the call.
  final String package;

  /// The file, relative to that package's root, in posix form.
  final String file;

  /// The line the call sits on, 1-based.
  final int line;

  /// The declaration as it is written - `Field.float64`, `CircleBody.of`.
  final String call;

  /// The variable that holds it - `speed`, `body`.
  final String holder;

  /// Which of the three spellings defers it. See [scanDeferredDeclarations].
  final DeferralKind deferral;

  /// `goo2d/lib/src/data/collider.dart:433`.
  String get where => '$package/$file:$line';
}

/// Why a variable's initialiser does not run where it is written.
enum DeferralKind {
  /// `late final speed = Field.float64();` - runs on first read.
  late$('a `late` initialiser runs on first read'),

  /// `static final speed = Field.float64();` - a static initialiser is lazy in
  /// Dart, with no `late` written anywhere.
  static$('a `static` initialiser is lazy, with or without `late`'),

  /// A top-level variable, which is lazy for the same reason a static is.
  topLevel('a top-level variable is initialised on first read');

  const DeferralKind(this.because);

  /// The half of the failure line that says what defers it.
  final String because;
}

/// What one pass over a package's `lib/` found.
@immutable
class DeclarationScan {
  const DeclarationScan({
    required this.deferred,
    required this.files,
    required this.calls,
    required this.entryPoints,
    required this.unparsed,
  });

  /// Every declaration a lazy variable holds, in file then line order.
  final List<DeferredDeclaration> deferred;

  /// How many files were read.
  final int files;

  /// How many declaration calls those files make, deferred or not.
  final int calls;

  /// How many `Type.member` pairs the run decided are declarations.
  final int entryPoints;

  /// Files the parser could not read, as `<package>/<path>`, sorted.
  ///
  /// The caller fails on a non-empty list. A file that does not parse
  /// contributes no entry point and no call site, so a run that dropped one
  /// and then reported "nothing is deferred" would be answering without having
  /// looked. Naming it under an exit code of 0 was the stopgap #347 shipped,
  /// and it is the same silence with more words: nothing in CI reads stderr on
  /// a green run.
  ///
  /// The list is empty in this repository. It held three files while the
  /// `analyzer` constraint was `^7.4.0` - the three that use primary
  /// constructors, which that version does not implement at any
  /// `enable-experiment` spelling. See the constraint in `pubspec.yaml` for
  /// what a future one costs.
  final List<String> unparsed;
}

/// Every declaration in [packages] held by a variable Dart initialises lazily.
///
/// A declaration hands back a handle and, as a side effect, appends to whatever
/// registrar `DeclarationContext` has open. The window is opened around one
/// object's construction and closed when it returns, so *when* the initialiser
/// runs is the whole of whether the declaration lands on its owner. An eager
/// field initialiser runs inside the window. The three spellings in
/// [DeferralKind] do not.
///
/// # Why the runtime cannot cover this
///
/// It covers half of it. Every level of `DeclarationContext` throws when its
/// stack is empty, and the messages name `late` by hand, so a deferred
/// declaration read while nothing is under construction reports itself. What it
/// cannot see is a deferred declaration read while *some other* window is open:
/// the registrar it reaches is real and open and belongs to somebody else, so
/// the call succeeds and the handle points into the wrong owner's storage.
/// Measured on two prefabs, `_A` holding a `late final lazy = Field.float64()`
/// that `_B`'s field initialiser is the first to read: `_A`'s archetype came
/// out 32 bits wide and `_B`'s 96, the two objects held the identical pointer,
/// and nothing threw until an entity of `_A` indexed the column and hit the
/// archetype-mismatch guard - a different error, in different code, at a
/// different time.
///
/// # What counts as a declaration
///
/// Not a fixed list. The seeds are the static methods of [known] whose body
/// names `DeclarationContext`, which is `good`'s registrar stack and is
/// `@internal`, so nothing outside the engine can be a seed. A static method
/// whose body calls one of those is a declaration too - `CircleBody.of` calls
/// `Component.declare` and `Field.float64` - and so on to a fixed point. That
/// is what makes the rule cover a package this tool has never been told about:
/// a game's own `static Turret of(...)` factory is in [packages], so its
/// callers are checked against it like any other.
///
/// [known] is normally [packages] plus the engine packages they depend on. The
/// seeds live in `good` and the goo2d-level factories in `goo2d`, and a scan
/// holding only the package under it would find no entry points at all and
/// report nothing.
///
/// # What it does not decide
///
/// **Which class may hold which declaration.** That is #290's `@Describes`, and
/// the runtime already refuses it: each level's getter throws when its stack is
/// empty, and the windows are disjoint, so a `Channel` on a prefab field or a
/// `Field` on a `Game` field is a `StateError` at boot naming the shape. This
/// pass would add nothing there.
///
/// **A declaration in a method or getter body.** `Field.array` in
/// `TextLabel._declare` is correct, and so is every declaration in the four
/// files that hold this repository's factories - `collider.dart`,
/// `render_2d.dart`, `text_2d.dart` and `effector.dart` - which is 106 calls
/// between them. Location alone does not separate a factory from a mistake, so
/// a rule keyed on it fires on all of them. The entry-point closure recognises
/// a factory that is `static`; an instance getter returning a declaration is
/// not decided here.
///
/// **A call through a variable or a tear-off.** `final make = Field.float64;`
/// then `make()` reads as neither. The pass matches a `Type.member(...)`
/// invocation written out.
///
/// **Two classes of one name in two packages.** Entry points are keyed on the
/// pair as written, so a `Field` of somebody else's in a package read here
/// would merge with `good`'s.
DeclarationScan scanDeferredDeclarations({
  required List<EnginePackage> packages,
  required List<EnginePackage> known,
}) {
  final scanned = <String>{for (final package in packages) package.libDir};
  final roots = <String, EnginePackage>{
    for (final package in known) package.libDir: package,
    for (final package in packages) package.libDir: package,
  };

  final read = <_ReadFile>[];
  final unparsed = <String>[];
  final statics = <String, _StaticBody>{};
  for (final MapEntry(key: libDir, value: package) in roots.entries) {
    final dir = Directory(libDir);
    if (!dir.existsSync()) continue;
    for (final file in dir.listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      final CompilationUnit unit;
      try {
        final parsed = parseString(
          content: file.readAsStringSync(),
          featureSet: _featureSet,
          throwIfDiagnostics: false,
        );
        if (parsed.errors.isNotEmpty) {
          // Recovery hands back a tree, and it is not one to read: the members
          // of a class whose header did not parse do not arrive as members, so
          // a factory in there is invisible and so is every call site under
          // it. Named instead, so the run says what it did not look at.
          unparsed.add(package.describe(file));
          continue;
        }
        unit = parsed.unit;
      } on ArgumentError {
        // Unreadable, or not Dart after all.
        unparsed.add(package.describe(file));
        continue;
      }
      final collector = _StaticCollector();
      unit.accept(collector);
      statics.addAll(collector.statics);
      if (scanned.contains(libDir)) read.add(_ReadFile(package, file, unit));
    }
  }

  final entryPoints = _entryPoints(statics);

  final deferred = <DeferredDeclaration>[];
  var calls = 0;
  read.sort((a, b) => a.file.path.compareTo(b.file.path));
  for (final entry in read) {
    final visitor = _CallVisitor(entryPoints);
    entry.unit.accept(visitor);
    calls += visitor.calls;
    for (final site in visitor.sites) {
      deferred.add(
        DeferredDeclaration(
          package: entry.package.name,
          file: p
              .split(p.relative(entry.file.path, from: entry.package.root.path))
              .join('/'),
          line: entry.unit.lineInfo.getLocation(site.offset).lineNumber,
          call: site.call,
          holder: site.holder,
          deferral: site.deferral,
        ),
      );
    }
  }

  return DeclarationScan(
    deferred: deferred,
    files: read.length,
    calls: calls,
    entryPoints: entryPoints.length,
    unparsed: unparsed..sort(),
  );
}

/// The `Type.member` pairs that declare, to a fixed point.
///
/// The seeds name `DeclarationContext`; every round adds a static whose body
/// calls something already in the set. It terminates because the set only
/// grows and [statics] is finite.
Set<String> _entryPoints(Map<String, _StaticBody> statics) {
  final found = <String>{};
  for (final MapEntry(key: key, value: body) in statics.entries) {
    if (body.namesRegistrar) found.add(key);
  }
  var growing = true;
  while (growing) {
    growing = false;
    for (final MapEntry(key: key, value: body) in statics.entries) {
      if (found.contains(key)) continue;
      if (!body.calls.any(found.contains)) continue;
      found.add(key);
      growing = true;
    }
  }
  return found;
}

/// What one line's failure says.
String deferredDeclarationLine(DeferredDeclaration deferred) =>
    '${deferred.where}: `${deferred.holder}` holds ${deferred.call} - '
    '${deferred.deferral.because}';

/// The report a run with findings prints under them.
String deferredDeclarationSummary(DeclarationScan scan) =>
    '\n${scan.deferred.length} declaration(s) are held by a variable Dart '
    'initialises lazily. A declaration lands on whichever owner is under '
    'construction when its initialiser runs, so one that runs later lands on '
    'the wrong owner or on nobody. Make the initialiser eager: an instance '
    '`final` field, with no `late` and not `static`.';

/// The registrar stack every declaration bottoms out at.
///
/// `@internal` to `good`, so a static naming it is the engine's own and the
/// seed set cannot be widened from outside.
const _registrar = 'DeclarationContext';

/// One parsed file the call sites are read out of.
class _ReadFile {
  _ReadFile(this.package, this.file, this.unit);

  final EnginePackage package;
  final File file;
  final CompilationUnit unit;
}

/// What one static method's body does that matters here.
class _StaticBody {
  _StaticBody({required this.namesRegistrar, required this.calls});

  /// Whether it names [_registrar], which makes it a seed.
  final bool namesRegistrar;

  /// The `Type.member` pairs it invokes, which is what carries the closure.
  final Set<String> calls;
}

/// Collects every static method of a unit, keyed `Type.member`.
///
/// Static only, which narrows the set rather than changing what is reported.
/// An instance method reaching a registrar - `RandomRegistry.declare`,
/// `CameraViewTable._add` - is the registrar's own side of the declaration, and
/// no call site can reach it through this pass anyway: `RandomRegistry
/// .declare()` does not compile, and `registry.declare()` reads as the pair
/// `registry.declare`. Leaving them in cost seven extra entry points over this
/// repository and reported the same 138 calls and the same nothing deferred.
///
/// The enclosing type comes from the member's ancestors rather than from a
/// visit per declaration kind. Every form that can hold a static member -
/// class, mixin, enum, extension type - is a `NamedCompilationUnitMember`, so
/// one test covers all of them and covers whatever the language adds next.
///
/// An ancestor and not the immediate parent, because the parent is the body
/// node: a member of `class C { ... }` hangs off a `ClassBody` under the
/// declaration, not off the declaration. Reading `node.parent` found no
/// declaration at all once that node existed, and the pass then reported zero
/// entry points and zero calls over a repository full of both.
class _StaticCollector extends RecursiveAstVisitor<void> {
  final statics = <String, _StaticBody>{};

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    super.visitMethodDeclaration(node);
    if (!node.isStatic || node.isGetter || node.isSetter) return;
    // ignore: deprecated_member_use
    final parent = node.thisOrAncestorOfType<NamedCompilationUnitMember>();
    if (parent == null) return;
    final body = _BodyVisitor();
    node.body.accept(body);
    statics['${parent.name.lexeme}.${node.name.lexeme}'] = _StaticBody(
      namesRegistrar: body.namesRegistrar,
      calls: body.calls,
    );
  }
}

/// Reads one static body for the registrar name and for the pairs it calls.
class _BodyVisitor extends RecursiveAstVisitor<void> {
  bool namesRegistrar = false;
  final calls = <String>{};

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    if (node.name == _registrar) namesRegistrar = true;
    super.visitSimpleIdentifier(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final pair = _pair(node);
    if (pair != null) calls.add(pair);
    super.visitMethodInvocation(node);
  }
}

/// `Field.float64` for `Field.float64(1.0)`, or null when the receiver is not
/// a bare name.
///
/// A bare name because that is what a static call on a type is written as. An
/// invocation with no target is an unqualified call and belongs to no type; one
/// whose target is itself an expression - `registry.field.float64()` - is an
/// instance call, and no declaration is spelled that way.
String? _pair(MethodInvocation node) {
  final target = node.target;
  if (target is! SimpleIdentifier) return null;
  return '${target.name}.${node.methodName.name}';
}

/// One declaration call a lazy variable holds.
class _Site {
  _Site(this.offset, this.call, this.holder, this.deferral);

  final int offset;
  final String call;
  final String holder;
  final DeferralKind deferral;
}

/// Finds the declaration calls in a unit, and which of them a lazy variable
/// holds.
///
/// The walk is over the variable declarations rather than over the calls,
/// because the question is what holds a call and not where a call is. A
/// declaration anywhere inside a lazy variable's initialiser is deferred with
/// it, however deep - `Field.array(.uint16, capacity)` nested in a constructor
/// argument runs when the variable is first read like everything else in there.
class _CallVisitor extends RecursiveAstVisitor<void> {
  _CallVisitor(this.entryPoints);

  final Set<String> entryPoints;
  final sites = <_Site>[];
  var calls = 0;

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final pair = _pair(node);
    if (pair != null && entryPoints.contains(pair)) calls++;
    super.visitMethodInvocation(node);
  }

  @override
  void visitFieldDeclaration(FieldDeclaration node) {
    final DeferralKind? kind;
    if (node.isStatic) {
      // Checked before `late`, because a `static late` is lazy for the reason
      // the static gives and would be lazy with the `late` removed.
      kind = DeferralKind.static$;
    } else if (node.fields.lateKeyword != null) {
      kind = DeferralKind.late$;
    } else {
      kind = null;
    }
    _variables(node.fields, kind);
    super.visitFieldDeclaration(node);
  }

  @override
  void visitTopLevelVariableDeclaration(TopLevelVariableDeclaration node) {
    _variables(node.variables, DeferralKind.topLevel);
    super.visitTopLevelVariableDeclaration(node);
  }

  @override
  void visitVariableDeclarationStatement(VariableDeclarationStatement node) {
    _variables(
      node.variables,
      node.variables.lateKeyword == null ? null : DeferralKind.late$,
    );
    super.visitVariableDeclarationStatement(node);
  }

  void _variables(VariableDeclarationList list, DeferralKind? deferral) {
    if (deferral == null) return;
    for (final variable in list.variables) {
      final initializer = variable.initializer;
      if (initializer == null) continue;
      final held = _HeldVisitor(entryPoints);
      initializer.accept(held);
      for (final call in held.found) {
        sites.add(
          _Site(call.offset, call.name, variable.name.lexeme, deferral),
        );
      }
    }
  }
}

/// Every declaration call inside one initialiser expression.
class _HeldVisitor extends RecursiveAstVisitor<void> {
  _HeldVisitor(this.entryPoints);

  final Set<String> entryPoints;
  final found = <({int offset, String name})>[];

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final pair = _pair(node);
    if (pair != null && entryPoints.contains(pair)) {
      found.add((offset: node.offset, name: pair));
    }
    super.visitMethodInvocation(node);
  }
}

/// The language this parses the packages as.
///
/// The same set `doc_references.dart` uses, for its reason: `good` and `goo2d`
/// turn these on in their `analysis_options.yaml`, and a file this pass cannot
/// parse contributes neither an entry point nor a call site.
final FeatureSet _featureSet = FeatureSet.fromEnableFlags2(
  sdkLanguageVersion: Version(3, 13, 0),
  flags: const <String>['primary-constructors', 'dot-shorthands'],
);
