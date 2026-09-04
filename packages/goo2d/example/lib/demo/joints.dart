import 'package:goo2d/goo2d.dart';
import 'package:goo2d_physics_box2d/goo2d_physics_box2d.dart';

import 'package:goo2d_example/demo/demo.dart';
import 'package:goo2d_example/demo/demo_game.dart';
import 'package:goo2d_example/demo/textures.dart';

/// Box2D joints, made visible.
///
/// Three things a joint is actually for, side by side:
///
///  * **chains** - a run of links on distance joints, hanging and swinging;
///  * **a driven wheel** - a revolute joint with a motor, which is how every
///    vehicle and every rotating platform is built;
///  * **a breakable chain** - Box2D has no notion of breaking, so this reads
///    each joint's constraint force and destroys it past a threshold. The
///    right-hand chain carries a heavy weight, snaps somewhere along its
///    length, drops what was below the break, and is hung again a moment
///    later so the whole thing repeats.
///
/// # The two-tick rule this case exists to demonstrate
///
/// Spawning an entity on tick N publishes its transform at the end of N; the
/// physics system reads that and creates the Box2D body during N+1; and the
/// `bodyHandle` it writes is only published at the end of N+1. So **N+2 is
/// the first tick on which a joint can be made**, and this case waits exactly
/// that long before stitching a chain together.
///
/// Getting it wrong by one is the interesting part, because it *appears* to
/// work: a read on a page that has never published falls through to the write
/// slot and sees the fresh handle anyway. The first chain therefore hangs
/// perfectly, and every chain rebuilt afterwards - on recycled rows, where
/// the fall-through no longer applies - silently gets no joints and drops in
/// a shower of loose links. This case builds and rebuilds chains constantly,
/// which is what makes it a test of that rule rather than a decoration.

/// World units are metres, as in the physics case. The camera's zoom is the
/// only thing that converts to pixels.
const double _linkHalfWidth = 0.18;
const double _linkHalfHeight = 0.45;

/// Vertical spacing between link centres. Slightly more than a link's height
/// so neighbours do not start overlapping - a chain born inside itself spends
/// its first second exploding rather than hanging.
const double _linkSpacing = 1.0;

const int _linksPerChain = 9;

/// Where each chain is anchored, in metres. **Positive y is up** - goo2d's
/// world +y is up, so the anchors are at the top of the view.
const double _anchorY = 11.0;

const int _anchorColor = 0xFF546E7A;
const int _linkColor = 0xFF90A4AE;
const int _weightColor = 0xFFEF5350;
const int _wheelColor = 0xFF42A5F5;
const int _spokeColor = 0xFF1E88E5;

/// A fixed point for a chain or an axle to hang from. Static, so Box2D never
/// integrates it and treats it as infinite mass.
class Anchor extends EntityStruct
    with Transform2D, Renderable2D, Collider2D, RigidBody2D {
  late final Sprite body;
  late final BoxBody box;

  @override
  void describeSprites(SpriteDescriptor descriptor) {
    super.describeSprites(descriptor);
    body = descriptor.has(width: 1.2, height: 0.4, color: _anchorColor);
  }

  @override
  void describeCollider(ColliderDescriptor descriptor) {
    super.describeCollider(descriptor);
    // Layer 1, excluded by everything else below: an anchor is scenery, and a
    // chain that collides with its own anchor jitters against it forever.
    box = descriptor.hasBoxCollider(
      halfWidth: 0.6,
      halfHeight: 0.2,
      layer: 1,
      excludeLayers: -1,
    );
  }

  @override
  void describeStruct(DataDescriptor data) {
    super.describeStruct(data);
    bodyType.initialValue = BodyType2D.staticBody;
  }
}

/// One link of a chain.
class Link extends EntityStruct
    with Transform2D, Renderable2D, Collider2D, RigidBody2D {
  late final Sprite body;
  late final BoxBody box;

  @override
  void describeSprites(SpriteDescriptor descriptor) {
    super.describeSprites(descriptor);
    body = descriptor.has(
      width: _linkHalfWidth * 2,
      height: _linkHalfHeight * 2,
      color: _linkColor,
    );
  }

  @override
  void describeCollider(ColliderDescriptor descriptor) {
    super.describeCollider(descriptor);
    // Layer 2, colliding with nothing: links are held together by joints, and
    // letting neighbours collide as well makes a chain buzz rather than hang.
    // That is the standard way to build a rope in Box2D, not a shortcut.
    box = descriptor.hasBoxCollider(
      halfWidth: _linkHalfWidth,
      halfHeight: _linkHalfHeight,
      layer: 2,
      excludeLayers: -1,
    );
  }
}

/// A heavy mass on the end of a chain, so the breakable one has something to
/// break under.
class Weight extends EntityStruct
    with Transform2D, Renderable2D, Collider2D, RigidBody2D {
  late final Sprite body;
  late final BoxBody box;

  @override
  void describeSprites(SpriteDescriptor descriptor) {
    super.describeSprites(descriptor);
    body = descriptor.has(width: 1.6, height: 1.6, color: _weightColor);
  }

  @override
  void describeCollider(ColliderDescriptor descriptor) {
    super.describeCollider(descriptor);
    // Density 12 against the links' default 1 - the whole point of this one
    // is to load the chain above it hard enough to tear.
    box = descriptor.hasBoxCollider(
      halfWidth: 0.8,
      halfHeight: 0.8,
      density: 12,
      layer: 2,
      excludeLayers: -1,
    );
  }
}

/// A motorised wheel, pinned to a static hub by a revolute joint.
class Wheel extends EntityStruct
    with Transform2D, Renderable2D, Collider2D, RigidBody2D {
  late final Sprite body;
  late final Sprite spoke;
  late final CircleBody circle;
  final disc = Asset.of(discTexture);


  @override
  void describeSprites(SpriteDescriptor descriptor) {
    super.describeSprites(descriptor);
    // **Textured, because a sprite is a quad.** goo2d draws rectangles; the
    // collider below is a *circle*, and an untextured square sprite over it
    // means the picture disagrees with the physics. Nothing collides with
    // this wheel today so the lie costs nothing yet - which is exactly how
    // that class of bug survives until the day something does.
    body = descriptor.has(
      texture: disc,
      width: 3.4,
      height: 3.4,
      color: _wheelColor,
    );
    // A second sprite on the same entity, pivoted at its **bottom edge** so
    // it reads as one spoke from hub to rim rather than a bar across the
    // whole wheel.
    //
    // That is not decoration. A plain disc spinning about its centre looks
    // completely static, and a full diameter bar looks identical every half
    // turn - so it appears to flicker between two positions and gives no
    // sense of direction. A single spoke is the smallest thing that shows
    // both that the wheel turns and which way.
    spoke = descriptor.has(
      width: 0.35,
      height: 1.7,
      color: _spokeColor,
      zIndex: 1,
      pivot: const RelativeOffset2D(fractionX: 0.5, fractionY: 1),
    );
  }

  @override
  void describeCollider(ColliderDescriptor descriptor) {
    super.describeCollider(descriptor);
    circle = descriptor.hasCircleCollider(radius: 1.7, layer: 3);
  }
}

class Eye extends EntityStruct with Transform2D, WorldTransform2D, Camera {}

class JointScene extends SceneStruct {
  late Scene handle;

  @sub
  final anchor = Anchor();
  @sub
  final link = Link();
  @sub
  final weight = Weight();
  @sub
  final wheel = Wheel();
  @sub
  final eye = Eye();

  /// The three chains, top link first, so [JointSystem] can stitch each run
  /// together once their bodies exist.
  final List<List<Entity>> chains = <List<Entity>>[];

  /// The anchor each chain hangs from, in the same order.
  final List<Entity> anchors = <Entity>[];

  /// The wheel and the hub it turns on.
  late Entity wheelEntity;
  late Entity hubEntity;

  late Entity camera;


  @override
  void onSceneMounted(Scene scene) {
    handle = scene;

    camera = scene.addEntity(eye);
    // Binding the camera to a view is what makes `zoom` mean anything. Without
    // it `ActiveCameraResolver` finds no camera, the renderer falls back to an
    // implicit one at the origin with zoom 1, and the whole scene draws about
    // 30 px across.
    eye
      ..cameraView[camera] = (game as Game2D).defaultCamera
      ..cameraZoom[camera] = 24;

    // Three chains: two plain, one carrying a weight and set to break.
    for (var i = 0; i < 3; i++) {
      final top = scene.addEntity(anchor);
      // **Written after `addEntity`, which is now correct.** It was not
      // before: the physics system used to create a body during the spawn
      // event, reading a transform that had not been published yet, so a
      // position set here arrived too late and the body was born at the
      // origin. Bodies are created on the *next* fixed step now, by which
      // time this write has been published.
      anchor.transformOffsetX[top] = chainX(i);
      anchor.transformOffsetY[top] = _anchorY;
      anchors.add(top);

      chains.add(spawnChain(i, loaded: i == 2));
    }

    // The driven wheel, off to the right.
    hubEntity = scene.addEntity(anchor);
    anchor.transformOffsetX[hubEntity] = 12;
    anchor.transformOffsetY[hubEntity] = 0;

    wheelEntity = scene.addEntity(wheel);
    wheel.transformOffsetX[wheelEntity] = 12;
    wheel.transformOffsetY[wheelEntity] = 0;
  }

  /// Where chain [i] hangs.
  static double chainX(int i) => (i - 1) * 7.0 - 4.0;

  /// Spawns one chain's links, top first, optionally with a weight on the end.
  ///
  /// Shared by the initial build and by [respawnLoadedChain], so a rebuilt
  /// chain is the same chain rather than a second description of one that has
  /// to be kept in step by hand (the one-fact-one-place rule).
  List<Entity> spawnChain(int i, {required bool loaded}) {
    final x = chainX(i);
    final chain = <Entity>[];
    for (var j = 0; j < _linksPerChain; j++) {
      final entity = handle.addEntity(link);
      link.transformOffsetX[entity] = x;
      link.transformOffsetY[entity] = _anchorY - (j + 1) * _linkSpacing;
      chain.add(entity);
    }
    if (loaded) {
      final mass = handle.addEntity(weight);
      weight.transformOffsetX[mass] = x;
      weight.transformOffsetY[mass] =
          _anchorY - (_linksPerChain + 1) * _linkSpacing;
      chain.add(mass);
    }
    return chain;
  }

  /// Throws away what is left of the weighted chain and hangs a fresh one, so
  /// the tearing repeats instead of being a thing you had to be watching for
  /// the first four seconds to see.
  void respawnLoadedChain() {
    for (final entity in chains.last) {
      entity.destroy();
    }
    chains[chains.length - 1] = spawnChain(chains.length - 1, loaded: true);
  }
}

/// Builds the joints once their bodies exist, drives the motor, and breaks
/// the loaded chain.
class JointSystem extends GameSystem with FixedTickable {
  /// After the physics system, so a force read here describes the step that
  /// has just been solved rather than the one before it.
  @override
  int compareTo(GameSystem other) => other is Box2DPhysicsSystem ? 1 : 0;

  /// Every joint in the loaded chain, so it can be checked for breaking.
  final List<Joint> _breakable = <Joint>[];

  bool _built = false;

  /// Force, in newtons, past which a link in the loaded chain lets go.
  ///
  /// Box2D has **no breaking of its own** - a joint holds until something
  /// destroys it. This is the whole mechanism: read the constraint force each
  /// tick, compare, destroy. Tuned so the chain survives a moment and then
  /// gives way, because a rope that snaps on frame one shows nothing.
  static const double _breakForce = 260.0;

  @override
  void onFixedUpdate() {
    final demo = getState<JointState>();
    final scene = demo.sandbox;
    final physics = state.getSystem<Box2DPhysicsSystem>();

    // **Two ticks after a spawn, not one.** Spawning publishes the entity's
    // transform at the end of tick N; the physics system creates its body and
    // writes `bodyHandle` during N+1; and that write is only *published* at
    // the end of N+1. `createDistanceJoint` reads the handle through an
    // ordinary component read, which serves the published snapshot - so at
    // N+1 it still reads 0 and quietly makes no joint.
    //
    // The initial build appeared to work at N+1 anyway, and that is the trap:
    // on a page that has never published, a read falls through to the write
    // slot and happens to see the fresh handle. The moment rows are recycled
    // - which is every rehang below - the fall-through stops and the same
    // code silently produces a chain of unconnected links in free fall.
    if (_joinIn > 0 && --_joinIn == 0) {
      if (!_built) {
        _build(scene, physics);
        _built = true;
      } else {
        _stitchLoadedChain(scene, physics);
      }
      return;
    }
    if (!_built) return;

    _breakOverloaded(physics, demo);

    // Rehang the chain once it has finished tearing, so the case is not a
    // one-shot that anyone arriving after the first few seconds misses.
    //
    // **The trigger is "tearing has stopped", not "every joint broke".** A
    // chain gives way at its most loaded link and everything below that point
    // drops away *still jointed to itself* - those joints now carry nothing
    // and never reach the threshold. Waiting for all of them was waiting for
    // something that does not happen, and the case rebuilt exactly never.
    if (demo.broken > _brokenSeen) {
      _brokenSeen = demo.broken;
      _sinceLastBreak = 0;
    } else if (_sinceLastBreak >= 0 && ++_sinceLastBreak >= _rebuildDelay) {
      _sinceLastBreak = -1;
      _breakable.clear();
      scene.respawnLoadedChain();
      _joinIn = _joinDelay;
      demo.rehangs++;
    }
  }

  /// Ticks to wait after the last joint breaks before hanging a new chain -
  /// long enough for the pieces to fall clear, short enough to be worth
  /// waiting for.
  static const int _rebuildDelay = 100;

  /// Ticks since the last joint gave way, or -1 when nothing has broken since
  /// the current chain was hung.
  int _sinceLastBreak = -1;

  /// The break count already accounted for, so a *new* break restarts the
  /// wait rather than each tick counting as one.
  int _brokenSeen = 0;

  /// Fixed steps until the freshly spawned chain can be jointed - see the
  /// note in [onFixedUpdate] on why it is two and not one.
  int _joinIn = _joinDelay;

  static const int _joinDelay = 2;

  /// Joints the freshly respawned weighted chain, exactly as [_build] does for
  /// the original.
  void _stitchLoadedChain(JointScene scene, Box2DPhysicsSystem physics) {
    final index = scene.chains.length - 1;
    _breakable
      ..clear()
      ..addAll(_breakableOf(_stitch(scene, physics, index)));
  }

  void _build(JointScene scene, Box2DPhysicsSystem physics) {
    for (var i = 0; i < scene.chains.length; i++) {
      final joints = _stitch(scene, physics, i);
      if (i == scene.chains.length - 1) _breakable.addAll(_breakableOf(joints));
    }

    // The wheel: pinned to its hub and driven. `maxMotorTorque` is what makes
    // a motor real - a motor with none of it is a motor that cannot move
    // anything, which looks exactly like the joint not working.
    physics.createRevoluteJoint(
      scene.hubEntity,
      scene.wheelEntity,
      enableMotor: true,
      motorSpeed: 2.5,
      maxMotorTorque: 900,
    );

    _swing(scene, physics);
  }

  /// The joints of a chain that are allowed to break: **everything except the
  /// one holding it to its anchor**, which is [_stitch]'s first.
  ///
  /// The anchor joint carries the whole chain plus the weight, so it is always
  /// the most loaded and always fails first - correct physics, and it reads on
  /// screen as the rope being *unhooked* rather than breaking: the entire
  /// thing drops away in one piece. Holding the hook and letting the chain be
  /// what fails puts the break in the middle, where it looks like a break.
  ///
  /// This is a statement about the scene, not a workaround: hooks are stronger
  /// than the rope hanging off them.
  Iterable<Joint> _breakableOf(List<Joint> joints) => joints.skip(1);

  /// Joints chain [i] to its anchor and to itself, returning every joint made.
  ///
  /// Anchors are in **body-local** space: the bottom of the upper body to the
  /// top of the lower one, which is what makes a chain read as a chain rather
  /// than a row of bodies all sharing one point.
  List<Joint> _stitch(JointScene scene, Box2DPhysicsSystem physics, int i) {
    final chain = scene.chains[i];
    final joints = <Joint>[
      physics.createDistanceJoint(
        scene.anchors[i],
        chain.first,
        anchorAY: -0.2,
        anchorBY: _linkHalfHeight,
        length: _linkSpacing - _linkHalfHeight,
      ),
    ];
    for (var j = 1; j < chain.length; j++) {
      joints.add(
        physics.createDistanceJoint(
          chain[j - 1],
          chain[j],
          anchorAY: -_linkHalfHeight,
          anchorBY: _linkHalfHeight,
          length: _linkSpacing - _linkHalfHeight * 2,
        ),
      );
    }
    return joints;
  }

  /// Shoves the two unloaded chains sideways so they swing.
  ///
  /// **Without this the case looks broken.** A chain built hanging straight
  /// down is already in equilibrium, so it simply stands there - correct
  /// physics, and completely indistinguishable from a chain that is not
  /// simulating at all. The first version of this case shipped like that and
  /// the honest reaction to it was "what am I supposed to be looking at".
  ///
  /// An impulse on the bottom link only: the joints carry it up the chain,
  /// which is itself the thing worth seeing.
  void _swing(JointScene scene, Box2DPhysicsSystem physics) {
    for (var i = 0; i < scene.chains.length - 1; i++) {
      final bottom = scene.chains[i].last;
      // Opposite directions, so the two chains are visibly independent rather
      // than looking like one animation applied twice.
      scene.link.applyImpulse(bottom, i.isEven ? 9 : -9, 0);
    }
  }

  /// Destroys any joint in the loaded chain that is carrying more than
  /// [_breakForce], which is how a breakable joint is built on top of Box2D.
  void _breakOverloaded(Box2DPhysicsSystem physics, JointState demo) {
    var worst = 0.0;
    for (var i = 0; i < _breakable.length; i++) {
      final joint = _breakable[i];
      if (!joint.exists) continue;

      joint.readReaction();
      final fx = Joint.forceX;
      final fy = Joint.forceY;
      final force = fx.abs() + fy.abs();
      if (force > worst) worst = force;

      if (force > _breakForce) {
        joint.destroy();
        _breakable[i] = Joint.none;
        demo.broken++;
      }
    }
    // **The largest force ever seen, not this tick's.** A live reading falls
    // back to zero the moment the last joint lets go, so the number the
    // overlay shows would be 0 exactly when the interesting thing had just
    // finished happening - and a test sampling it at the end would read 0 and
    // conclude no force was ever measured. Which is what the first version of
    // both did.
    if (worst > demo.peakForce) demo.peakForce = worst;
    demo.intact = _breakable.where((joint) => joint != Joint.none).length;
  }
}

class JointState extends DemoState<JointGame> {
  final JointScene sandbox = JointScene();

  /// Joints in the loaded chain that are still holding, and how many have
  /// given way. Published so the overlay shows the breaking as a number and
  /// not only as a rope falling off the screen.
  int intact = 0;
  int broken = 0;
  double peakForce = 0;

  /// How many times the weighted chain has been torn down and hung again.
  ///
  /// Its own counter rather than something inferred from [broken], because a
  /// chain gives way at one link rather than everywhere - so "more joints
  /// broke than a chain contains" is not the signal it looks like, and a test
  /// built on that reasoning failed against perfectly working code.
  int rehangs = 0;

  @override
  void onMounted() => loadScene(sandbox);

  @override
  void describeSystems(SystemDescriptor descriptor) {
    super.describeSystems(descriptor);
    descriptor.has(Box2DPhysicsSystem.new);
    descriptor.has(JointSystem.new);
    descriptor.has(_JointStats.new);
  }
}

/// Publishes this case's own numbers, after the fixed step - the same shape
/// and the same reasoning as `DemoStats`.
class _JointStats extends GameSystem with Tickable {
  @override
  void onTick(Duration delta) {
    final demo = getState<JointState>();
    getGame<JointGame>()
      ..intactJoints.value = demo.intact
      ..brokenJoints.value = demo.broken
      ..peakJointForce.value = demo.peakForce.round();
  }
}

class JointGame extends DemoGame {
  final intactJoints = Channel.int32();
  final brokenJoints = Channel.int32();

  /// The largest constraint force seen in the loaded chain **since the case
  /// started**, in newtons - not the current one, which drops to zero the
  /// instant the last joint gives way. Watching this climb towards the break
  /// threshold is what makes the mechanism legible rather than magical.
  final peakJointForce = Channel.int32();

  @override
  JointState createState() => JointState();
}

/// Distance and revolute joints, with a motor and a breaking threshold.
class JointsDemo extends Demo {
  JointsDemo();

  late final JointGame _game;

  @override
  String get name => 'Joints';

  @override
  String get blurb =>
      'Chains on distance joints, a motorised wheel on a revolute one, and a '
      'loaded chain that tears itself apart under its own constraint force.';

  @override
  DemoGame create() => _game = JointGame();

  @override
  DemoGame get game => _game;

  @override
  List<DemoStat> get stats => <DemoStat>[
    DemoStat('intact', _game.intactJoints),
    DemoStat('broken', _game.brokenJoints),
    DemoStat('peak N', _game.peakJointForce),
  ];
}
