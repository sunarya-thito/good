/// Viewport culling (#23): a sprite the camera cannot see must never become a
/// draw record.
///
/// # What these tests are actually guarding
///
/// The easy half is that a sprite a million units away stops being drawn, and
/// a suite that only checked that would pass against a bound so tight it
/// clipped everything at the edge of the screen. So most of what is below is
/// the *positive* side: a sprite that is only half on screen, or on screen
/// only because it is rotated, or only because the camera zoomed out, has to
/// survive. Those are the cases a wrong bound gets wrong, and a wrong bound
/// looks like a hole in the picture rather than like a crash.
///
/// # The geometry these numbers are written against
///
/// Every test uses an 800x600 view and no camera entity unless it says
/// otherwise, so the projection is the identity plus centring:
///
/// ```text
/// viewX = worldX + 400        world x in [-400, 400] is on screen
/// viewY = 300 - worldY        world y in [-300, 300] is on screen
/// ```
///
/// World +y is up, so "past the top edge" means a world y above 300.
///
/// # The bound, stated once
///
/// A circle centred on the sprite's pivot, with the radius of its furthest
/// corner. Rotation turns the sprite about the pivot, so every corner stays
/// at the same distance from it and the radius does not depend on the angle -
/// which is what makes the bound safe for a rotated sprite without measuring
/// the rotation. It over-covers, most visibly for a sprite pivoted on its own
/// corner (the circle then reaches a full width the other way), and the tests
/// below pin that as the deliberate behaviour it is rather than pretending
/// the bound is tight.
library;

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:goo2d/goo2d.dart';

part 'viewport_culling_test.g.dart';

/// The live run under test. A file-level binding, matching the rest of this
/// package's suites: the bring-up helper returns the `Game` while tests also
/// need the run.
late Game run;

/// A plain renderable. Size, pivot and rotation are written per entity, so one
/// prefab backs the straddling, rotated and off-pivot cases without three
/// nearly identical archetypes.
class _Quad extends EntityStruct
    with Transform2D, WorldTransform2D, Renderable2D {
  final quad = Sprite.of(width: 20, height: 20, color: 0xFF00FF00);
}

/// A renderable with **no `WorldTransform2D`** - the other half of the
/// `_TransformSource` split, drawn straight from its local `Transform2D`.
/// Culling reads position and scale through that same indirection, so it has
/// to be exercised on both sides or one of the two paths is untested.
class _Flat extends EntityStruct with Transform2D, Renderable2D {
  final quad = Sprite.of(width: 20, height: 20, color: 0xFF0000FF);
}

/// The 2x1 PNG the other suites use. Never decoded on the producing isolate -
/// a nine-slice needs a texture to exist, not to have a size.
final Uint8List _png2x1 = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAIAAAABCAYAAAD0In+KAAAADklEQVR42mP4z8AAQv8BD/kD'
  '/Zh51wAAAAAASUVORK5CYII=',
);

final TextureKey _panelKey = TextureKey(MemorySource(_png2x1, name: 'panel'));

/// A nine-sliced panel: nine records from one sprite, filling exactly the
/// rectangle one quad would have. Culling has to treat it as one thing.
class _Panel extends EntityStruct
    with Transform2D, WorldTransform2D, Renderable2D {
  static const double size = 100;

  final frame = Sprite.of(
    texture: _panelKey,
    width: size,
    height: size,
    color: 0xFFFFFFFF,
    nineSliceBorder: NineSliceBorder.all(4, sourceSize: 16),
  );
}

class _Eye extends EntityStruct with Transform2D, WorldTransform2D, Camera {}

class _Scene extends SceneStruct {
  late Scene handle;

  @override
  void onSceneMounted(Scene scene) => handle = scene;

  Entity addEntity<T extends EntityStruct>(T prefab) =>
      handle.addEntity(prefab);

  @sub
  final quad = _Quad();
  @sub
  final flat = _Flat();
  @sub
  final panel = _Panel();
  @sub
  final eye = _Eye();
}

class _State extends GameState2D<_CullGame> {
  @override
  void onMounted() {
    super.onMounted();
    loadScene(_Scene());
  }
}

class _CullGame extends Game2D {
  CameraView get view => defaultCamera;

  /// Large enough that the 2000-entity scene below is a handful of pages
  /// rather than hundreds - this suite measures record counts, not paging.
  @override
  int get pageSize => 1 << 16;

  @override
  Duration get fixedTimeStep => const Duration(milliseconds: 10);

  @override
  GameState2D<_CullGame> createState() => _State();
}

const Duration _step = Duration(milliseconds: 10);

/// The view every test that culls uses. World x in [-400, 400] and world y in
/// [-300, 300] are on screen.
const double _viewWidth = 800;
const double _viewHeight = 600;

Future<_CullGame> _game({bool laidOut = true}) async {
  final game = await Game.startInline(_CullGame.new);
  run = game;
  addTearDown(() async {
    if (run.isRunning) await run.stop();
  });
  // The panel prefab declares a texture, and `loadScene`'s decode is still in
  // flight when `start` resolves - awaiting the same key is free and keeps the
  // decode from landing after teardown.
  await game.assets.load(_panelKey);
  // A test has no `GameView` to lay the view out, so it says the size itself.
  // Without this the view reports zero, which means "unknown" and culls
  // nothing - which is its own test below.
  if (laidOut) game.view.setViewport(_viewWidth, _viewHeight);
  return game;
}

_Scene _scene() => run.state.singleScene<_Scene>();

GameRenderer2D get _renderer => run.state.getSystem<GameRenderer2D>();

/// Places and sizes one `_Quad`. Safe before the first tick: the row's page
/// has never published, so nothing will copy over the write.
Entity _quadAt(
  _Scene scene, {
  double x = 0,
  double y = 0,
  double width = 20,
  double height = 20,
  double rotation = 0,
  double scaleX = 1,
  double scaleY = 1,
  double pivotFractionX = 0.5,
  double pivotFractionY = 0.5,
}) {
  final entity = scene.addEntity(scene.quad);
  scene.quad
    ..transformOffsetX[entity] = x
    ..transformOffsetY[entity] = y
    ..transformRotation[entity] = rotation
    ..transformScaleX[entity] = scaleX
    ..transformScaleY[entity] = scaleY;
  scene.quad.quad
    ..width[entity] = width
    ..height[entity] = height
    ..pivotFractionX[entity] = pivotFractionX
    ..pivotFractionY[entity] = pivotFractionY;
  return entity;
}

/// A camera occupying the game's view. Written immediately after the row is
/// created, before its page has published.
Entity _eye(_CullGame game, _Scene scene, {double x = 0, double zoom = 1}) {
  final eye = scene.addEntity(scene.eye);
  scene.eye
    ..cameraView[eye] = game.view
    ..cameraZoom[eye] = zoom
    ..transformOffsetX[eye] = x;
  return eye;
}

void main() {
  _installDeclarations();

  tearDown(() {
    SceneRegistry.reset();
    ArchetypeRegistry.reset();
    ComponentTypeRegistry.reset();
  });

  group('a sprite clear of the view is never queued', () {
    test('it is dropped, and the one beside it is not', () async {
      await _game();
      final scene = _scene();
      _quadAt(scene);
      _quadAt(scene, x: 1000000, y: 1000000);

      run.state.advance(_step);

      expect(_renderer.lastRecordCount, 1);
      expect(
        _renderer.lastSpriteCount,
        1,
        reason:
            'the far sprite has to be gone before the queue, not merely '
            'written off-screen - a queued record still costs a sort slot '
            'and a share of maxSpritesPerTick',
      );
    });

    test(
      'the same scene draws both when nothing has laid the view out',
      () async {
        await _game(laidOut: false);
        final scene = _scene();
        _quadAt(scene);
        _quadAt(scene, x: 1000000, y: 1000000);

        run.state.advance(_step);

        expect(
          _renderer.lastRecordCount,
          2,
          reason:
              'the pair above it is the same scene with a viewport. If this '
              'one did not draw both, the test above would be passing on a '
              'headless quirk rather than on culling',
        );
      },
    );
  });

  group('the bound is conservative at every edge', () {
    // A 100x100 sprite whose centre sits 40 past an edge: 10 units of it are
    // still inside, so it must be drawn. The pairs below place the same
    // sprite 200 past the same edge, where it is genuinely gone.
    const cases = <(String, double, double, bool)>[
      ('straddling the left edge', -440, 0, true),
      ('straddling the right edge', 440, 0, true),
      ('straddling the top edge', 0, 340, true),
      ('straddling the bottom edge', 0, -340, true),
      ('straddling the top-left corner', -440, 340, true),
      ('clear of the left edge', -600, 0, false),
      ('clear of the right edge', 600, 0, false),
      ('clear of the top edge', 0, 500, false),
      ('clear of the bottom edge', 0, -500, false),
      ('clear of the top-left corner diagonally', -460, 360, false),
    ];

    for (final (name, x, y, visible) in cases) {
      test(name, () async {
        await _game();
        final scene = _scene();
        _quadAt(scene, x: x, y: y, width: 100, height: 100);

        run.state.advance(_step);

        expect(
          _renderer.lastRecordCount,
          visible ? 1 : 0,
          reason: visible
              ? 'part of this sprite is on screen; culling it is a visible '
                    'hole at the edge of the view'
              : 'no part of this sprite is on screen',
        );
      });
    }

    test('the diagonal case is a corner test, not two edge tests', () async {
      await _game();
      final scene = _scene();
      // 60 past the left edge and 60 past the top. Its half-diagonal is 70.7,
      // so on either axis taken alone it still reaches - a bound that tested
      // the two axes independently would keep it. Diagonally it is 84.9 out
      // and reaches nothing, and its nearest corner lands at view (-10, -10).
      _quadAt(scene, x: -460, y: 360, width: 100, height: 100);

      run.state.advance(_step);

      expect(_renderer.lastRecordCount, 0);
    });
  });

  group('rotation', () {
    // A 200x4 bar, 100 units of reach along its length and 2 across.
    const double barLength = 200;
    const double barThickness = 4;

    test('a bar on screen only because it is turned is kept', () async {
      await _game();
      final scene = _scene();
      // Centre 80 above the top edge. Lying flat it spans world y 378..382 and
      // is invisible; turned a quarter turn it spans 280..480 and 20 units of
      // it are on screen.
      _quadAt(
        scene,
        x: 0,
        y: 380,
        width: barLength,
        height: barThickness,
        rotation: math.pi / 2,
      );

      run.state.advance(_step);

      expect(
        _renderer.lastRecordCount,
        1,
        reason:
            'this is the case a bound taken from width and height alone gets '
            'wrong: 2 units of half-height puts the bar 78 clear of the top '
            'edge, and it is 20 units on screen',
      );
    });

    test('a turned bar that clears the view is still dropped', () async {
      await _game();
      final scene = _scene();
      // Same bar, 700 above the edge. Even turned it reaches only to y 900.
      _quadAt(
        scene,
        x: 0,
        y: 1000,
        width: barLength,
        height: barThickness,
        rotation: math.pi / 2,
      );

      run.state.advance(_step);

      expect(
        _renderer.lastRecordCount,
        0,
        reason:
            'rotation-invariance must not become "keep every rotated sprite" '
            '- without this the test above passes on a bound that culls '
            'nothing that turns',
      );
    });

    test(
      'the same bar lying flat is kept too, and that is deliberate',
      () async {
        await _game();
        final scene = _scene();
        _quadAt(scene, x: 0, y: 380, width: barLength, height: barThickness);

        run.state.advance(_step);

        expect(
          _renderer.lastRecordCount,
          1,
          reason:
              'the bound is a circle around the pivot and so cannot depend on '
              'the angle - the flat bar gets the turned one is bound. It is '
              'over-covering, which costs a quad nobody sees; the other '
              'direction costs a sprite nobody can find',
        );
      },
    );
  });

  group('pivot', () {
    // Pivoted on its own top-left corner, so the sprite is drawn entirely
    // right and down of the entity's position rather than around it. A bound
    // measured from the entity position outward by half the size - the
    // obvious wrong answer - is wrong by a whole half-width here.
    test(
      'a sprite drawn off its own origin is bounded where it is drawn',
      () async {
        await _game();
        final scene = _scene();
        // Entity at world x -700, extending 400 to the right: world x
        // -700..-300, so 100 units are on screen.
        _quadAt(
          scene,
          x: -700,
          y: 20,
          width: 400,
          height: 40,
          pivotFractionX: 0,
          pivotFractionY: 0,
        );

        run.state.advance(_step);

        expect(
          _renderer.lastRecordCount,
          1,
          reason:
              'the pivot is in the bound, so the circle reaches where the '
              'sprite actually is. A radius of half the size about the entity '
              'position reaches 200 and this is 300 out',
        );
      },
    );

    test('an off-origin sprite clear of the view is still dropped', () async {
      await _game();
      final scene = _scene();
      // Same sprite at world x 900: it extends right, to 1300, so every part
      // of it is past the 400 the view reaches.
      _quadAt(
        scene,
        x: 900,
        y: 20,
        width: 400,
        height: 40,
        pivotFractionX: 0,
        pivotFractionY: 0,
      );

      run.state.advance(_step);

      expect(_renderer.lastRecordCount, 0);
    });
  });

  group('scale', () {
    test('a sprite scaled up into the view is kept', () async {
      await _game();
      final scene = _scene();
      // 20x20 at world x 480 is clear of the edge by 70. At 10x scale it is
      // 200 wide and reaches back to 380, which is on screen.
      _quadAt(scene, x: 480, scaleX: 10, scaleY: 10);

      run.state.advance(_step);

      expect(_renderer.lastRecordCount, 1);
    });

    test(
      'a negative scale flips the sprite and does not shrink its bound',
      () async {
        await _game();
        final scene = _scene();
        _quadAt(scene, x: 480, scaleX: -10, scaleY: -10);

        run.state.advance(_step);

        expect(
          _renderer.lastRecordCount,
          1,
          reason:
              'a negative scale mirrors the sprite about its pivot and covers '
              'the same ground. A bound that multiplied extents without '
              'squaring them would come out negative and cull it',
        );
      },
    );

    test('a sprite scaled down out of the view is dropped', () async {
      await _game();
      final scene = _scene();
      // 20x20 at 0.1 scale is 2 units wide, and 480 is well clear.
      _quadAt(scene, x: 480, scaleX: 0.1, scaleY: 0.1);

      run.state.advance(_step);

      expect(_renderer.lastRecordCount, 0);
    });
  });

  group('zoom', () {
    test('a sprite off screen at zoom 1 comes back at zoom 0.5', () async {
      final game = await _game();
      final scene = _scene();
      _eye(game, scene, zoom: 0.5);
      // World x 700. At zoom 1 the view reaches 400; at zoom 0.5 it reaches
      // 800, so this is 100 units inside.
      _quadAt(scene, x: 700);

      run.state.advance(_step);

      expect(
        _renderer.lastRecordCount,
        1,
        reason:
            'a zoomed-out camera sees more world. Zoom has to reach the cull '
            'through the projection, not only through the sprite size',
      );
    });

    test('the same sprite at zoom 1 is dropped', () async {
      final game = await _game();
      final scene = _scene();
      _eye(game, scene);
      _quadAt(scene, x: 700);

      run.state.advance(_step);

      expect(_renderer.lastRecordCount, 0);
    });

    test('a sprite on screen at zoom 1 leaves it at zoom 4', () async {
      final game = await _game();
      final scene = _scene();
      _eye(game, scene, zoom: 4);
      // World x 300 is on screen at zoom 1 (the view reaches 400) and off it
      // at zoom 4, where the view reaches only 100.
      _quadAt(scene, x: 300);

      run.state.advance(_step);

      expect(_renderer.lastRecordCount, 0);
    });
  });

  group('nine-slice', () {
    test('a panel half on screen keeps all nine of its records', () async {
      await _game();
      final scene = _scene();
      final panel = scene.addEntity(scene.panel);
      // Centre 400 out, so half its 100 units are inside.
      scene.panel.transformOffsetX[panel] = 400;

      run.state.advance(_step);

      expect(
        _renderer.lastSpriteCount,
        1,
        reason: 'one sprite, whatever it emits',
      );
      expect(
        _renderer.lastRecordCount,
        9,
        reason:
            'the sprite is culled whole. Testing cell by cell would drop the '
            'six that happen to fall outside and leave a panel with holes in '
            'it, since the cells are not independent quads - they share one '
            'source image and one transform',
      );
    });

    test('a panel clear of the view spends none of the budget', () async {
      await _game();
      final scene = _scene();
      final panel = scene.addEntity(scene.panel);
      scene.panel.transformOffsetX[panel] = 2000;

      run.state.advance(_step);

      expect(
        _renderer.lastRecordCount,
        0,
        reason:
            'nine records, not one, are what an off-screen panel used to '
            'cost - which is the whole of why #128 could not draw a tilemap '
            'larger than one screen',
      );
    });
  });

  group('renderables without WorldTransform2D', () {
    test('a flat sprite off screen is culled the same way', () async {
      await _game();
      final scene = _scene();
      final near = scene.addEntity(scene.flat);
      final far = scene.addEntity(scene.flat);
      scene.flat.transformOffsetX[far] = 5000;

      run.state.advance(_step);

      expect(_renderer.lastRecordCount, 1);
      expect(near, isNot(far));
    });

    test('a flat sprite straddling an edge is kept', () async {
      await _game();
      final scene = _scene();
      final entity = scene.addEntity(scene.flat);
      scene.flat.transformOffsetX[entity] = 405;
      scene.flat.quad
        ..width[entity] = 100
        ..height[entity] = 100;

      run.state.advance(_step);

      expect(
        _renderer.lastRecordCount,
        1,
        reason:
            'position and scale reach the cull through _TransformSource, and '
            'the local branch of it has to read the same five fields the '
            'world branch does',
      );
    });
  });

  group('the record count follows the view, not the world', () {
    // 2000 sprites 50 units apart: 100,000 world units of scene, of which one
    // 800-unit view can hold 17 - the ones from 400 left of the camera to 400
    // right, inclusive, plus nothing else, because an 8x8 sprite reaches only
    // 5.66 further and the spacing is 50.
    const int count = 2000;
    const double spacing = 50;
    const double first = -50000;
    const int visible = 17;

    void fill(_Scene scene) {
      for (var i = 0; i < count; i++) {
        _quadAt(scene, x: first + spacing * i, width: 8, height: 8);
      }
    }

    test('without a viewport the whole world is queued', () async {
      await _game(laidOut: false);
      fill(_scene());

      run.state.advance(_step);

      expect(
        _renderer.lastRecordCount,
        count,
        reason:
            'the control. Without this the flat count below would be '
            'consistent with a renderer that had simply stopped working',
      );
    });

    test('with a viewport it is flat as the camera pans across', () async {
      final game = await _game();
      final scene = _scene();
      final eye = _eye(game, scene);
      fill(scene);

      run.state.advance(_step);
      expect(_renderer.lastRecordCount, visible);

      // Multiples of the spacing, so the visible window holds exactly the same
      // number of sprites at each stop - the count is flat because the view is
      // the same size, not because the sprites happened to line up.
      for (final x in <double>[10000, -10000, 25000, -37500]) {
        scene.pool.beginTick();
        scene.eye.transformOffsetX[eye] = x;
        scene.pool.commitTick();
        // Two: the first carries the move through WorldTransformSystem, the
        // second draws from the world transform it published.
        run.state.advance(_step);
        run.state.advance(_step);
        expect(
          _renderer.lastRecordCount,
          visible,
          reason: 'camera at $x should see the same $visible of $count',
        );
      }
    });
  });
}
