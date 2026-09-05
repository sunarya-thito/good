/// What every generated page library imports.
///
/// Two jobs. It re-exports the engine, so a snippet gets the same names a reader
/// would get from `import 'package:goo2d/goo2d.dart'`. And it declares the
/// handful of identifiers the prose uses without ever introducing — `entity`,
/// `game`, `scene`, `descriptor` — so a two-line fragment about one API does not
/// have to grow a page of setup around it to compile.
///
/// **Nothing here may be `dynamic`.** A `dynamic` ambient would make every
/// member access on it legal, and the check would pass over exactly the renames
/// it exists to catch. `avoid_dynamic_calls` is an error in analysis_options for
/// the same reason.
library;

export 'dart:async';
export 'dart:math';
export 'dart:typed_data';

export 'package:flutter/material.dart' hide Texture, Transform, Image;
// The audio backend is a package of its own, so a page teaching
// `createAudioBackend` names a type the engine re-exports nothing of.
export 'package:good_audio_soloud/good_audio_soloud.dart';
export 'package:good_net/good_net.dart';
export 'package:good_net_p2p/good_net_p2p.dart';
// goo2d and goo3d both re-export `package:good`. That is not an ambiguity —
// they re-export the *same* declarations — so the kernel comes in once and both
// dimension layers sit on top of it.
export 'package:goo2d/goo2d.dart';
export 'package:goo2d_physics_box2d/goo2d_physics_box2d.dart';
export 'package:goo3d/goo3d.dart';

import 'package:goo2d/goo2d.dart';

/// A stand-in for something a fragment is handed by the code around it.
///
/// `final descriptor = given<ColliderDescriptor>();` in a
/// `<!-- snippet-setup -->`
/// block gives the fence a correctly typed local without a page of
/// construction. Typed and never `dynamic`, so the call inside the fence is
/// still checked against the real class.
T given<T>() => throw UnimplementedError();

/// The entity a fragment is talking about. Row 0 of nothing in particular; the
/// snippets only ever index columns with it.
Entity get entity => const Entity(0);

/// A second one, for the fragments that need two.
Entity get otherEntity => const Entity(1);

/// Free identifiers the prose uses for "some entity you have".
Entity get playerEntity => const Entity(2);
Entity get orcEntity => const Entity(3);
Entity get hubEntity => const Entity(4);
Entity get parentEntity => const Entity(5);
Entity get childEntity => const Entity(6);
Entity get target => const Entity(7);
Entity get turretEntity => const Entity(8);

/// The scene a fragment spawns into. `SceneStruct` has one of these and so does
/// every entity, so the prose writes `scene.addEntity(...)` without saying which
/// of the two it came from.
Scene get scene => const Scene(0);

/// `query`, `group` and `entity` are the three loop variables of the walk every
/// guide page shows. A fragment that starts partway into it gets them here.
Query get query => throw UnimplementedError();
QueryGroup get group => throw UnimplementedError();

/// Wall-clock deltas the prose uses bare.
double get dt => 1 / 60;
double get fixedDelta => 1 / 60;

// ---------------------------------------------------------------------------
// The cast.
//
// A `Player`, an `Enemy`, an `Eye` and a `MyGame` turn up on a dozen pages, and
// most of those pages are about something else and only borrow the name. These
// are the borrowed versions. A page that declares its own shadows the one here
// — a declaration in the library beats a name from an import — so a page
// teaching what a `Player` looks like still checks its own.
// ---------------------------------------------------------------------------

enum Textures with LocalEnumAssetKey<Texture> {
  spritesPlayer('assets/sprites/player.webp', 512, 512),
  uiButton('assets/ui/button.webp', 64, 64),
  worldTileset('assets/world/tileset.webp', 256, 256),
  worldGrass('assets/world/grass.webp', 32, 32);

  const Textures(this.path, this.width, this.height);

  @override
  final String path;

  final int width;

  final int height;
}

// The sizes again, as constants. `good generate` emits both forms because they
// are not interchangeable: field access on an enum value is never a constant
// expression, so only these can appear in a `static const List<SpriteFrame>`.
abstract final class TextureSize {
  static const int spritesPlayerWidth = 512;
  static const int spritesPlayerHeight = 512;
  static const int uiButtonWidth = 64;
  static const int uiButtonHeight = 64;
  static const int worldTilesetWidth = 256;
  static const int worldTilesetHeight = 256;
  static const int worldGrassWidth = 32;
  static const int worldGrassHeight = 32;
}

enum Audios with LocalEnumAssetKey<AudioClip> {
  musicTheme('assets/audio/theme.ogg');

  const Audios(this.path);

  @override
  final String path;
}

class Player extends EntityStruct
    with Transform2D, WorldTransform2D, Renderable2D, Collider2D {
  final texture = Asset.of(Textures.spritesPlayer);
  final sprite = Sprite.of(
    texture: Textures.spritesPlayer,
    width: 64,
    height: 64,
  );
  late final CircleBody hitbox;
  final speed = Field.float64(120);
  final shielded = Field.boolean();

  @override
  void describeCollider(ColliderDescriptor descriptor) {
    super.describeCollider(descriptor);
    hitbox = descriptor.hasCircleCollider(radius: 0.5);
  }
}

class Enemy() extends EntityStruct
    with Transform2D, WorldTransform2D, Renderable2D;

class Eye() extends EntityStruct with Transform2D, WorldTransform2D, Camera;

class MyGame extends Game2D {
  /// The two state channels the guide publishes to. A page that teaches
  /// `describeState` declares its own and shadows this one.
  late final StateChannel<int> score;
  late final StateChannel<int> contactCount;

  @override
  MyState createState() => MyState();

  @override
  void describeState(StateDescriptor descriptor) {
    super.describeState(descriptor);
    score = descriptor.hasInt32();
    contactCount = descriptor.hasInt32();
  }
}

class MyState extends GameState2D<MyGame> {
  int score = 0;
}
