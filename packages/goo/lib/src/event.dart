import 'package:meta/meta.dart';

/// Something that happens on the **game isolate**, inside the tick window:
/// `FixedTickEvent`, `TickEvent`, `MountEvent`, `UnmountEvent`.
///
/// # There is only one event system, and it is this one
///
/// There used to be two - a `WidgetEvent` half for things that happen where
/// Flutter lives, dispatched to a `WidgetListener`. It is gone, along with
/// the whole idea of a main-isolate listener. What replaced it is simpler:
/// the only main-isolate object is `Game`, the only thing it has to do for
/// Flutter is build a widget, and a method (`Game.buildView`) says that
/// better than an event ever did - an event implies several listeners
/// contributing, and there is exactly one.
///
/// So *every* event in this engine is a game-isolate event, every listener is
/// a [GameListener], and "which isolate does this run on" is no longer a
/// question anyone has to ask about an event. That is the real fix for the
/// hazard the two-hierarchy design was built to catch (registering for a tick
/// on an object that lives on the wrong heap, which compiled fine and then
/// silently never fired): with one hierarchy and one isolate, it cannot be
/// expressed.
abstract class GameEvent<T extends GameListener> {
  void dispatchListener(T listener);

  void tryDispatch(GameListener listener) {
    if (listener is T && listener.listensToEvents) {
      dispatchListener(listener);
    }
  }
}

/// Something on the game isolate that can receive a [GameEvent]: a
/// `GameState`, a `SceneStruct`, or a `GameSystem`.
///
/// # Who is allowed to be one
///
/// Those three and nothing else, and that is enforced rather than asked
/// for: the only implementation, [GameListenerMixin], is `@internal` and is
/// **not exported** from `package:goo/goo.dart`, so a game's own
/// `class MyThing with GameListenerMixin` cannot even name it - and reaching
/// past the export into `src/` to try trips `invalid_use_of_internal_member`
/// on the way.
///
/// `sealed` would be the airtight version, and it was tried. It costs two
/// structural things: an `on` clause naming a sealed type is itself illegal
/// outside that type's library, so all three capability mixins
/// (`FixedTickable`, `Tickable`, `LifecycleListener`) plus all three
/// listener classes would have to collapse into one `part`-based library;
/// and a game could then never write a capability mixin of its own against
/// this type. The `@internal` version buys the same practical guarantee -
/// no game class can become a listener by accident or by trying - without
/// either.
///
/// This half stays a public *contract* (what it means to be a listener) so
/// that the bounds on the capability mixins mean something and a game can
/// still write `mixin MyThing on GameSystem`.
abstract interface class GameListener {
  /// Whether events should be dispatched to this listener at all - a system
  /// that has been disabled, a scene that is being torn down.
  bool get listensToEvents;

  /// Offers [event] to this listener, which takes it if the types match.
  void fireEvent(GameEvent event);
}

/// The one implementation of [GameListener], applied by the framework's three
/// listener types.
///
/// Split from the interface so that "is a listener" and "here is how a
/// listener works" are separate ideas: a subclass overriding [fireEvent] to
/// forward to sub-listeners it owns (a `SceneStruct` forwarding to its
/// prefabs, say) overrides a method with a body, not an abstract one, and
/// `super.fireEvent(event)` means something.
///
/// `@internal`, and deliberately absent from `package:goo/goo.dart`'s
/// exports: this is the door that decides who is a listener, and only the
/// kernel's own three types may walk through it. See [GameListener].
@internal
mixin GameListenerMixin implements GameListener {
  @override
  bool get listensToEvents => true;

  @override
  @mustCallSuper
  void fireEvent(GameEvent event) {
    event.tryDispatch(this);
    // Subclasses that own sub-listeners override this and dispatch onward
    // after calling super.
  }
}
