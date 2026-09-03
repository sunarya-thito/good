import 'package:meta/meta.dart';

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
///     they share;
///   * `Asset`, whose handle carries a key and takes its address when the
///     scene holding it is brought up;
///   * `EntityStruct`, so a struct held in another struct's field is that
///     struct's declared child.
///
/// The last one is the one that reads oddly, because an `EntityStruct` is a
/// whole prefab rather than a handle to something. It is a declaration for
/// the same reason the rest are: the field holds a value nothing registered,
/// and the class that holds it is what the registration has to be attributed
/// to. `_SceneDescriptor._register` is what reads them back off.
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
/// `Asset` and `EntityStruct` are the two most recent, and both were held
/// back by the same thing. `Asset.of` reached an ambient asset descriptor and
/// `EntityStruct.of` an ambient prefab registrar, so neither value could be
/// produced by a field initialiser alone. Now `Asset.of` builds a handle
/// carrying a key and `Barrel()` builds a prefab, and the scene addresses and
/// registers what it finds afterwards.
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

// ---------------------------------------------------------------------------
// The collectors
// ---------------------------------------------------------------------------

/// Reads every declaration [object] holds, in the order its class declares
/// them.
///
/// This is the whole of what replaced the ambient window. A declaration
/// reaches nothing where it is written - `Field.float64(3)` builds a column
/// and hands it back, `Event.of(...)` builds a dispatcher and hands it back -
/// so the only record of what a class declared is the fields it holds, and
/// this is what reads them back off. `ArchetypeDataDescriptor.declare` and
/// `EventBinder.declare` each take what comes out and keep the part they can
/// use.
///
/// # The order, and why it is a requirement rather than a description
///
/// A row's field order is the order its columns were declared in, so the list
/// this hands back *is* the layout of every entity of that archetype. It is:
///
///  1. the class's own fields, in source order;
///  2. then each mixin application's, **last in the `with` clause first**;
///  3. then the superclass's, the same way, recursively.
///
/// That is what Dart itself does with the same `with` clause - a class's own
/// field initialisers run before its superclass constructor, and a mixin
/// application is a superclass - so for as long as the window collected
/// declarations while those initialisers ran, this order was a consequence of
/// the mechanism. It is not one any more: nothing runs at a declaration, so
/// the generator is what has to hand them over in that order, and `good_tool`
/// does it by walking the `extends` and `with` clauses it read.
///
/// # Why it is generated
///
/// A run cannot ask an object what fields it has. That is the whole of the
/// reason - not that reflection would be slow, but that AOT Dart has none at
/// all. So the field list is read out of the source at build time and written
/// into `lib/src/declarations.g.dart`, the same way the component-bit table
/// is; see [GeneratedDeclarations].
///
/// # What a missing collector means
///
/// It throws, and it has to. Every `EntityStruct` inherits two dispatchers
/// and every `SceneStruct` two more, so no scanned class declares nothing; a
/// lookup that missed and answered "none" would give an archetype an empty
/// row and a scene an event nobody is ever told about, and say nothing about
/// either. That silence is the failure this engine keeps paying for, so the
/// miss is loud instead.
List<ScannableField> collectDeclarations(Object object) {
  final collect = DeclarationRegistry.collectorFor(object.runtimeType);
  if (collect == null) {
    throw StateError(
      'No generated collector for ${object.runtimeType}. Its declarations are '
      'fields it holds, and nothing at run time can list a class\'s fields - '
      'so the list is read out of the source at build time and installed '
      'before anything registers.\n'
      '\n'
      'Either the table holding ${object.runtimeType} was never named to '
      '`Game.declarations` - a scene brought up without a `Game` names it '
      'itself, through `DeclarationRegistry.installGenerated` - or the '
      'generator never read the file ${object.runtimeType} is written in. Run '
      '`dart run good_tool --dir <directory>` and commit what it writes.',
    );
  }
  return collect(object);
}

/// One package's generated collectors, keyed by the class each one reads.
///
/// Written by `good_tool` into `lib/src/declarations.g.dart` in each package
/// that declares anything, and reached through that package's entry library -
/// `goodDeclarations`, `goo2dDeclarations`. A game names the ones it uses to
/// `Game.declarations`; importing one installs nothing.
///
/// # Why it names its dependencies
///
/// The same reason `GeneratedComponentBits` does: a game on `goo2d` gets
/// `Child`, `Parent` and every `good` root collected without having to know
/// that `goo2d` is built on `good`.
///
/// # Why installing it is nothing like seeding component bits
///
/// A component bit is a *number*, so seeding twice, or in a different order,
/// renumbers types that already hold one and every signature built so far
/// stops matching. A collector is a function looked up by the class it reads.
/// There is no numbering, so installing is a merge: any order, any number of
/// times. The one thing that can go wrong is two tables claiming one class,
/// which is a build holding two versions of a package and throws saying so.
@immutable
class GeneratedDeclarations {
  const GeneratedDeclarations({
    required this.package,
    required this.collectors,
    this.dependencies = const <GeneratedDeclarations>[],
  });

  /// The package this table was generated for, and the key it is installed
  /// once under.
  final String package;

  /// Its collectors, one per class with a declaration anywhere above it.
  final List<DeclarationCollector> collectors;

  /// The tables of the packages this one is built on.
  final List<GeneratedDeclarations> dependencies;
}

/// One class's collector: the class, and the function that reads it.
///
/// A pair in a list rather than a `Map<Type, ...>` literal, so a generated
/// table reads in a diff the way `GeneratedComponentBits.types` does - one
/// line per class, in a fixed order - and so the registry is the one place
/// that decides what two tables claiming one class means.
@immutable
class DeclarationCollector {
  const DeclarationCollector(this.type, this.collect);

  /// The class this reads. Matched against a value's `runtimeType` exactly: a
  /// subclass gets its own entry, holding its own fields as well as these.
  final Type type;

  /// Reads that class's declarations off an instance of it, in declaration
  /// order. It casts, so handing it anything else throws.
  final List<ScannableField> Function(Object object) collect;
}

/// Every installed collector, keyed by the class it reads.
///
/// Process-global and per-isolate, exactly as `ComponentTypeRegistry` is and
/// for the same reason: [collectDeclarations] is reached from a scene
/// registration and from an event bind, neither of which has a `Game` in
/// scope, and a scene brought up headlessly never has one at all.
abstract final class DeclarationRegistry {
  static final Map<Type, List<ScannableField> Function(Object)> _collectors =
      <Type, List<ScannableField> Function(Object)>{};

  /// The packages installed so far.
  static final Set<String> _packages = <String>{};

  /// Installs [tables] and, transitively, everything they depend on.
  ///
  /// Idempotent and order-independent - see [GeneratedDeclarations] for why
  /// that is not the concession it would be for a bit table. Installing one
  /// package twice is a no-op; installing two different builds of it throws,
  /// because a collector reading the wrong field list is a row that silently
  /// holds the wrong columns.
  static void installGenerated(Iterable<GeneratedDeclarations> tables) {
    void walk(GeneratedDeclarations table) {
      if (!_packages.add(table.package)) return;
      for (final collector in table.collectors) {
        final existing = _collectors[collector.type];
        if (existing != null) {
          throw StateError(
            'Two generated tables both hold a collector for '
            '${collector.type}. One is from another build of the package '
            'that declares it, and whichever of them was asked would read '
            'the other one\'s field list. Regenerate, or depend on one '
            'version of it.',
          );
        }
        _collectors[collector.type] = collector.collect;
      }
      for (final dependency in table.dependencies) {
        walk(dependency);
      }
    }

    for (final table in tables) {
      walk(table);
    }
  }

  /// The collector for [type], or null when nothing installed holds one.
  static List<ScannableField> Function(Object)? collectorFor(Type type) =>
      _collectors[type];

  /// Forgets everything installed.
  ///
  /// For a test that installs a table and must not leak it into the next one.
  /// A game never calls it: the collectors are facts about the program, and
  /// dropping them mid-run leaves the next registration with nothing.
  @visibleForTesting
  static void reset() {
    _collectors.clear();
    _packages.clear();
  }
}
