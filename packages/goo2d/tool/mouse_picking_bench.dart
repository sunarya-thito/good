// What does `MousePickingSystem` cost per receiver per fixed tick?
//
//   cd packages/goo2d && flutter test tool/mouse_picking_bench.dart
//
// Deliberately **not** in `test/`: a measurement, not an assertion, and one
// that would fail the suite on a busy machine. It lives under `tool/` with
// the other stress harnesses.
//
// # This one cannot be AOT-compiled, and will not be able to be
//
// The rule is to AOT-compile any benchmark that would change code, because
// `flutter test` is JIT and has been wrong about this engine's write-path
// costs by roughly 100x. `packages/good/tool/` obeys it by importing leaf
// modules only. This cannot: what it measures is a `GameSystem` driven by a
// real `Game` over a real scene, and #154 is that `system.dart` reaches
// `package:flutter` through `game.dart`, so `dart compile exe` refuses
// anything holding a `Query`. `packages/goo2d/tool/`'s other benches are in
// the same position for the same reason.
//
// So read every number here as a **ratio between legs** measured in one VM
// over one set of rows - which is what it is built to give - and not as a
// figure a device would produce.
//
// # What it answers
//
// #184 measured picking at 122.3 ns/receiver at 20,000 receivers, against a
// fill pass of 88.8 ns/entity - picking cost more per entity than drawing.
// This is the harness that says whether that is still true.
//
// The number is a **difference**: the same scene, the same transforms, the
// same tick count, with the picker enabled and then disabled through
// `GameState.disableSystem`. Everything the picker does not own cancels, and
// `WorldTransformSystem` runs in both legs.
//
// # It can fail
//
// The control is [_spread]. At `_spread = 0` every receiver sits on top of
// the cursor, so no bound can reject anything and the coarse reject must show
// as no saving at all. At a realistic spread almost everything is rejected.
// A harness that only ever ran the second case could not tell a working
// reject from a compiler that hoisted the whole loop.
//
import 'package:flutter_test/flutter_test.dart';
import 'package:goo2d/goo2d.dart';

const int _warmTicks = 40;
const int _timedTicks = 200;

/// Timed runs per leg; the fastest is reported. See `timeTicks`.
const int _repeats = 5;

/// Receiver counts. Doubling, so "flat ns per receiver" is a straight line.
const List<int> _counts = <int>[5000, 20000];

/// How far apart the receivers are laid out, in world units. `0` stacks them
/// all under the cursor - the control leg, where nothing can be rejected.
const List<double> _spreads = <double>[0, 40];

/// Set before the scene is described, read by [_Target.describeCollider]. A
/// global because the prefab is built inside `describeScene` and the point is
/// to vary it between runs, each of which resets the registries anyway.
double _colliderOffset = 0;

/// A plain receiver: one circle collider, no sprite. No `Renderable2D`, so
/// `_depthOf` short-circuits - that path runs once per *hit*, not per
/// candidate, and is not what this measures.
class _Target extends EntityStruct
    with Transform2D, WorldTransform2D, Collider2D, MouseReceiver {
  late final CircleBody hitArea;

  @override
  void describeCollider(ColliderDescriptor descriptor) {
    super.describeCollider(descriptor);
    hitArea = descriptor.hasCircleCollider(
      radius: 20,
      offsetX: _colliderOffset,
      offsetY: _colliderOffset,
    );
  }
}

class _Eye extends EntityStruct with Transform2D, WorldTransform2D, Camera {}

class _Scene extends SceneStruct {
  @override
  void onSceneMounted(Scene scene) => handle = scene;

  late Scene handle;

  late final _Target target;
  late final _Eye eye;

  @override
  void describeScene(SceneDescriptor descriptor) {
    super.describeScene(descriptor);
    target = descriptor.has(_Target.new);
    eye = descriptor.has(_Eye.new);
  }
}

class _BenchState extends GameState<_BenchGame> {
  @override
  void onMounted() => loadScene(_Scene());

  @override
  void describeSystems(SystemDescriptor descriptor) {
    super.describeSystems(descriptor);
    descriptor.has(WorldTransformSystem.new);
    descriptor.has(MousePickingSystem.new);
  }
}

class _BenchGame extends Game {
  late final CameraView view;

  @override
  void describeCameras(CameraDescriptor descriptor) {
    super.describeCameras(descriptor);
    view = descriptor.has();
  }

  @override
  int get pageSize => 1 << 20;

  @override
  Duration get fixedTimeStep => const Duration(milliseconds: 10);

  @override
  GameState createState() => _BenchState();
}

/// ns per receiver per tick, picking on minus picking off.
final Map<String, double> results = <String, double>{};

void main() {
  for (final spread in _spreads) {
    for (final count in _counts) {
      test('$count receivers, spread $spread', () async {
        _colliderOffset = 0;
        final game = _BenchGame();
        final run = await Game.startInline(game);
        addTearDown(() async {
          if (run.isRunning) await run.stop();
          // Each cell runs its own game in the same process, so the
          // process-global registries have to go back to empty between them.
          // ignore: invalid_use_of_visible_for_testing_member
          SceneRegistry.reset();
          // ignore: invalid_use_of_visible_for_testing_member
          ArchetypeRegistry.reset();
          // ignore: invalid_use_of_visible_for_testing_member
          ComponentTypeRegistry.reset();
        });

        final scene = run.state.singleScene<_Scene>();
        final eye = scene.handle.addEntity(scene.eye);
        scene.eye.view[eye] = game.view;

        // A square block of receivers around the origin. The cursor sits at
        // the origin, so exactly the entities near it survive a bound.
        final side = _isqrt(count);
        final half = side * spread / 2;
        final entities = List<Entity>.generate(
          count,
          (_) => scene.handle.addEntity(scene.target),
        );
        scene.pool.beginTick();
        for (var i = 0; i < count; i++) {
          scene.target
            ..transformOffsetX[entities[i]] = (i % side) * spread - half
            ..transformOffsetY[entities[i]] = (i ~/ side) * spread - half;
        }
        scene.pool.commitTick();

        game.inputDevice!.movePointer(screenX: 0, screenY: 0);

        // The best of [_repeats] runs, not the mean. What varies between
        // them is the machine being interrupted, and that only ever adds
        // time - so the fastest run is the one with the least of something
        // this bench is not measuring in it.
        double timeTicks() {
          var best = double.infinity;
          for (var r = 0; r < _repeats; r++) {
            final watch = Stopwatch()..start();
            for (var i = 0; i < _timedTicks; i++) {
              run.state.runFixedStep();
            }
            watch.stop();
            final ns = watch.elapsedMicroseconds * 1000 / (_timedTicks * count);
            if (ns < best) best = ns;
          }
          return best;
        }

        for (var i = 0; i < _warmTicks; i++) {
          run.state.runFixedStep();
        }
        final on = timeTicks();

        run.state.disableSystem<MousePickingSystem>();
        for (var i = 0; i < _warmTicks; i++) {
          run.state.runFixedStep();
        }
        final off = timeTicks();

        results['$spread/$count'] = on - off;
      });
    }
  }

  tearDownAll(() {
    final report = StringBuffer()
      ..writeln('\nMousePickingSystem, ns per receiver per fixed tick')
      ..writeln('(picker enabled minus disabled, best of $_repeats x $_timedTicks ticks)\n')
      ..write('  receivers');
    for (final spread in _spreads) {
      report.write('spread $spread'.padLeft(16));
    }
    report
      ..writeln()
      ..writeln('  ${'-' * (9 + 16 * _spreads.length)}');
    for (final count in _counts) {
      report.write('  ${count.toString().padLeft(9)}');
      for (final spread in _spreads) {
        final cell = results['$spread/$count'];
        report.write(
          (cell == null ? '-' : cell.toStringAsFixed(1)).padLeft(16),
        );
      }
      report.writeln();
    }
    // ignore: avoid_print
    print(report);
  });
}

int _isqrt(int n) {
  var r = 1;
  while ((r + 1) * (r + 1) <= n) {
    r++;
  }
  return r;
}
