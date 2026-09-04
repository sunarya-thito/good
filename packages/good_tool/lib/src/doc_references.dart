// The pre-`ClassBody` AST - `ClassDeclaration.name`, `.members`,
// `ExtensionTypeDeclaration.representation`, `NamedCompilationUnitMember` - is
// deprecated in analyzer 10, and only some of it has a replacement there.
// `BlockClassBody.members` and `ClassDeclaration.namePart` are public in
// 10.2.0; `MixinDeclaration.namePart` is not - probed, "The getter 'namePart'
// isn't defined for the type 'MixinDeclaration'". So the tree cannot be read
// through one spelling until the analyzer 11 bump, which drops the old names
// in the release that finishes the new ones. That bump is a migration and not
// a constraint edit (#348). `scan.dart` carries the same note for the same
// reason.
// ignore_for_file: deprecated_member_use

import 'dart:io';

import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';
// ignore: implementation_imports
import 'package:good_cli/src/generate/engine_package.dart';

/// One `[Reference]` in a doc comment whose name is written nowhere.
@immutable
class DanglingReference {
  const DanglingReference({
    required this.package,
    required this.file,
    required this.line,
    required this.reference,
    required this.name,
  });

  /// The package whose `lib/` holds the comment.
  final String package;

  /// The file, relative to that package's root, in posix form.
  final String file;

  /// The line the reference sits on, 1-based.
  final int line;

  /// The reference as the parser read it - `Game.addTickListener`.
  final String reference;

  /// The part of [reference] that names nothing.
  final String name;

  /// `goo2d/lib/src/data/collider.dart:433`.
  String get where => '$package/$file:$line';
}

/// What one pass over the doc comments found.
@immutable
class DocReferenceScan {
  const DocReferenceScan({
    required this.dangling,
    required this.files,
    required this.references,
    required this.checked,
    required this.names,
    required this.unparsed,
  });

  /// Every reference that names nothing, in file then line order.
  final List<DanglingReference> dangling;

  /// How many files were read for references.
  final int files;

  /// How many `[...]` references those files hold.
  final int references;

  /// How many of [references] the rule was able to ask about.
  ///
  /// The rest are the ones [scanDocReferences] leaves alone: an operator, and a
  /// member named on a type declared outside the packages read.
  final int checked;

  /// How many distinct identifiers the packages read write in code.
  final int names;

  /// Every file the parser reported an error on, named `goo2d/lib/...`.
  ///
  /// A file in here contributed nothing: not its references, not its names.
  /// The parser recovers and hands back a tree either way, and the tree it
  /// hands back is missing whichever doc comments hung off the part it could
  /// not read - so a run that read it would check some of its references and
  /// report the rest as checked too. That is what #348 was: `collider.dart`
  /// held 46 references and 15 of them reached this pass, under a summary
  /// counting the run as clean.
  ///
  /// The caller fails on a non-empty list. There is no useful answer to give
  /// over a tree this pass could not read, and the alternative - saying so on
  /// stderr under an exit code of 0 - is the same silence with more words.
  final List<String> unparsed;
}

/// Every doc reference in [packages] that names nothing anywhere in [known].
///
/// [packages] are the ones whose `lib/` is read for doc comments. [known] is
/// the set the names are looked up in, and is normally [packages] plus the
/// engine packages they depend on: a `goo2d` comment may name a `good` type,
/// and one package's word list would report that as missing.
///
/// # What counts as written
///
/// Every identifier token in the `lib/` of a [known] package, outside comments.
/// Not a list of declarations: a reference may name a member, a constructor, a
/// named parameter, a library prefix or a private field, and only the token
/// stream holds all of those under one question. `[Future]` resolves because
/// the packages write `Future` in code, not because anything here reads
/// `dart:async`.
///
/// # Which part of a reference is looked up
///
/// A reference is a chain of identifiers - `Game`, or `Game.addTickListener`.
/// The first name is looked up always. A later name is looked up only when the
/// name in front of it is a top-level declaration of a [known] package, which
/// is the case where the type is one of ours and its members are all in the
/// token stream. `[Canvas.drawRect]` is left alone, because `Canvas` is
/// declared in Flutter and nothing here can say what its members are.
///
/// A reference holding anything that is not an identifier is left alone
/// entirely. That is `[operator +]` and `[InputEventStream.operator +]`, which
/// the parser hands over with `+` as the name.
///
/// # What it does not find
///
/// A name that is written somewhere in code and named in a comment where it
/// makes no sense - `[length]` on a type that has no `length`. Resolving that
/// needs types, and this pass reads tokens. It also passes a reference to a
/// name that another package in the run writes and this one does not, which is
/// the price of not reporting `[Entity]` in every package that documents one
/// without naming it in code.
DocReferenceScan scanDocReferences({
  required List<EnginePackage> packages,
  required List<EnginePackage> known,
}) {
  final scanned = <String>{for (final package in packages) package.libDir};
  final roots = <String, EnginePackage>{
    for (final package in known) package.libDir: package,
    for (final package in packages) package.libDir: package,
  };

  final written = <String>{};
  final declared = <String>{};
  final read = <_ReadFile>[];
  final unparsed = <String>[];
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
          unparsed.add(package.describe(file));
          continue;
        }
        unit = parsed.unit;
      } on ArgumentError {
        // Unreadable, or not Dart after all.
        unparsed.add(package.describe(file));
        continue;
      }
      for (var token = unit.beginToken; !token.isEof; token = token.next!) {
        if (token.type == TokenType.IDENTIFIER || token.isKeyword) {
          written.add(token.lexeme);
        }
      }
      for (final declaration in unit.declarations) {
        if (declaration is NamedCompilationUnitMember) {
          declared.add(declaration.name.lexeme);
        } else if (declaration is ExtensionDeclaration) {
          final name = declaration.name;
          if (name != null) declared.add(name.lexeme);
        }
      }
      if (scanned.contains(libDir)) {
        read.add(_ReadFile(package, file, unit));
      }
    }
  }

  final dangling = <DanglingReference>[];
  var references = 0;
  var checked = 0;
  read.sort((a, b) => a.file.path.compareTo(b.file.path));
  for (final entry in read) {
    final visitor = _ReferenceVisitor(entry.unit);
    entry.unit.accept(visitor);
    references += visitor.references.length;
    for (final reference in visitor.references) {
      final names = reference.names;
      if (names == null) continue;
      checked++;
      final dead = _firstDeadName(names, written: written, declared: declared);
      if (dead == null) continue;
      dangling.add(
        DanglingReference(
          package: entry.package.name,
          file: p
              .split(p.relative(entry.file.path, from: entry.package.root.path))
              .join('/'),
          line: reference.line,
          reference: names.join('.'),
          name: dead,
        ),
      );
    }
  }

  return DocReferenceScan(
    dangling: dangling,
    files: read.length,
    references: references,
    checked: checked,
    names: written.length,
    unparsed: unparsed..sort(),
  );
}

/// The first name in [names] that nothing writes, or null when all of them are.
///
/// See [scanDocReferences] for why a name past the first is only looked up
/// under a declaration this run can see.
String? _firstDeadName(
  List<String> names, {
  required Set<String> written,
  required Set<String> declared,
}) {
  if (!written.contains(names.first)) return names.first;
  for (var index = 1; index < names.length; index++) {
    if (!declared.contains(names[index - 1])) return null;
    if (!written.contains(names[index])) return names[index];
  }
  return null;
}

/// What one line's failure says.
String danglingReferenceLine(DanglingReference reference) =>
    '${reference.where}: [${reference.reference}] - nothing writes '
    '`${reference.name}`';

/// The report a run with findings prints under them.
String danglingReferenceSummary(DocReferenceScan scan) =>
    '\n${scan.dangling.length} doc reference(s) name something that is written '
    'nowhere in the packages read. A doc comment is the published API '
    'reference, so each one is a link a reader follows to nothing. Fix the '
    'name or drop the brackets.';

/// One parsed file the references are read out of.
class _ReadFile {
  _ReadFile(this.package, this.file, this.unit);

  final EnginePackage package;
  final File file;
  final CompilationUnit unit;
}

/// One `[...]` the parser recognised as a reference.
class _Reference {
  _Reference(this.line, this.names);

  final int line;

  /// The identifier chain, or null when any part of it is not an identifier.
  final List<String>? names;
}

/// Collects the references out of every doc comment in one unit.
///
/// The parser has already decided what a reference is, which is the reason this
/// reads `Comment.references` and not the comment text: a `[label](url)` link,
/// a `[label][target]` link and anything inside a fenced code block are not
/// references and never reach here.
class _ReferenceVisitor extends RecursiveAstVisitor<void> {
  _ReferenceVisitor(this.unit);

  final CompilationUnit unit;
  final references = <_Reference>[];

  @override
  void visitComment(Comment node) {
    for (final reference in node.references) {
      references.add(
        _Reference(
          unit.lineInfo.getLocation(reference.offset).lineNumber,
          _names(reference.expression),
        ),
      );
    }
    super.visitComment(node);
  }

  /// The identifier chain behind a reference expression.
  ///
  /// Null when a part of it is not an identifier. `[operator +]` arrives as an
  /// identifier whose name is `+`, so the test is on the spelling and not on
  /// the node type.
  static List<String>? _names(AstNode node) {
    if (node is SimpleIdentifier) {
      return _identifier(node.name) ? <String>[node.name] : null;
    }
    if (node is PrefixedIdentifier) {
      final prefix = _names(node.prefix);
      final identifier = _names(node.identifier);
      if (prefix == null || identifier == null) return null;
      return <String>[...prefix, ...identifier];
    }
    if (node is PropertyAccess) {
      final target = node.target;
      if (target == null) return null;
      final head = _names(target);
      final tail = _names(node.propertyName);
      if (head == null || tail == null) return null;
      return <String>[...head, ...tail];
    }
    return null;
  }

  static bool _identifier(String name) => _identifierPattern.hasMatch(name);
}

final RegExp _identifierPattern = RegExp(r'^[_$a-zA-Z][_$a-zA-Z0-9]*$');

/// The language this parses the packages as.
///
/// `primary-constructors` because `good` and `goo2d` turn it on in their
/// `analysis_options.yaml`, and a file this pass cannot parse contributes no
/// names - every reference to one of them would then report as dangling.
final FeatureSet _featureSet = FeatureSet.fromEnableFlags2(
  sdkLanguageVersion: Version(3, 13, 0),
  flags: const <String>['primary-constructors', 'dot-shorthands'],
);
