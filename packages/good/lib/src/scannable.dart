// The three things a scan is allowed to look at, each one opt-in and each one
// a compile error to get wrong.
//
// Nothing here has a member. They exist so that the generic signatures a
// generated collector is reached through carry a bound, and a bound is the
// only kind of "you asked for the wrong thing" this engine accepts: a scanner
// that reported a mistake would report it when somebody ran the tool, and the
// rule is that a typo is a compile error instead.
//
// # Why three and not one
//
// They answer three separate questions, and a single marker would conflate
// them into "this name is involved in declarations somehow":
//
//   * which classes get scanned at all - [Scannable];
//   * which of a scanned class's field types count as declarations -
//     [ScannableField];
//   * which annotations written on those are carried into generated output -
//     [ScannableAnnotation].
//
// Each is separately opted into, so a field of an unrelated type on a scanned
// class is ordinary state, and an annotation the engine has no way to act on
// stays out of the generated table rather than shipping in it.
//
// # Why a supertype and not an annotation
//
// `@Scannable` on a class would be readable, and asking for an unmarked type
// would then compile. `List<F> collectFields<T extends Scannable, F extends
// ScannableField>(T instance)` refuses `collectFields<NotScannable, ...>` at
// the call site, with the analyzer saying which bound was missed. That is the
// same reason `Entity` is a typed handle and not an int.
//
// Marking is inherited, so a user writing `class Player extends EntityStruct`
// has nothing to remember and nothing to keep in step.

/// A class a scan reads declarations off.
///
/// Implemented by the roots a user builds on - `Component` (so every
/// component mixin and every `EntityStruct` carries it), `SceneStruct`,
/// `GameState`, `GameSystem`, `Game` and `TimelineStruct` - never by a user
/// directly.
///
/// It says nothing about *what* the class declares. That is the field's type,
/// which is [ScannableField]'s question.
abstract interface class Scannable {}

/// A value a declaration produces, and therefore a value a collector may
/// hand back.
///
/// The roots that implement it:
///
///   * [DataPointer], so `InitialPointer` and `PackedPointer` come with it;
///   * `DataArrayPointer` - a **separate** root, not a `DataPointer`, which
///     is why it has to say so here rather than being caught by one test on
///     the other;
///   * `Query`;
///   * `EventDispatcher` and `SignalDispatcher`, through the listener set
///     they share.
///
/// # What a root has to be able to do first
///
/// Marking a type here says every field of it is a declaration, and
/// `good_tool --declarations` then refuses each one that is `late`, `static`
/// or filled in from somewhere else. So a root can only be marked once its
/// values can be *produced by the field initialiser* - which means the type
/// has nothing ambient to reach for while it is being built.
///
/// `EventDispatcher` could not, and the reason was written down: a dispatcher
/// had to be created with a binder open around the constructor, and
/// `SceneDescriptor.has` takes a `T Function()` that may hand back an object
/// built long before. That reason is gone. A declaration reserves nothing and
/// resolves nothing where it is written, so a dispatcher is built with its
/// delivery closure and read off the constructed object afterwards -
/// `EventBinder.bind` does it, exactly as `ArchetypeDataDescriptor.realize`
/// does for a column.
///
/// `Sprite`, `ColliderBody`, `ParamPointer`, `StateChannel` and `Track` are
/// declaration values too and are not marked, for the same reason and not a
/// different one: each is still handed out by a descriptor inside a hook, so
/// every field holding one is `late` and marking the type would refuse them
/// all. Each becomes a root with the change that gives it a `Field.*`-shaped
/// spelling, not before.
///
/// A field whose type is not one of these is not a declaration:
///
/// ```dart
/// final speed = Field.float64(220);  // InitialPointer<double>, a declaration
/// final label = 'player';            // ordinary state, and the type says so
/// ```
///
/// Nothing decides at run time whether a field counted. The bound decides, and
/// it decides while the code is being written.
abstract interface class ScannableField {}

/// An annotation a scan carries into what it generates.
///
/// Unbounded, this would put every annotation on every scanned class into a
/// const table that ships - `@override`, `@internal`, `@pragma`,
/// `@Deprecated` - none of which the engine reads. So an annotation opts in,
/// the same way a class and a field type do.
///
/// The cost is that an annotation from outside this engine cannot be read by
/// the scan without implementing this. That is the trade: an annotation the
/// engine has no way to act on has no reason to be in the table.
///
/// Marking is what makes an annotation *carried*, not what makes it
/// meaningful. An annotation the generator merely keys on at build time - one
/// that decides what gets emitted and is then finished with - needs nothing
/// here, because it is never written into the output for anything to look up.
abstract interface class ScannableAnnotation {}
