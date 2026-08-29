/// The 2D good engine: everything needed to build a 2D game.
///
/// **One dependency, one import.** Adding `goo2d` to a pubspec and importing
/// this library gives you the whole engine - the kernel (ECS, scenes, the
/// tick loop, `Game`/`GameState`, `GameView`) *and* the 2D layer (transforms,
/// camera, colliders, rendering). The kernel is re-exported below, so it is
/// not a second dependency you add and keep version-matched by hand.
///
/// Opt-in packages stay separate, because they carry weight not every game
/// wants: `goo2d_physics_box2d` (native Box2D) and `good_net`/`good_net_p2p`
/// (networking). Those you add explicitly and declare their systems yourself.
library;

export 'package:good/good.dart';

export 'src/data/camera.dart';
export 'src/data/collider.dart';
export 'src/data/transform.dart';
export 'src/input/mouse.dart';
export 'src/data/world_transform.dart';
export 'src/render/debug_draw_2d.dart';
export 'src/render/draw/draw_2d.dart';
export 'src/render/render_2d.dart';
export 'src/render/text_2d.dart';
export 'src/render/game_2d.dart';
export 'src/render/texture.dart';
export 'src/render/sprite_widget.dart';
