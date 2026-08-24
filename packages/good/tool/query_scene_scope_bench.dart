// Does skipping a whole page beat testing every row's scene? (#145, #154)
//
// #145 scoped a query to one loaded scene by comparing `MemoryPage
// .ownerSceneSlot` once per page instead of `Entity.sceneSlot` once per row,
// and landed on that claim without measuring it. This measures it.
//
// Run it AOT. `flutter test` is the JIT and has been wrong about this
// engine's write-path costs by roughly 100x:
//
//   dart compile exe tool/query_scene_scope_bench.dart -o build/query_scene_scope_bench
//   ./build/query_scene_scope_bench
//
// **That command does not work yet, and #154 is why.** Eight files in
// `system.dart`'s import closure reach Flutter, not the one the issue names,
// and one of them - `widget/frame_meter.dart`, through `game.dart` - imports
// `dart:ui` outright, which no amount of narrowing a `Game` accessor can
// remove. Until all eight are cut, this compiles only against a stand-in
// `package:flutter`:
// a package literally named `flutter` supplying the ~30 `show`-listed symbols
// the kernel names, wired in with `dependency_overrides` from a throwaway
// package that depends on `good` by path. Nothing here executes a line of it.
// The numbers in #145 were taken that way.
//
// # The setup, and why it is the setup
//
// Two loaded scenes over **one** `SceneStruct`, so both share one archetype
// and therefore one page list. Rows are added to the two alternately, so the
// pages in that list alternate owners: A, B, A, B. A scoped walk can then
// only win by stepping over every second page.
//
// Two `SceneStruct`s would have been the easier fixture and would have
// measured nothing - each declaration registers its own archetype, so a
// scoped query would skip whole *archetypes* before reaching a page, and the
// number would say the page skip works when the page skip never ran.
//
// 4KB pages, 40,000 rows per scene: ~200 pages each, 400 alternating.
//
// # What is compared
//
//  * `groups(scene)` / `run(scene)` - the #145 path, one compare per page.
//  * the hand-written filter it replaces - walk everything, keep rows whose
//    `Entity.sceneSlot` matches. This is `Camera2DView.shows` in goo2d
//    (`data/camera.dart`), the obvious first consumer.
//  * an unscoped walk over both scenes - the control, and what tells you
//    whether either number above is a saving or noise.
//
// And one falsification pass: scoping to a third scene that holds no rows at
// all. Every page is skipped, so it must come out near zero. If it does not,
// nothing in this file is measuring a page skip and the other numbers mean
// nothing.

import 'package:good/src/data.dart';
import 'package:good/src/pool.dart';
import 'package:good/src/scene.dart';
import 'package:good/src/scene_handle.dart';
import 'package:good/src/struct.dart';
import 'package:good/src/system.dart';

const int rowsPerScene = 40000;
const int pageSizeBytes = 4096;
const int warmupRounds = 20;
const int measuredRounds = 200;

mixin _Position on Component {
  final x = Field.float64();
  final y = Field.float64();

  @override
  void describeType(ComponentDescriptor component) {
    super.describeType(component);
    component.has<_Position>();
  }
}

class _Mote extends EntityStruct with _Position {}

class _Field extends SceneStruct {
  late final _Mote mote;

  @override
  void describeScene(SceneDescriptor descriptor) {
    super.describeScene(descriptor);
    mote = descriptor.has(_Mote.new);
  }
}

/// The #145 path: one `ownerSceneSlot` compare per page, none per row.
double scopedGroups(Query query, Scene scene) {
  var sum = 0.0;
  for (final group in query.groups(scene)) {
    final position = group.get<_Position>();
    for (final entity in group) {
      sum += position.x[entity];
    }
  }
  return sum;
}

/// The same, through the lazy `run()` walk rather than the group iterator.
double scopedRun(Query query, Scene scene) {
  var sum = 0.0;
  for (final entity in query.run(scene)) {
    sum += entity.get<_Position>().x[entity];
  }
  return sum;
}

/// What #145 replaces: walk every row, test each one's scene.
///
/// The shape `Camera2DView.shows` has today.
double perRowFilter(Query query, int sceneSlot) {
  var sum = 0.0;
  for (final group in query.groups()) {
    final position = group.get<_Position>();
    for (final entity in group) {
      if (entity.sceneSlot != sceneSlot) continue;
      sum += position.x[entity];
    }
  }
  return sum;
}

/// The control: no scoping at all, so both scenes' rows are read.
double unscoped(Query query) {
  var sum = 0.0;
  for (final group in query.groups()) {
    final position = group.get<_Position>();
    for (final entity in group) {
      sum += position.x[entity];
    }
  }
  return sum;
}

/// Best of [measuredRounds], in microseconds. Best rather than mean: the
/// floor is the cost of the code, and everything above it is the machine
/// doing something else.
({double best, double median}) time(double Function() pass) {
  for (var i = 0; i < warmupRounds; i++) {
    pass();
  }
  final samples = <double>[];
  final watch = Stopwatch();
  for (var i = 0; i < measuredRounds; i++) {
    watch
      ..reset()
      ..start();
    final sum = pass();
    watch.stop();
    if (sum.isNaN) throw StateError('unreachable');
    samples.add(watch.elapsedMicroseconds.toDouble());
  }
  samples.sort();
  return (best: samples.first, median: samples[samples.length ~/ 2]);
}

void report(String label, ({double best, double median}) t, int rows) {
  final perRow = t.best * 1000 / rows;
  print(
    '  ${label.padRight(34)} '
    '${t.best.toStringAsFixed(0).padLeft(7)} us best  '
    '${t.median.toStringAsFixed(0).padLeft(7)} us median  '
    '${perRow.toStringAsFixed(1).padLeft(6)} ns/row over $rows rows',
  );
}

void main() {
  final field = _Field()
    ..initializeScene(MemoryPool(pageSize: pageSizeBytes, maxPages: 8192));

  // Three loads of one declaration: two that hold rows and one that holds
  // none. One `SceneStruct`, so one archetype and one page list.
  final sceneA = SceneRegistry.register(field);
  final sceneB = SceneRegistry.register(field);
  final empty = SceneRegistry.register(field);

  field.pool.beginTick();
  for (var i = 0; i < rowsPerScene; i++) {
    final a = sceneA.addEntity(field.mote);
    field.mote.x[a] = 1.0;
    final b = sceneB.addEntity(field.mote);
    field.mote.x[b] = 2.0;
  }
  field.pool.commitTick();

  final storage = field.mote.archetype;
  var pagesA = 0;
  var pagesB = 0;
  var flips = 0;
  var previous = -1;
  for (var i = 0; i < storage.pageCount; i++) {
    final page = storage.pageAt(i);
    if (page == null) continue;
    final owner = page.ownerSceneSlot;
    if (owner == sceneA.slot) pagesA++;
    if (owner == sceneB.slot) pagesB++;
    if (previous != -1 && owner != previous) flips++;
    previous = owner;
  }

  print('good query scene-scope benchmark (#145)');
  print(
    '  rows            ${rowsPerScene * 2} '
    '($rowsPerScene per scene, 2 scenes over 1 SceneStruct)',
  );
  print(
    '  page size       $pageSizeBytes bytes, '
    'stride ${storage.pageAt(0)?.strideBytes} bytes',
  );
  print(
    '  pages           ${storage.pageCount} '
    '($pagesA in A, $pagesB in B, $flips owner changes walking the list)',
  );
  if (flips < pagesA) {
    print(
      '  !! pages are not interleaved - a scoped walk has runs of pages '
      'to skip rather than every second one, and the numbers below are '
      'measuring an easier problem than the one #145 is about.',
    );
  }
  print('');

  final descriptor = ArchetypeQueryDescriptor();
  final query = descriptor.query().withAll(_Position).build();

  // Correctness first. A benchmark whose passes disagree is timing three
  // different walks, and the fastest of those is the one doing least.
  final expectedScoped = rowsPerScene * 1.0;
  final expectedAll = rowsPerScene * 3.0;
  void check(String label, double got, double want) {
    if (got != want) {
      throw StateError('$label summed $got, expected $want');
    }
  }

  check('scopedGroups', scopedGroups(query, sceneA), expectedScoped);
  check('scopedRun', scopedRun(query, sceneA), expectedScoped);
  check('perRowFilter', perRowFilter(query, sceneA.slot), expectedScoped);
  check('unscoped', unscoped(query), expectedAll);
  check('emptyScope', scopedGroups(query, empty), 0);

  report(
    'scoped groups(scene)  [#145]',
    time(() => scopedGroups(query, sceneA)),
    rowsPerScene,
  );
  report(
    'scoped run(scene)     [#145]',
    time(() => scopedRun(query, sceneA)),
    rowsPerScene,
  );
  report(
    'per-row sceneSlot filter',
    time(() => perRowFilter(query, sceneA.slot)),
    rowsPerScene,
  );
  report(
    'unscoped walk (control)',
    time(() => unscoped(query)),
    rowsPerScene * 2,
  );
  print('');
  report(
    'scoped to an empty scene',
    time(() => scopedGroups(query, empty)),
    storage.pageCount,
  );
  print('    ^ every page skipped. Near zero means the page skip is real;');
  print('      anything near the unscoped walk means it never ran.');
}
