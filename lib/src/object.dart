import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:goo2d/src/game.dart';
import 'package:goo2d/src/component.dart';
import 'package:goo2d/src/event.dart';
import 'package:goo2d/src/coroutine.dart';

// Registry mapping tag values to their live GameObjects.
// Maintained by GameObjectElement on mount/unmount/update.
// ignore: library_private_types_in_public_api
final Map<Object, List<GameObject>> tagRegistry = {};

/// The primary interface for all entities within the Goo2D game engine.
///
/// [GameObject] represents a single node in the game's scene graph. It
/// follows an entity-component model where the object itself provides the
/// identity and hierarchy (parent/children), while its functionality is
/// provided by attached [Component]s.
///
/// As it implements Flutter's [BuildContext], it integrates directly with
/// the widget tree, allowing components to access inherited widgets and
/// engine systems using standard Flutter patterns while maintaining high
/// performance for game logic.
///
/// ```dart
/// // Example component stubs
/// class HealthComponent extends Component {
///   double value = 100;
///   bool get isDead => value <= 0;
///   void takeDamage(double amount) => value -= amount;
/// }
///
/// class AttackComponent extends Component {
///   double power = 10;
/// }
///
/// class EntityDeathListener extends Component with EventListener {}
///
/// class EntityDeathEvent extends Event<EntityDeathListener> {
///   const EntityDeathEvent();
///   @override
///   void dispatch(EntityDeathListener listener) {}
/// }
///
/// // Standard pattern for interacting with game objects in systems or behaviors
/// void handleCombat(GameObject player, GameObject enemy) {
///   final health = player.getComponent<HealthComponent>();
///   final attack = enemy.getComponent<AttackComponent>();
///
///   health.takeDamage(attack.power);
///
///   if (health.isDead) {
///     player.broadcastEvent(const EntityDeathEvent());
///   }
/// }
/// ```
///
/// See also:
/// * [Component], the modular building blocks of game objects.
/// * [GameEngine], the root container managing the scene graph.
abstract class GameObject implements BuildContext {
  /// The user-friendly name assigned to this object.
  ///
  /// Names are primarily used for debugging and identifying objects in the
  /// hierarchy. They are not guaranteed to be unique; use [tag] if you need
  /// a reliable global identifier.
  String get name;

  /// The [GameEngine] instance this object belongs to.
  ///
  /// This provides the object with access to global systems like physics,
  /// input, and the world rendering context.
  GameEngine get game;

  /// An optional tag for this object, used for global lookups.
  ///
  /// Any value can serve as a tag — strings, enums, or any [Object] that
  /// implements equality. Multiple objects may share the same tag value,
  /// matching Unity's tag behavior. Use [GameObject.findWithTag] to get the
  /// first matching object or [GameObject.findGameObjectsWithTag] for all.
  Object? get tag;

  /// Whether this object is currently active in the simulation.
  ///
  /// Inactive objects and their components are ignored by most engine
  /// systems (ticks, physics updates, etc.). Deactivating a parent also
  /// effectively deactivates all its children.
  bool get active;

  /// The root [GameObject] of the current scene hierarchy.
  ///
  /// This allows for navigation to the top-level container of the entity
  /// tree, which is often a [World] or a major scene container.
  GameObject get rootObject;

  /// The parent [GameObject] of this object in the scene graph.
  ///
  /// This will be null if the object is a root-level entity. Moving an
  /// object is typically done by modifying its transform or re-parenting it.
  GameObject? get parentObject;

  /// All immediate children of this object in the hierarchy.
  ///
  /// This provides a direct way to iterate over sub-entities. For deep
  /// searches, use [findChild] or [getComponentsInChildren].
  Iterable<GameObject> get childrenObjects;

  /// All [Component]s currently attached to this object.
  ///
  /// This includes all data and logic modules that define the object's
  /// behavior and state.
  Iterable<Component> get components;

  /// The rendering layer this object belongs to.
  ///
  /// Layers are used to control the draw order and visibility of objects.
  /// Higher layer numbers are generally rendered on top of lower ones.
  int get layer;

  /// Sets the rendering layer for this object.
  ///
  /// Changing the layer will update how the object is sorted during the
  /// next paint cycle.
  ///
  /// * [value]: The new layer index.
  set layer(int value);

  /// Adds one or more [Component]s to this object.
  ///
  /// Components are the primary way to add functionality to a [GameObject].
  /// When added, they are initialized and integrated into the engine's
  /// processing systems.
  ///
  /// ```dart
  /// void setup(GameObject obj) {
  ///   obj.addComponent(ObjectTransform()..localAngle = 1.5);
  ///   obj.addComponent(SpriteRenderer()..texture = GameTexture('player.png'));
  /// }
  /// ```
  ///
  /// * [component]: The primary component to add.
  /// * [a]: Optional additional component to add.
  /// * [b]: Optional additional component to add.
  /// * [c]: Optional additional component to add.
  /// * [d]: Optional additional component to add.
  /// * [e]: Optional additional component to add.
  /// * [f]: Optional additional component to add.
  /// * [g]: Optional additional component to add.
  /// * [h]: Optional additional component to add.
  /// * [i]: Optional additional component to add.
  /// * [j]: Optional additional component to add.
  void addComponent(
    Component component, [
    Component? a,
    Component? b,
    Component? c,
    Component? d,
    Component? e,
    Component? f,
    Component? g,
    Component? h,
    Component? i,
    Component? j,
  ]);

  /// Removes one or more [Component] instances from this object.
  ///
  /// Removing a component stops its logic and unregisters it from the
  /// engine. The component's [Component.onUnmounted] callback is triggered.
  ///
  /// * [component]: The primary component instance to remove.
  /// * [a]: Optional additional component instance to remove.
  /// * [b]: Optional additional component instance to remove.
  /// * [c]: Optional additional component instance to remove.
  /// * [d]: Optional additional component instance to remove.
  /// * [e]: Optional additional component instance to remove.
  /// * [f]: Optional additional component instance to remove.
  /// * [g]: Optional additional component instance to remove.
  /// * [h]: Optional additional component instance to remove.
  /// * [i]: Optional additional component instance to remove.
  /// * [j]: Optional additional component instance to remove.
  void removeComponent(
    Component component, [
    Component? a,
    Component? b,
    Component? c,
    Component? d,
    Component? e,
    Component? f,
    Component? g,
    Component? h,
    Component? i,
    Component? j,
  ]);

  /// Removes all components of the specified types from this object.
  ///
  /// This is useful for clearing entire categories of functionality, such
  /// as removing all colliders or all visual components.
  ///
  /// * [type]: The primary component type to remove.
  /// * [a]: Optional additional component type to remove.
  /// * [b]: Optional additional component type to remove.
  /// * [c]: Optional additional component type to remove.
  /// * [d]: Optional additional component type to remove.
  /// * [e]: Optional additional component type to remove.
  /// * [f]: Optional additional component type to remove.
  /// * [g]: Optional additional component type to remove.
  /// * [h]: Optional additional component type to remove.
  /// * [i]: Optional additional component type to remove.
  /// * [j]: Optional additional component type to remove.
  void removeComponentOfExactType(
    Type type, [
    Type? a,
    Type? b,
    Type? c,
    Type? d,
    Type? e,
    Type? f,
    Type? g,
    Type? h,
    Type? i,
    Type? j,
  ]);

  /// Removes all components of type [T] from this object.
  ///
  /// This is a type-safe convenience method for [removeComponentOfExactType].
  ///
  /// * [T]: The type of components to remove.
  void removeComponentOfType<T extends Component>();

  /// Adds a collection of [Component]s to this object.
  ///
  /// This is an alternative to [addComponent] for adding pre-built lists of
  /// components, common during dynamic object instantiation.
  ///
  /// * [components]: The iterable collection of components to add.
  void addComponents(Iterable<Component> components);

  /// Removes components of the specified types from this object.
  ///
  /// * [types]: The collection of component types to remove.
  void removeComponents(Iterable<Type> types);

  /// Removes the component at the specified index in the [components] list.
  ///
  /// * [index]: The 0-based index of the component to remove.
  void removeComponentAt(int index);

  /// Removes all components currently attached to this object.
  ///
  /// This effectively resets the object's functionality to a blank state.
  void removeAllComponents();

  /// Retrieves all components of type [T] from this object and all its descendants.
  ///
  /// This performs a recursive search down the scene graph. Use sparingly in
  /// update loops as it can be computationally expensive for deep hierarchies.
  ///
  /// * [T]: The type of components to collect.
  Iterable<T> getComponentsInChildren<T extends Component>();

  /// Retrieves the first component of type [T] found in the parent hierarchy.
  ///
  /// Searches upward from this object's parent to the root of the scene graph.
  /// Throws an error if the component is not found.
  ///
  /// * [T]: The type of component to search for.
  T getComponentInParent<T extends Component>();

  /// Safely attempts to retrieve a component of type [T] from the parent hierarchy.
  ///
  /// Returns null if no ancestor contains the requested component type.
  ///
  /// * [T]: The type of component to search for.
  T? tryGetComponentInParent<T extends Component>();

  /// Broadcasts an [event] to this object and all its descendants.
  ///
  /// This allows for efficient communication across sub-trees of the scene
  /// graph (e.g., notifying all components in a character object of a damage event).
  ///
  /// * [event]: The event to broadcast.
  void broadcastEvent(Event event);

  /// Sends an [event] specifically to this object.
  ///
  /// Only components attached directly to this object will receive the event.
  ///
  /// * [event]: The event to send.
  void sendEvent(Event event);

  /// Broadcasts an async [event] to this object and all its descendants, awaiting each dispatch.
  FutureOr<void> broadcastEventAsync(AsyncEvent event);

  /// Sends an async [event] to this object's children, awaiting each dispatch.
  FutureOr<void> sendEventAsync(AsyncEvent event);

  /// Retrieves the first component of type [T] attached to this object.
  ///
  /// Throws an error if no component of the requested type exists. Use
  /// [tryGetComponent] if the component might be missing.
  ///
  /// ```dart
  /// void updatePosition(GameObject gameObject) {
  ///   final transform = gameObject.getComponent<ObjectTransform>();
  ///   transform.translate(Vector2(5, 0));
  /// }
  /// ```
  ///
  /// * [T]: The type of component to retrieve.
  T getComponent<T extends Component>();

  /// Safely attempts to retrieve a component of type [T] from this object.
  ///
  /// Returns null if the component is not found.
  ///
  /// * [T]: The type of component to retrieve.
  T? tryGetComponent<T extends Component>();

  /// Returns all components of type [T] attached to this object.
  ///
  /// Use this when multiple instances of the same component type are allowed
  /// (see [MultiComponent]).
  ///
  /// * [T]: The type of components to collect.
  Iterable<T> getComponents<T extends Component>();

  /// Finds the first component of type [T] in this object or its children.
  ///
  /// Performs a breadth-first search down the hierarchy. Throws an error if
  /// not found.
  ///
  /// * [T]: The type of component to search for.
  T getComponentInChildren<T extends Component>();

  /// Safely attempts to find a component of type [T] in this object or its children.
  ///
  /// Returns null if no component of the requested type is found in the sub-tree.
  ///
  /// * [T]: The type of component to search for.
  T? tryGetComponentInChildren<T extends Component>();

  /// Returns all components of type [T] found in the parent hierarchy.
  ///
  /// * [T]: The type of components to collect from ancestors.
  Iterable<T> getComponentsInParent<T extends Component>();

  /// Whether this object has at least one component of type [T].
  ///
  /// * [T]: The type of component to check for.
  bool hasComponent<T extends Component>();

  /// Whether this object has at least one component of the specified [type].
  ///
  /// * [type]: The exact [Type] of component to check for.
  bool hasComponentOfType(Type type);

  /// Retrieves the component at the specified index.
  ///
  /// * [index]: The 0-based index in the [components] list.
  Component getComponentAt(int index);

  /// Returns the total number of components attached to this object.
  ///
  /// This provides a quick way to check the complexity of an object or to
  /// verify that components have been added or removed as expected.
  int getComponentsCount();

  /// Returns a list of all components of type [T] on this object.
  ///
  /// This is a convenience method that returns a concrete [List] instead of
  /// an [Iterable].
  ///
  /// * [T]: The type of components to collect.
  List<T> getComponentsOfType<T extends Component>();

  /// Returns the index of the specified [component] in the [components] list.
  ///
  /// Returns -1 if the component is not attached to this object.
  ///
  /// * [component]: The component instance to locate.
  int getComponentIndex(Component component);

  /// Finds a child object by its [name] in the hierarchy.
  ///
  /// This performs a recursive search down the tree starting from the
  /// current object's children.
  ///
  /// * [name]: The name of the child object to find.
  GameObject? findChild(String name);

  /// Global search for a [GameObject] by its [name] or path.
  ///
  /// Paths can be absolute (starting with `/`) or relative. The search is
  /// conducted across all root objects in the current [GameEngine] context.
  ///
  /// * [context]: The build context to use for engine lookup.
  /// * [name]: The name or path of the object to find.
  static GameObject? find(BuildContext context, String name) {
    final engine = GameEngine.of(context);
    final isAbsolute = name.startsWith('/');
    final path = isAbsolute ? name.substring(1) : name;
    final parts = path.split('/');

    final roots = engine.getSystem<TickerSystem>()?.rootObjects ?? [];
    for (final root in roots) {
      if (root.name == parts[0]) {
        if (parts.length == 1) return root;
        final found = root.findChild(path.substring(parts[0].length + 1));
        if (found != null) return found;
      }

      if (!isAbsolute) {
        final foundStart = root.findChild(parts[0]);
        if (foundStart != null) {
          if (parts.length == 1) return foundStart;
          final foundFull = foundStart.findChild(
            path.substring(parts[0].length + 1),
          );
          if (foundFull != null) return foundFull;
        }
      }
    }
    return null;
  }

  /// Finds the first active [GameObject] with the given [tag], or null.
  ///
  /// Queries the global tag registry in O(1). Multiple objects may share the
  /// same tag; use [findGameObjectsWithTag] to retrieve all of them.
  ///
  /// * [context]: The build context (kept for API consistency).
  /// * [tag]: The tag value to search for.
  static GameObject? findWithTag(BuildContext context, Object tag) {
    return tagRegistry[tag]?.firstOrNull;
  }

  /// Finds all active [GameObject]s that share the given [tag].
  ///
  /// Returns an empty iterable when no object carries the tag. The order
  /// reflects mount order (earliest-mounted first).
  ///
  /// * [context]: The build context (kept for API consistency).
  /// * [tag]: The tag value to search for.
  static Iterable<GameObject> findGameObjectsWithTag(
    BuildContext context,
    Object tag,
  ) => List<GameObject>.from(tagRegistry[tag] ?? const []);

  /// Starts a [coroutine] on this object.
  ///
  /// Coroutines are asynchronous functions that can yield execution back to
  /// the engine, making them ideal for time-based logic, animations, or
  /// sequential game events. They are automatically cancelled when the
  /// object is destroyed.
  ///
  /// ```dart
  /// Stream flashEffect() async* {
  ///   final renderer = getComponent<SpriteRenderer>();
  ///   final original = renderer.sprite;
  ///   for (int i = 0; i < 5; i++) {
  ///     renderer.sprite = null;
  ///     yield WaitForSeconds(0.1);
  ///     renderer.sprite = original;
  ///     yield WaitForSeconds(0.1);
  ///   }
  /// }
  ///
  /// void example(GameObject gameObject) {
  ///   gameObject.startCoroutine(flashEffect);
  /// }
  /// ```
  ///
  /// * [coroutine]: The async logic to run.
  Future<void> startCoroutine(CoroutineFunction coroutine);

  /// Starts a [coroutine] on this object with an initial [option] parameter.
  ///
  /// This is useful for reusable coroutine logic that depends on external state.
  /// Using named records is the preferred way to pass multiple options in a
  /// type-safe and readable manner.
  ///
  /// ```dart
  /// // Define a coroutine that accepts multiple options via a named record
  /// Stream fade(({double target, double speed}) options) async* {
  ///   final renderer = getComponent<SpriteRenderer>();
  ///
  ///   while ((renderer.color.opacity - options.target).abs() > 0.01) {
  ///     renderer.color = renderer.color.withOpacity(
  ///       lerpDouble(renderer.color.opacity, options.target, options.speed)!,
  ///     );
  ///     yield null; // Wait for next frame
  ///   }
  ///   renderer.color = renderer.color.withOpacity(options.target);
  /// }
  ///
  /// void example(GameObject gameObject) {
  ///   gameObject.startCoroutineWithOption(fade, option: (target: 0.5, speed: 0.05));
  /// }
  /// ```
  ///
  /// * [coroutine]: The logic function that accepts the [option].
  /// * [option]: The initial data to pass to the coroutine.
  Future<void> startCoroutineWithOption<T>(
    CoroutineFunctionWithOptions<T> coroutine, {
    required T option,
  });

  /// Stops a specific running [coroutine].
  ///
  /// Use the [Future] returned by `startCoroutine` to identify the routine
  /// you wish to terminate early.
  ///
  /// ```dart
  /// Stream myTask() async* { yield null; }
  ///
  /// void example(GameObject gameObject) {
  ///   final routine = gameObject.startCoroutine(myTask);
  ///
  ///   // Some time later
  ///   gameObject.stopCoroutine(routine);
  /// }
  /// ```
  ///
  /// * [coroutine]: The coroutine future to cancel.
  void stopCoroutine(Future<void> coroutine);

  /// Stops all coroutines currently running on this object.
  ///
  /// You can optionally filter by a specific [coroutine] function reference
  /// to stop only instances of that logic.
  ///
  /// ```dart
  /// Stream flashEffect() async* { yield null; }
  ///
  /// void example(GameObject gameObject) {
  ///   // Stop everything
  ///   gameObject.stopAllCoroutines();
  ///
  ///   // Stop only instances of the 'flashEffect' logic
  ///   gameObject.stopAllCoroutines(flashEffect);
  /// }
  /// ```
  ///
  /// * [coroutine]: Optional function reference to filter the cancellation.
  void stopAllCoroutines([Function? coroutine]);
}
