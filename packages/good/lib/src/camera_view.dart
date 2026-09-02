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
///   final mainCamera = CameraView.of();
///   final minimapCamera = CameraView.of();
/// }
///
/// GameView(camera: game.mainCamera)
/// ```
///
/// [of] takes no argument because there is nothing to tell it: the field name
/// is the identity (the typed-handle rule), so a camera is never addressed by
/// a name repeated at the use site.
///
/// # Why declared at boot
///
/// Each view is drawn into shared memory allocated **before**
/// `Isolate.spawn` - allocating on demand afterwards is not available to us.
/// So the *number* of views is fixed at boot, while which entity occupies a
/// view, and whether any does, stays entirely dynamic. A view with no camera
/// entity draws nothing; it does not fall back to another camera's.
///
/// # It is an [IntRepresentable], so a row can name it
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
/// Every member is a getter and the constructor is private, so a view can only
/// come from [of] - there is no way to forge one whose address collides with a
/// declared view, and no way to repoint one at another game. That last part is
/// why `GameView` needs no `game` parameter: with only one reference there is
/// nothing for a second to disagree with.
final class CameraView implements IntRepresentable {
  CameraView._(this._index);

  /// Declares one view on the game being constructed, and returns the handle
  /// the field holds:
  ///
  /// ```dart
  /// class MyGame extends Game {
  ///   final mainCamera = CameraView.of();
  /// }
  /// ```
  ///
  /// Takes nothing, for the reason the class doc gives, and hands back a view
  /// whose address is its position in the game's [CameraViewTable]. Which game
  /// it belongs to is settled once the constructor returns, so [game] answers
  /// from that point on and throws before it.
  ///
  /// The number of views is fixed at construction: each is drawn into shared
  /// memory allocated before `Isolate.spawn`, so a view declared later would
  /// have no storage. Declaring one from a prefab, a scene or a system is
  /// refused with the sentence saying so - `CameraView.representation()` is
  /// what a prefab wants, and it names the table rather than adding to it.
  ///
  /// # Eager, always
  ///
  /// `late final mainCamera = CameraView.of()` compiles and is wrong. The call
  /// runs on the first *read*, after the table has been closed and its storage
  /// allocated, and is refused there.
  static CameraView of() {
    final table = DeclarationContext.cameraViewsOrNull;
    if (table == null) CameraViewTable.refuseDeclaration();
    return table.declare();
  }

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

  /// The game that declared this view, hung on once its constructor returns -
  /// a field initialiser runs before there is a `Game` to name. Stays null for
  /// [CameraViewTable.declareDetached].
  Game? _game;

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
        '$this belongs to no Game, so there is nothing for a GameView to '
        'show. Either it came from CameraViewTable.declareDetached - a '
        'headless fixture\'s view, which exists to be named by a camera '
        'component - or the game that declared it is still being constructed. '
        'A `CameraView.of()` field on a Game is displayable from the moment '
        'that constructor returns.',
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

  /// Eight bits, not thirty-two. A game declares its views on fields and they
  /// are counted on the fingers of one hand - a split-screen four-player game
  /// has four - so a `DataPointer<CameraView>` costs a row one byte instead of
  /// four. [declare] enforces the ceiling instead of letting the 257th view
  /// silently alias the first.
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
        '${_views.length} view(s). A row holding an '
        'address this table never issued is either stale or came from a '
        'different table; addresses are only meaningful against the table '
        'that issued them.',
      );
    }
    return view;
  }

  CameraView _add() {
    if (_views.length >= _maxViews) {
      throw StateError(
        'A game may declare at most $_maxViews camera views; this one '
        'declared ${_views.length + 1}. The limit is the width of the row '
        'field a Camera stores its view in (see bitWidth) - raise that if a '
        'game genuinely needs more.',
      );
    }
    final view = CameraView._(_views.length);
    _views.add(view);
    return view;
  }

  /// Whether [declare] is accepting views. True only while the `Game` that
  /// owns this table is being constructed - `Game._construct` opens it before
  /// the call and closes it in [bindGame].
  ///
  /// It is what makes `CameraView.of()` outside that window a refusal rather
  /// than a view with no storage: the table is also on the declaration stack
  /// for the whole of a scene's bring-up, where `CameraView.representation()`
  /// reads it, and a `CameraView.of()` there would otherwise land in a table
  /// whose memory was allocated a phase earlier.
  bool _open = false;

  @internal
  void open() => _open = true;

  /// The one refusal for declaring a view outside a game's constructor -
  /// whether the stack is empty or the table on it has been closed.
  @internal
  static Never refuseDeclaration() {
    throw StateError(
      'A camera view was declared with no game being constructed. '
      'CameraView.of reads the table Game.start opens around a constructor '
      'call, so the framework has to be the one constructing:\n'
      '  Game.start(MyGame.new)   // not Game.start(MyGame())\n'
      'A `late final` initialiser lands here too, and that is the point: it '
      'runs on first read, after the table was closed and every view\'s two '
      'floats of shared memory allocated, so the view would have nowhere to '
      'report its size. Field initialisers here are eager, always.\n'
      'A Game is the only thing that declares a view - the storage is '
      'allocated on main before the spawn, so only a pass that runs there can '
      'own an address. A prefab naming a view holds an address in a column: '
      '`Field.optPacked(CameraView.representation())`.',
    );
  }

  /// Adds one view. `CameraView.of` is the only caller.
  @internal
  CameraView declare() {
    if (!_open) refuseDeclaration();
    return _add();
  }

  /// Hands every declared view its game and closes the table. Called once, by
  /// `Game._construct`, as soon as the constructor returns.
  @internal
  void bindGame(Game game) {
    _open = false;
    for (var i = 0; i < _views.length; i++) {
      _views[i]._game = game;
    }
  }

  /// A view belonging to no game, for a headless fixture that brings a scene
  /// up without one - public for exactly the reason `SceneRegistry.register`
  /// and `SceneStruct.initializeScene` are. It can be stored in a `Camera`'s
  /// `view` field and resolved through this table; it cannot be shown.
  @visibleForTesting
  CameraView declareDetached() => _add();

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
