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
// # Why it parses instead of resolving
//
// A resolved scan reads the element model, so it would take a column's value
// type from the analyzer rather than deriving it, and "is this a Component"
// from the real supertype graph rather than from names. That is better
// information, and it is not available here.
//
// Resolution needs a `.dart_tool/package_config.json` beside every package it
// reads, and this tool's whole input is "the directories `--dir` named".
// `enginePackages` deliberately builds the engine-dependency graph out of the
// pubspecs sitting next to each other, precisely so a checkout that has never
// been resolved still generates - and measured on such a checkout, resolution
// reports the type of every one of the 67 columns in this repository as
// `InvalidType`, because `package:good/good.dart` does not resolve, so `Field`
// is undeclared, so `final transformOffsetX = Field.float64()` has no inferred
// type. Nothing throws. The run finds zero columns, reports success, and
// `--check` calls all eight committed files stale - which, run without
// `--check`, deletes every generated accessor in the repository. That is the
// failure #305 is named for, with a bigger blast radius.
//
// It would do the same to a project. `good generate` runs before
// `flutter pub get`, on a project that may never have resolved, and the fixture
// the shadowed-column refusal is tested against is a `game.dart` that imports
// nothing at all.
//
// Cost is the second argument and not the first. Measured over this
// repository: this walk parses 123 files in 0.9s, and an
// `AnalysisContextCollection` resolves the 79 under the four packages that
// declare components in 14.1s - 7ms a file against 178ms, and `--check` is on
// the inner loop of every CI run.
//
// What resolution would have bought is bought another way. Everything this
// needs to know about the engine is *in the read set*: `Field`'s static
// signatures are in `good/lib/src/data.dart`, and so is the `Component`
// hierarchy, because a package generated into depends on `good` by definition
// and `enginePackages` puts that `lib/` in the same walk. So a column's value
// type is read off `Field.float64`'s own declared return type rather than out
// of a table in this file that nothing would report as out of date.
//
// The one thing parsing gets wrong on its own is the language version, and that
// is #348: `parseString` does not read `analysis_options.yaml`, so a file using
// `primary-constructors` failed to parse, the parser recovered, and a shorter
// tree came back with no error anywhere. [scanFeatureSet] names the experiments
// instead of inheriting them, and [ScanSources.unparsed] carries every file
// that still did not parse, so a caller fails the run rather than reporting a
// clean pass over a tree it read a fraction of.

import 'dart:io';

import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';

import 'package:good_cli/src/generate/assets.dart';
import 'package:good_cli/src/generate/engine_dependency.dart';

/// The language every file in the walk is parsed as.
///
/// The experiments are named here and not inherited from an
/// `analysis_options.yaml`, because `parseString` does not read one - which is
/// the whole of #348. `good`, `goo2d`, `goo3d`, `good_net` and `good_net_p2p`
/// all turn `primary-constructors` on, and a file this cannot parse is one
/// whose components, columns and doc references all vanish from the answer.
///
/// The SDK version is pinned rather than read from `Platform.version`, so the
/// same source parses the same way on every machine. Raising it is a deliberate
/// edit made when the repository starts using something newer.
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

/// One field or top-level variable, as it is written.
///
/// Everything here is syntax. [typeSource] is the annotation if there is one
/// and null if there is not; [factory] is the dotted name of the call its
/// initialiser is, if it is a call at all. Whether either of them makes this a
/// column is [columnValueType]'s question and not this class's - a field is
/// recorded whatever it holds, because several passes ask about different
/// fields and none of them should need its own walk.
@immutable
class ScannedField {
  const ScannedField({
    required this.name,
    required this.typeSource,
    required this.factory,
    required this.factoryTypeArguments,
    required this.factoryArguments,
    required this.annotations,
    required this.isStatic,
    required this.isLate,
    required this.hasInitializer,
  });

  final String name;

  /// The written type annotation - `DataPointer<CameraView?>` - or null.
  final String? typeSource;

  /// The dotted name of the initialiser's callee - `Field.float64` - or null
  /// when the initialiser is absent or is not a plain call.
  final String? factory;

  /// The call's explicit type arguments, if it was given any.
  final List<String> factoryTypeArguments;

  /// The source of each positional argument, in order.
  final List<String> factoryArguments;

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
  /// Read because a declaration held by a `late` field is refused, and
  /// nothing else in the walk can tell one from an ordinary field: both are
  /// `DataPointer<CameraView?> cameraView` with an initialiser somewhere
  /// else. It was removed once as dead and is here again for the check that
  /// needs it - see `declarationRefusals`.
  final bool isLate;

  /// Whether it has an initialiser at its declaration.
  ///
  /// A `late final X x;` with no initialiser is the half of a double
  /// declaration this walk can see; the other half is a statement in a
  /// `describeX` body, which it deliberately does not go looking for. One
  /// half is enough to refuse.
  final bool hasInitializer;

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
    required this.returnTypeSource,
    required this.typeParameters,
    required this.parameters,
    required this.parameterNames,
    required this.annotations,
    required this.isEmptyBody,
    required this.callsSuper,
    required this.registeredTypes,
  });

  final String name;
  final bool isStatic;

  /// The written return type - `InitialPointer<double>` - or null.
  final String? returnTypeSource;

  /// The method's own type parameter names, in order.
  final List<String> typeParameters;

  /// Each parameter's written type, keyed by parameter name.
  final Map<String, String> parameters;

  /// Parameter names, in order.
  final List<String> parameterNames;

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
    required this.exports,
    required this.types,
    required this.variables,
  });

  /// The file, normalised and absolute.
  final String path;

  /// Every top-level name it declares.
  final Set<String> declaredNames;

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
  const ScanSources({required this.units, required this.unparsed});

  /// Keyed by normalised absolute path.
  final Map<String, ScannedUnit> units;

  /// Every file the parser reported a diagnostic on, as an absolute path.
  ///
  /// Carried rather than thrown, because the caller decides what a file it
  /// could not read means. It means the run checked less than it was pointed
  /// at, and the mode that has one exits on it - see #348 for what reporting it
  /// as a warning cost.
  final List<String> unparsed;

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
ScanSources readSources(
  Directory dir, {
  List<String>? rootOverride,
  Set<String> exclude = const <String>{},
}) {
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

  final units = <String, ScannedUnit>{};
  final unparsed = <String>[];
  for (final root in <String>{...roots}) {
    final directory = Directory(root);
    if (!directory.existsSync()) continue;
    final files = <File>[
      for (final entry in directory.listSync(recursive: true))
        if (entry is File && entry.path.endsWith('.dart')) entry,
    ]..sort((a, b) => a.path.compareTo(b.path));
    for (final file in files) {
      final path = p.normalize(p.absolute(file.path));
      if (skip.contains(path)) continue;
      if (units.containsKey(path)) continue;
      final String content;
      try {
        content = file.readAsStringSync();
      } on FileSystemException {
        unparsed.add(path);
        continue;
      }
      final parsed = parseString(
        content: content,
        featureSet: scanFeatureSet,
        throwIfDiagnostics: false,
      );
      if (parsed.errors.isNotEmpty) {
        unparsed.add(path);
        continue;
      }
      units[path] = _readUnit(path, parsed.unit);
    }
  }
  return ScanSources(units: units, unparsed: unparsed);
}

ScannedUnit _readUnit(String path, CompilationUnit unit) {
  final declaredNames = <String>{};
  final exports = <ScannedExport>[];
  final types = <ScannedType>[];
  final variables = <ScannedField>[];

  for (final directive in unit.directives) {
    if (directive is! ExportDirective) continue;
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
    exports.add(ScannedExport(uri: uri, shown: shown, hidden: hidden));
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
            typeSource: declaration.variables.type?.toSource(),
            annotations: annotations,
            isStatic: true,
            isLate: true,
          ),
        );
      }
    }

    final scanned = _readType(path, declaration);
    if (scanned != null) types.add(scanned);
  }

  return ScannedUnit(
    path: path,
    declaredNames: declaredNames,
    exports: exports,
    types: types,
    variables: variables,
  );
}

ScannedType? _readType(String path, CompilationUnitMember declaration) {
  final String name;
  final supertypes = <String>[];
  final mixins = <String>[];
  String? superclass;
  var isAbstract = false;
  final List<ClassMember> members;
  String? representation;

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
    isAbstract = true;
    addAll(declaration.onClause?.superclassConstraints ?? const <NamedType>[]);
    addAll(declaration.implementsClause?.interfaces ?? const <NamedType>[]);
    members = _members(declaration.body);
  } else if (declaration is EnumDeclaration) {
    name = declaration.name.lexeme;
    addMixins(declaration.withClause?.mixinTypes ?? const <NamedType>[]);
    addAll(declaration.withClause?.mixinTypes ?? const <NamedType>[]);
    addAll(declaration.implementsClause?.interfaces ?? const <NamedType>[]);
    // An `EnumBody` and not a `ClassBody`, and an enum always has a block, so
    // there is no empty case for [_members] to guard against here.
    members = declaration.body.members;
  } else if (declaration is ExtensionTypeDeclaration) {
    name = declaration.name.lexeme;
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
            typeSource: member.fields.type?.toSource(),
            annotations: annotations,
            isStatic: member.isStatic,
            isLate: member.fields.lateKeyword != null,
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

ScannedField _readVariable(
  VariableDeclaration variable, {
  required String? typeSource,
  required List<String> annotations,
  required bool isStatic,
  required bool isLate,
}) {
  final initializer = variable.initializer;
  String? factory;
  final typeArguments = <String>[];
  final arguments = <String>[];
  if (initializer is MethodInvocation) {
    final target = initializer.target;
    factory = target == null
        ? initializer.methodName.name
        : '${target.toSource()}.${initializer.methodName.name}';
    for (final argument
        in initializer.typeArguments?.arguments ?? const <TypeAnnotation>[]) {
      typeArguments.add(argument.toSource());
    }
    for (final argument in initializer.argumentList.arguments) {
      if (argument is NamedExpression) continue;
      arguments.add(argument.toSource());
    }
  }
  return ScannedField(
    name: variable.name.lexeme,
    typeSource: typeSource,
    factory: factory,
    factoryTypeArguments: typeArguments,
    factoryArguments: arguments,
    annotations: annotations,
    isStatic: isStatic,
    isLate: isLate,
    hasInitializer: initializer != null,
  );
}

ScannedMethod _readMethod(MethodDeclaration member) {
  final name = member.name.lexeme;
  final parameters = <String, String>{};
  final parameterNames = <String>[];
  for (final parameter
      in member.parameters?.parameters ?? const <FormalParameter>[]) {
    final parameterName = parameter.name?.lexeme;
    if (parameterName == null) continue;
    parameterNames.add(parameterName);
    final normal = parameter is DefaultFormalParameter
        ? parameter.parameter
        : parameter;
    if (normal is SimpleFormalParameter) {
      final type = normal.type;
      if (type != null) parameters[parameterName] = type.toSource();
    }
  }
  final visitor = _MethodBodyVisitor(
    name: name,
    receiver: parameterNames.isEmpty ? null : parameterNames.first,
  );
  member.body.accept(visitor);
  return ScannedMethod(
    name: name,
    isStatic: member.isStatic,
    returnTypeSource: member.returnType?.toSource(),
    typeParameters: <String>[
      for (final parameter
          in member.typeParameters?.typeParameters ?? const <TypeParameter>[])
        parameter.name.lexeme,
    ],
    parameters: parameters,
    parameterNames: parameterNames,
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
/// Two shapes declare one, and both are in the tree:
///
/// ```dart
/// final transformOffsetX = Field.float64();          // the factory's return
/// late final DataPointer<CameraView?> cameraView;    // the annotation
/// ```
///
/// The first is answered by reading `Field.float64`'s own declared return type
/// out of the parse - `InitialPointer<double>` - rather than out of a table
/// here. `Field` is in the read set whenever a component is, because a package
/// holding components depends on `good`, so such a table would be a second copy
/// of something already present and free to go stale against it.
///
/// Returns null when the field is not a column at all, which is most of them.
ColumnResolution? columnValueType(
  ScannedField field,
  Map<String, ScannedType> typesByName,
) {
  final annotation = field.typeSource;
  if (annotation != null) {
    final parsed = TypeSource.parse(annotation);
    if (parsed == null) return null;
    return _fromPointer(parsed);
  }

  final factory = field.factory;
  if (factory == null) return null;
  final dot = factory.lastIndexOf('.');
  if (dot <= 0) return null;
  final owner = typesByName[factory.substring(0, dot)];
  if (owner == null) return null;
  final method = owner.methods[factory.substring(dot + 1)];
  if (method == null || !method.isStatic) return null;
  final returnType = method.returnTypeSource;
  if (returnType == null) return null;
  final parsed = TypeSource.parse(returnType);
  if (parsed == null) return null;
  final resolved = _fromPointer(parsed);
  if (resolved == null || resolved.problem != null) return resolved;

  final value = resolved.valueType!;
  final variable = value.endsWith('?')
      ? value.substring(0, value.length - 1)
      : value;
  if (!method.typeParameters.contains(variable)) return resolved;

  final inferred = _inferTypeArgument(field, method, variable);
  if (inferred == null) {
    return ColumnResolution.problem(
      'its value type is the `$variable` of ${owner.name}.${method.name}, and '
      'the call leaves it to inference in a shape this pass does not read. '
      'Write the type argument, or annotate the field',
    );
  }
  return ColumnResolution.column(value.endsWith('?') ? '$inferred?' : inferred);
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

/// The type argument a call left to inference, where the call says enough.
///
/// Two ways, and no third. An explicit `Field.enumOf<BodyType2D>(...)` says it
/// outright. Otherwise a parameter declared `List<E>` given `BodyType2D.values`
/// says it too, which is the shape every enum column in the tree is written in.
/// Anything else is reported rather than guessed at: a wrong value type
/// generates a property that reads the column as something it is not, and that
/// compiles.
String? _inferTypeArgument(
  ScannedField field,
  ScannedMethod method,
  String variable,
) {
  final index = method.typeParameters.indexOf(variable);
  if (field.factoryTypeArguments.length == method.typeParameters.length) {
    return field.factoryTypeArguments[index];
  }
  for (var i = 0; i < method.parameterNames.length; i++) {
    if (i >= field.factoryArguments.length) break;
    final declared = method.parameters[method.parameterNames[i]];
    if (declared == null) continue;
    final parsed = TypeSource.parse(declared);
    if (parsed == null) continue;
    if (parsed.name != 'List' || parsed.arguments.length != 1) continue;
    if (parsed.arguments.single != variable) continue;
    final argument = field.factoryArguments[i];
    if (!argument.endsWith('.values')) continue;
    final head = argument.substring(0, argument.length - '.values'.length);
    if (!_namePattern.hasMatch(head)) continue;
    return head;
  }
  return null;
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

/// The type of the value [field] holds, as far as the source says.
///
/// The written annotation when there is one, and otherwise the declared
/// return type of the static factory the initialiser calls - the same two
/// shapes [columnValueType] reads, kept apart from it because they answer
/// different questions. [columnValueType] wants what one entity's *value* is
/// (`double`, `CameraView?`), which is what a generated property returns.
/// This wants what the *field* holds (`InitialPointer<double>`,
/// `DataPointer<CameraView?>`), which is what decides whether the field is a
/// declaration at all and what a collector would hand back.
///
/// Null when neither is written. `final x = someHelper();` on a helper this
/// walk did not read is not a declaration as far as anything here can tell,
/// and saying so rather than guessing is the point.
///
/// # What the type arguments say, and where they do not
///
/// A factory's return type is written against the factory's own type
/// parameters, so `Field.enumOf<BodyType2D>(...)` declares
/// `PackedPointer<E>` and the `E` is filled in from the call - the same two
/// ways [columnValueType] fills one in, and no third. Where neither way
/// reaches, the parameter is left standing: `Field.array(.uint16, 32)`
/// answers `DataArrayPointer<T>`, because `T` is inferred from a
/// `DataElement<T>` argument written as a dot shorthand and nothing here
/// resolves one.
///
/// That is enough to decide whether a field is a declaration, which is only
/// ever the head of the type. It is **not** enough for an emitter that has to
/// write the type out, and a caller doing that has to say what it does with a
/// type argument still spelled `T`.
String? declaredValueType(
  ScannedField field,
  Map<String, ScannedType> typesByName,
) {
  final annotation = field.typeSource;
  if (annotation != null) return annotation;
  final factory = field.factory;
  if (factory == null) return null;
  final dot = factory.lastIndexOf('.');
  if (dot <= 0) return null;
  final owner = typesByName[factory.substring(0, dot)];
  if (owner == null) return null;
  final method = owner.methods[factory.substring(dot + 1)];
  if (method == null || !method.isStatic) return null;
  final returnType = method.returnTypeSource;
  if (returnType == null) return null;
  if (method.typeParameters.isEmpty) return returnType;
  final parsed = TypeSource.parse(returnType);
  if (parsed == null || parsed.arguments.isEmpty) return returnType;
  final arguments = <String>[];
  for (final argument in parsed.arguments) {
    final nullable = argument.endsWith('?');
    final head = nullable
        ? argument.substring(0, argument.length - 1)
        : argument;
    if (!method.typeParameters.contains(head)) {
      arguments.add(argument);
      continue;
    }
    final inferred = _inferTypeArgument(field, method, head);
    arguments.add(
      inferred == null ? argument : '$inferred${nullable ? '?' : ''}',
    );
  }
  return '${parsed.name}<${arguments.join(', ')}>'
      '${parsed.isNullable ? '?' : ''}';
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
  final declared = declaredValueType(field, typesByName);
  if (declared == null) return false;
  final parsed = TypeSource.parse(declared);
  if (parsed == null || parsed.isNullable) return false;
  return isSubtypeOf(parsed.name, scannableFieldRoot, typesByName);
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
    required this.uncollectable,
  });

  /// Classes holding at least one declaration, in path order.
  final List<ScannedDeclarer> declarers;

  /// What refuses a run - see [declarationRefusalMessage].
  final List<DeclarationRefusal> refusals;

  /// Declarations that are accepted and that a collector cannot read, keyed
  /// `Class.field`, to why.
  ///
  /// Private ones, and today that is all of them. A collector is generated
  /// into another library and a private field is `undefined_getter` there, so
  /// these contribute nothing to a collect pass - which is exactly the shape
  /// this engine keeps being bitten by, and exactly why it is listed rather
  /// than swallowed. It is not a refusal: whether the engine's own cache
  /// columns become public (28 of them, and every one would then generate a
  /// public accessor property) is an open call, and a check that decided it
  /// by refusing would be making it.
  final Map<String, String> uncollectable;

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
/// **`late`.** A `late final DataPointer<CameraView?> cameraView;` filled in
/// from a `describeStruct` body is one declaration written twice, and the
/// second half runs at a moment nothing at the declaration says. It is also
/// what a collector trips over first: a collect pass reads declarations off a
/// freshly constructed instance, and an unassigned `late final` throws there
/// instead of yielding anything.
///
/// **No initialiser at all.** The same thing with the word missing - the
/// field is filled in from somewhere else, and the declaration does not say
/// where.
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
  final declarers = <ScannedDeclarer>[];
  final refusals = <DeclarationRefusal>[];
  final uncollectable = <String, String>{};

  final paths = sources.units.keys.toList()..sort();
  for (final path in paths) {
    final unit = sources.units[path]!;
    for (final variable in unit.variables) {
      if (!isDeclarationField(variable, typesByName)) continue;
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
      if (!isSubtypeOf(type.name, scannableRoot, typesByName)) continue;
      final declarations = <ScannedDeclaration>[];
      for (final field in type.fields) {
        if (!isDeclarationField(field, typesByName)) continue;
        final valueType = declaredValueType(field, typesByName)!;
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
        if (field.isLate) {
          refusals.add(
            DeclarationRefusal(
              owner: type.name,
              field: field.name,
              path: path,
              reason:
                  'it is late, so the value is assigned somewhere else - a '
                  'describe pass, a constructor body - and the declaration is '
                  'written twice. A collect pass reads declarations off a '
                  'freshly constructed instance and finds this one '
                  'unassigned. Give the field its initialiser',
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
              reason:
                  'it has no initialiser, so whatever assigns it does so '
                  'somewhere the declaration does not say. Give the field its '
                  'initialiser',
            ),
          );
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
                if (isSubtypeOf(
                  annotationName(annotation),
                  scannableAnnotationRoot,
                  typesByName,
                ))
                  annotation,
            ],
            isPrivate: field.isPrivate,
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
    uncollectable: uncollectable,
  );
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
List<ScannedDeclaration> flattenedDeclarations(
  ScannedType type,
  Map<String, ScannedType> typesByName, {
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
          valueType: declaredValueType(field, typesByName)!,
          annotations: <String>[
            for (final annotation in field.annotations)
              if (isSubtypeOf(
                annotationName(annotation),
                scannableAnnotationRoot,
                typesByName,
              ))
                annotation,
          ],
          isPrivate: field.isPrivate,
        ),
  ];
  for (final mixin in type.mixins.reversed) {
    final applied = typesByName[mixin];
    if (applied == null) continue;
    flattened.addAll(flattenedDeclarations(applied, typesByName, seen: visited));
  }
  final superclass = type.superclass;
  if (superclass != null) {
    final above = typesByName[superclass];
    if (above != null) {
      flattened.addAll(flattenedDeclarations(above, typesByName, seen: visited));
    }
  }
  return flattened;
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
/// `describeX` override must call super": `TimelineStruct.describeTrack` and
/// `.describeAnimation` are **abstract**, so an override of either has no
/// implementation above it and calling super would not compile. Both are
/// written that way in `goo2d`'s own example, and a rule keyed on the name
/// alone reports them - measured, before this line was here.
StructRuleScan scanStructRules(Directory project) {
  final sources = readSources(project);
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
SceneUsage scanScenes(Directory project, AssetScan assets) {
  final sources = readSources(project);
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
