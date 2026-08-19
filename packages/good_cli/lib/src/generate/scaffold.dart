/// Which engine package a new project is built against.
///
/// Never named on the command line - `--2d` and `--3d` choose it. The names
/// here exist because a Dart enum value cannot begin with a digit, and that is
/// this file's problem rather than the user's.
///
/// It lives beside the templates rather than beside the command, because what
/// it selects *is* a set of templates: the package to import, the components a
/// prefab is made of, and what `main.dart` can honestly claim will appear on
/// screen.
enum GoodEngine {
  twoD('goo2d'),

  /// Transforms, hierarchy and the camera. No renderer - see [scaffoldFiles].
  threeD('goo3d');

  const GoodEngine(this.package);

  final String package;
}

/// What a good project consists of, as a map of relative path to content.
///
/// A pure function on purpose. Deciding *what a starting project is* is the
/// interesting and reviewable part of `good create`; running `flutter create`
/// and writing bytes is not. Keeping them apart means the templates can be
/// tested - that they compile against the real API, that they name the right
/// package - on a machine with no Flutter SDK.
///
/// The pubspec is **not** here. `flutter create` writes one, and rewriting it
/// wholesale would discard whatever the installed Flutter version put in it;
/// the good dependency is added by patching instead - see
/// [patchedPubspecLines].
///
/// # The two dimensions do not scaffold the same project
///
/// A 2D project draws a sprite on its first run. A 3D one cannot: `goo3d` is
/// transforms, hierarchy composition and the camera, and the draw path -
/// meshes, materials, lights - is issue #43. So the 3D templates scaffold what
/// is actually there (a spinning entity, a composed world transform, a camera
/// entity occupying a declared view) and say in their own comments that
/// nothing turns it into pixels yet. Emitting a `Renderable3D` that does not
/// exist would scaffold a project that does not compile; emitting a blank
/// screen with no explanation would scaffold one that looks broken.
Map<String, String> scaffoldFiles({
  required String projectName,
  required GoodEngine engine,
  required String command,
}) {
  final className = _pascal(projectName);
  // `my_game` already ends in Game once pascalised, so appending would give
  // `MyGameGame` - the same doubling `_gameFile` avoids for the filename.
  final gameClass = _gameClass(className);
  final package = engine.package;
  final gameFile = _gameFile(projectName);
  return <String, String>{
    'lib/main.dart': engine == GoodEngine.threeD
        ? _main3D(projectName, className, gameClass, package)
        : _main2D(projectName, className, gameClass, package),
    'lib/game/$gameFile.dart': engine == GoodEngine.threeD
        ? _game3D(className, gameClass, package)
        : _game2D(className, gameClass, package),
    'lib/game/scenes/main_scene.dart': engine == GoodEngine.threeD
        ? _scene3D(gameClass, gameFile, package)
        : _scene2D(package),
    'lib/game/prefabs/player.dart': engine == GoodEngine.threeD
        ? _player3D(package)
        : _player2D(package),
    if (engine == GoodEngine.threeD) ...<String, String>{
      'lib/game/prefabs/eye.dart': _eye3D(package),
      'lib/game/systems/spin_system.dart': _spinSystem3D(package),
    },
    'assets/.gitkeep': _gitkeep(command),
    // Present from the start so the entry below resolves before anything has
    // been packed: Flutter refuses to build over an asset directory that does
    // not exist, and the first `good build` is the worst moment to discover it.
    'assets/packed/.gitkeep': _packedGitkeep(),
  };
}

/// The lines a good project needs in its pubspec, as something to show someone.
///
/// [patchedPubspecLines] applies this to a pubspec good just had `flutter
/// create` write. This form is what gets printed when that is not possible - an
/// existing project under `--no-flutter-create`, or a pubspec whose shape the
/// patcher does not recognise. Editing someone's pubspec blind is not something
/// to do on their behalf.
String pubspecPatch(String package) =>
    '''
dependencies:
  $package: $engineConstraint

flutter:
  assets:
    - assets/
    - assets/packed/
''';

/// The version range a scaffolded project depends on.
///
/// It has to admit what is on pub.dev. This said `^0.0.1` for long enough to
/// outlive the 0.1.0 release, and `^0.0.1` does not allow 0.1.0 - so every
/// project scaffolded in between failed `flutter pub get` on a machine without
/// a path override, which is every machine but this repository's.
const String engineConstraint = '^0.1.0';

/// [lines] with the good dependency and the asset entries added, or null if the
/// pubspec is not a shape this can edit safely.
///
/// Null rather than a best guess: the caller prints [pubspecPatch] instead, and
/// a wrong edit to someone's pubspec is worse than an instruction to make the
/// right one by hand.
///
/// Textual rather than a YAML round-trip, which would re-emit the file and
/// strip every comment `flutter create` wrote - and those comments are most of
/// what a new project has to read. Both anchors are lines `flutter create`
/// always writes. The dependency goes directly under `dependencies:`: order
/// within the map means nothing to pub, and the top is the one position that
/// does not depend on what else is in the list.
List<String>? patchedPubspecLines(List<String> lines, String package) {
  final deps = lines.indexWhere((line) => line.trimRight() == 'dependencies:');
  final material = lines.indexWhere(
    (line) => line.trimRight() == '  uses-material-design: true',
  );
  if (deps < 0 || material < 0) return null;
  // Already patched. `good create --no-flutter-create` over a project that has
  // been through this before must not add the dependency twice.
  if (lines.any((line) => line.trimRight() == '  $package: $engineConstraint')) {
    return lines;
  }

  // Bottom-up, so the first insertion does not move the second's index.
  return List<String>.of(lines)
    ..insertAll(material + 1, <String>[
      '',
      '  # Both directories ship. `good build` fills assets/packed/ and empties',
      '  # assets/ of what it packed, so each asset is bundled exactly once.',
      '  assets:',
      '    - assets/',
      '    - assets/packed/',
    ])
    ..insert(deps + 1, '  $package: $engineConstraint');
}

/// Why the packed directory exists in a fresh project with nothing in it.
String _packedGitkeep() => '''
# `good build` writes its chunks here, and strips the loose copies out of
# ../ once they are inside one. Both directories are listed under
# `flutter: assets:`, which is what makes the chunks ship.
#
# Generated. Safe to delete; `good build` writes it again.
''';

/// The game file's name.
///
/// Avoids `demo_game_game.dart` when the project is already called
/// `demo_game` - a doubled suffix reads like a mistake because it is one.
String _gameFile(String projectName) =>
    projectName.endsWith('_game') ? projectName : '${projectName}_game';

String _pascal(String snake) {
  final words = snake.split('_').where((w) => w.isNotEmpty);
  return words
      .map((w) => w.substring(0, 1).toUpperCase() + w.substring(1))
      .join();
}

/// The game class's name, avoiding `MyGameGame` for a project called
/// `my_game` - the class-name half of what [_gameFile] does for the filename.
String _gameClass(String className) =>
    className.endsWith('Game') ? className : '${className}Game';

/// The app shell both dimensions share: start the game, then show it.
///
/// [surface] is the whole of what differs - a 2D project has a renderer to
/// hand the camera to, and a 3D one has a camera and nothing that reads it.
String _mainShell(
  String projectName,
  String className,
  String gameClass,
  String package, {
  required String surface,
  required String extras,
  String imports = '',
}) =>
    '''
import 'package:flutter/material.dart';
${imports}import 'package:$package/$package.dart';

import 'game/${_gameFile(projectName)}.dart';

void main() {
  // `ensureInitialized` before anything touches the engine: good allocates
  // native memory and decodes assets through Flutter, both of which need the
  // binding up.
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ${className}App());
}

class ${className}App extends StatelessWidget {
  const ${className}App({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: '$className',
      home: Scaffold(body: ${className}Surface()),
    );
  }
}

/// Starts the game, then shows it.
///
/// Stateful because starting is asynchronous - `Game.start` spawns the
/// simulation isolate and brings the world up - and because a `GameView` needs
/// a camera from a game that is already running. Showing something while that
/// happens is the whole reason for the branch in [build].
class ${className}Surface extends StatefulWidget {
  const ${className}Surface({super.key});

  @override
  State<${className}Surface> createState() => _${className}SurfaceState();
}

class _${className}SurfaceState extends State<${className}Surface> {
  $gameClass? _game;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    final game = $gameClass();
    await Game.start(game);
    if (mounted) setState(() => _game = game);
  }

  @override
  void dispose() {
    // The game owns native memory and an isolate; neither is reclaimed by the
    // widget going away.
    _game?.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final game = _game;
    if (game == null) return const Center(child: CircularProgressIndicator());
$surface
  }
}
$extras''';

String _main2D(
  String projectName,
  String className,
  String gameClass,
  String package,
) => _mainShell(
  projectName,
  className,
  gameClass,
  package,
  surface: '    return GameView(camera: game.defaultCamera);',
  extras: '',
);

String _main3D(
  String projectName,
  String className,
  String gameClass,
  String package,
) => _mainShell(
  projectName,
  className,
  gameClass,
  package,
  // `Ticker`, for the tick readout below. `material.dart` does not export it.
  imports: "import 'package:flutter/scheduler.dart';\n",
  // The `GameView` is first and real: it routes keyboard, gamepad and pointer
  // input to the game whether or not anything paints. It is what the renderer
  // will fill in, so the notice sits on top of it rather than in place of it.
  surface:
      '''
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        GameView(camera: game.mainView),
        _NoRendererYet(game: game),
      ],
    );''',
  extras:
      '''
/// Says what is running and what is not.
///
/// `goo3d` today is transforms, hierarchy composition and the camera. There is
/// no draw path - no meshes, no materials, no lights - so the `GameView` above
/// paints nothing, which is the honest answer rather than a crash or a
/// placeholder pretending something is there. The renderer is issue #43, a
/// native backend behind a C shim.
///
/// The tick number is not decoration: it is read off the running game and it is
/// the one thing on screen that proves the simulation isolate is up, the scene
/// loaded, and `SpinSystem` is turning your entity. Delete this widget the day
/// there is something to look at instead.
class _NoRendererYet extends StatefulWidget {
  const _NoRendererYet({required this.game});

  final $gameClass game;

  @override
  State<_NoRendererYet> createState() => _NoRendererYetState();
}

class _NoRendererYetState extends State<_NoRendererYet>
    with SingleTickerProviderStateMixin {
  Ticker? _repaint;

  @override
  void initState() {
    super.initState();
    // Repainted on Flutter's vsync rather than on the engine's tick, because
    // this is a *label*: it wants to be readable, not frame-accurate, and a
    // rebuild per fixed tick would be a rebuild the rest of the tree does not
    // need.
    _repaint = createTicker((_) => setState(() {}))..start();
  }

  @override
  void dispose() {
    _repaint?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Text(
              'Nothing is drawn here yet.',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'goo3d ships transforms, hierarchy and the camera. The renderer '
              'is issue #43. Your scene is simulating regardless:',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'tick \${widget.game.tick}',
              style: const TextStyle(fontFeatures: <FontFeature>[
                FontFeature.tabularFigures(),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}
''',
);

String _game2D(String className, String gameClass, String package) =>
    '''
import 'package:$package/$package.dart';

import 'scenes/main_scene.dart';

/// The **main isolate** half: what the game *is*. Declarations live here -
/// systems, buffers, cameras - and no simulation runs on this side.
class $gameClass extends Game2D {
  @override
  GameState2D<$gameClass> createState() => ${className}State();
}

/// The **game isolate** half: what the game *does*.
class ${className}State extends GameState2D<$gameClass> {
  @override
  void onMounted() {
    // Brings the world into being. Everything a scene declares - its prefabs,
    // its assets - is registered by this call, on this copy.
    loadScene(MainScene());
  }
}
''';

String _game3D(String className, String gameClass, String package) =>
    '''
import 'package:$package/$package.dart';

import 'scenes/main_scene.dart';
import 'systems/spin_system.dart';

/// The **main isolate** half: what the game *is*. Declarations live here -
/// systems, buffers, cameras - and no simulation runs on this side.
///
/// `Game` and not a `Game3D`: there is no such class, because what `Game2D`
/// gives you over `Game` is a renderer and a default camera view to point it
/// at, and `goo3d` has no renderer yet (issue #43). Everything a 3D game
/// declares, it declares here by hand - which is two overrides, both below.
class $gameClass extends Game {
  /// The view `main.dart` shows, and the one the camera entity in
  /// `MainScene` is pointed at.
  ///
  /// A view is a place a game is drawn, declared at boot because its storage
  /// is allocated before the simulation isolate is spawned. `Game2D` declares
  /// one called `defaultCamera` on your behalf; nothing does that here.
  late final CameraView mainView;

  @override
  void describeCameras(CameraDescriptor descriptor) {
    super.describeCameras(descriptor);
    mainView = descriptor.has();
  }

  @override
  GameState<$gameClass> createState() => ${className}State();
}

/// The **game isolate** half: what the game *does*.
class ${className}State extends GameState<$gameClass> {
  @override
  void describeSystems(SystemDescriptor descriptor) {
    super.describeSystems(descriptor);
    // Composes every entity's local `Transform3D` against its ancestors into
    // its `WorldTransform3D`, once per tick. Without it a child never moves
    // with its parent - and again, `Game2D` declares the 2D twin of this for
    // you while nothing declares this one.
    descriptor.has(WorldTransform3DSystem());
    descriptor.has(SpinSystem());
  }

  @override
  void onMounted() {
    // Brings the world into being. Everything a scene declares - its prefabs,
    // its assets - is registered by this call, on this copy.
    loadScene(MainScene());
  }
}
''';

String _scene2D(String package) =>
    '''
import 'package:$package/$package.dart';

import '../prefabs/player.dart';

/// One scene: which prefabs can be spawned in it, and what exists when it
/// loads.
class MainScene extends SceneStruct {
  late final Player player;

  @override
  void describeScene(SceneDescriptor descriptor) {
    super.describeScene(descriptor);
    // Declares the prefab: registers its archetype and runs its describe
    // passes. Returns the handle to spawn from.
    player = descriptor.has(Player.new);
  }

  @override
  void onSceneMounted(Scene scene) {
    scene.addEntity(player);
  }
}
''';

String _scene3D(String gameClass, String gameFile, String package) =>
    '''
import 'package:$package/$package.dart';

import '../$gameFile.dart';
import '../prefabs/eye.dart';
import '../prefabs/player.dart';

/// One scene: which prefabs can be spawned in it, and what exists when it
/// loads.
class MainScene extends SceneStruct {
  late final Player player;
  late final Eye eye;

  @override
  void describeScene(SceneDescriptor descriptor) {
    super.describeScene(descriptor);
    // Declares the prefab: registers its archetype and runs its describe
    // passes. Returns the handle to spawn from.
    player = descriptor.has(Player.new);
    eye = descriptor.has(Eye.new);
  }

  @override
  void onSceneMounted(Scene scene) {
    scene.addEntity(player);

    final camera = scene.addEntity(eye);
    // A camera entity that occupies no view is a camera nothing would show.
    // Nothing shows it today either - there is no renderer to read this - but
    // the wiring is the wiring, and it is the line that will stop being
    // inert when issue #43 lands.
    eye.view[camera] = (game as $gameClass).mainView;
    // Backed off along +Z. A camera looks down its own -Z, and this one's
    // rotation is left at identity, so from here it faces the origin - where
    // the player is. `camera<Transform3D>().lookAt(x, y, z)` is the general
    // way to aim one.
    eye.transformOffsetZ[camera] = 6;
  }
}
''';

String _player2D(String package) =>
    '''
import 'package:$package/$package.dart';

/// One kind of entity, declared as the components it is made of.
///
/// A column is declared by the field that holds it, so this is all a piece of
/// per-entity state takes:
///
/// ```dart
/// final speed = Field.float64(220);   // read and written as speed[entity]
/// ```
///
/// To give it a texture, declare one in `describeAssets` and hand the handle
/// to the sprite:
///
/// ```dart
/// late final TextureAsset texture;
///
/// @override
/// void describeAssets(AssetDescriptor descriptor) {
///   super.describeAssets(descriptor);
///   texture = descriptor.has(Textures.yourAsset);  // from good.generated
/// }
/// ```
///
/// Drop an image into `assets/`, list it under `flutter: assets:` in the
/// pubspec, and run `good generate` to get the `Textures` enum.
class Player extends EntityStruct with Transform2D, WorldTransform2D, Renderable2D {
  late final Sprite sprite;

  @override
  void describeSprites(SpriteDescriptor descriptor) {
    super.describeSprites(descriptor);
    // Untextured to start with: a flat colour is one branch in the renderer
    // and needs no asset, so a new project draws something on the first run.
    sprite = descriptor.has(width: 64, height: 64, color: 0xFF4FC3F7);
  }
}
''';

String _player3D(String package) =>
    '''
import 'package:$package/$package.dart';

/// One kind of entity, declared as the components it is made of.
///
/// `Transform3D` is where it sits, how it is turned and how big it is,
/// relative to its parent. `WorldTransform3D` is the same thing composed
/// against its ancestors, written each tick by `WorldTransform3DSystem` - it
/// is what a renderer would read.
///
/// There is no `Renderable3D` to add here, and that is not an omission:
/// `goo3d` is transforms, hierarchy and the camera today, and meshes,
/// materials and lights arrive with the renderer in issue #43. This entity is
/// simulated every tick and drawn by nothing.
class Player extends EntityStruct with Transform3D, WorldTransform3D {
  /// How fast this entity turns, in radians per second, read by `SpinSystem`.
  ///
  /// A column is declared by the field that holds it: this one line reserves
  /// a float64 in every `Player` row and gives it a default. Read and write it
  /// as `spin[entity]`.
  final spin = Field.float64(0.6);
}
''';

String _eye3D(String package) =>
    '''
import 'package:$package/$package.dart';

/// The camera - an entity, not a global.
///
/// Where a view is looked at the world from is wherever this entity's
/// `WorldTransform3D` puts it, which is why it mixes in the transforms too. A
/// follow camera is therefore just a camera parented to the thing it follows;
/// there is no separate camera-controller concept to learn.
///
/// Nothing reads these columns yet. The camera is declared, positioned and
/// pointed at a view in `MainScene`, and the renderer that would turn that
/// into a projection matrix is issue #43.
class Eye extends EntityStruct with Transform3D, WorldTransform3D, Camera3D {
  @override
  void describeCamera(Camera3DDescriptor descriptor) {
    super.describeCamera(descriptor);
    // The named arguments are this archetype's row defaults, so a camera that
    // never changes its lens at run time needs no write at mount time at all.
    // The field of view is vertical, in degrees.
    descriptor.has(fieldOfView: 60, near: 0.1, far: 1000);
  }
}
''';

String _spinSystem3D(String package) =>
    '''
import 'package:$package/$package.dart';

import '../prefabs/player.dart';

/// Turns every [Player] on the spot, once per fixed tick.
///
/// A system is where per-tick work lives: it declares the entities it wants
/// as a [Query] and is handed them in archetype groups, so the columns are
/// resolved once per group instead of once per entity.
///
/// It is also the whole of what a 3D project can demonstrate today. The local
/// rotation this writes is real, and `WorldTransform3DSystem` composing it is
/// real; the only missing step is something that turns the result into pixels
/// (issue #43).
class SpinSystem extends GameSystem with FixedTickable {
  late final Query _players;

  double _elapsed = 0;

  @override
  void describeQuery(QueryDescriptor descriptor) {
    super.describeQuery(descriptor);
    _players = descriptor.query().withAll(Transform3D, Player).build();
  }

  /// Before `WorldTransform3DSystem`, and it has to be: this writes the local
  /// rotation that pass composes, so running after it would leave every
  /// entity's world transform one tick behind its own local one.
  @override
  int compareTo(GameSystem other) => other is WorldTransform3DSystem ? -1 : 0;

  @override
  void onFixedUpdate() {
    _elapsed += state.game.fixedTimeStep.inMicroseconds / 1000000.0;
    for (final group in _players.groups()) {
      final player = group.get<Player>();
      for (final entity in group) {
        // Euler angles are an input format, not storage: this writes the four
        // quaternion columns that everything downstream reads.
        entity<Transform3D>().setEuler(yaw: _elapsed * player.spin[entity]);
      }
    }
  }
}
''';

String _gitkeep(String command) =>
    '''
# Drop images here, list them under `flutter: assets:` in pubspec.yaml, then
# run `$command`'s sibling: `good generate`. That writes lib/good.generated/,
# where each asset becomes a value of the `Textures` enum.
''';
