import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:meta/meta.dart';

import 'package:good/src/data.dart';
import 'package:good/src/declare.dart';
import 'package:good/src/game.dart';

/// One addressable place a game is drawn - what a `GameView` shows and what a
/// camera entity is pointed at.
///
/// ```dart
/// class MyGame extends Game2D {
///   late final CameraView mainCamera;
///   late final CameraView minimapCamera;
///
///   @override
///   void describeCameras(CameraDescriptor descriptor) {
///     super.describeCameras(descriptor);
///     mainCamera    = descriptor.has();
///     minimapCamera = descriptor.has();
///   }
/// }
///
/// GameView(camera: game.mainCamera)
/// ```
///
/// [CameraDescriptor.has] takes no argument because there is nothing to tell
/// it: the field name is the identity (the typed-handle rule), so a camera is
/// never addressed by a name repeated at the use site.
///
/// # Why declared at boot
///
/// Each view is drawn into shared memory allocated **before**
/// `Isolate.spawn` - allocating on demand afterwards is not available to us.
/// So the *number* of views is fixed at boot, while which entity occupies a
/// view, and whether any does, stays entirely dynamic. A view with no camera
/// entity draws nothing; it does not fall back to another camera's.
///
/// # It is a [GlobalObject], so a row can name it
///
/// A camera entity records which view it belongs to, and a row holds a `num`
/// or an [IntRepresentable] and nothing else. Being one makes that field
/// *typed* - `DataPointer<CameraView>` refuses a stray int, which an extension
/// type over `int` would have accepted.
///
/// Its address is issued by the game's own [CameraViewTable] and means
/// nothing anywhere else; see [IntRepresentation].
///
/// # Nothing here is settable
///
/// Every member is a getter and the constructor is private, so a view can
/// only come from [CameraDescriptor.has] - there is no way to forge one whose
/// address collides with a declared view, and no way to repoint one at
/// another game. That last part is why `GameView` needs no `game` parameter:
/// with only one reference there is nothing for a second to disagree with.
final class CameraView implements IntRepresentable {
  CameraView._(this._index, this._game);

  /// The [IntRepresentation] a camera-view column binds to, for the scene
  /// being brought up.
  ///
  /// A row stores a view as its address, and an address only means anything
  /// against the table that issued it - so a component holding one names the
  /// table:
  ///
  /// ```dart
  /// mixin Camera on Component {
  ///   final cameraView = Field.optPacked(CameraView.representation());
  /// }
  /// ```
  ///
  /// The table belongs to the game, not to the prefab, so there is one of
  /// them for a whole scene's bring-up and every camera component binds to
  /// the same object. `Asset.representation` is the same move for the asset
  /// table.
  ///
  /// Throws outside a scene's declaration passes - a prefab constructed by
  /// hand, or a `late final` that runs on first read.
  static IntRepresentation<CameraView> representation() =>
      DeclarationContext.cameraViews;

  final int _index;
  final Game? _game;

  /// Its index in the declaring game's [CameraViewTable]. Meaningful only
  /// against that table.
  @override
  int pack() => _index;

  /// The game that declared this view.
  ///
  /// Throws for a view from [CameraViewTable.declareDetached] - a headless
  /// fixture's view, which exists to be *named* by a camera component and
  /// never to be shown. That is the only way to obtain one without a game,
  /// and handing one to a `GameView` is the mistake this reports.
  Game get game {
    final game = _game;
    if (game == null) {
      throw StateError(
        '$this was created detached (CameraViewTable.declareDetached) and '
        'belongs to no Game, so there is nothing for a GameView to show. '
        'Declare views in Game.describeCameras for anything that has to be '
        'displayed.',
      );
    }
    return game;
  }

  /// Viewport size in logical pixels: what the `GameView` showing this view
  /// gives it, and what the camera projection centres on.
  ///
  /// **Getters over shared memory, never fields**, and that is load-bearing,
  /// not stylistic. A `CameraView` reaches the game isolate through
  /// the `Isolate.spawn` deep copy, so the two isolates hold two *separate*
  /// objects: a plain field written by the widget on layout would update
  /// main's copy while the renderer read a value frozen at spawn time, with
  /// nothing to show for it. It is the same trap as caching a typed-data view
  /// over native memory in a field - see `Game`'s notes on what survives a
  /// spawn - with a plain field instead of a view.
  ///
  /// Zero before [Game.start] and after [Game.stop], and zero for a view
  /// nothing is showing. A headless game therefore reports zero, exactly as
  /// `Game.viewWidth` does, which is what lets a test that never built a
  /// widget see plain world coordinates.
  double get viewportWidth => _readViewport(0);
  double get viewportHeight => _readViewport(1);

  /// Two floats of shared memory, written by main and read by the game
  /// isolate. Naturally-aligned 32-bit stores, so each is atomic on every
  /// architecture Dart targets and no lock is needed - the same argument
  /// `HandoffBuffer`'s control words rest on. A torn *pair* (new width, old
  /// height) is possible for one frame during a resize and is harmless: it
  /// draws one frame at an intermediate size.
  Pointer<Float>? _viewport;

  double _readViewport(int offset) {
    final block = _viewport;
    return block == null ? 0 : block[offset];
  }

  /// Reports the size this view is being drawn at. Called by the `GameView`
  /// showing it, on layout.
  ///
  /// Writes only on change, so a rebuild at the same size costs two float
  /// comparisons instead of two stores plus whatever the game isolate makes of
  /// them.
  ///
  /// Public for the same reason `SceneRegistry.register` and
  /// `SceneStruct.initializeScene` are: a test or a headless harness has no
  /// widget to do the laying out, and still needs the projection to centre on
  /// something. Normal code never calls it - the `GameView` does.
  void setViewport(double width, double height) {
    final block = _viewport;
    if (block == null) return;
    if (block[0] != width) block[0] = width;
    if (block[1] != height) block[1] = height;
  }

  @internal
  void allocate() => _viewport ??= calloc<Float>(2);

  @internal
  void release({required bool owns}) {
    final block = _viewport;
    if (block != null && owns) calloc.free(block);
    _viewport = null;
  }

  @override
  String toString() => 'CameraView#$_index';
}

/// Declares a game's camera views - one [has] call per view, each returning
/// the handle to keep in a `late final` field.
abstract class CameraDescriptor {
  /// Declares one view. Takes nothing: the field it is assigned to is the
  /// identity, and its size comes from the `GameView` that shows it.
  CameraView has();
}

/// A game's camera views, numbered from zero.
///
/// Its own [IntRepresentation], not a tenant in the asset table: a camera view
/// is not an asset, and pouring unrelated populations into one address space
/// is what makes an address unanswerable on its own. This table and `Assets`
/// may issue the same address without conflict, because an address is only
/// ever unpacked by the representation the field was declared against.
final class CameraViewTable implements IntRepresentation<CameraView> {
  final List<CameraView> _views = <CameraView>[];

  /// How many views the game declared.
  int get length => _views.length;

  /// The view at [address] - declaration order.
  CameraView operator [](int address) => _views[address];

  /// Eight bits, not thirty-two. A game declares its views in
  /// `describeCameras` and they are counted on the fingers of one hand - a
  /// split-screen four-player game has four - so a `DataPointer<CameraView>`
  /// costs a row one byte instead of four. [declare] enforces the ceiling
  /// instead of letting the 257th view silently alias the first.
  @override
  int get bitWidth => 8;

  static const int _maxViews = 1 << 8;

  @override
  CameraView? tryUnpack(int bits) {
    if (bits < 0 || bits >= _views.length) return null;
    return _views[bits];
  }

  @override
  CameraView unpack(int bits) {
    final view = tryUnpack(bits);
    if (view == null) {
      throw StateError(
        'No camera view at address $bits - this game declared '
        '${_views.length} view(s) in describeCameras. A row holding an '
        'address this table never issued is either stale or came from a '
        'different table; addresses are only meaningful against the table '
        'that issued them.',
      );
    }
    return view;
  }

  CameraView _add(Game? game) {
    if (_views.length >= _maxViews) {
      throw StateError(
        'A game may declare at most $_maxViews camera views; this one '
        'declared ${_views.length + 1}. The limit is the width of the row '
        'field a Camera stores its view in (see bitWidth) - raise that if a '
        'game genuinely needs more.',
      );
    }
    final view = CameraView._(_views.length, game);
    _views.add(view);
    return view;
  }

  @internal
  CameraView declare(Game game) => _add(game);

  /// A view belonging to no game, for a headless fixture that brings a scene
  /// up without one - public for exactly the reason `SceneRegistry.register`
  /// and `SceneStruct.initializeScene` are. It can be stored in a `Camera`'s
  /// `view` field and resolved through this table; it cannot be shown.
  @visibleForTesting
  CameraView declareDetached() => _add(null);

  @internal
  void allocate() {
    for (var i = 0; i < _views.length; i++) {
      _views[i].allocate();
    }
  }

  @internal
  void release({required bool owns}) {
    for (var i = 0; i < _views.length; i++) {
      _views[i].release(owns: owns);
    }
  }
}

@internal
final class GameCameraDescriptor implements CameraDescriptor {
  GameCameraDescriptor(this._game, this._table);

  final Game _game;
  final CameraViewTable _table;

  @override
  CameraView has() => _table.declare(_game);
}
