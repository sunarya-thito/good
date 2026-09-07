import 'package:flutter_test/flutter_test.dart';
import 'package:goo3d/goo3d.dart';

part 'game_3d_test.g.dart';

/// The live run under test. A file-level binding, for the reason
/// `world_transform_3d_test.dart` has one: the bring-up helper returns the
/// `Game` while the tests also need the run.
late Game run;

class _Node extends EntityStruct
    with Transform3D, WorldTransform3D, Child, Parent {}

class _Eye extends EntityStruct with Transform3D, WorldTransform3D, Camera3D {}

class _Scene extends SceneStruct {
  @override
  void onSceneMounted(Scene scene) => handle = scene;

  late Scene handle;

  @sub
  final node = _Node();
  @sub
  final eye = _Eye();
}

/// A 3D game written the way a project should be able to write one: a state
/// that loads a scene, and nothing else.
///
/// The point of the file is what is **absent** here - no `describeCameras`
/// override, no `@system final worldTransform` line. Both are what #92 says
/// every 3D game repeats today.
class _State extends GameState3D<_Game> {
  @override
  void onMounted() => loadScene(_Scene());
}

class _Game extends Game3D {
  @override
  Duration get fixedTimeStep => const Duration(milliseconds: 10);

  @override
  GameState3D createState() => _State();
}

/// A game that wants a second view, declaring it the documented way.
class _TwoViewGame extends Game3D {
  late final CameraView minimap;

  @override
  Duration get fixedTimeStep => const Duration(milliseconds: 10);

  @override
  void describeCameras(CameraDescriptor descriptor) {
    super.describeCameras(descriptor);
    minimap = descriptor.has();
  }

  @override
  GameState3D createState() => _TwoViewState();
}

class _TwoViewState extends GameState3D<_TwoViewGame> {
  @override
  void onMounted() => loadScene(_Scene());
}

/// A game whose base class is already something else, reaching the same two
/// declarations through the mixins instead of the classes.
class _MixedGame extends Game with View3D {
  @override
  Duration get fixedTimeStep => const Duration(milliseconds: 10);

  @override
  GameState createState() => _MixedState();
}

class _MixedState extends GameState<_MixedGame>
    with Composition3DState<_MixedGame> {
  @override
  void onMounted() => loadScene(_Scene());
}

const Duration _step = Duration(milliseconds: 10);

Future<G> _start<G extends Game>(G Function() create) async {
  final game = await Game.startInline(create);
  run = game;
  addTearDown(() async {
    if (run.isRunning) await run.stop();
  });
  return game;
}

void main() {
  _installDeclarations();

  tearDown(() {
    SceneRegistry.reset();
    ArchetypeRegistry.reset();
    ComponentTypeRegistry.reset();
  });

  test('a Game3D declares one camera view without saying so', () async {
    final game = await _start(_Game.new);

    expect(game.cameraViews.length, 1);
    expect(game.defaultCamera.pack(), 0);
  });

  test('a camera entity points at it', () async {
    final game = await _start(_Game.new);
    final scene = run.state.singleScene<_Scene>();
    final entity = scene.handle.addEntity(scene.eye);

    scene.eye.cameraView[entity] = game.defaultCamera;

    expect(scene.eye.cameraView[entity], game.defaultCamera);
  });

  test(
    'a second view goes after it, and defaultCamera keeps address 0',
    () async {
      final game = await _start(_TwoViewGame.new);

      expect(game.cameraViews.length, 2);
      expect(game.defaultCamera.pack(), 0);
      expect(game.minimap.pack(), 1);
    },
  );

  test('a GameState3D composes a child against its parent', () async {
    await _start(_Game.new);
    final scene = run.state.singleScene<_Scene>();

    final parent = scene.handle.addEntity(scene.node);
    final child = scene.handle.addEntity(scene.node, parent: parent);
    scene.node
      ..transformOffsetX[parent] = 10
      ..transformOffsetX[child] = 5;

    run.state.advance(_step);

    // 15 and not 5: the child's local offset resolved against its parent's, so
    // `WorldTransform3DSystem` ran. Without the declaration the child keeps
    // the world offset it was spawned with, which is 0.
    expect(scene.node.worldX[child], 15);
    expect(scene.node.worldX[parent], 10);
  });

  test('the mixins give a game with another base class the same two', () async {
    final game = await _start(_MixedGame.new);
    final scene = run.state.singleScene<_Scene>();

    final parent = scene.handle.addEntity(scene.node);
    final child = scene.handle.addEntity(scene.node, parent: parent);
    scene.node
      ..transformOffsetX[parent] = 3
      ..transformOffsetX[child] = 4;

    run.state.advance(_step);

    expect(game.defaultCamera.pack(), 0);
    expect(scene.node.worldX[child], 7);
  });
}
