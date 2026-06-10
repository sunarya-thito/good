// Generates Docusaurus MDX API reference pages from dartdoc comments.
//
// Run: dart run scripts/dartdoc_to_mdx.dart
//
// Reads all public Dart source files under lib/src/, extracts class/mixin/enum
// documentation using the analyzer, groups declarations by module, and writes
// one .mdx file per module to docs_site/docs/api/.
//
// Requires dev dependencies: analyzer ^7.2.0, glob ^2.1.2, path ^1.9.0

// ignore_for_file: deprecated_member_use, avoid_print

import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:glob/glob.dart';
import 'package:glob/list_local_fs.dart';
import 'package:path/path.dart' as p;

// ---------------------------------------------------------------------------
// Module mapping
// ---------------------------------------------------------------------------

const _modules = <String, String>{
  'core': 'Core',
  'transform': 'Transform',
  'rendering': 'Rendering',
  'input': 'Input',
  'audio': 'Audio',
  'physics': 'Physics',
  'coroutines': 'Coroutines',
  'assets': 'Assets',
  'utility': 'Utility',
  'networking': 'Networking',
};

const _fileToModule = <String, String>{
  'game.dart': 'core',
  'component.dart': 'core',
  'object.dart': 'core',
  'widget.dart': 'core',
  'lifecycle.dart': 'core',
  'event.dart': 'core',
  'world.dart': 'core',
  'element.dart': 'core',
  'ticker.dart': 'core',
  'transform.dart': 'transform',
  'screen.dart': 'transform',
  'point.dart': 'transform',
  'sprite.dart': 'rendering',
  'sprite_mesh.dart': 'rendering',
  'sprite_pivot.dart': 'rendering',
  'sprite_fit.dart': 'rendering',
  'tile_renderer.dart': 'rendering',
  'camera.dart': 'rendering',
  'camera_view.dart': 'rendering',
  'painter.dart': 'rendering',
  'clipper.dart': 'rendering',
  'input.dart': 'input',
  'keyboard.dart': 'input',
  'audio.dart': 'audio',
  'coroutine.dart': 'coroutines',
  'asset.dart': 'assets',
  'utility.dart': 'utility',
};

// ---------------------------------------------------------------------------

void main() async {
  final repoRoot = p.normalize(
    p.join(p.dirname(Platform.script.toFilePath()), '..'),
  );

  final libSrcDir = p.join(repoRoot, 'lib', 'src');
  final outputDir = p.join(repoRoot, 'docs_site', 'docs', 'api');

  final outputDirectory = Directory(outputDir);
  if (outputDirectory.existsSync()) {
    stderr.writeln('Clearing existing contents of $outputDir');
    outputDirectory.deleteSync(recursive: true);
  }
  outputDirectory.createSync(recursive: true);

  final dartFiles = Glob('**.dart')
      .listSync(root: libSrcDir)
      .whereType<File>()
      .map((f) => p.normalize(f.path))
      .toList();

  if (dartFiles.isEmpty) {
    stderr.writeln('No Dart files found under $libSrcDir');
    return;
  }

  final collection = AnalysisContextCollection(includedPaths: dartFiles);

  // module key → accumulated MDX content
  final moduleContent = <String, StringBuffer>{};

  for (final filePath in dartFiles) {
    final relPath = p.relative(filePath, from: libSrcDir);
    final parts = p.split(relPath);
    final baseName = parts.last;

    final moduleKey = switch (true) {
      _ when parts.length > 1 && parts[0] == 'physics' => 'physics',
      _ when parts.length > 1 && parts[0] == 'rpc' => 'networking',
      _ => _fileToModule[baseName],
    };

    if (moduleKey == null) continue;

    final ctx = collection.contextFor(filePath);
    final result = await ctx.currentSession.getResolvedLibrary(filePath);
    if (result is! ResolvedLibraryResult) continue;

    final library = result.element;

    for (final unit in library.units) {
      for (final cls in [...unit.classes, ...unit.mixins]) {
        if (cls.isPrivate) continue;
        final section = _renderClassSection(cls);
        if (section != null) {
          moduleContent.putIfAbsent(moduleKey, StringBuffer.new).write(section);
        }
      }

      for (final enm in unit.enums) {
        if (enm.isPrivate) continue;
        final section = _renderEnumSection(enm);
        if (section != null) {
          moduleContent.putIfAbsent(moduleKey, StringBuffer.new).write(section);
        }
      }
    }
  }

  // Write one .mdx per module
  var sidebarPos = 1;
  for (final key in _modules.keys) {
    final buf = moduleContent[key];
    if (buf == null) continue;

    final label = _modules[key]!;
    final outPath = p.join(outputDir, '$key.mdx');

    File(outPath).writeAsStringSync(
      '---\nsidebar_position: $sidebarPos\n---\n\n'
      '# $label API Reference\n\n'
      '${buf.toString()}',
    );
    stderr.writeln('Wrote $outPath');
    sidebarPos++;
  }

  // Write sidebar category index
  File(p.join(outputDir, '_category_.json')).writeAsStringSync('''{
  "label": "API Reference",
  "position": 4,
  "link": {
    "type": "generated-index",
    "description": "Generated API reference for all public goo2d classes."
  }
}
''');

  stderr.writeln(
    'Done. Generated ${moduleContent.length} module files in $outputDir',
  );
}

// ---------------------------------------------------------------------------
// Section renderers
// ---------------------------------------------------------------------------

String? _renderClassSection(InterfaceElement element) {
  final doc = _extractDoc(element.documentationComment);

  final sb = StringBuffer()
    ..writeln('## ${element.displayName}')
    ..writeln();

  if (doc != null) {
    final (:prose, :example) = _splitDocExample(doc);
    sb
      ..writeln(prose)
      ..writeln();
    if (example != null) {
      sb
        ..writeln('```dart')
        ..writeln(example)
        ..writeln('```')
        ..writeln();
    }
  }

  // Properties
  final fields = element.fields
      .where((f) => !f.isPrivate && !f.isStatic && !f.isSynthetic)
      .toList();

  final getters = element.accessors
      .where((a) => !a.isPrivate && !a.isStatic && a.isGetter && !a.isSynthetic)
      .toList();

  final propRows = [
    for (final f in fields)
      '| `${f.name}` | `${f.type.getDisplayString()}` | ${_oneLiner(_extractDoc(f.documentationComment))} |',
    for (final g in getters)
      if (!fields.any((f) => f.name == g.name))
        '| `${g.name}` | `${g.returnType.getDisplayString()}` | ${_oneLiner(_extractDoc(g.documentationComment))} |',
  ];

  if (propRows.isNotEmpty) {
    sb
      ..writeln('### Properties')
      ..writeln()
      ..writeln('| Name | Type | Description |')
      ..writeln('|---|---|---|');
    for (final row in propRows) {
      sb.writeln(row);
    }
    sb.writeln();
  }

  // Methods
  final methods = element.methods
      .where((m) => !m.isPrivate && !m.isStatic)
      .toList();

  if (methods.isNotEmpty) {
    sb
      ..writeln('### Methods')
      ..writeln()
      ..writeln('| Signature | Description |')
      ..writeln('|---|---|');
    for (final m in methods) {
      sb.writeln(
        '| `${_methodSig(m)}` | ${_oneLiner(_extractDoc(m.documentationComment))} |',
      );
    }
    sb.writeln();
  }

  sb
    ..writeln('---')
    ..writeln();
  return sb.toString();
}

String? _renderEnumSection(EnumElement element) {
  final doc = _extractDoc(element.documentationComment);

  final sb = StringBuffer()
    ..writeln('## ${element.displayName}')
    ..writeln();

  if (doc != null) {
    sb
      ..writeln(_splitDocExample(doc).prose)
      ..writeln();
  }

  final values = element.fields.where((f) => f.isEnumConstant).toList();
  if (values.isNotEmpty) {
    sb
      ..writeln('### Values')
      ..writeln()
      ..writeln('| Name | Description |')
      ..writeln('|---|---|');
    for (final v in values) {
      sb.writeln(
        '| `${v.name}` | ${_oneLiner(_extractDoc(v.documentationComment))} |',
      );
    }
    sb.writeln();
  }

  sb
    ..writeln('---')
    ..writeln();
  return sb.toString();
}

// ---------------------------------------------------------------------------
// Utilities
// ---------------------------------------------------------------------------

String? _extractDoc(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  final lines = raw.split('\n').map((l) {
    l = l.trim();
    if (l.startsWith('///')) return l.replaceFirst(RegExp(r'^///\s?'), '');
    if (l.startsWith('*')) return l.replaceFirst(RegExp(r'^\*\s?'), '');
    if (l == '/**' || l == '*/') return '';
    return l;
  });
  final result = lines.join('\n').trim();
  return result.isEmpty ? null : result;
}

({String prose, String? example}) _splitDocExample(String doc) {
  final start = doc.indexOf('```dart');
  if (start == -1) return (prose: doc.trim(), example: null);
  final end = doc.indexOf('```', start + 7);
  if (end == -1) return (prose: doc.trim(), example: null);
  final prose = (doc.substring(0, start) + doc.substring(end + 3)).trim();
  final example = doc.substring(start + 7, end).trim();
  return (prose: prose, example: example.isEmpty ? null : example);
}

String _oneLiner(String? doc) {
  if (doc == null) return '';
  return doc
      .split('\n\n')
      .first
      .trim()
      .replaceAll('\n', ' ')
      .replaceAll('|', '\\|')
      .replaceAll('[', '\\[')
      .replaceAll(']', '\\]');
}

String _methodSig(MethodElement m) {
  final params = m.parameters
      .map((param) {
        final type = param.type.getDisplayString();
        final name = param.name;
        if (param.isNamed) return '{$type $name}';
        if (param.isOptionalPositional) return '[$type $name]';
        return '$type $name';
      })
      .join(', ');
  return '${m.returnType.getDisplayString()} ${m.name}($params)';
}
