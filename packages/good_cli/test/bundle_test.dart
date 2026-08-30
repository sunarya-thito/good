import 'dart:convert';
import 'dart:io';

import 'package:good_cli/src/commands/assets/pack.dart';
import 'package:good_cli/src/commands/build/windows.dart';
import 'package:good_cli/src/generate/bundle.dart';
import 'package:good_cli/src/generate/run.dart';
import 'package:good_cli/src/runner.dart';
import 'package:good_cli/src/verbosable.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

// The generated sibling package: who owns it, what proves it, and what happens
// to a project that still keeps its generated code in `lib/`.
//
// Every test here runs on a real temp directory. What is being checked is a
// decision about files - which ones may be written over, which ones must not
// be - and a fake filesystem would be a fake of exactly the thing in question.
//
// `pubGet: false` throughout. These projects are a pubspec and a few empty
// files, not something `flutter pub get` could resolve, and the resolve step
// has its own tests below that do not need a Flutter SDK.

const String _pubspec = '''
name: demo

environment:
  sdk: ^3.13.0

dependencies:
  goo2d: ^0.3.0-dev
  flutter:
    sdk: flutter

flutter:
  uses-material-design: true

  assets:
    - assets/
''';

Directory _project([String pubspec = _pubspec]) {
  final dir = Directory.systemTemp.createTempSync('good_bundle_test');
  addTearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });
  File('${dir.path}/pubspec.yaml').writeAsStringSync(pubspec);
  Directory('${dir.path}/assets').createSync();
  return dir;
}

GenerateResult _generate(Directory project, {bool rotateKeys = false}) =>
    runGenerate(
      projectDir: project,
      command: 'good generate',
      out: _quiet,
      verbose: _quiet,
      pubGet: false,
      rotateKeys: rotateKeys,
    );

/// A project already on the retired layout.
void _legacyGenerated(Directory project, {String keys = _legacyKeys}) {
  const names = <String>['textures.dart', 'audios.dart', 'good.dart'];
  for (final name in names) {
    File('${project.path}/lib/good.generated/$name')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('// GENERATED - do not edit.\n// $name\n');
  }
  File('${project.path}/lib/good.generated/asset_key.dart')
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(keys);
}

const String _legacyKeys = '''
// GENERATED - do not edit.
final List<int> _assetKey = [0x01];
final Map<String, String> assetMapping = <String, String>{
  'assets/player.png': 'assets/packed/chunk_0.dat',
};
''';

/// What was in the bundle directory each time the run said something.
///
/// The output is the one seam a caller has inside `runGenerate`, and every
/// `Wrote %s` comes straight after the write it names - so a listing taken
/// here is the directory as it stood at that write. Nothing else can see the
/// order: the files are all there by the time the call returns, and a
/// timestamp on two writes a millisecond apart says nothing.
class _Watching implements VerboseOutput {
  _Watching(this.directory);

  final Directory directory;
  final List<Set<String>> snapshots = <Set<String>>[];

  void _look() {
    if (!directory.existsSync()) return;
    snapshots.add(<String>{
      for (final entity in directory.listSync(recursive: true))
        p.relative(entity.path, from: directory.path).replaceAll('\\', '/'),
    });
  }

  @override
  void println(Object? object) => _look();
  @override
  void print(Object? object) => _look();
  @override
  void printf(String format, List<Object?> args) => _look();
}

/// A run that dies the moment it says it has written something in the bundle.
///
/// A closed terminal, a full disk, a killed process - what they have in common
/// is that they land between two of these writes, and what the directory looks
/// like afterwards is the whole of what the next run has to go on. The throw
/// keys off the path being inside the bundle, not off the wording, so it fires
/// at the first write there and at nothing said before it.
class _Interrupt implements VerboseOutput {
  _Interrupt(this.directory);

  final Directory directory;

  @override
  void println(Object? object) {}
  @override
  void print(Object? object) {}
  @override
  void printf(String format, List<Object?> args) {
    if (args.isEmpty) return;
    if (p.isWithin(directory.path, '${args.first}')) throw const _Died();
  }
}

class _Died implements Exception {
  const _Died();
}

final VerboseOutput _quiet = _NullOutput();

class _NullOutput implements VerboseOutput {
  @override
  void println(Object? object) {}
  @override
  void print(Object? object) {}
  @override
  void printf(String format, List<Object?> args) {}
}

Matcher _refusesWith(Object? matcher) => throwsA(
  isA<ArgumentError>().having((e) => '${e.message}', 'message', matcher),
);

void main() {
  group('which package is the bundle', () {
    test('derives it from the project name once, then records it', () {
      final project = _project();
      final result = _generate(project);

      expect(result.bundle.name, 'demo_bundle');
      expect(
        File('${project.path}/pubspec.yaml').readAsStringSync(),
        contains('bundle: demo_bundle'),
        reason:
            'recorded rather than recomputed - a project renamed after this '
            'point has to keep pointing at the directory that already exists',
      );
    });

    test('a renamed project keeps the bundle it already has', () {
      final project = _project();
      _generate(project);

      // Exactly the rename #113 is about: the project is called something
      // else now, and the recorded name is untouched.
      final pubspec = File('${project.path}/pubspec.yaml');
      pubspec.writeAsStringSync(
        pubspec.readAsStringSync().replaceFirst('name: demo', 'name: cool'),
      );

      expect(_generate(project).bundle.name, 'demo_bundle');
      expect(
        Directory('${project.path}/cool_bundle').existsSync(),
        isFalse,
        reason:
            'a second bundle beside the first is the failure this exists to '
            'prevent: both resolve, both would declare assets, and nothing '
            'says which one answered',
      );
    });

    test('refuses a package sitting at the bundle path without the marker', () {
      final project = _project();
      File('${project.path}/demo_bundle/pubspec.yaml')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('name: demo_bundle\n');
      File('${project.path}/demo_bundle/lib/mine.dart')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('// mine');

      expect(
        () => _generate(project),
        _refusesWith(
          allOf(contains('demo_bundle'), contains(bundleMarkerName)),
        ),
      );
      expect(
        File('${project.path}/demo_bundle/lib/mine.dart').readAsStringSync(),
        '// mine',
        reason: 'refusing means writing nothing and deleting nothing',
      );
    });

    test('refuses when two directories carry the marker', () {
      final project = _project();
      _generate(project);
      // A copied project, an interrupted rename - however it happened, both
      // would resolve.
      File('${project.path}/old_bundle/$bundleMarkerName')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('bundle: old_bundle\n');

      expect(
        () => _generate(project),
        _refusesWith(
          allOf(contains('demo_bundle'), contains('old_bundle')),
        ),
      );
    });

    test('refuses a marked directory that is not the recorded name', () {
      final project = _project();
      _generate(project);
      Directory(
        '${project.path}/demo_bundle',
      ).renameSync('${project.path}/renamed_bundle');

      expect(
        () => _generate(project),
        _refusesWith(
          allOf(contains('renamed_bundle'), contains('demo_bundle')),
        ),
      );
      expect(
        Directory('${project.path}/demo_bundle').existsSync(),
        isFalse,
        reason:
            'it stops rather than generating a fresh one beside the renamed '
            'directory, and rather than renaming on its own - the generated '
            "code is imported by name, so moving it edits the user's source",
      );
    });

    test('refuses a dependency of that name pointing somewhere else', () {
      final project = _project(
        _pubspec.replaceFirst(
          'dependencies:\n',
          'dependencies:\n  demo_bundle: ^1.0.0\n',
        ),
      );
      expect(
        () => _generate(project),
        _refusesWith(contains('demo_bundle')),
      );
    });

    test('refuses a recorded name that is not a package name', () {
      final project = _project('$_pubspec\ngood:\n  bundle: Demo Bundle\n');
      expect(() => _generate(project), _refusesWith(contains('package name')));
    });
  });

  group('what it writes', () {
    test('the four generated files, the marker and a generated pubspec', () {
      final project = _project();
      final bundle = _generate(project).bundle;

      for (final name in generatedFileNames) {
        expect(
          File('${bundle.libDir.path}/$name').existsSync(),
          isTrue,
          reason: '$name is missing from the bundle package',
        );
      }
      expect(bundle.isMarked, isTrue);
      expect(
        bundle.pubspec.readAsStringSync(),
        allOf(contains('name: demo_bundle'), contains('GENERATED')),
      );
      expect(
        Directory('${project.path}/lib/good.generated').existsSync(),
        isFalse,
        reason: 'lib/ is the project\'s, entirely',
      );
    });

    test('the engine dependency is indented into the dependencies map', () {
      // A dependency emitted at column 0 is still valid YAML and still parses
      // - as a *top-level* key, so the bundle depends on nothing and every
      // generated file fails to resolve. The emitter got this wrong once.
      final project = _project();
      final bundle = _generate(project).bundle;
      expect(
        bundleProblems(
          projectDir: project,
          bundle: bundle,
          enginePackage: 'goo2d',
          writtenFiles: const <String>[],
          checkResolution: false,
        ),
        isNot(contains(contains('does not depend on goo2d'))),
      );
    });

    test('the bundle depends on the engine the project depends on', () {
      final project = _project(
        _pubspec.replaceFirst('goo2d: ^0.3.0-dev', 'goo2d: 0.2.0'),
      );
      expect(
        _generate(project).bundle.pubspec.readAsStringSync(),
        contains('goo2d: 0.2.0'),
        reason:
            'a bundle asking for a different version than the project resolves '
            'one game\'s generated code against two engines',
      );
    });

    test('a relative path dependency is re-based by one directory', () {
      final project = _project(
        _pubspec.replaceFirst(
          '  goo2d: ^0.3.0-dev\n',
          '  goo2d:\n    path: ../goo2d\n',
        ),
      );
      expect(
        _generate(project).bundle.pubspec.readAsStringSync(),
        contains('path: "../../goo2d"'),
        reason: 'the bundle sits one directory further in than the project',
      );
    });

    test('the generated code imports through the bundle package', () {
      final project = _project();
      final bundle = _generate(project).bundle;
      expect(
        File('${bundle.libDir.path}/good.dart').readAsStringSync(),
        allOf(
          contains("import 'textures.dart'"),
          contains("import 'audios.dart'"),
        ),
        reason:
            'they are siblings inside one package now, so the readiness check '
            'reaches them relatively and nothing outside has to know',
      );
    });
  });

  group('regeneration rewrites in place', () {
    test('a second run leaves the directory and its extra files alone', () {
      final project = _project();
      final bundle = _generate(project).bundle;
      final stray = File('${bundle.directory.path}/notes.txt')
        ..writeAsStringSync('still here');

      _generate(project);

      expect(
        stray.existsSync(),
        isTrue,
        reason:
            'clearing and refilling would break every `package:demo_bundle/` '
            'import for as long as the directory was empty, and would lose '
            'anything the next write did not put back',
      );
    });

    test('the keys survive a regeneration', () {
      final project = _project();
      final bundle = _generate(project).bundle;
      final keys = bundle.assetKeyFile.readAsStringSync();

      _generate(project);

      expect(
        bundle.assetKeyFile.readAsStringSync(),
        keys,
        reason: 'rewriting them orphans every pack already built',
      );
    });

    test('--rotate-keys is what replaces them', () {
      final project = _project();
      final bundle = _generate(project).bundle;
      final keys = bundle.assetKeyFile.readAsStringSync();

      _generate(project, rotateKeys: true);

      expect(bundle.assetKeyFile.readAsStringSync(), isNot(keys));
    });
  });

  group('migrating off lib/good.generated/', () {
    test('the generated files move and the directory goes away', () {
      final project = _project();
      _legacyGenerated(project);

      final bundle = _generate(project).bundle;

      expect(
        Directory('${project.path}/lib/good.generated').existsSync(),
        isFalse,
      );
      for (final name in generatedFileNames) {
        expect(File('${bundle.libDir.path}/$name').existsSync(), isTrue);
      }
    });

    test('the keys are carried over byte for byte, not minted again', () {
      final project = _project();
      _legacyGenerated(project);

      final bundle = _generate(project).bundle;

      expect(
        bundle.assetKeyFile.readAsStringSync(),
        _legacyKeys,
        reason:
            'minting new keys during a migration rotates a shipped game\'s '
            'asset keys as a side effect of an upgrade, and orphans every pack '
            'built with the old ones - the mapping in there goes with them',
      );
    });

    test('imports of the old directory are repointed, in every spelling', () {
      final project = _project();
      _legacyGenerated(project);
      File('${project.path}/lib/game/prefabs/player.dart')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(
          "import 'package:goo2d/goo2d.dart';\n"
          "import '../../good.generated/textures.dart';\n"
          "\nclass Player {}\n",
        );
      File('${project.path}/lib/boot.dart').writeAsStringSync(
        "import 'package:demo/good.generated/good.dart';\n",
      );
      File('${project.path}/test/probe_test.dart')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(
          "export 'package:demo/good.generated/audios.dart';\n",
        );

      _generate(project);

      expect(
        File('${project.path}/lib/game/prefabs/player.dart').readAsStringSync(),
        contains("import 'package:demo_bundle/textures.dart';"),
      );
      expect(
        File('${project.path}/lib/boot.dart').readAsStringSync(),
        "import 'package:demo_bundle/good.dart';\n",
      );
      expect(
        File('${project.path}/test/probe_test.dart').readAsStringSync(),
        "export 'package:demo_bundle/audios.dart';\n",
      );
    });

    test('an import that only mentions the name in a string is left alone', () {
      final project = _project();
      _legacyGenerated(project);
      final file = File('${project.path}/lib/note.dart')
        ..writeAsStringSync(
          "const String where = 'lib/good.generated/textures.dart';\n",
        );

      _generate(project);

      expect(
        file.readAsStringSync(),
        "const String where = 'lib/good.generated/textures.dart';\n",
        reason:
            'the rewrite is confined to import and export directives - it is '
            "an edit to somebody else's source and has to be exactly that",
      );
    });

    test('a file good did not write is left where it is', () {
      final project = _project();
      _legacyGenerated(project);
      final mine = File('${project.path}/lib/good.generated/mine.dart')
        ..writeAsStringSync('// mine');
      final edited = File('${project.path}/lib/good.generated/good.dart')
        ..writeAsStringSync('// I took the header off\n');

      _generate(project);

      expect(mine.readAsStringSync(), '// mine');
      expect(
        edited.readAsStringSync(),
        '// I took the header off\n',
        reason:
            'deleting strictly by plan means the plan is the four names *and* '
            'the header - the same rule stripLoose follows for assets',
      );
    });
  });

  group('recording the bundle in the pubspec', () {
    test('adds the dependency and the name, and says so in the document', () {
      final patched = patchedBundlePubspecLines(
        _pubspec.split('\n'),
        'demo_bundle',
      );
      expect(patched, isNotNull);
      final text = patched!.join('\n');
      expect(text, contains('  demo_bundle:\n    path: demo_bundle'));
      expect(text, contains('good:\n  bundle: demo_bundle'));
    });

    test('a second run changes nothing', () {
      final once = patchedBundlePubspecLines(
        _pubspec.split('\n'),
        'demo_bundle',
      )!;
      expect(
        patchedBundlePubspecLines(once, 'demo_bundle'),
        once,
        reason:
            'two `demo_bundle:` keys or two `good:` keys is not a bad merge, '
            'it is a pubspec every flutter command refuses to read at all',
      );
    });

    test('a project with no dependencies section gets one', () {
      final patched = patchedBundlePubspecLines(<String>[
        'name: demo',
        'environment:',
        '  sdk: ^3.13.0',
      ], 'demo_bundle');
      expect(patched, isNotNull);
      expect(patched!.join('\n'), contains('dependencies:'));
    });

    test('an existing good: section is added to rather than duplicated', () {
      final patched = patchedBundlePubspecLines(<String>[
        'name: demo',
        'dependencies:',
        '  goo2d: ^0.3.0-dev',
        'good:',
        '  assets:',
        '    source: art/',
      ], 'demo_bundle')!;
      expect(
        patched.where((line) => line.trimRight() == 'good:').length,
        1,
      );
      expect(patched.join('\n'), contains('  bundle: demo_bundle'));
    });

    test('a pubspec it cannot parse is left alone', () {
      expect(
        patchedBundlePubspecLines(<String>[
          'name: demo',
          'dependencies:',
          'dependencies:',
        ], 'demo_bundle'),
        isNull,
        reason:
            'already unparseable - editing it further is not something to do '
            'blind, and the caller prints what to add instead',
      );
    });
  });

  group('what the generator asserts about its own output', () {
    test('an emptied bundle is reported rather than passed over', () {
      final project = _project();
      final bundle = _generate(project).bundle;
      final textures = File('${bundle.libDir.path}/textures.dart')
        ..deleteSync();

      expect(
        bundleProblems(
          projectDir: project,
          bundle: bundle,
          enginePackage: 'goo2d',
          writtenFiles: <String>[textures.path],
          checkResolution: false,
        ),
        contains(contains('was not written')),
      );
    });

    test('a dependency that was never added is reported', () {
      final project = _project();
      final bundle = _generate(project).bundle;
      // What an unpatchable pubspec leaves behind: the package is written and
      // nothing depends on it, so its code is unreachable and no build says so.
      File('${project.path}/pubspec.yaml').writeAsStringSync(_pubspec);

      expect(
        bundleProblems(
          projectDir: project,
          bundle: bundle,
          enginePackage: 'goo2d',
          writtenFiles: const <String>[],
          checkResolution: false,
        ),
        allOf(
          contains(contains('does not depend on demo_bundle')),
          contains(contains('does not record')),
        ),
      );
    });

    test('an unresolved bundle is reported, and that is the silent one', () {
      final project = _project();
      final bundle = _generate(project).bundle;
      expect(
        bundleIsResolved(project, bundle),
        isFalse,
        reason: 'nothing has run pub get in this temp directory',
      );
      expect(
        bundleProblems(
          projectDir: project,
          bundle: bundle,
          enginePackage: 'goo2d',
          writtenFiles: const <String>[],
          checkResolution: true,
        ),
        contains(contains('resolved package config')),
      );
    });

    test('a package config naming the bundle is what resolved means', () {
      final project = _project();
      final bundle = _generate(project).bundle;
      File('${project.path}/.dart_tool/package_config.json')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(
          jsonEncode(<String, Object?>{
            'configVersion': 2,
            'packages': <Object?>[
              <String, Object?>{
                'name': 'demo_bundle',
                'rootUri': '../demo_bundle',
                'packageUri': 'lib/',
              },
            ],
          }),
        );
      expect(bundleIsResolved(project, bundle), isTrue);
    });

    test('a package config pointing somewhere else does not count', () {
      final project = _project();
      final bundle = _generate(project).bundle;
      File('${project.path}/.dart_tool/package_config.json')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(
          jsonEncode(<String, Object?>{
            'configVersion': 2,
            'packages': <Object?>[
              <String, Object?>{
                'name': 'demo_bundle',
                'rootUri': '../somewhere_else',
                'packageUri': 'lib/',
              },
            ],
          }),
        );
      expect(
        bundleIsResolved(project, bundle),
        isFalse,
        reason:
            'the entry existing is not the question - a stale one resolves and '
            'ships whatever is at the other end, or nothing',
      );
    });
  });

  group('the ownership check comes before the first write', () {
    test('the marker is in the directory before any file beside it', () {
      final project = _project();
      final watching = _Watching(Directory('${project.path}/demo_bundle'));

      runGenerate(
        projectDir: project,
        command: 'good generate',
        out: watching,
        verbose: watching,
        pubGet: false,
      );

      final whileWriting = watching.snapshots
          .where(
            (snapshot) => snapshot.any(
              (entry) => entry != bundleMarkerName && entry != 'lib',
            ),
          )
          .toList();
      expect(
        whileWriting,
        isNotEmpty,
        reason:
            'nothing was watched while the directory had anything in it, so '
            'this could not have failed however the marker was ordered',
      );
      for (final snapshot in whileWriting) {
        expect(
          snapshot,
          contains(bundleMarkerName),
          reason:
              'the claim has to cover the first file, not follow it - a marker '
              'written last is one the run never had while it was writing',
        );
      }
    });

    test('an interrupted run leaves a directory the next run finishes', () {
      final project = _project();
      final directory = Directory('${project.path}/demo_bundle');

      expect(
        () => runGenerate(
          projectDir: project,
          command: 'good generate',
          out: _Interrupt(directory),
          verbose: _quiet,
          pubGet: false,
        ),
        throwsA(isA<_Died>()),
      );

      expect(
        File('${directory.path}/$bundleMarkerName').existsSync(),
        isTrue,
        reason:
            'this is what the ordering buys: the half-written directory is '
            'still provably good\'s',
      );

      final bundle = _generate(project).bundle;
      for (final name in generatedFileNames) {
        expect(
          File('${bundle.libDir.path}/$name').existsSync(),
          isTrue,
          reason:
              'an unmarked half-written directory would be refused from here '
              'on, and the only way out of it is deleting a package by hand',
        );
      }
    });

    test('packing refuses before it makes the chunk directory', () async {
      final project = _project();
      File('${project.path}/assets/a.png').writeAsBytesSync(<int>[1, 2, 3]);
      Directory('${project.path}/demo_bundle').createSync();

      final runner = CommandRunner(PackCommand(), out: StringBuffer());
      await expectLater(
        runner.run(<String>['--project-dir=${project.path}']),
        _refusesWith(contains(bundleMarkerName)),
      );

      expect(
        Directory('${project.path}/assets/packed').existsSync(),
        isFalse,
        reason:
            'a refusal that has already made a directory in the project has '
            'changed the tree it declined to touch',
      );
    });

    test('good build refuses before it compacts anything', () async {
      final project = _project();
      File('${project.path}/assets_src/a.png')
        ..parent.createSync(recursive: true)
        ..writeAsBytesSync(<int>[1, 2, 3]);
      Directory('${project.path}/demo_bundle').createSync();

      final runner = CommandRunner(WindowsBuildCommand(), out: StringBuffer());
      await expectLater(
        runner.run(<String>[
          '--project-dir=${project.path}',
          '--no-download',
          '--no-pub-get',
        ]),
        _refusesWith(contains(bundleMarkerName)),
        reason:
            'reached inside step 2 instead, the command spends step 1 on '
            'ffmpeg and fails as a build that could not finish rather than as '
            'a directory it may not write to',
      );

      expect(
        Directory('${project.path}/assets').listSync(),
        isEmpty,
        reason:
            'compaction writes the canonical files into assets/, and it ran '
            'before the refusal if anything is there',
      );
    });
  });
}
