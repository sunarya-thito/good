@Timeout(Duration(minutes: 10))
library;

import 'dart:convert';
import 'dart:io';

import 'package:good_cli/src/generate/bundle.dart';
import 'package:good_cli/src/generate/scaffold.dart';
import 'package:test/test.dart';

import '_cli.dart';
import '_scaffolded.dart';

// `good create` -> `good generate`, over the project `good create` writes.
//
// # Why this file exists
//
// Nothing ran the walk. `build_assets_test` runs the build steps over a
// hand-written pubspec fixture and never over scaffold output, `create_test`
// runs `--dry-run` and returns before writing anything, and
// `scaffold_analyze_test` writes the scaffold files and runs no command at
// all. So the scaffold's pubspec and the commands' expectations were checked
// against two fixtures that nothing forced to agree, which is how a project
// that scaffolds clean and generates nothing gets to be green here.
//
// What that shipped was this, from a project with art in `assets_src/`:
//
//     No assets found in the declared directories.
//     0 texture(s), 0 audio file(s).
//     EXIT=0
//
// Every assertion below is about one link in the chain: the art is converted,
// the enum names the converted file, the chunk holds it, and the mapping
// points at the chunk. Break any stage and a different one of them fails.
// (#238)

bool get _hasFfmpeg {
  try {
    return Process.runSync('ffmpeg', <String>['-version']).exitCode == 0;
  } on ProcessException {
    return false;
  }
}

/// A real image ffmpeg can convert, written where an artist would put it.
void _sourceImage(Directory project, String name) {
  final path = '${project.path}/assets_src/$name';
  File(path).parent.createSync(recursive: true);
  final result = Process.runSync('ffmpeg', <String>[
    '-loglevel',
    'error',
    '-y',
    '-f',
    'lavfi',
    '-i',
    'color=c=red:s=32x32:d=1',
    '-frames:v',
    '1',
    path,
  ]);
  if (result.exitCode != 0) {
    throw StateError('ffmpeg could not write $path: ${result.stderr}');
  }
}

/// `--no-pub-get`, because the project's resolution is borrowed from this
/// repository rather than fetched - see `_scaffolded.dart`.
ProcessResult _generate(Directory project, [List<String> extra = const []]) =>
    GoodCli.instance.run(<String>[
      'generate',
      '--project-dir',
      project.path,
      '--no-pub-get',
      ...extra,
    ]);

/// Repoints [name]'s entry in [project]'s package config at the relative
/// `rootUri` a `pub get` would have left there.
///
/// `_scaffolded.dart` borrows this repository's resolution and writes every
/// entry absolute, and an absolute `rootUri` is the one form the resolve check
/// never got wrong: it means the same thing whatever it is resolved against.
/// What pub writes for a path dependency inside the project is `../<name>`,
/// which only names a directory once it is read against the directory holding
/// the file - and that is the reading #395 is about.
void _asPubGetWritesIt(Directory project, String name) {
  final file = File('${project.path}/.dart_tool/package_config.json');
  final config = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
  file.writeAsStringSync(
    jsonEncode(<String, Object?>{
      ...config,
      'packages': <Object?>[
        for (final entry in config['packages']! as List<Object?>)
          if ((entry as Map<String, Object?>)['name'] != name)
            entry
          else
            <String, Object?>{...entry, 'rootUri': '../$name'},
      ],
    }),
  );
}

void main() {
  test('art dropped in assets_src reaches the enum and the chunk', () async {
    final project = await scaffoldProject(
      name: 'walk_probe',
      engine: GoodEngine.twoD,
      // The point is what `good generate` does, so nothing may have generated
      // into this project before the command runs.
      generate: false,
    );
    _sourceImage(project, 'player.png');

    final run = _generate(project);
    final log = '${run.stdout}${run.stderr}';
    expect(run.exitCode, 0, reason: log);

    expect(
      File('${project.path}/assets/player.webp').existsSync(),
      isTrue,
      reason:
          'the source art was never converted, so nothing downstream can see '
          'it:\n$log',
    );

    final bundle = resolveBundle(project);
    final textures = File(
      '${bundle.libDir.path}/textures.dart',
    ).readAsStringSync();
    expect(
      textures,
      contains('assets/player.webp'),
      reason:
          'generation read the asset directory before anything filled it - '
          'this is the "0 texture(s)" the fold exists to remove:\n$log',
    );

    final chunks =
        Directory('${project.path}/assets/packed')
            .listSync()
            .whereType<File>()
            .map((file) => file.uri.pathSegments.last)
            .where((name) => name.endsWith('.dat'))
            .toList()
          ..sort();
    expect(
      chunks,
      isNotEmpty,
      reason: 'nothing packed what generation had just bound:\n$log',
    );

    expect(
      bundle.assetKeyFile.readAsStringSync(),
      contains("'assets/player.webp':"),
      reason:
          'the pack wrote no mapping back, so a release build would look for '
          'a chunk it cannot name:\n$log',
    );
  }, skip: _hasFfmpeg ? null : 'ffmpeg is not installed');

  test('--no-normalize is the whole of what turns a stage off', () async {
    // The counterpart to the test above, and the reason the flag is not just
    // a convenience: a project whose art is slow to convert has to be able to
    // iterate on code without paying for it. Skipping the stage has to skip
    // the conversion and nothing else, so generation still runs and still
    // reports honestly about what it found.
    final project = await scaffoldProject(
      name: 'walk_skip_probe',
      engine: GoodEngine.twoD,
      generate: false,
    );
    _sourceImage(project, 'player.png');

    final run = _generate(project, <String>['--no-normalize']);
    final log = '${run.stdout}${run.stderr}';
    expect(run.exitCode, 0, reason: log);
    expect(
      File('${project.path}/assets/player.webp').existsSync(),
      isFalse,
      reason: '--no-normalize converted the art anyway:\n$log',
    );
    expect(
      File('${resolveBundle(project).libDir.path}/textures.dart').existsSync(),
      isTrue,
      reason: 'skipping one stage stopped the others:\n$log',
    );
  }, skip: _hasFfmpeg ? null : 'ffmpeg is not installed');

  test('generate run from inside the project takes `.` as the project', () async {
    // The documented invocation, and the one every other test here avoids by
    // passing an absolute `--project-dir`. With a relative project directory
    // the resolve check read the package config against a base that had no
    // scheme, answered no for a project that was fully resolved, and the run
    // ended at exit 65 saying the package config did not point at the bundle.
    //
    // `pubGet` is left on, because that is what makes the check run at all.
    // The project is already resolved, so a run that answers correctly has
    // nothing to resolve and never reaches the stub `flutter`. (#395)
    final project = await scaffoldProject(
      name: 'walk_cwd_probe',
      engine: GoodEngine.twoD,
    );
    _asPubGetWritesIt(project, 'walk_cwd_probe_bundle');

    final run = GoodCli.instance.run(const <String>[
      'generate',
    ], workingDirectory: project.path);
    final log = '${run.stdout}${run.stderr}';

    expect(run.exitCode, 0, reason: log);
    expect(
      log,
      isNot(contains('resolved package config')),
      reason:
          'the bundle this project resolves was reported as unresolved:\n$log',
    );
    expect(
      log,
      isNot(contains('flutter pub get')),
      reason:
          'a project whose bundle already resolves was sent to pub anyway, '
          'which is the same wrong answer arriving one step earlier:\n$log',
    );
  });

  test('good build --no-generate runs no stage of the pipeline', () async {
    // `good build` runs `good generate` first, the way `flutter build` runs
    // `flutter pub get`, and this is the flag that says not to. The build
    // itself fails - `flutter` is a stub that exits at once, see GoodCli - so
    // what is asserted is that nothing was written before it got there.
    final project = await scaffoldProject(
      name: 'walk_nogen_probe',
      engine: GoodEngine.twoD,
      generate: false,
    );
    _sourceImage(project, 'player.png');

    final run = GoodCli.instance.run(<String>[
      'build',
      'windows',
      '--project-dir',
      project.path,
      '--no-pub-get',
      '--no-generate',
    ]);
    final log = '${run.stdout}${run.stderr}';

    expect(
      File('${project.path}/assets/player.webp').existsSync(),
      isFalse,
      reason: '--no-generate normalized anyway:\n$log',
    );
    expect(
      resolveBundle(project).exists,
      isFalse,
      reason: '--no-generate generated anyway:\n$log',
    );
  }, skip: _hasFfmpeg ? null : 'ffmpeg is not installed');
}
