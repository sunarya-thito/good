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
// The markers a reader needs
// ---------------------------------------------------------------------------

/// The type of [sub]. Written `@sub`, never `@Sub()`.
///
/// Public because the generator keys a table by it and a type argument cannot
/// be a private name; constructed only here, so there is one spelling of the
/// annotation and no way to write a second.
///
/// # Why `sub` and not `child`
///
/// An instance field named `child` shadows a top-level `const child` for the
/// whole of its class body, so a struct that holds one gets `Undefined name
/// 'child' used as an annotation` on **every** marked field in that class and
/// not just on the colliding line. A struct holding a field called `child` is
/// what a scene graph is made of, so this repository's own tests reached it.
/// Shadowing is structural to Dart, so what the marker can do about it is take
/// a name nothing holding a prefab calls a field; `good_lint` carries the
/// diagnostic for the collisions that are left.
///
/// Renaming also lets the type and the const agree again. `Child` was already
/// taken by the mixin a declared prefab keeps its parent handle on
/// (`data/hierarchy.dart`), both are exported from `good.dart`, and that is
/// the only reason the type was ever spelled differently from the annotation.
class Sub implements ScannableAnnotation {
  const Sub._();
}

/// Says the field it is written on declares a child prefab.
///
/// ```dart
/// class Turret extends EntityStruct with Transform2D, Parent {
///   @sub final barrel = Barrel();   // declares a prefab
///   final spare = Barrel();         // declares nothing
/// }
/// ```
///
/// # Why the type is not enough
///
/// It is enough for the *scanner*: `EntityStruct` is a [ScannableField], so a
/// walk over the source can tell what the field holds. It is not enough for
/// whoever reads the file. `final barrel = Barrel();` is spelled exactly like
/// a field holding an ordinary object, and nothing at the line says that
/// bringing the scene up registers an archetype for it, runs its describe
/// passes and reserves a column in this struct's row for the handle.
///
/// So the rule is **shape tells, or annotation tells**:
///
/// ```dart
/// final hp   = Field.float64();   // a dotted static - the shape tells
/// final near = Query.all(A, B);   // a dotted static - the shape tells
/// final tex  = Asset.of(k);       // a dotted static - the shape tells
/// @sub  final enemy = Enemy();    // a bare constructor - nothing tells
/// ```
///
/// A field the reader cannot tell about is the one that carries a marker, and
/// that does not stop being true if the tooling gets better at reading.
///
/// # It is read at build time and never at run time
///
/// `good_tool` reads this off the source and leaves an unmarked
/// bare-constructor field out of the generated collector. Nothing looks the
/// annotation up while a game runs, and [collectDeclarations] never sees the
/// difference - it is handed the list the generator wrote.
///
/// An unmarked field is **reported and not refused**: holding a spare
/// instance of a declarable type is ordinary code, and half the reason this
/// marker exists is that such a field stays legal. `good_tool --declarations
/// --verbose` names every one of them.
const Sub sub = Sub._();

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
/// It throws, and it has to. A lookup that answered "none" on a miss would
/// give an archetype an empty row and a scene an event nobody is ever told
/// about, and say nothing about either - the silence this engine keeps
/// paying for.
///
/// What makes that throw safe is the generator, not the class: `good_tool`
/// writes an entry for **every** instantiable scanned class, holding an empty
/// list where the class declares nothing. So a miss has exactly one meaning -
/// this class was never scanned - and "declares nothing" and "never generated
/// for" are two different answers rather than one.
///
/// An earlier version of this paragraph argued the other way, that no scanned
/// class declares nothing because every `EntityStruct` inherits two
/// dispatchers and every `SceneStruct` two more. That is true of structs and
/// false of commands: `GameCommandBase` is scanned too, and
/// `final class StepOnceCommand extends SignalCommand {}` declares nothing at
/// all. It reached a table with no line for it, and `_bootMain` threw on a
/// class that had been scanned and had nothing to say.
List<ScannableField> collectDeclarations(Object object) {
  final collect = DeclarationRegistry.collectorForInstance(object);
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
/// An entry in a list rather than a `Map<Type, ...>` literal, so a generated
/// table reads in a diff the way `GeneratedComponentBits.types` does - one
/// line per class, in a fixed order - and so the registry is the one place
/// that decides what two tables claiming one class means.
///
/// Two constructors, because a `Type` answers for a class with no type
/// parameters and cannot answer for one that has them. See
/// [DeclarationCollector.generic].
@immutable
class DeclarationCollector {
  /// A class with no type parameters, matched against `runtimeType` exactly.
  ///
  /// A subclass gets its own entry, holding its own fields as well as these,
  /// so exact is the whole of the match.
  const DeclarationCollector(this.type, this.collect) : matches = null;

  /// A generic class, matched against every instantiation of it.
  ///
  /// # Why a type test and not a key
  ///
  /// `Type` is opaque at run time - it compares and it prints, and there is
  /// no way to take type arguments off one. So for
  /// `class Spawner<T extends EntityStruct> extends EntityStruct`, the
  /// literal `Spawner` this table is keyed by is `Spawner<EntityStruct>`
  /// (instantiate-to-bounds) and an instance's `runtimeType` is
  /// `Spawner<Enemy>`. They never compare equal, so every generic scanned
  /// class missed its own collector and threw.
  ///
  /// What the run cannot obtain, the generator writes down: [matches] is
  /// `(object) => object is Spawner`, emitted beside the collector. Dart
  /// generics are covariant, so that is true of every legal instantiation
  /// and of nothing else with that class above it - which is the same answer
  /// stripping the type arguments would have given.
  ///
  /// # What one entry per class costs
  ///
  /// Nothing, because a collector reads *field names* and a class's field
  /// list does not vary by type argument - `Spawner<Enemy>` and
  /// `Spawner<Pickup>` declare the same fields in the same order. Keying per
  /// instantiation would need the generator to enumerate instantiations
  /// across every library that writes one, which it cannot see.
  ///
  /// # The one thing this widens
  ///
  /// A subclass of a generic class answers `is` too. A *scanned* one has its
  /// own entry and is found by the exact match first, so it never reaches
  /// here. One the generator never read does reach here, and now collects
  /// its superclass's declarations instead of throwing "never scanned". That
  /// is the trade: it is only ever a class no generator saw, which is what
  /// `good_tool --check` in CI is for.
  const DeclarationCollector.generic(this.type, this.collect, this.matches);

  /// The class this reads.
  final Type type;

  /// Reads that class's declarations off an instance of it, in declaration
  /// order. It casts, so handing it anything else throws.
  final List<ScannableField> Function(Object object) collect;

  /// Whether an object is an instantiation of a generic [type], or null for
  /// a class with no type parameters. See [DeclarationCollector.generic].
  final bool Function(Object object)? matches;
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

  /// The entries for generic classes, which no `runtimeType` ever equals.
  ///
  /// Walked only when the exact map misses, so a class with no type
  /// parameters pays one map lookup and nothing else.
  static final List<DeclarationCollector> _generic = <DeclarationCollector>[];

  /// What [_generic] answered for a `runtimeType`, so the walk runs once per
  /// instantiation rather than once per registration.
  ///
  /// Kept apart from [_collectors] so that installing a table later cannot
  /// find one of these sitting in the place its own entry belongs; the whole
  /// cache is dropped whenever anything is installed.
  static final Map<Type, List<ScannableField> Function(Object)> _matched =
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
        if (collector.matches != null) _generic.add(collector);
      }
      for (final dependency in table.dependencies) {
        walk(dependency);
      }
    }

    for (final table in tables) {
      walk(table);
    }
    _matched.clear();
  }

  /// The collector that reads [object], or null when nothing installed holds
  /// one.
  ///
  /// It takes the object and not its `runtimeType`, and that is the whole of
  /// what a generic class needed. A `Type` can be compared and printed and
  /// nothing else - there is no run-time way to take `<Enemy>` off
  /// `Spawner<Enemy>` - so a table keyed by the literal `Spawner` was
  /// unreachable from any instance of it. What answers instead is a type test
  /// the generator wrote, which needs the value rather than its type. See
  /// [DeclarationCollector.generic].
  static List<ScannableField> Function(Object)? collectorForInstance(
    Object object,
  ) {
    final type = object.runtimeType;
    final exact = _collectors[type];
    if (exact != null) return exact;
    final cached = _matched[type];
    if (cached != null) return cached;
    DeclarationCollector? found;
    for (final candidate in _generic) {
      if (!candidate.matches!(object)) continue;
      if (found != null) {
        throw StateError(
          '$type is an instantiation of both ${found.type} and '
          '${candidate.type}, so two collectors claim it and they read '
          'different field lists. One of those classes extends the other, '
          'and picking between them needs a most-derived-first order that a '
          'merge of tables from several packages does not have. Give the '
          'more derived one a non-generic subclass to register instead.',
        );
      }
      found = candidate;
    }
    if (found == null) return null;
    return _matched[type] = found.collect;
  }

  /// Forgets everything installed.
  ///
  /// For a test that installs a table and must not leak it into the next one.
  /// A game never calls it: the collectors are facts about the program, and
  /// dropping them mid-run leaves the next registration with nothing.
  @visibleForTesting
  static void reset() {
    _collectors.clear();
    _generic.clear();
    _matched.clear();
    _packages.clear();
  }
}
