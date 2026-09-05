/// A scaffolded project, standing where `good create` would have left one.
///
/// # Why the two suites over a scaffolded project share this
///
/// Because they were checking two different projects. `scaffold_analyze_test`
/// wrote the templates beside a hand-written pubspec and analyzed them, and
/// nothing forced that pubspec to be the one `good create` produces - which is
/// the structural hole that let a scaffold ship a project that does not boot.
/// One builder, so the project a suite is asked about is the project a person
/// gets.
///
/// # What it does not do, and why that is not a shortcut
///
/// It runs neither `flutter create` nor `flutter pub get`. The generated files
/// import `package:flutter`, `package:flutter_test` and the engine package,
/// all of which this repository has already resolved under `packages/`, so the
/// project is handed the engine's own package config with its relative entries
/// made absolute and itself added. That is resolution, done by borrowing
/// rather than by fetching: the analyzer and `flutter test --no-pub` both read
/// exactly the same file `pub get` would have written.
library;

import 'dart:convert';
import 'dart:io';

import 'package:good_cli/src/generate/bundle.dart';
import 'package:good_cli/src/generate/run.dart';
import 'package:good_cli/src/generate/scaffold.dart';
import 'package:good_cli/src/verbosable.dart';
import 'package:test/test.dart';

import '_temp.dart';

/// The analysis options every scaffolded project here is read under, which is
/// the file `flutter create` writes and nothing else.
///
/// That one line is what brings in `depend_on_referenced_packages`, through
/// `package:lints/core.yaml`. The other lint these projects exist to catch,
/// `unnecessary_import`, needs no line: it is not a lint rule in this SDK -
/// naming it under `linter: rules:` is an `undefined_lint` warning - and the
/// analyzer reports it on its own, at info severity, whatever the options file
/// says.
const String scaffoldAnalysisOptions =
    'include: package:flutter_lints/flutter.yaml\n';

/// The repository root, found by walking up from wherever the suite was run.
Directory repoRoot() {
  var dir = Directory.current;
  for (var i = 0; i < 6; i++) {
    if (File('${dir.path}/mkdocs.yml').existsSync() &&
        Directory('${dir.path}/packages').existsSync()) {
      return dir;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  fail('run this suite from inside the repository');
}

/// `packages/<engine>`'s resolved package config, with every path absolute.
///
/// A relative `rootUri` is relative to the `.dart_tool` directory holding the
/// file, so it means nothing once the config is written somewhere else.
/// Resolving them here is what lets a project sit in a temp directory and
/// still see this repository's packages.
Map<String, Object?> absolutePackageConfig(Directory root, String engine) {
  final file = File(
    '${root.path}/packages/$engine/.dart_tool/package_config.json',
  );
  if (!file.existsSync()) {
    fail(
      'packages/$engine is not resolved - run `flutter pub get` there. These '
      'suites borrow its package config rather than resolving one of their '
      'own.',
    );
  }
  final base = file.parent.uri;
  final config = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
  return <String, Object?>{
    ...config,
    'packages': <Object?>[
      for (final entry in config['packages']! as List<Object?>)
        <String, Object?>{
          ...entry as Map<String, Object?>,
          'rootUri': base.resolve(entry['rootUri']! as String).toString(),
        },
    ],
  };
}

/// Nothing here reads what a generate run printed.
final VerboseOutput quietOutput = _NullOutput();

class _NullOutput implements VerboseOutput {
  @override
  void println(Object? object) {}
  @override
  void print(Object? object) {}
  @override
  void printf(String format, List<Object?> args) {}
}

/// One scaffolded project: the templates, the pubspec, and a package config
/// that resolves the engine out of this repository.
///
/// [generate] runs `good generate` into it, which is what writes the bundle
/// package and the project's own declaration collectors. It is a parameter and
/// not a default only because one case exists to say what generation is
/// responsible for - see `scaffold_analyze_test`.
Future<Directory> scaffoldProject({
  required String name,
  required GoodEngine engine,
  bool generate = true,
}) async {
  final root = repoRoot();
  final dir = testTempDir('good_scaffold');

  final files = scaffoldFiles(
    projectName: name,
    engine: engine,
    command: 'good create',
  );
  for (final entry in files.entries) {
    File('${dir.path}/${entry.key}')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(entry.value);
  }

  // `flutter create` writes the pubspec and `patchedPubspecLines` adds what
  // good needs to it. Both halves are here, in the shape they come out in: the
  // dependencies the lints read - an import the pubspec does not declare is a
  // `depend_on_referenced_packages` info - and the two asset lists, which are
  // what `good generate` reads to decide what to bundle.
  File('${dir.path}/pubspec.yaml').writeAsStringSync('''
name: $name

environment:
  sdk: ^3.13.0

dependencies:
  flutter:
    sdk: flutter
  ${engine.package}: $engineConstraint

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: any

flutter:
  assets:
    - assets/
    - assets/packed/

good:
  assets:
    - assets/
''');
  File(
    '${dir.path}/analysis_options.yaml',
  ).writeAsStringSync(scaffoldAnalysisOptions);

  writeResolution(dir, root, engine.package, name, <String, Directory>{
    name: dir,
  });

  if (generate) {
    await runGenerate(
      projectDir: dir,
      command: 'good generate',
      out: quietOutput,
      verbose: quietOutput,
      enginePackage: engine.package,
      // The project is resolved by the config written above, so there is
      // nothing for `flutter pub get` to establish and no network to reach for.
      pubGet: false,
    );
    // The bundle exists only once generation has written it, so it joins the
    // config afterwards. Without this, every import of
    // `package:<name>_bundle/good.dart` fails to resolve - which is the one
    // import `main.dart` needs to mount an asset pack.
    writeResolution(dir, root, engine.package, name, <String, Directory>{
      name: dir,
      defaultBundleName(name): resolveBundle(dir).directory,
    });
  }
  return dir;
}

/// Writes what a `pub get` in [dir] would have left behind.
///
/// Two files, because Flutter reads two. `package_config.json` is what the
/// analyzer and the VM resolve imports through; `package_graph.json` is what
/// `flutter test` reads, and a project without one is refused before any test
/// is compiled. Both are borrowed from `packages/<engine>` and widened by
/// [extra] - the project itself, and the bundle package once generation has
/// written it.
void writeResolution(
  Directory dir,
  Directory root,
  String engine,
  String project,
  Map<String, Directory> extra,
) {
  final config = absolutePackageConfig(root, engine);
  File('${dir.path}/.dart_tool/package_config.json')
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(
      jsonEncode(<String, Object?>{
        ...config,
        'packages': <Object?>[
          ...config['packages']! as List<Object?>,
          for (final entry in extra.entries)
            <String, Object?>{
              'name': entry.key,
              'rootUri': entry.value.uri.toString(),
              'packageUri': 'lib/',
              'languageVersion': '3.13',
            },
        ],
      }),
    );

  final graphFile = File(
    '${root.path}/packages/$engine/.dart_tool/package_graph.json',
  );
  if (!graphFile.existsSync()) {
    fail(
      'packages/$engine has no package_graph.json - run `flutter pub get` '
      'there. `flutter test` refuses a project without one.',
    );
  }
  final graph = jsonDecode(graphFile.readAsStringSync()) as Map<String, Object?>;
  File('${dir.path}/.dart_tool/package_graph.json')
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(
      jsonEncode(<String, Object?>{
        ...graph,
        'roots': <String>[project],
        'packages': <Object?>[
          ...graph['packages']! as List<Object?>,
          for (final entry in extra.entries)
            <String, Object?>{
              'name': entry.key,
              'version': '0.0.0',
              'dependencies': <String>[
                'flutter',
                engine,
                for (final other in extra.keys)
                  if (other != entry.key) other,
              ],
              if (entry.key == project)
                'devDependencies': <String>['flutter_test', 'flutter_lints'],
            },
        ],
      }),
    );
}
