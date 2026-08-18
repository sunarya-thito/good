/// What a goo project consists of, as a map of relative path to content.
///
/// A pure function on purpose. Deciding *what a starting project is* is the
/// interesting and reviewable part of `goo create`; running `flutter create`
/// and writing bytes is not. Keeping them apart means the templates can be
/// tested - that they compile against the real API, that they name the right
/// package - on a machine with no Flutter SDK.
///
/// The pubspec is **not** here. `flutter create` writes one, and rewriting it
/// wholesale would discard whatever the installed Flutter version put in it;
/// the goo dependency is added by patching instead - see [patchedPubspecLines].
Map<String, String> scaffoldFiles({
  required String projectName,
  required String package,
  required String command,
}) {
  final className = _pascal(projectName);
  // `my_game` already ends in Game once pascalised, so appending would give
  // `MyGameGame` - the same doubling `_gameFile` avoids for the filename.
  final gameClass = _gameClass(className);
  return <String, String>{
    'lib/main.dart': _main(projectName, className, gameClass, package),
    'lib/game/${_gameFile(projectName)}.dart': _game(
      className,
      gameClass,
      package,
    ),
    'lib/game/scenes/main_scene.dart': _scene(package),
    'lib/game/prefabs/player.dart': _player(package),
    'assets/.gitkeep': _gitkeep(command),
    // Present from the start so the entry below resolves before anything has
    // been packed: Flutter refuses to build over an asset directory that does
    // not exist, and the first `goo build` is the worst moment to discover it.
    'assets/packed/.gitkeep': _packedGitkeep(),
  };
}

/// The lines a goo project needs in its pubspec, as something to show someone.
///
/// [patchedPubspecLines] applies this to a pubspec goo just had `flutter create`
/// write. This form is what gets printed when that is not possible - an
/// existing project under `--no-flutter-create`, or a pubspec whose shape the
/// patcher does not recognise. Editing someone's pubspec blind is not
/// something to do on their behalf.
String pubspecPatch(String package) =>
    '''
dependencies:
  $package: ^0.0.1

flutter:
  assets:
    - assets/
    - assets/packed/
''';

/// [lines] with the goo dependency and the asset entries added, or null if the
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
  // Already patched. `goo create --no-flutter-create` over a project that has
  // been through this before must not add the dependency twice.
  if (lines.any((line) => line.trimRight() == '  $package: ^0.0.1')) {
    return lines;
  }

  // Bottom-up, so the first insertion does not move the second's index.
  return List<String>.of(lines)
    ..insertAll(material + 1, <String>[
      '',
      '  # Both directories ship. `goo build` fills assets/packed/ and empties',
      '  # assets/ of what it packed, so each asset is bundled exactly once.',
      '  assets:',
      '    - assets/',
      '    - assets/packed/',
    ])
    ..insert(deps + 1, '  $package: ^0.0.1');
}

/// Why the packed directory exists in a fresh project with nothing in it.
String _packedGitkeep() => '''
# `goo build` writes its chunks here, and strips the loose copies out of
# ../ once they are inside one. Both directories are listed under
# `flutter: assets:`, which is what makes the chunks ship.
#
# Generated. Safe to delete; `goo build` writes it again.
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

String _main(
  String projectName,
  String className,
  String gameClass,
  String package,
) =>
    '''
import 'package:flutter/material.dart';
import 'package:$package/$package.dart';

import 'game/${_gameFile(projectName)}.dart';

void main() {
  // `ensureInitialized` before anything touches the engine: goo allocates
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
    return GameView(camera: game.defaultCamera);
  }
}
''';

String _game(String className, String gameClass, String package) =>
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

String _scene(String package) =>
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
    player = descriptor.has(Player());
  }

  @override
  void onSceneMounted(Scene scene) {
    scene.addEntity(player);
  }
}
''';

String _player(String package) =>
    '''
import 'package:$package/$package.dart';

/// One kind of entity, declared as the components it is made of.
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
///   texture = descriptor.has(Textures.yourAsset);  // from goo.generated
/// }
/// ```
///
/// Drop an image into `assets/`, list it under `flutter: assets:` in the
/// pubspec, and run `goo generate` to get the `Textures` enum.
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

String _gitkeep(String command) =>
    '''
# Drop images here, list them under `flutter: assets:` in pubspec.yaml, then
# run `$command`'s sibling: `goo generate`. That writes lib/goo.generated/,
# where each asset becomes a value of the `Textures` enum.
''';
