// The order this repository's projects number their component bits in.
//
// # Why this exists as a separate suite
//
// `good_tool --check` regenerates each package's `component_bits.g.dart` and
// fails on one that is not byte-for-byte what the generator would write now. That is the whole proof that bit order has not moved, and #381
// deletes those files: bits become per game, allocated for the components a
// project's prefabs actually use. The proof has to survive the files, so it
// has to be stated about a project rather than about a package.
//
// It is also a wider question than `--check` asks. A package's table holds the
// order *within* that package; what a peer reads is a whole game's numbering,
// which is the packages it depends on sorted by name with each table's own
// order inside. Every committed table can be current and a game's numbering
// still move - when the game gains a dependency, when a package name changes,
// or when the rule in `ComponentTypeRegistry.installGenerated` changes. None
// of that is visible in the diff of a `component_bits.g.dart`.
//
// # Why the expected orders are written out here
//
// They are typed, not regenerated. A golden file a command rewrites is fixed
// by running the command, and this is the one number in the repository that
// two machines have to agree on: a query signature is a bitmask, and a peer
// reading one is asking what each bit meant where it was written. Changing it
// should cost somebody the work of writing the new order down and saying in
// the commit why the wire changed.
//
// # What it does not catch
//
// A change to `installGenerated` itself. The rule is restated in
// `bit_order.dart` because `good_tool` cannot import a Flutter package, and
// `good`'s own `component_bits_test.dart` is what pins the engine's half of
// it. Two deliberate edits, one to each, would agree with each other and move
// the wire.

import 'dart:io';

// ignore: implementation_imports
import 'package:good_cli/src/generate/engine_package.dart';
// ignore: implementation_imports
import 'package:good_cli/src/generate/scan.dart';
import 'package:good_tool/src/bit_order.dart';
import 'package:good_tool/src/scan.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '_repo.dart';

void main() {
  group('the bit order this repository hands a project', () {
    late Directory root;
    late List<EnginePackage> packages;
    late ComponentBitScan scan;

    // One scan for the group. It is the same walk `--check` does - every
    // engine package's `lib/`, with the generated tables left out so nothing
    // here reads the file it is standing in for.
    setUpAll(() async {
      root = repositoryRoot();
      packages = repoPackages(root);
      final sources = await readSources(
        root,
        rootOverride: <String>[for (final package in packages) package.libDir],
        exclude: <String>{
          for (final package in packages) package.componentBitsFile.path,
        },
      );
      scan = scanComponentBits(packages: packages, sources: sources);
    });

    ProjectBitOrder orderFor(String path) => projectBitOrder(
      projectDir: Directory(p.join(root.path, p.joinAll(p.posix.split(path)))),
      packages: packages,
      scan: scan,
    );

    // The demo game, which is the only project in this repository that is one:
    // a Flutter application built on `goo2d` and the physics backend, with
    // prefabs of its own and no component of its own. What a peer receiving
    // one of its query signatures would have to agree with, bit by bit.
    test('goo2d/example numbers thirteen bits, in this order', () {
      final order = orderFor('packages/goo2d/example');

      expect(order.project, 'goo2d_example');
      // The cross-package half, which no committed table states: sorted by
      // package name, so `good`'s two bits come last and not first.
      expect(order.packages, <String>[
        'goo2d',
        'goo2d_physics_box2d',
        'good',
      ]);
      expect(order.lines, <String>[
        '0 goo2d:Camera',
        '1 goo2d:Collider2D',
        '2 goo2d:ScreenTransform2D',
        '3 goo2d:Transform2D',
        '4 goo2d:WorldTransform2D',
        '5 goo2d:HoverReceiver',
        '6 goo2d:PointerReceiver',
        '7 goo2d:Renderable2D',
        '8 goo2d:Text2D',
        '9 goo2d_physics_box2d:Effector2D',
        '10 goo2d_physics_box2d:RigidBody2D',
        '11 good:Child',
        '12 good:Parent',
      ], reason: _reason);

      // `goo3d` is not in the list because the example does not depend on it,
      // and that is the point of asking a project rather than the repository:
      // three bits this game never spends.
      expect(
        order.bits.map((bit) => bit.package),
        isNot(contains('goo3d')),
      );
      // A game's own prefabs take the bits after these, at run time, so the
      // seeded ones have to leave room - and this is what #337 is about.
      expect(order.bits.length, lessThan(maxComponentTypes));
    });

    // Not a game, and it is here for one reason: it is the only package in the
    // checkout that depends on every engine package holding a table, so it is
    // the only subject that numbers `goo3d`'s three bits. `goo2d/example` is
    // the checkout's only example, and it is 2D. Without `doc_snippets` those
    // three bits are ordered by nothing.
    test('doc_snippets, on every engine package, numbers sixteen', () {
      final order = orderFor('packages/doc_snippets');

      expect(order.project, 'doc_snippets');
      expect(order.packages, <String>[
        'goo2d',
        'goo2d_physics_box2d',
        'goo3d',
        'good',
      ]);
      expect(order.lines, <String>[
        '0 goo2d:Camera',
        '1 goo2d:Collider2D',
        '2 goo2d:ScreenTransform2D',
        '3 goo2d:Transform2D',
        '4 goo2d:WorldTransform2D',
        '5 goo2d:HoverReceiver',
        '6 goo2d:PointerReceiver',
        '7 goo2d:Renderable2D',
        '8 goo2d:Text2D',
        '9 goo2d_physics_box2d:Effector2D',
        '10 goo2d_physics_box2d:RigidBody2D',
        '11 goo3d:Camera3D',
        '12 goo3d:Transform3D',
        '13 goo3d:WorldTransform3D',
        '14 good:Child',
        '15 good:Parent',
      ], reason: _reason);
    });

    // The two subjects above are a list, and a list goes stale. A new engine
    // package with components of its own would be numbered into some game's
    // signature with nothing here having an opinion about where, which is the
    // failure this whole suite exists to prevent - so it fails here instead,
    // naming the package and what to do about it.
    test('leaves no package with a table unpinned', () {
      final pinned = <String>{
        for (final path in const <String>[
          'packages/goo2d/example',
          'packages/doc_snippets',
        ])
          ...orderFor(path).packages,
      };
      expect(
        scan.byPackage.keys.toSet().difference(pinned),
        isEmpty,
        reason:
            'this package registers components and no project pinned above '
            'depends on it, so where its bits land in a game is written down '
            'nowhere. Add a project that depends on it to this suite, with '
            'the order it produces.',
      );
    });
  }, timeout: const Timeout(Duration(minutes: 5)));
}

/// What a changed order means, said where somebody reading the failure is.
const String _reason =
    'the bit order this project numbers has changed. A query signature is a '
    'bitmask and its bits are these types, so two builds that disagree here '
    'read each other\'s signatures as different queries. If the change is '
    'meant, write the new order down and say in the commit message what moved '
    'and why; if it is not, the scan or the project\'s dependencies changed '
    'under it.';
