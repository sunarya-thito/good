import 'package:flutter/widgets.dart';

import 'package:goo2d/src/object.dart';
import 'package:goo2d/src/element.dart';
import 'package:goo2d/src/render.dart';

/// The base class for all widgets that represent entities in the Goo2D engine.
///
/// [GameWidget] is the bridge between Flutter's declarative widget system and
/// the engine's persistent [GameObject] hierarchy. Unlike standard widgets,
/// a [GameWidget] creates a [GameObjectElement] that survives across rebuilds
/// and maintains the state of attached components.
///
/// ```dart
/// class MyStatelessEntity extends StatelessGameWidget {
///   const MyStatelessEntity({super.key});
///
///   @override
///   Iterable<Widget> build(BuildContext context) sync* {
///     yield const GameObjectWidget(name: 'Static');
///   }
/// }
///
/// class MyStatefulEntity extends StatefulGameWidget {
///   const MyStatefulEntity({super.key});
///
///   @override
///   GameState createState() => MyEntityState();
/// }
///
/// class MyEntityState extends GameState<MyStatefulEntity> {
///   @override
///   Iterable<Widget> build(BuildContext context) => [];
/// }
/// ```
///
/// See also:
/// * [StatefulGameWidget] for widgets with persistent logic.
/// * [StatelessGameWidget] for declarative-only entities.
abstract class GameWidget extends RenderObjectWidget {
  /// The rendering layer assigned to the [GameObject] created by this widget.
  ///
  /// Layers determine the draw order of objects in the scene. Objects on
  /// higher layers are rendered after (and thus on top of) objects on
  /// lower layers.
  final int layer;

  /// The human-readable name for the [GameObject] created by this widget.
  ///
  /// This name is primarily used for debugging and identifying objects
  /// within the hierarchy. It does not need to be unique across the game.
  final String? name;

  /// An optional tag for the [GameObject] created by this widget.
  ///
  /// Any value (string, enum, or any [Object] with equality) can be used.
  /// Unlike Flutter widget keys, multiple objects may share the same tag,
  /// matching Unity's tag behavior. Use [GameObject.findWithTag] or
  /// [GameObject.findGameObjectsWithTag] to look up tagged objects.
  final Object? tag;

  /// Creates a [GameWidget] with an optional [layer], [name], and [tag].
  ///
  /// The [key] parameter follows standard Flutter widget behavior, allowing
  /// for efficient identity checks during the widget reconciliation phase.
  ///
  /// * [key]: The Flutter widget key for identity.
  /// * [layer]: The rendering layer for the game object.
  /// * [name]: The debug name for the game object.
  /// * [tag]: The lookup tag for the game object.
  const GameWidget({
    super.key,
    this.layer = RenderLayer.defaultLayer,
    this.name,
    this.tag,
  });

  @override
  RenderObject createRenderObject(BuildContext context) {
    return GameRenderObject(context as GameObject);
  }

  @override
  void updateRenderObject(BuildContext context, GameRenderObject renderObject) {
    renderObject.object = context as GameObject;
  }
}

/// A game widget that maintains persistent state across rebuilds.
///
/// [StatefulGameWidget] is used for entities that require complex logic,
/// local variables, or asynchronous operations like coroutines. It
/// corresponds to Flutter's `StatefulWidget` but produces a [GameState]
/// instead of a standard `State`.
///
/// ```dart
/// class Player extends StatefulGameWidget {
///   const Player({super.key});
///
///   @override
///   GameState createState() => PlayerState();
/// }
///
/// class PlayerState extends GameState<Player> {
///   @override
///   void initState() {
///     super.initState();
///     // Initialize player logic by adding components
///     // addComponent(const SpriteRenderer());
///   }
///
///   @override
///   Iterable<Widget> build(BuildContext context) sync* {
///     yield const GameObjectWidget(name: 'Visuals');
///   }
/// }
/// ```
///
/// See also:
/// * [GameState] for the object that holds the state and logic.
/// * [StatelessGameWidget] for simpler, purely declarative entities.
abstract class StatefulGameWidget extends GameWidget {
  /// Creates a [StatefulGameWidget].
  ///
  /// This constructor passes configuration data down to the [GameWidget]
  /// base class, ensuring the resulting [GameObject] is correctly
  /// initialized with the specified [layer] and [name].
  ///
  /// * [key]: The Flutter widget key for identity.
  /// * [layer]: The rendering layer for the game object.
  /// * [name]: The debug name for the game object.
  /// * [tag]: The lookup tag for the game object.
  const StatefulGameWidget({
    super.key,
    super.layer,
    super.name,
    super.tag,
  });

  @override
  GameObjectElement createElement() => GameObjectElement(this);

  /// Creates the [GameState] associated with this widget.
  ///
  /// This method is called when the widget is first mounted to the
  /// engine's object tree. The resulting state object handles the
  /// object's lifecycle and internal logic.
  GameState createState();
}

/// A game widget that does not require persistent state.
///
/// [StatelessGameWidget] is ideal for simple decorative objects or
/// compositions that are fully defined by their constructor parameters.
/// It simplifies the implementation by combining the widget and build
/// logic into a single class.
///
/// ```dart
/// class StaticTree extends StatelessGameWidget {
///   const StaticTree({super.key});
///
///   @override
///   Iterable<Widget> build(BuildContext context) sync* {
///     yield const GameObjectWidget(name: 'Leaves');
///   }
/// }
/// ```
///
/// See also:
/// * [StatefulGameWidget] for widgets that require persistent state.
abstract class StatelessGameWidget extends StatefulGameWidget {
  /// Creates a [StatelessGameWidget].
  ///
  /// The provided [layer] and [name] are passed to the [GameObject]
  /// instance created by the engine when this widget is first mounted.
  ///
  /// * [key]: The Flutter widget key for identity.
  /// * [layer]: The rendering layer for the game object.
  /// * [name]: The debug name for the game object.
  /// * [tag]: The lookup tag for the game object.
  const StatelessGameWidget({
    super.key,
    super.layer,
    super.name,
    super.tag,
  });

  /// Describes the children or components of this game object.
  ///
  /// This method is called during the build phase and should return an
  /// iterable of widgets (typically other [GameWidget]s) that will be
  /// parented to this object.
  ///
  /// * [context]: The [GameObject] context for this build call.
  Iterable<Widget> build(BuildContext context);

  @override
  GameState createState() => _StatelessGameWidgetState();
}

class _StatelessGameWidgetState extends GameState<StatelessGameWidget> {
  @override
  Iterable<Widget> build(BuildContext context) => widget.build(context);
}

/// A general-purpose widget for creating [GameObject]s with children.
///
/// [GameObjectWidget] is a concrete implementation of [StatefulGameWidget]
/// that allows for nesting multiple children within the game hierarchy. It
/// is frequently used to group related entities or to create organizational
/// nodes in the scene graph.
///
/// ```dart
/// void example() {
///   final group = GameObjectWidget(
///     name: 'Environment',
///     children: [
///       const GameObjectWidget(name: 'Tree'),
///       const ComponentWidget(ObjectTransform.new),
///     ],
///   );
/// }
/// ```
///
/// See also:
/// * [GameWidget] for the base class and shared configuration.
class GameObjectWidget extends StatefulGameWidget {
  /// The list of child widgets to be parented to this object.
  ///
  /// Changes to this list during a rebuild will trigger the appropriate
  /// addition, removal, or reordering of [GameObject]s in the scene.
  final List<Widget> children;

  /// Creates a [GameObjectWidget] with the specified [children].
  ///
  /// This constructor facilitates the creation of hierarchical scene
  /// structures by allowing developers to pass a static or dynamic
  /// list of child entities.
  ///
  /// * [key]: The Flutter widget key for identity.
  /// * [layer]: The rendering layer for the game object.
  /// * [name]: The debug name for the game object.
  /// * [tag]: The lookup tag for the game object.
  /// * [children]: The list of child entities.
  const GameObjectWidget({
    super.key,
    super.layer,
    super.name,
    super.tag,
    this.children = const [],
  });

  @override
  GameState createState() => _GameWidgetState();
}

class _GameWidgetState extends GameState<GameObjectWidget> {
  @override
  Iterable<Widget> build(BuildContext context) => widget.children;
}
