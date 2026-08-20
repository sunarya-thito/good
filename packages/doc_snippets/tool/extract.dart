// Turns every fenced `dart` block in docs/ into Dart the analyzer will read.
//
// One generated library per documentation page, fences in page order, so a
// `mixin Health` declared near the top of a page is in scope for every fence
// below it the way a reader assumes it is. Run it, then analyze this package:
//
//     dart run tool/extract.dart
//     flutter analyze --no-pub
//
// The conventions are documented in README.md. Briefly: an untagged fence is
// checked, and the tags are HTML comments on the line above it.
//
// No package: imports on purpose. This has to run before `pub get` in CI.

import 'dart:io';

void main(List<String> args) {
  final root = _repoRoot();
  final docsDir = Directory('${root.path}/docs');
  if (!docsDir.existsSync()) {
    stderr.writeln('no docs/ directory under ${root.path}');
    exit(2);
  }

  final outDir = Directory('${root.path}/packages/doc_snippets/lib/pages');
  if (outDir.existsSync()) outDir.deleteSync(recursive: true);
  outDir.createSync(recursive: true);

  final pages = <_Page>[];
  final files = docsDir
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.md'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  for (final file in files) {
    final rel = file.path
        .substring(root.path.length + 1)
        .replaceAll(r'\', '/');
    final page = _parse(rel, file.readAsLinesSync());
    if (page.fences.isEmpty) continue;
    pages.add(page);
  }

  var checked = 0;
  var skipped = 0;
  final skipReasons = <String, int>{};

  for (final page in pages) {
    for (final f in page.fences) {
      final reason = page.skipReason ?? f.skipReason;
      if (reason != null) {
        skipped++;
        skipReasons[reason] = (skipReasons[reason] ?? 0) + 1;
      } else {
        checked++;
      }
    }
    for (final entry in _emit(page).entries) {
      File('${outDir.path}/${entry.key}').writeAsStringSync(entry.value);
    }
  }

  stdout.writeln(
    'doc_snippets: ${checked + skipped} dart fences in ${pages.length} pages '
    '— $checked checked, $skipped skipped',
  );
  if (skipReasons.isNotEmpty) {
    final keys = skipReasons.keys.toList()..sort();
    for (final k in keys) {
      stdout.writeln('  skip: $k (${skipReasons[k]})');
    }
  }

  // A tag nobody recognises is a silent hole: the fence looks annotated and is
  // checked anyway, or worse, looks checked and is not. Fail instead.
  final bad = [for (final p in pages) ...p.errors];
  if (bad.isNotEmpty) {
    stderr.writeln('\nbad snippet tags:');
    for (final e in bad) {
      stderr.writeln('  $e');
    }
    exit(1);
  }
}

Directory _repoRoot() {
  var dir = Directory.current;
  for (var i = 0; i < 6; i++) {
    if (Directory('${dir.path}/docs').existsSync() &&
        File('${dir.path}/mkdocs.yml').existsSync()) {
      return dir;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  stderr.writeln('run this from inside the repository');
  exit(2);
}

/// How a fence is placed in the generated library.
enum _Placement {
  /// Straight into the library, for `class`/`mixin`/`enum`/`import` blocks.
  top,

  /// Into a method of a generated subclass - `GameSystem` unless the tag names
  /// something else. This is the default
  /// for statement fragments, and it is what makes most of them compile with no
  /// tagging at all: `game`, `state`, `getSystem`, `getScene` and
  /// `startCoroutine` are all members a system already has, and the prose uses
  /// them bare because that is where the code it is describing lives.
  body,

  /// Into a plain top-level function, for fragments that run on the Flutter
  /// isolate and have no system around them.
  plain,

  /// Into the body of a generated class, for `@override` member fragments.
  member,

  /// Into a top-level function's expression body, for a fence that is one
  /// expression with no semicolon after it. A widget tree is the case: the page
  /// shows the `Stack(...)` a `buildView` returns, and a reader who sees a
  /// trailing `;` there will write one.
  expression,
}

class _Fence {
  _Fence({
    required this.line,
    required this.code,
    required this.placement,
    required this.memberHeader,
    required this.skipReason,
  });

  final int line;
  final List<String> code;
  final _Placement placement;

  /// Lines from a `<!-- snippet-setup -->` block above this fence, emitted
  /// inside the same wrapper and above the snippet itself.
  List<String> setup = const [];

  /// What the generated wrapper class extends, e.g.
  /// `GameSystem with FixedTickable`. Set by `snippet: in <header>` and by
  /// `snippet: body <header>`; null means `GameSystem` for a body fence.
  final String? memberHeader;

  final String? skipReason;
}

class _Page {
  _Page(this.relPath);

  final String relPath;
  final fences = <_Fence>[];
  final scope = <String>[];
  final errors = <String>[];

  /// Set by `<!-- snippet-page: skip ... -->`, for a page whose whole subject
  /// is an API that does not exist yet. One line beats tagging every fence.
  String? skipReason;

  List<String> get scopeDeclarations => _declarations(scope);

  String get libraryName => relPath
      .substring('docs/'.length)
      .replaceAll('.md', '')
      .replaceAll('/', '_')
      .replaceAll('-', '_');
}

final _fenceStart = RegExp(r'^(\s*)```dart\b(.*)$');
final _tag = RegExp(r'^\s*<!--\s*snippet:\s*(.*?)\s*-->\s*$');
final _scopeOpen = RegExp(r'^\s*<!--\s*snippet-(scope|setup)\s*$');
final _pageSkip = RegExp(r'^\s*<!--\s*snippet-page:\s*skip\s+(.*?)\s*-->\s*$');

_Page _parse(String relPath, List<String> lines) {
  final page = _Page(relPath);
  String? pendingTag;
  var pendingTagLine = 0;
  var pendingSetup = <String>[];

  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];

    if (_pageSkip.firstMatch(line) case final m?) {
      page.skipReason = m.group(1);
      continue;
    }

    final scopeOpen = _scopeOpen.firstMatch(line);
    if (scopeOpen != null) {
      final into = scopeOpen.group(1) == 'scope' ? page.scope : pendingSetup;
      var j = i + 1;
      while (j < lines.length && lines[j].trimRight() != '-->') {
        into.add(lines[j]);
        j++;
      }
      if (j >= lines.length) {
        page.errors.add(
          '$relPath:${i + 1}: unterminated <!-- snippet-${scopeOpen.group(1)}',
        );
      }
      i = j;
      continue;
    }

    final tag = _tag.firstMatch(line);
    if (tag != null) {
      pendingTag = tag.group(1);
      pendingTagLine = i + 1;
      continue;
    }

    final start = _fenceStart.firstMatch(line);
    if (start == null) {
      // A tag has to sit directly above its fence. Blank lines between are
      // allowed because markdown formatting habits vary; prose is not.
      if (line.trim().isNotEmpty) {
        if (pendingTag != null) {
          page.errors.add(
            '$relPath:$pendingTagLine: `snippet:` tag is not above a '
            '```dart fence',
          );
          pendingTag = null;
        }
        pendingSetup = <String>[];
      }
      continue;
    }

    final indent = start.group(1)!;
    final code = <String>[];
    var j = i + 1;
    for (; j < lines.length; j++) {
      if (lines[j].trimRight() == '$indent```') break;
      // A line that is nothing but `...` is the page eliding the rest of a
      // body, not Dart. Dropping it keeps the fence checked instead of forcing
      // the author to write out a body the page deliberately left out. A spread
      // is `...name` and never stands alone on a line, so nothing else matches.
      if (lines[j].trim() == '...') continue;
      code.add(_dedent(lines[j], indent.length));
    }
    i = j;

    final fence = _fence(page, relPath, i + 1, code, pendingTag, pendingTagLine)
      ..setup = pendingSetup;
    pendingTag = null;
    pendingSetup = <String>[];
    page.fences.add(fence);
  }

  if (pendingTag != null) {
    page.errors.add(
      '$relPath:$pendingTagLine: `snippet:` tag is not above a ```dart fence',
    );
  }
  return page;
}

String _dedent(String line, int n) {
  var i = 0;
  while (i < n && i < line.length && line[i] == ' ') {
    i++;
  }
  return line.substring(i);
}

_Fence _fence(
  _Page page,
  String relPath,
  int line,
  List<String> code,
  String? tag,
  int tagLine,
) {
  if (tag != null) {
    if (tag == 'skip' || tag.startsWith('skip ')) {
      final reason = tag.substring(4).trim();
      if (reason.isEmpty) {
        page.errors.add(
          '$relPath:$tagLine: `snippet: skip` needs a reason after it',
        );
      }
      return _Fence(
        line: line,
        code: code,
        placement: _Placement.body,
        memberHeader: null,
        skipReason: reason.isEmpty ? 'unexplained' : reason,
      );
    }
    if (tag == 'top') {
      return _Fence(
        line: line,
        code: code,
        placement: _Placement.top,
        memberHeader: null,
        skipReason: null,
      );
    }
    if (tag == 'body' || tag.startsWith('body ')) {
      // `body` on its own wraps in a GameSystem. `body <header>` wraps in
      // something else, for the fragments whose surrounding code is a prefab or
      // a system with a mixin on it - `startAnimation` is on `Animations`,
      // which GameSystem does not have.
      final header = tag.length > 4 ? tag.substring(5).trim() : '';
      return _Fence(
        line: line,
        code: code,
        placement: _Placement.body,
        memberHeader: header.isEmpty ? null : header,
        skipReason: null,
      );
    }
    if (tag == 'expr') {
      return _Fence(
        line: line,
        code: code,
        placement: _Placement.expression,
        memberHeader: null,
        skipReason: null,
      );
    }
    if (tag == 'plain') {
      return _Fence(
        line: line,
        code: code,
        placement: _Placement.plain,
        memberHeader: null,
        skipReason: null,
      );
    }
    if (tag.startsWith('in ')) {
      return _Fence(
        line: line,
        code: code,
        placement: _Placement.member,
        memberHeader: tag.substring(3).trim(),
        skipReason: null,
      );
    }
    page.errors.add('$relPath:$tagLine: unknown snippet tag `$tag`');
  }
  return _Fence(
    line: line,
    code: code,
    placement: _guess(code),
    memberHeader: null,
    skipReason: null,
  );
}

// Only declarations that are illegal inside a function body force top level.
// Everything else goes in a body, because a body accepts local classes' worth of
// Dart already: local functions, local variables, and bare statements. Guessing
// wrong in that direction produces a comprehensible error; guessing wrong the
// other way produces "expected a declaration" on a line of prose.
const _topLevelOnly = [
  'import ',
  'export ',
  'part ',
  'library ',
  'class ',
  'abstract ',
  'mixin ',
  'enum ',
  'extension ',
  'typedef ',
  'sealed ',
  'base ',
  'interface ',
  'final class ',
];

_Placement _guess(List<String> code) {
  for (final line in code) {
    if (line.isEmpty || line.startsWith(' ') || line.startsWith('\t')) continue;
    for (final kw in _topLevelOnly) {
      if (line.startsWith(kw)) return _Placement.top;
    }
  }
  return _Placement.body;
}

/// One page becomes one library — unless the page redefines a name.
///
/// Teaching pages do that constantly: `class Orc` appears five times in
/// thinking-in-ecs.md, each version a little bigger than the last, and each
/// fence below it means the nearest one above. Emitting them all into one
/// library gives five `Orc`s and no answer. So the page is cut into segments at
/// every redefinition, and segment N imports segment N-1 with the names it is
/// about to redefine hidden. A reference resolves to the most recent definition
/// above it, which is what the page says and what a reader assumes.
Map<String, String> _emit(_Page page) {
  if (page.skipReason != null) return const {};
  final live = page.fences.where((f) => f.skipReason == null).toList();
  if (live.isEmpty) return const {};

  final segments = <List<_Fence>>[<_Fence>[]];
  final shadowed = <List<String>>[<String>[]];
  var declared = <String>{...page.scopeDeclarations};

  for (final fence in live) {
    final names = fence.placement == _Placement.top
        ? _declarations(fence.code)
        : const <String>[];
    final clash = names.where(declared.contains).toList();
    if (clash.isNotEmpty) {
      segments.add(<_Fence>[]);
      shadowed.add(clash);
      declared = {...declared, ...names};
    } else {
      declared.addAll(names);
    }
    segments.last.add(fence);
  }

  final files = <String, String>{};
  var n = 0;
  for (var s = 0; s < segments.length; s++) {
    final base = segments.length == 1
        ? page.libraryName
        : '${page.libraryName}_${s + 1}';
    final out = StringBuffer()
      ..writeln('// GENERATED by packages/doc_snippets/tool/extract.dart')
      ..writeln('// Source: ${page.relPath}')
      ..writeln('// Edit the documentation, not this file.')
      ..writeln('//')
      ..writeln('// ignore_for_file: non_constant_identifier_names, '
          'unnecessary_import')
      ..writeln();

    if (s == 0) {
      // Exported as well as imported, so a later segment picks the engine up
      // through the chain instead of importing it a second time and colliding
      // with the page declarations it is meant to inherit.
      out
        ..writeln("import 'package:doc_snippets/scaffold.dart';")
        ..writeln("export 'package:doc_snippets/scaffold.dart';");
    } else {
      final prev = '${page.libraryName}_$s.dart';
      final hide = shadowed[s].isEmpty ? '' : ' hide ${shadowed[s].join(', ')}';
      out
        ..writeln("import '$prev'$hide;")
        ..writeln("export '$prev'$hide;");
    }
    out.writeln();

    if (s == 0 && page.scope.isNotEmpty) {
      out
        ..writeln('// <!-- snippet-scope --> from ${page.relPath}')
        ..writeln(page.scope.join('\n'))
        ..writeln();
    }

    for (final fence in segments[s]) {
      n++;
      out.writeln('// ---- ${page.relPath}:${fence.line} ----');
      final body = [...fence.setup, ...fence.code];
      switch (fence.placement) {
        case _Placement.top:
          if (fence.setup.isNotEmpty) out.writeln(fence.setup.join('\n'));
          final split = _splitLooseStatements(_withoutDirectives(fence.code));
          out.writeln(split.declarations.join('\n'));
          if (split.statements.isNotEmpty) {
            out
              ..writeln(_wrapper(n, split.statements))
              ..writeln(_indent(split.statements, 2))
              ..writeln('}');
          }
        case _Placement.body:
          out
            ..writeln('abstract class _Snippet$n extends '
                '${fence.memberHeader ?? 'GameSystem'} {')
            ..writeln('  ${_wrapper(n, fence.code)}')
            ..writeln(_indent(body, 4))
            ..writeln('  }')
            ..writeln('}');
        case _Placement.plain:
          out
            ..writeln(_wrapper(n, fence.code))
            ..writeln(_indent(body, 2))
            ..writeln('}');
        case _Placement.expression:
          out
            ..writeln('Object? expr$n() =>')
            ..writeln(_indent(body, 4))
            ..writeln('    ;');
        case _Placement.member:
          out
            ..writeln('abstract class _Snippet$n extends ${fence.memberHeader} {')
            ..writeln(_indent(body, 2))
            ..writeln('}');
      }
      out.writeln();
    }
    files['$base.dart'] = out.toString();
  }
  return files;
}

// A fragment that yields is an excerpt of a coroutine, and coroutines in this
// engine are `sync*`. Inferred rather than tagged: there is exactly one right
// answer and the fence already says which.
// `Object?` and not `void`, because a fragment is an excerpt of some method
// whose return type the page never shows. Insisting on one would only make
// authors tag the return type of code that is not about returning.
String _wrapper(int n, List<String> code) => _yields(code)
    ? 'Iterable<Object?> run$n() sync* {'
    : 'Future<Object?> run$n() async {';

final _directive = RegExp(r"^\s*(import|export|library|part)\b[^;]*;\s*(//.*)?$");

/// Drops the `import` lines out of a fence.
///
/// A snippet that opens with `import 'package:goo2d/goo2d.dart';` is showing
/// the reader which package to depend on, and the generated library already
/// has every one of them through the scaffold. The relative ones —
/// `import '../prefabs/player.dart'` — name files in the reader's project and
/// could never resolve here at all. Either way the line is prose about the
/// project layout, not an assertion about the API, and Dart wants directives
/// before declarations, which a fence halfway down a page cannot be.
List<String> _withoutDirectives(List<String> code) =>
    [for (final l in code) if (!_directive.hasMatch(l)) l];

/// A bare statement at the outermost level of an otherwise top-level fence.
///
/// Pages mix the two constantly — declare the dispatcher, then fire it, in one
/// block — because that is how the idea reads. A call or an assignment on a
/// lowercase name is never a Dart declaration, so it can be lifted into a
/// function without asking the author to split the fence in two.
final _looseStatement = RegExp(
  r'^[a-z_][\w.]*\s*(<[\w<>, ?]+>\s*)?(\(|\[|=[^=]|\.\.)',
);

({List<String> declarations, List<String> statements}) _splitLooseStatements(
  List<String> code,
) {
  final declarations = <String>[];
  final statements = <String>[];
  var depth = 0;
  var inStatement = false;
  for (final line in code) {
    if (depth == 0 && !inStatement && _looseStatement.hasMatch(line)) {
      inStatement = true;
    }
    (inStatement ? statements : declarations).add(line);
    depth += _delta(line);
    if (depth == 0 && line.trimRight().endsWith(';')) inStatement = false;
  }
  return (declarations: declarations, statements: statements);
}

int _delta(String line) {
  var d = 0;
  for (final c in line.split('')) {
    if (c == '{' || c == '(' || c == '[') d++;
    if (c == '}' || c == ')' || c == ']') d--;
  }
  return d;
}

final _yield = RegExp(r'^\s*yield\b');

bool _yields(List<String> code) => code.any(_yield.hasMatch);

final _decl = RegExp(
  r'^(?:abstract\s+|final\s+|base\s+|interface\s+|sealed\s+|mixin\s+)*'
  r'(?:class|mixin|enum|typedef|extension\s+type(?:\s+const)?|extension)\s+'
  r'(\w+)',
);

List<String> _declarations(List<String> code) => [
      for (final line in code)
        if (!line.startsWith(' ') && !line.startsWith('\t'))
          if (_decl.firstMatch(line) case final m?) m.group(1)!,
    ];

String _indent(List<String> code, int n) {
  final pad = ' ' * n;
  return code.map((l) => l.isEmpty ? '' : '$pad$l').join('\n');
}
