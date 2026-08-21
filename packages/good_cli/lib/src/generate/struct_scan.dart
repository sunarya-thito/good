import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

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
  final String winnerFile;

  /// The declaration whose member is now unreachable under [field].
  final String loser;
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

  /// `describeType`, `describeAssets` or `describeStruct`.
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
/// like. The name exists in the source and nowhere else, which is why this is a
/// source scan and why it can say `Velocity.x shadows Transform2D.x` with both
/// files when a throw could only ever have said that a row was bigger than
/// expected.
///
/// # What it reads
///
/// Parsed, not resolved, for the reason `scanScenes` gives: resolution needs
/// every dependency's summary and seconds per run, and the shapes that matter
/// here are syntactic. It reads the project's own `lib/`, plus the engine
/// packages it finds through `.dart_tool/package_config.json` - without those,
/// `Child.parent` and `Transform2D.transformOffsetX` would be invisible, and
/// those are the collisions a user is likeliest to walk into.
///
/// A name that resolves to two different files is not guessed at. Both land in
/// [StructScan.unresolved], because a build error that fires wrongly is worse
/// than the bug it is looking for.
StructScan scanStructRules(Directory projectDir) {
  final roots = _scanRoots(projectDir);
  if (roots.isEmpty) {
    return const StructScan(
      shadowed: <ShadowedField>[],
      missingSuper: <MissingSuperCall>[],
      unresolved: <String, String>{},
    );
  }

  // By bare name, and a list rather than one entry: two libraries can each
  // declare a `Velocity`, and this pass has no resolution to tell which one a
  // `with Velocity` means. Ambiguity is reported, never picked.
  //
  // `parseString` on each file, not an `AnalysisContextCollection`. The
  // collection resolves packages, reads every pubspec and builds a context per
  // root before it hands back a syntax tree, and none of that is used here -
  // this pass only ever looks at tokens. Against the demo project - 49 engine
  // files plus its own - dropping it took the scan from 826ms to 272ms on a
  // second run and from 563ms to 136ms warm, against 1-7ms for everything
  // `good generate` did before this check existed.
  final byName = <String, List<_Owner>>{};
  for (final root in roots) {
    for (final file in Directory(root).listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      final CompilationUnit unit;
      try {
        unit = parseString(
          content: file.readAsStringSync(),
          throwIfDiagnostics: false,
        ).unit;
      } on ArgumentError {
        // Unreadable or not Dart after all. A file this pass cannot parse
        // declares nothing it can compare, and whatever names it held show up
        // as unresolved on the structs that mention them.
        continue;
      }
      final visitor = _OwnerVisitor(file.path);
      unit.accept(visitor);
      for (final owner in visitor.owners) {
        byName.putIfAbsent(owner.name, () => <_Owner>[]).add(owner);
      }
    }
  }

  _markStructs(byName);
  _markComponentMixins(byName);

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
void _markStructs(Map<String, List<_Owner>> byName) {
  bool declaresColumn(_Owner owner) =>
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
void _markComponentMixins(Map<String, List<_Owner>> byName) {
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
/// to point at, and `Component` declares all three hooks with no body. So the
/// annotation is inert exactly where mixins chain, which is the whole of the
/// gap and the reason this is here.
///
/// A mixin that never overrides a hook is fine and is not mentioned. Only an
/// override that leaves the call out is a defect, and the engine's own eleven
/// component mixins all chain, so this fires on nothing that ships today.
void _checkHooks(
  _Owner owner,
  Map<String, List<_Owner>> byName,
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
  _Owner struct,
  Map<String, List<_Owner>> byName,
  List<ShadowedField> shadowed,
  Map<String, String> unresolved,
  Directory projectDir,
) {
  final applied = <_Owner>[];
  _linearize(struct, byName, applied, <String>{}, unresolved, struct.name);

  // name -> the declaration that most recently claimed it.
  final claimed = <String, _Owner>{};
  for (final part in applied) {
    for (final field in part.fields) {
      final previous = claimed[field.name];
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
      claimed[field.name] = part;
    }
  }
}

/// Appends [owner]'s parts in applied order, base first.
void _linearize(
  _Owner owner,
  Map<String, List<_Owner>> byName,
  List<_Owner> into,
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
  Map<String, List<_Owner>> byName,
  List<_Owner> into,
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
/// `Child` declares `parent`, `Parent` declares `firstChild`, `Camera` declares
/// `zoom` and `view` - none of them prefixed - and a user component naming a
/// field `parent` is the collision this issue was filed about. Reading only the
/// project would leave every one of those in `unresolved`.
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
List<String> _enginePackageLibs(Directory projectDir) {
  final file = File(
    p.join(projectDir.path, '.dart_tool', 'package_config.json'),
  );
  if (!file.existsSync()) return const <String>[];
  final Object? doc;
  try {
    doc = jsonDecode(file.readAsStringSync());
  } on FormatException {
    return const <String>[];
  }
  if (doc is! Map<String, Object?>) return const <String>[];
  final packages = doc['packages'];
  if (packages is! List<Object?>) return const <String>[];

  final roots = <String>[];
  for (final entry in packages) {
    if (entry is! Map<String, Object?>) continue;
    final name = entry['name'];
    if (name is! String || !_isEnginePackage(name)) continue;
    final rootUri = entry['rootUri'];
    if (rootUri is! String) continue;
    final packageUri = entry['packageUri'];
    final base = rootUri.startsWith('file:')
        ? File.fromUri(Uri.parse(rootUri)).path
        : p.normalize(p.join(file.parent.path, rootUri));
    final libDir = Directory(
      p.normalize(p.join(base, packageUri is String ? packageUri : 'lib/')),
    );
    if (libDir.existsSync()) roots.add(p.normalize(p.absolute(libDir.path)));
  }
  return roots;
}

/// Whether [name] is one of the engine's own packages.
///
/// The kernel plus anything built on it - `goo2d`, `goo3d`, a physics backend.
/// A third-party component package is not covered and lands in
/// [StructScan.unresolved]; widening this to every dependency would mean
/// parsing Flutter itself on every generate.
bool _isEnginePackage(String name) => name == 'good' || name.startsWith('goo');

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
class _Field {
  const _Field(this.name, {required this.isColumn});

  final String name;

  /// Whether this declaration allocates a column - a `Field.*` initialiser,
  /// `EntityStruct.of`, or the `late final DataPointer<...>` shape a
  /// `describeStruct` body fills in.
  final bool isColumn;
}

extension on List<_Field> {
  _Field? byName(String name) {
    for (final field in this) {
      if (field.name == name) return field;
    }
    return null;
  }
}

/// One class or mixin that can contribute fields to a struct.
class _Owner {
  _Owner(this.name, this.file);

  final String name;
  final String file;

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
  final List<_Field> fields = <_Field>[];

  /// The declare-time hooks this declaration overrides with a body.
  final List<_HookOverride> hooks = <_HookOverride>[];
}

/// One `describeX` override, and whether it chains.
@immutable
class _HookOverride {
  const _HookOverride(this.hook, {required this.callsSuper});

  final String hook;
  final bool callsSuper;
}

/// The declare-time passes a component contributes to, each chained through
/// every mixin on the entity.
const Set<String> _describeHooks = <String>{
  'describeType',
  'describeAssets',
  'describeStruct',
};

/// Looks for `super.<hook>(...)` anywhere in one method body.
///
/// Matched on the AST and not the text, so a mention inside a comment or a
/// string is not a call, and `super.describeStruct(data)` inside a
/// `describeType` body does not count as chaining `describeType`.
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

/// Collects declarations and the fields they declare.
class _OwnerVisitor extends RecursiveAstVisitor<void> {
  _OwnerVisitor(this._file);

  final String _file;
  final List<_Owner> owners = <_Owner>[];

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    final superName = node.extendsClause?.superclass.name2.lexeme;
    final owner = _Owner(node.name.lexeme, _file)..superName = superName;
    for (final type in node.withClause?.mixinTypes ?? const <NamedType>[]) {
      owner.mixes.add(type.name2.lexeme);
    }
    _readFields(node.members, owner);
    _readHooks(node.members, owner);
    owners.add(owner);
    super.visitClassDeclaration(node);
  }

  @override
  void visitMixinDeclaration(MixinDeclaration node) {
    final owner = _Owner(node.name.lexeme, _file)..isMixin = true;
    for (final type
        in node.onClause?.superclassConstraints ?? const <NamedType>[]) {
      owner.onConstraints.add(type.name2.lexeme);
    }
    _readFields(node.members, owner);
    _readHooks(node.members, owner);
    owners.add(owner);
    super.visitMixinDeclaration(node);
  }

  /// Records each declare-time hook this declaration overrides with a body,
  /// and whether that body chains to the one it is overriding.
  ///
  /// A bodiless declaration is skipped. `Component` itself declares all three
  /// with no body, and re-declaring one abstract overrides nothing at run
  /// time - there is no call to leave out.
  void _readHooks(List<ClassMember> members, _Owner owner) {
    for (final member in members) {
      if (member is! MethodDeclaration) continue;
      final hook = member.name.lexeme;
      if (!_describeHooks.contains(hook)) continue;
      final body = member.body;
      if (body is EmptyFunctionBody) continue;
      final visitor = _SuperCallVisitor(hook);
      body.accept(visitor);
      owner.hooks.add(_HookOverride(hook, callsSuper: visitor.found));
    }
  }

  void _readFields(List<ClassMember> members, _Owner owner) {
    for (final member in members) {
      if (member is! FieldDeclaration) continue;
      // An explicit override is somebody stating the intent this checks for,
      // so it is theirs to make.
      if (member.metadata.any((a) => a.name.name == 'override')) continue;
      if (member.isStatic) continue;
      for (final variable in member.fields.variables) {
        owner.fields.add(
          _Field(
            variable.name.lexeme,
            isColumn: _isColumn(variable, member.fields.type),
          ),
        );
      }
    }
  }
}

/// Whether a field declaration allocates a row column.
///
/// Three shapes, all syntactic. `final speed = Field.float64()` is the one
/// components are written in now. `final barrel = EntityStruct.of(Barrel.new)`
/// takes a column for the child's handle. The third is the older form, a bare
/// `DataPointer` declaration that a `describeStruct` body assigns into, which
/// the engine still supports.
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
    };
    if (columnTypes.contains(declaredType.name2.lexeme)) return true;
  }
  return false;
}

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
