/// The primary entry point for the Goo2D game engine.
///
/// This barrel file centralizes all public APIs of the Goo2D engine, allowing
/// developers to import a single library to access the complete feature set.
/// It simplifies dependency management and ensures that internal implementation
/// details remain hidden while exposing stable interfaces.
///
/// Developers should import this file using `import 'package:goo2d/goo2d.dart';`.
/// The library exports essential modules including [Game], [GameObject],
/// [Component], and the physics systems. Selective hiding is used to prevent
/// name collisions with internal render objects or private providers.
///
/// ```dart
/// import 'package:goo2d/goo2d.dart';
///
/// void main() async {
///   WidgetsFlutterBinding.ensureInitialized();
///   final engine = await GameEngine.create();
///   runApp(Game(engine: engine, child: MyWorld()));
/// }
/// ```
library;

export 'src/game.dart' hide GameProvider;
export 'src/event.dart';
export 'src/component.dart';
export 'src/object.dart' hide tagRegistry;
export 'src/element.dart' hide GameObjectElement;
export 'src/widget.dart';
export 'src/render.dart' hide GameRenderObject, GameParentData;
export 'src/pointer.dart';
export 'src/transform.dart';
export 'src/physics/physics.dart';
export 'src/physics/physics_system.dart';
export 'src/collision/collision.dart';
export 'src/rpc/buffer.dart';
export 'src/rpc/parser.dart';
export 'src/rpc/parsers.dart';
export 'src/rpc/registry.dart';
export 'src/rpc/rpc.dart';
export 'src/camera.dart';
export 'src/metrics/fps.dart';
export 'src/ticker.dart'
    hide GameLoop, GameRenderer, RenderGameLoop, RenderGameRenderer;
export 'src/camera_view.dart' hide RenderCameraView;
export 'src/lifecycle.dart';
export 'src/screen.dart';
export 'src/input.dart';
export 'src/asset.dart';
export 'src/coroutine.dart' hide CoroutineFuture, CoroutineInternal;
export 'src/point.dart';
export 'src/sprite.dart';
export 'src/sprite_mesh.dart';
export 'src/sprite_pivot.dart';
export 'src/sprite_fit.dart';
export 'src/tile_renderer.dart';
export 'src/utility.dart';
export 'src/audio.dart';
export 'src/world.dart' hide RenderWorldSpace;
export 'src/data/component.dart'
    hide entityDataAssignBitmask, entityDataGetBitmask;
export 'src/data/object.dart';
export 'src/data/system.dart';
export 'src/data/world.dart';
export 'src/data/transform/data.dart';
export 'src/data/physics/component.dart';
export 'src/data/physics/system.dart';
export 'src/transitions/transition.dart';
export 'src/transitions/layer.dart';
export 'src/route.dart';
export 'src/painter.dart';
export 'src/clipper.dart';
export 'src/texture_group.dart';
export 'src/used_textures.dart';
export 'src/data/renderer/buffer_manager.dart';

// bundled
export 'package:vector_math/vector_math_64.dart' hide Colors;

import 'package:vector_math/vector_math_64.dart' as vector_math_64;

typedef ColorUtils = vector_math_64.Colors;
