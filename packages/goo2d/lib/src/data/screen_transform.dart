import 'package:good/good.dart';

import 'package:goo2d/src/data/world_transform.dart';

/// Which point of the **view** a screen-space entity's origin sits on.
///
/// The fractions are view-space, so [fractionY] runs downwards while
/// `Transform2D`'s own offsets still run upwards - see [ScreenTransform2D]
/// for the arithmetic that puts those two together.
enum ScreenAnchor {
  topLeft(0, 0),
  topCenter(0.5, 0),
  topRight(1, 0),
  centerLeft(0, 0.5),
  center(0.5, 0.5),
  centerRight(1, 0.5),
  bottomLeft(0, 1),
  bottomCenter(0.5, 1),
  bottomRight(1, 1);

  const ScreenAnchor(this.fractionX, this.fractionY);

  /// `0` is the view's left edge, `1` its right.
  final double fractionX;

  /// `0` is the view's **top** edge, `1` its bottom. View space is y-down.
  final double fractionY;
}

/// What one of a screen-space sprite's two sizes means.
enum ScreenAxis {
  /// `Sprite.width`/`Sprite.height` is a length in view units - a viewport
  /// pixel. The same number at every view size.
  units,

  /// `Sprite.width`/`Sprite.height` is a fraction of the view's own width or
  /// height. `1` fills the view on that axis, `0.5` covers half of it, and
  /// the pixels come out different in a 400-pixel view and a 1920-pixel one.
  fraction,
}

/// Which side of the world a screen-space entity draws on.
///
/// Screen-space entities do not interleave with world sprites by `zIndex`;
/// they form a layer in front of the world or a layer behind it, and sort by
/// `zIndex` among themselves. A HUD that had to out-rank every world sprite
/// by z would need a `zIndex` above whatever the scene happens to use, and
/// `GameRenderer2D` buckets its whole queue over the range between the
/// smallest and largest z it sees - so one HUD element at `1 << 20` drops
/// every sprite in the frame onto the merge sort instead.
enum ScreenLayer {
  /// Drawn before every world sprite, so the world covers it. Backdrops.
  behind,

  /// Drawn after every world sprite and after every label, so nothing in the
  /// world covers it. Anything pinned to the view.
  front,
}

/// Places an entity relative to the **view** instead of relative to the
/// world: `Transform2D`'s offsets become view units measured from
/// [screenAnchor], the camera's zoom does not scale it, and the camera's
/// position does not move it.
///
/// ```dart
/// class Backdrop extends EntityStruct
///     with Transform2D, ScreenTransform2D, Renderable2D {
///   late final Sprite fill;
///
///   @override
///   ScreenLayer get screenLayer => ScreenLayer.behind;
///
///   @override
///   ScreenAxis get screenWidthAxis => ScreenAxis.fraction;
///
///   @override
///   ScreenAxis get screenHeightAxis => ScreenAxis.fraction;
///
///   @override
///   void describeSprites(SpriteDescriptor descriptor) {
///     super.describeSprites(descriptor);
///     fill = descriptor.has(texture: sky, width: 1, height: 1);
///   }
/// }
/// ```
///
/// # Nothing per view is stored in the row
///
/// Two views can show one scene at two sizes in the same tick, so there is no
/// single pixel width to keep anywhere. Every member here is an **overridable
/// getter and not a column**: it belongs to the entity's type, it is read
/// once per archetype per view, and `GameRenderer2D` turns it into pixels
/// inside its own per-view walk, where that view's size is already in scope.
/// The row grows by nothing at all, and one entity is correct in a 400-pixel
/// minimap and a 1920-pixel main view in the same tick.
///
/// The cost of that is the other half of the same fact: an entity cannot
/// change its own anchor, layer or sizing mode at run time. Its offsets,
/// scale, rotation and every `Sprite` field still move - what is fixed is
/// which corner it measures from, and whether a width is a fraction or a
/// pixel count. Two anchors means two prefabs.
///
/// # Where a screen-space entity lands
///
/// ```text
/// viewX = anchor.fractionX * viewWidth  + transformOffsetX
/// viewY = anchor.fractionY * viewHeight - transformOffsetY
/// ```
///
/// `+y` is up, as everywhere else in the engine, which is where the second
/// minus sign comes from. [ScreenAnchor.center] with no offsets is the middle
/// of the view.
///
/// A view that has not been laid out reports a size of zero, so every anchor
/// collapses onto the view's top-left corner and the offsets read straight
/// out as view coordinates. That is what a headless run and the first tick of
/// a real game both see.
///
/// # Zoom and the camera are both out
///
/// The camera's zoom scales world content and is not applied here; neither is
/// the camera's position. A HUD that shrank when the player zoomed out is the
/// thing this component exists to avoid, and it is why parenting to the
/// camera entity is not the same feature.
///
/// # It replaces `WorldTransform2D`, it does not join it
///
/// A prefab mixing both trips a debug-only `assert`. The two answer one
/// question - what does this entity's offset mean - with two answers, and
/// there is no composition that reconciles them: an ancestor's offset is
/// world units, this entity's is view units, and a parent and a child
/// anchored to two different corners share no origin to compose through.
/// Group screen-space art with several `Sprite`s on one entity, which is what
/// `Renderable2D` being a `MultiComponent` is for.
///
/// `Text2D` is refused as well, for a different reason: there is no
/// screen-space text. A score in the corner is a Flutter widget over the
/// `GameView`, which has layout, accessibility and hot reload.
mixin ScreenTransform2D on Component {
  /// Which point of the view this entity's offsets are measured from.
  /// Defaults to the middle, which is where a world entity standing on the
  /// camera's own position draws.
  ScreenAnchor get screenAnchor => ScreenAnchor.center;

  /// Whether this entity draws in front of the world or behind it.
  ScreenLayer get screenLayer => ScreenLayer.front;

  /// What every one of this entity's `Sprite.width` values means.
  ScreenAxis get screenWidthAxis => ScreenAxis.units;

  /// What every one of this entity's `Sprite.height` values means.
  ScreenAxis get screenHeightAxis => ScreenAxis.units;

  // Registering the type is what sets this component's bit in the archetype
  // signature, and therefore the only reason `withAll(ScreenTransform2D)`
  // matches anything and `withNone(ScreenTransform2D)` excludes anything.
  // Without it the renderer's world query would forbid a bit no archetype
  // ever sets, and its screen query would match every archetype in the game.
  @override
  void describeType(ComponentDescriptor component) {
    super.describeType(component);
    // Asking what else this prefab mixes in, once, at declare time. Nothing
    // downstream branches on the answer - it is a validity check, and the
    // combination it rejects is silently wrong rather than loudly wrong if it
    // is allowed through: the renderer would read composed world coordinates
    // as view offsets and put the art somewhere plausible and incorrect.
    assert(
      this is! WorldTransform2D,
      '$runtimeType mixes in both ScreenTransform2D and WorldTransform2D. '
      'They mean two different things by an entity offset - view units from '
      'an anchor, and world units composed with every ancestor - and only one '
      'of them can be true. Drop WorldTransform2D and put the parts that move '
      'together on one entity as several Sprites, or drop ScreenTransform2D '
      'and place the entity in the world.',
    );
    component.has<ScreenTransform2D>();
  }
}
