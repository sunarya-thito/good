import 'package:good/good.dart';
import 'package:meta/meta.dart';

import 'package:goo3d/src/data/world_transform.dart';

/// A [Game] in three dimensions. Extend this instead of `Game` and a 3D game
/// starts with the two declarations every 3D game needs.
///
/// ```dart
/// class MyGame extends Game3D {
///   @override
///   MyGameState createState() => MyGameState();
/// }
///
/// class MyGameState extends GameState3D<MyGame> {
///   @override
///   void onMounted() => loadScene(Level());
/// }
/// ```
///
/// That is the whole opt-in. [View3D] declares the camera view the game is
/// shown in, and [Composition3DState] declares `WorldTransform3DSystem`, so
/// neither is a line a project has to carry and neither is a line a project
/// can forget.
///
/// # There is no renderer behind this
///
/// [buildView] is not overridden here, so a `GameView` showing a `Game3D`
/// paints nothing - the same as `Game` itself. `goo3d` has transforms,
/// hierarchy composition and the camera and no draw path; the renderer is
/// issue #43. What this class removes is the ceremony, not the gap.
///
/// A 3D game therefore still simulates: the scene loads, the tick runs, and
/// world transforms compose. Show something on screen by stacking Flutter
/// widgets over the `GameView`, driven off a channel the game publishes.
///
/// # Why a superclass and not a declared system
///
/// The same split `Game2D` makes. A system is wholly a game-isolate thing, and
/// the one object that lives where Flutter does is `Game` - so a camera view,
/// whose storage is reserved on main before the spawn, is declared on the
/// `Game`, and the composition system is declared on the `GameState` where
/// systems live.
abstract class Game3D extends Game with View3D {
  /// Narrowed to [GameState3D], and that narrowing is the whole reason a 3D
  /// game cannot end up without hierarchy composition.
  ///
  /// `WorldTransform3DSystem` is what turns a child's local `Transform3D` into
  /// its `WorldTransform3D` once per fixed tick. A game missing it does not
  /// fail: every parented entity simply keeps the world transform it was
  /// spawned with, forever, and nothing anywhere says so. Returning a plain
  /// `GameState` here is a **compile error** instead.
  @override
  GameState3D createState();
}

/// The simulation half of [Game3D] - declares the system 3D hierarchy
/// composition cannot work without.
///
/// A game with its own state hierarchy mixes in [Composition3DState] instead;
/// this class is that mixin applied to the plain base, which is what almost
/// every game wants.
abstract class GameState3D<G extends Game3D> extends GameState<G>
    with Composition3DState<G> {}

/// Declares `WorldTransform3DSystem`, for a state whose base class is already
/// something else.
mixin Composition3DState<G extends Game> on GameState<G> {
  /// Composes every `WorldTransform3D` from its local `Transform3D` and its
  /// parent's, once per fixed tick.
  ///
  /// A field and not a `describeSystems` line, because a declaration in this
  /// engine is a field holding its own value - the generated collector for
  /// whichever concrete state applies this mixin reads it back off.
  ///
  /// A scene with no `WorldTransform3D` in it pays nothing for the system
  /// being here: its query matches no archetype and its fixed tick walks an
  /// empty set.
  @system
  final worldTransform = WorldTransform3DSystem();
}

/// Declares the camera view a [Game3D] is drawn into, for a game whose base
/// class is already something else.
///
/// One view, at address 0, named [defaultCamera] - the same name and the same
/// address `goo2d`'s `Renderer2D` declares, so the two dimensions spell the
/// zero-configuration case identically.
mixin View3D on Game {
  /// The view a 3D game is shown in when it declares none of its own.
  ///
  /// A view is a place a game is drawn, declared at boot because whatever
  /// draws it reserves its storage before the simulation isolate is spawned.
  /// It is what a camera entity is pointed at:
  ///
  /// ```dart
  /// eye.cameraView[entity] = game.defaultCamera;
  /// ```
  ///
  /// Declared for the reason [Composition3DState] declares the system:
  /// `extends Game3D` is meant to be the whole opt-in, and a game that had to
  /// remember a second declaration before a camera had anywhere to point would
  /// be carrying the ceremony this class exists to remove.
  ///
  /// A game wanting several views declares them itself and calls
  /// `super.describeCameras(descriptor)` first, so this one keeps address 0.
  late final CameraView defaultCamera;

  @override
  @mustCallSuper
  void describeCameras(CameraDescriptor descriptor) {
    super.describeCameras(descriptor);
    defaultCamera = descriptor.has();
  }
}
