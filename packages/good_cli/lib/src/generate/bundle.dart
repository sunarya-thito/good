/// The generated sibling package, and the proof that it is good's to write to.
///
/// A project has two directories of Dart: `lib/`, which is the person's, and
/// one package beside it that the tooling wrote end to end. Splitting by
/// **author** rather than by file type is what gives "may this be overwritten"
/// a single answer - `lib/good.generated/` used to sit inside the one
/// directory a user is most likely to treat as entirely theirs, and nothing in
/// it proved it had been generated rather than typed.
///
/// Two things have to be answerable at any moment, and neither is answerable
/// from the project's name alone:
///
///  * **which package is the bundle** - recorded in the pubspec's `good:`
///    section, so renaming the project is a non-event rather than something
///    that leaves a second, still-resolving bundle on disk;
///  * **is that directory ours** - answered by [bundleMarkerName], which is
///    written into the package and checked before anything is written or
///    deleted. Absent, every command refuses and names the path.
library;

import 'dart:convert';
import 'dart:io';

import 'package:good_cli/src/config.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// The file that says a directory is a generated bundle package.
///
/// Checked before any write and before any delete. It is the whole of the
/// ownership claim, which is why it is one file with an unmistakable name
/// rather than something inferred from the contents: a package that happens to
/// hold a `textures.dart` is not thereby good's to empty.
const String bundleMarkerName = '.good_bundle';

/// The bundle package's name for a project called [projectName].
///
/// Derived **only** at first create, then recorded. Deriving it on every run
/// is the failure #113 exists to prevent: `my_game` renamed to `cool_game`
/// leaves `my_game_bundle` on disk and in `dependencies:`, and the next
/// generate builds `cool_game_bundle` beside it. Two bundles, one dead, and
/// nothing saying which.
String defaultBundleName(String projectName) => '${projectName}_bundle';

/// Which package [projectDir] calls its bundle, reading and writing nothing.
///
/// The recorded name when there is one, and the derived name only for a
/// project that has never had a bundle generated. Separate from
/// [resolveBundle] because two callers want the name without the ownership
/// question: a dry run reports what would be written, and neither of them
/// should refuse.
///
/// Throws when the pubspec is missing or records something that is not a
/// package name, which are conditions no caller can proceed past.
String bundleNameFor(Directory projectDir) =>
    GoodConfig.read(projectDir).bundle ??
    defaultBundleName(projectNameOf(projectDir));

/// A project's bundle package: the name that is recorded and the directory it
/// names.
@immutable
class BundlePackage {
  const BundlePackage({required this.name, required this.directory});

  /// The package name, and therefore what `package:` imports of the generated
  /// code spell.
  final String name;

  /// The directory, directly under the project root.
  final Directory directory;

  /// Where the generated Dart goes - what `lib/good.generated/` used to be.
  Directory get libDir => Directory(p.join(directory.path, 'lib'));

  File get pubspec => File(p.join(directory.path, 'pubspec.yaml'));

  File get marker => File(p.join(directory.path, bundleMarkerName));

  /// The per-project keys and the pack manifest. Written once and then edited
  /// in place by `good assets pack`, never rewritten - see
  /// `emitAssetKeys`.
  File get assetKeyFile => File(p.join(libDir.path, 'asset_key.dart'));

  bool get exists => directory.existsSync();

  bool get isMarked => marker.existsSync();
}

/// The project's own package name, from its pubspec.
///
/// Throws rather than guessing from the directory name: everything below keys
/// off this, and a bundle named after a directory that was renamed while the
/// pubspec was not is exactly the mess being avoided.
String projectNameOf(Directory projectDir) {
  final file = File(p.join(projectDir.path, 'pubspec.yaml'));
  if (!file.existsSync()) {
    throw ArgumentError(
      'No pubspec.yaml in ${projectDir.path} - good reads the project name '
      'and the bundle package name from it.',
    );
  }
  final doc = loadYaml(file.readAsStringSync());
  final name = doc is YamlMap ? doc['name'] : null;
  if (name is! String || name.isEmpty) {
    throw ArgumentError(
      '${file.path} declares no `name:`. That is the project name every '
      'generated package and import is built from.',
    );
  }
  return name;
}

/// Whether [packageRoot] is a package good generated.
///
/// The marker and nothing else, so the answer holds for a directory this
/// project did not write: a bundle belonging to another project, reached
/// through a `path:` dependency, is generated code by the same test. `null`
/// is a package with no directory to look in - one the package config does not
/// resolve - and the answer for it is no.
///
/// Every caller that asks "is this good's" goes through here, including
/// [markedBundles] and `enginePackageOf`.
bool isGeneratedBundle(Directory? packageRoot) =>
    packageRoot != null &&
    File(p.join(packageRoot.path, bundleMarkerName)).existsSync();

/// Every directory directly under the project that carries the marker.
///
/// Immediate children only. A marker further down is not a bundle package this
/// tool would ever have written, and walking the whole tree would find one
/// inside `build/` on a machine that has built once.
List<Directory> markedBundles(Directory projectDir) {
  if (!projectDir.existsSync()) return const <Directory>[];
  final found = <Directory>[];
  for (final entity in projectDir.listSync()) {
    if (entity is! Directory) continue;
    if (isGeneratedBundle(entity)) found.add(entity);
  }
  found.sort((a, b) => a.path.compareTo(b.path));
  return found;
}

/// Which package is the bundle, having proved the directory is good's.
///
/// Throws `ArgumentError` - exit code 65, and the message is what the person
/// has to act on - rather than doing anything destructive on a guess. The four
/// refusals, in the order a project meets them:
///
///  * **two marked directories.** However it arose - a hand rename, a copied
///    project, an interrupted migration - both resolve, both would eventually
///    declare assets, and the build would say nothing about which one won.
///  * **one marked directory that is not the recorded name.** The recorded
///    name is the source of truth; a directory disagreeing with it is a
///    question only the person can answer, because the generated code is
///    imported as `package:<name>/...` and moving it renames every one of
///    those imports in code good did not write.
///  * **a directory at the recorded path with no marker.** Somebody's package
///    is sitting there. Emptying it is the thing the marker exists to stop.
///  * **a `dependencies:` entry of that name pointing somewhere else.** Merging
///    into it would silently repoint a real dependency at generated code.
///
/// Renaming automatically is deliberately not done. It was the shape #113
/// asked for, before generated *Dart* moved into the package; now that
/// `package:<bundle>/textures.dart` appears in the project's own source, a
/// rename good performs on its own breaks every one of those imports at a
/// moment the person did not ask for anything to move.
BundlePackage resolveBundle(Directory projectDir) {
  final recorded = GoodConfig.read(projectDir).bundle;
  final name = bundleNameFor(projectDir);
  final bundle = BundlePackage(
    name: name,
    directory: Directory(p.join(projectDir.path, name)),
  );

  final marked = markedBundles(projectDir);
  if (marked.length > 1) {
    throw ArgumentError(
      'More than one generated bundle package under ${projectDir.path}: '
      '${marked.map((d) => p.basename(d.path)).join(', ')}. Exactly one may '
      'carry $bundleMarkerName. Delete the ones you do not want and set '
      '`good: bundle:` in pubspec.yaml to the one you keep.',
    );
  }
  if (marked.length == 1) {
    final found = p.basename(marked.single.path);
    if (found != name) {
      final source = recorded == null
          ? 'has no `good: bundle:` entry, so the name derived from the '
                'project is'
          : 'records';
      throw ArgumentError(
        'The generated bundle package under ${projectDir.path} is called '
        '"$found", and pubspec.yaml $source '
        '"$name". Nothing is written until they agree, because the generated '
        'code is imported as `package:<name>/...` and good moving it would '
        'break those imports in your own source.\n'
        'Either set `good: bundle: $found` in pubspec.yaml, or rename '
        '${marked.single.path} to $name and update the imports and the '
        '`dependencies:` entry that name it.',
      );
    }
  }
  if (bundle.exists && !bundle.isMarked) {
    throw ArgumentError(
      '${bundle.directory.path} exists and carries no $bundleMarkerName, so '
      'good cannot prove it wrote it. Nothing there is written or deleted.\n'
      'If it is good\'s, the marker was removed and adding an empty '
      '$bundleMarkerName file restores the claim. If it is yours, record a '
      'different name under `good: bundle:` in pubspec.yaml.',
    );
  }

  final declared = _dependencyEntry(projectDir, name);
  if (declared != null && !(declared is YamlMap && declared['path'] == name)) {
    throw ArgumentError(
      'pubspec.yaml already depends on "$name", and not on the generated '
      'package at ./$name. good will not repoint a dependency somebody else '
      'declared. Record a different bundle name under `good: bundle:`.',
    );
  }
  return bundle;
}

Object? _dependencyEntry(Directory projectDir, String name) {
  final file = File(p.join(projectDir.path, 'pubspec.yaml'));
  if (!file.existsSync()) return null;
  final doc = loadYaml(file.readAsStringSync());
  final deps = doc is YamlMap ? doc['dependencies'] : null;
  if (deps is! YamlMap) return null;
  return deps[name];
}

/// The marker's contents.
///
/// Rewritten on every run like everything else in the package, so the names in
/// it follow a rename rather than going stale. Nothing gates on what is in
/// here - the *presence* of the file is the claim - but a person who opens it
/// should be told what the directory is and what happens if they delete it.
String bundleMarkerContents({
  required String bundleName,
  required String projectName,
  required String command,
}) =>
    '''
# This package is generated. `$command` writes every file in it, and
# rewrites them in place on each run.
#
# This file is what says the directory is good's to write to. Without it every
# good command refuses to touch anything here, which is what stops a routine
# regeneration from emptying a package somebody wrote by hand.
bundle: $bundleName
project: $projectName
''';

/// The bundle package's pubspec - every line of it generated.
///
/// Each engine dependency is copied from the **project's**, rather than being
/// a constant here. A project pinned to one version would otherwise get a
/// bundle asking for another, and the two halves of one game's generated code
/// would resolve against different engines. A relative path dependency is
/// re-based by one directory, which is the difference between the project root
/// and this package sitting inside it.
///
/// [dependencies] maps a package name to the text that follows its key, as
/// [engineDependencyFor] writes it. It holds the project's entry package and
/// every package the generated files import - which are not the same set: the
/// entry package can be one that re-exports nothing, and the imports are then
/// the kernel and the renderer directly (#316). Written in sorted order, so
/// two runs over one project produce the same file.
String emitBundlePubspec({
  required String bundleName,
  required String projectName,
  required Map<String, String> dependencies,
  required String sdkConstraint,
  required String command,
}) =>
    '''
# GENERATED - do not edit.
#
# `$command` writes this file end to end and rewrites it on every run.
#
# This package holds everything good generates for $projectName: the asset
# bindings, the per-project keys, and the readiness check. The project's own
# lib/ beside it is yours, entirely.
name: $bundleName
description: The generated package for $projectName. Rewritten on every run.
publish_to: "none"
version: 0.0.0

environment:
  sdk: "$sdkConstraint"

dependencies:
  flutter:
    sdk: flutter
${_dependencyLines(dependencies)}''';

/// [dependencies] as pubspec lines, sorted by name, each ending in a newline.
String _dependencyLines(Map<String, String> dependencies) {
  final names = dependencies.keys.toList()..sort();
  return names.map((name) => '  $name:${dependencies[name]}\n').join();
}

/// How the bundle's pubspec should spell its dependency on [enginePackage],
/// given what the project's own pubspec says.
///
/// Returns the text that follows `  <package>:`, newline included when the
/// value is a nested map.
///
/// A `path:` that is relative is re-based: the project resolves `../goo2d`
/// from its own root, and the bundle sits one directory further in. An
/// absolute path, a git dependency or a hosted one is copied verbatim, because
/// none of those means anything different from inside a subdirectory.
String engineDependencyFor(Directory projectDir, String enginePackage) {
  final value = _dependencyEntry(projectDir, enginePackage);
  if (value is String) return ' $value';
  if (value is YamlMap) {
    final path = value['path'];
    if (value.length == 1 && path is String) {
      final rebased = p.isAbsolute(path) ? path : '../$path';
      return '\n    path: "$rebased"';
    }
    final buffer = StringBuffer();
    for (final key in value.keys) {
      buffer.write('\n    $key: ${_scalar(value[key])}');
    }
    return buffer.toString();
  }
  // The project declares no engine dependency at all. `enginePackageOf` falls
  // back to the kernel in that case, and so does this - a bundle that names a
  // package nothing resolves would fail `pub get` for the whole project.
  return ' any';
}

String _scalar(Object? value) {
  if (value is YamlMap) {
    final buffer = StringBuffer();
    for (final key in value.keys) {
      buffer.write('\n      $key: ${_scalar(value[key])}');
    }
    return buffer.toString();
  }
  if (value is String) return '"$value"';
  return '$value';
}

/// The project's Dart SDK constraint, so the generated package never demands a
/// newer SDK than the project it lives inside.
String sdkConstraintOf(Directory projectDir) {
  final file = File(p.join(projectDir.path, 'pubspec.yaml'));
  if (file.existsSync()) {
    final doc = loadYaml(file.readAsStringSync());
    final environment = doc is YamlMap ? doc['environment'] : null;
    final sdk = environment is YamlMap ? environment['sdk'] : null;
    if (sdk is String && sdk.isNotEmpty) return sdk;
  }
  return '^3.13.0';
}

/// [lines] with the bundle dependency and the recorded name added, or null if
/// the pubspec is not a shape this can edit safely.
///
/// Null and not a best guess, exactly as `patchedPubspecLines` does it: the
/// caller prints what to add instead, and a wrong edit to somebody's pubspec is
/// worse than an instruction to make the right one by hand.
///
/// Textual rather than a YAML round-trip, so the comments `flutter create`
/// wrote survive. What makes that safe is the last step: the result is
/// **parsed again** and both values read back out of the document before it is
/// returned. A patch that produced a pubspec saying something other than what
/// was intended never reaches the caller, which matters more here than for the
/// engine dependency - `good:` is a whole section, and appending one at the
/// wrong indentation would nest it inside whatever came last.
List<String>? patchedBundlePubspecLines(List<String> lines, String bundleName) {
  final YamlNode doc;
  try {
    doc = loadYamlNode(lines.join('\n'));
  } on YamlException {
    return null;
  }
  if (doc is! YamlMap) return null;

  final dependencies = doc['dependencies'];
  final hasDependency =
      dependencies is YamlMap && dependencies.containsKey(bundleName);
  final good = doc['good'];
  final hasRecord = good is YamlMap && good['bundle'] is String;
  if (hasDependency && hasRecord) return lines;

  final patched = List<String>.of(lines);
  if (!hasRecord) {
    // A `good:` key with nothing under it parses as null and is still a
    // section to add to; no key at all means appending one at column 0, which
    // ends any block above it whatever that block was.
    if (doc.containsKey('good')) {
      final index = patched.indexWhere((line) => line.trimRight() == 'good:');
      if (index < 0) return null;
      patched.insert(index + 1, '  bundle: $bundleName');
    } else {
      if (patched.isNotEmpty && patched.last.trim().isNotEmpty) patched.add('');
      patched.addAll(<String>[
        '# Which package holds what good generates. Recorded rather than',
        '# derived from the project name: renaming the project would otherwise',
        '# leave the old bundle on disk and still in dependencies, and build a',
        '# second one beside it.',
        'good:',
        '  bundle: $bundleName',
      ]);
    }
  }
  if (!hasDependency) {
    final deps = patched.indexWhere(
      (line) => line.trimRight() == 'dependencies:',
    );
    if (deps >= 0) {
      patched.insertAll(deps + 1, <String>[
        '  $bundleName:',
        '    path: $bundleName',
      ]);
    } else if (dependencies == null) {
      // No `dependencies:` at all, which a package with none legitimately has.
      // Appended whole, at column 0, for the same reason the `good:` section
      // above is: a top-level key ends whatever block precedes it, whatever
      // that block was.
      if (patched.isNotEmpty && patched.last.trim().isNotEmpty) patched.add('');
      patched.addAll(<String>[
        'dependencies:',
        '  $bundleName:',
        '    path: $bundleName',
      ]);
    } else {
      // A `dependencies:` the document has and the text does not - flow style,
      // or an anchor. Editing that blind is what this refuses to do.
      return null;
    }
  }

  // Read back what was just written, from the document and not from the text.
  final YamlNode check;
  try {
    check = loadYamlNode(patched.join('\n'));
  } on YamlException {
    return null;
  }
  if (check is! YamlMap) return null;
  final checkedDeps = check['dependencies'];
  if (checkedDeps is! YamlMap) return null;
  final entry = checkedDeps[bundleName];
  if (entry is! YamlMap || entry['path'] != bundleName) return null;
  final checkedGood = check['good'];
  if (checkedGood is! YamlMap || checkedGood['bundle'] != bundleName) {
    return null;
  }
  return patched;
}

/// What to add by hand when [patchedBundlePubspecLines] will not edit.
String bundlePubspecPatch(String bundleName) =>
    '''
dependencies:
  $bundleName:
    path: $bundleName

good:
  bundle: $bundleName
''';

/// The directory generated Dart used to live in, inside the project's own
/// `lib/`.
///
/// Kept as a constant because two very different things need it: the migration
/// that empties it, and the import rewrite that has to recognise a reference to
/// it in somebody's source.
const String legacyGeneratedDir = 'lib/good.generated';

/// The four files `good generate` has always written, by the name they keep in
/// the bundle package.
const List<String> generatedFileNames = <String>[
  'asset_key.dart',
  'audios.dart',
  'good.dart',
  'textures.dart',
];

/// What moving a project onto the bundle package did.
@immutable
class BundleMigration {
  const BundleMigration({
    required this.moved,
    required this.rewritten,
    required this.leftBehind,
  });

  /// Generated files carried over from `lib/good.generated/`.
  final List<String> moved;

  /// Project-relative paths of source files whose imports were repointed.
  final List<String> rewritten;

  /// Anything in `lib/good.generated/` that good did not write and therefore
  /// did not delete.
  final List<String> leftBehind;

  bool get isEmpty => moved.isEmpty && rewritten.isEmpty && leftBehind.isEmpty;
}

/// The first line every file good generates carries.
const String _generatedHeader = '// GENERATED - do not edit.';

/// `lib/good.generated/asset_key.dart`, if a project still has one.
///
/// Read **before** anything is written, because it decides whether the run
/// mints keys or keeps the ones already there. Regenerating them instead would
/// rotate a project's asset keys as a side effect of an unrelated upgrade, and
/// orphan every pack ever built with them - the one thing `--rotate-keys`
/// exists to make deliberate.
File? legacyAssetKeyFile(Directory projectDir) {
  final file = File(
    p.join(projectDir.path, legacyGeneratedDir, 'asset_key.dart'),
  );
  return file.existsSync() ? file : null;
}

/// Empties `lib/good.generated/` and repoints the imports that named it.
///
/// Deletes **strictly by plan** - one of the four names good writes, and only
/// while the file still carries the generated header - which is the rule
/// `stripLoose` already follows for the asset directory. A file somebody added
/// there is reported and left where it is, and the directory only goes away
/// once nothing is in it.
///
/// The imports are rewritten rather than merely reported. Moving generated code
/// out of `lib/` renames every import of it, and the alternative is a project
/// that does not compile after running the command that was supposed to bring
/// it up to date. The edit is confined to `import`/`export` directives naming a
/// path good itself wrote, and every file changed is named in the output.
BundleMigration migrateLegacyGenerated({
  required Directory projectDir,
  required BundlePackage bundle,
}) {
  final legacy = Directory(p.join(projectDir.path, legacyGeneratedDir));
  // Nothing to migrate is the ordinary case, and it costs nothing to answer.
  // The import rewrite reads every Dart file under four directories and can
  // write to any of them; running it on a project that has already moved would
  // be good reaching into somebody's source on every single run for no reason.
  if (!legacy.existsSync()) {
    return const BundleMigration(
      moved: <String>[],
      rewritten: <String>[],
      leftBehind: <String>[],
    );
  }

  final moved = <String>[];
  final leftBehind = <String>[];
  for (final entity in legacy.listSync()) {
    final name = p.basename(entity.path);
    if (entity is! File ||
        !generatedFileNames.contains(name) ||
        !entity.readAsStringSync().startsWith(_generatedHeader)) {
      leftBehind.add('$legacyGeneratedDir/$name');
      continue;
    }
    entity.deleteSync();
    moved.add(name);
  }
  if (legacy.listSync().isEmpty) legacy.deleteSync();
  return BundleMigration(
    moved: moved..sort(),
    rewritten: _rewriteGeneratedImports(projectDir, bundle),
    leftBehind: leftBehind..sort(),
  );
}

/// Every `import`/`export` of `good.generated/<file>` becomes the same file in
/// the bundle package.
///
/// Matches the directory name rather than a package name, so it covers all
/// three spellings a project can have used: a relative path from anywhere under
/// `lib/`, `package:<project>/good.generated/...`, and the `../../` form the
/// scaffold's own nesting produces.
List<String> _rewriteGeneratedImports(
  Directory projectDir,
  BundlePackage bundle,
) {
  final pattern = RegExp(
    r'''^(\s*(?:import|export)\s+)(['"])[^'"]*good\.generated/'''
    r'''([A-Za-z0-9_]+\.dart)\2''',
  );
  final rewritten = <String>[];
  for (final name in const <String>['lib', 'test', 'bin', 'tool']) {
    final dir = Directory(p.join(projectDir.path, name));
    if (!dir.existsSync()) continue;
    for (final file in dir.listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.dart')) continue;
      final lines = file.readAsLinesSync();
      var changed = false;
      for (var i = 0; i < lines.length; i++) {
        final match = pattern.firstMatch(lines[i]);
        if (match == null) continue;
        lines[i] = lines[i].replaceRange(
          match.start,
          match.end,
          "${match.group(1)}'package:${bundle.name}/${match.group(3)}'",
        );
        changed = true;
      }
      if (!changed) continue;
      file.writeAsStringSync('${lines.join('\n')}\n');
      rewritten.add(
        p.relative(file.path, from: projectDir.path).replaceAll(r'\', '/'),
      );
    }
  }
  return rewritten..sort();
}

/// Whether the project's resolved package config already points at the bundle.
///
/// This is the question a build silently gets wrong. Flutter's staleness gate
/// is pure mtime and never compares content, and `pub get` legitimately leaves
/// `package_config.json` newer than `pubspec.yaml` - so a project whose bundle
/// was never resolved, or was resolved and then had its directory removed,
/// builds green and ships nothing from it. Asking the resolved config directly
/// is the only answer that does not depend on a timestamp.
bool bundleIsResolved(Directory projectDir, BundlePackage bundle) {
  final file = File(
    p.join(projectDir.path, '.dart_tool', 'package_config.json'),
  );
  if (!file.existsSync()) return false;
  final Object? doc;
  try {
    doc = jsonDecode(file.readAsStringSync());
  } on FormatException {
    return false;
  }
  if (doc is! Map<String, Object?>) return false;
  final packages = doc['packages'];
  if (packages is! List<Object?>) return false;
  for (final entry in packages) {
    if (entry is! Map<String, Object?>) continue;
    if (entry['name'] != bundle.name) continue;
    final rootUri = entry['rootUri'];
    if (rootUri is! String) return false;
    final resolved = file.parent.uri.resolve(
      rootUri.endsWith('/') ? rootUri : '$rootUri/',
    );
    if (!resolved.isScheme('file')) return false;
    return p.canonicalize(resolved.toFilePath()) ==
        p.canonicalize(bundle.directory.path);
  }
  return false;
}

/// Runs `flutter pub get` in [projectDir]. Returns null on success, or what
/// went wrong.
///
/// `flutter`, not `dart`. `dart pub get` resolves a path dependency perfectly
/// well but does not write `.dart_tool/version`, so the next Flutter command
/// re-resolves anyway - which turns a step taken to make the build
/// deterministic into one that does nothing.
String? runFlutterPubGet(Directory projectDir) {
  final ProcessResult result;
  try {
    result = Process.runSync('flutter', <String>[
      'pub',
      'get',
    ], workingDirectory: projectDir.path, runInShell: true);
  } on ProcessException catch (error) {
    return 'Could not run `flutter pub get` in ${projectDir.path}: '
        '${error.message}';
  }
  if (result.exitCode == 0) return null;
  return 'flutter pub get failed in ${projectDir.path}:\n'
      '${result.stdout}${result.stderr}';
}

/// Everything wrong with what was just written, as messages, or empty.
///
/// The generator checks its own output because this layout's one weakness is
/// that its failure mode is silence: an empty generated package, an absent one
/// and a malformed generated pubspec all build green, and a missing asset
/// directory makes `flutter build` print an error and then exit 0 anyway. The
/// first symptom is otherwise a `FlutterError` at load time, a long way from
/// the build that caused it and looking like a runtime bug.
///
/// [checkResolution] is what `--no-pub-get` turns off, and only that. The
/// files, the marker and the two pubspecs are asserted either way, because
/// those are this command's own output rather than pub's.
/// [importedPackages] is every package the generated files name a type
/// through, from `generatedImports`. All of them, and not the entry package
/// alone: the entry package is whatever the dependency graph resolves and it
/// need not re-export anything, so it is the imports that have to be declared
/// (#316).
List<String> bundleProblems({
  required Directory projectDir,
  required BundlePackage bundle,
  required Iterable<String> importedPackages,
  required Iterable<String> writtenFiles,
  required bool checkResolution,
}) {
  final problems = <String>[];
  if (!bundle.exists) {
    problems.add('${bundle.directory.path} was not created.');
    return problems;
  }
  if (!bundle.isMarked) {
    problems.add(
      '${bundle.marker.path} is missing, so the next run would refuse to '
      'write here.',
    );
  }
  for (final path in writtenFiles) {
    final file = File(path);
    if (!file.existsSync()) {
      problems.add('$path was not written.');
    } else if (file.lengthSync() == 0) {
      problems.add('$path is empty.');
    }
  }
  if (!bundle.pubspec.existsSync()) {
    problems.add('${bundle.pubspec.path} was not written.');
  } else {
    final Object? doc;
    try {
      doc = loadYaml(bundle.pubspec.readAsStringSync());
    } on YamlException catch (error) {
      problems.add(
        '${bundle.pubspec.path} is not valid YAML: ${error.message}',
      );
      return problems;
    }
    final name = doc is YamlMap ? doc['name'] : null;
    if (name != bundle.name) {
      problems.add(
        '${bundle.pubspec.path} declares `name: $name`, and the project '
        'records `good: bundle: ${bundle.name}`.',
      );
    }
    // Every generated file imports one of these, so a bundle that does not
    // depend on them is a package that cannot be analysed and a project that
    // will not build - and one wrong indent in the emitter is all it takes,
    // because a dependency at column 0 is still valid YAML.
    final bundleDeps = doc is YamlMap ? doc['dependencies'] : null;
    for (final package in importedPackages) {
      if (bundleDeps is! YamlMap || !bundleDeps.containsKey(package)) {
        problems.add(
          '${bundle.pubspec.path} does not depend on $package, which '
          'something generated into it imports.',
        );
      }
    }
  }

  final projectPubspec = File(p.join(projectDir.path, 'pubspec.yaml'));
  final Object? project = projectPubspec.existsSync()
      ? loadYaml(projectPubspec.readAsStringSync())
      : null;
  final deps = project is YamlMap ? project['dependencies'] : null;
  final entry = deps is YamlMap ? deps[bundle.name] : null;
  if (entry is! YamlMap || entry['path'] != bundle.name) {
    problems.add(
      '${projectPubspec.path} does not depend on ${bundle.name} at '
      './${bundle.name}, so nothing generated into it would reach the build.',
    );
  }
  final good = project is YamlMap ? project['good'] : null;
  if (good is! YamlMap || good['bundle'] != bundle.name) {
    problems.add(
      '${projectPubspec.path} does not record `good: bundle: ${bundle.name}`, '
      'so the next run would not know which package is the bundle.',
    );
  }
  if (checkResolution && !bundleIsResolved(projectDir, bundle)) {
    problems.add(
      'The resolved package config does not point at ${bundle.directory.path}. '
      'A build would not fail - it would ship without the generated package.',
    );
  }
  return problems;
}
