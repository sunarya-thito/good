import 'dart:typed_data';
import 'package:meta/meta.dart';
import 'package:goo/src/data.dart';

/// Assigns every declared asset instance a stable, process-global integer
/// [GlobalObject.address] the moment it's declared - the exact pattern
/// [ArchetypeRegistry] uses for archetype ids, and for the same reason:
/// `DataPointer<T extends GlobalObject>` (see `hasObject`/`optObject` in
/// data.dart) stores a plain `Uint32` in the row, never a heap reference
/// (RULES.md rule 1 - a component row is native memory, it cannot hold a
/// Dart object pointer), and resolves it back to the live instance on read
/// through this registry rather than by threading an asset-manager
/// reference through every field access. `data.dart`'s own note on
/// `hasObject` ("we don't store the asset manager here") is this: no
/// `DataPointer` implementation ever needs one.
///
/// Global rather than per-manager for the same reason
/// `ArchetypeRegistry` is global rather than per-scene: a `DataPointer`
/// read has no way to reach back to "which manager loaded this," only the
/// address baked into the row.

/// The declare-time pass that names every asset a prefab or a scene needs -
/// the third `describe*` hook alongside `describeType`/`describeStruct`, and
/// RULES.md rule 6 applied to assets.
///
/// There is no asset name and nothing to look up at use time: [has] returns
/// the instance handle, the declarer keeps it in a `late final` field, and
/// that field is the only thing an asset-typed component field will accept.
///
/// ```dart
/// class Player extends EntityStruct<Player> with Renderable2D {
///   static final playerTexture = TextureAsset.bundle('assets/player.png');
///
///   late final Texture texture;
///   late final DataPointer<Texture> sprite;
///
///   @override
///   void describeAssets(AssetDescriptor descriptor) {
///     super.describeAssets(descriptor);
///     texture = descriptor.has(playerTexture);   // typed handle, kept
///   }
///
///   @override
///   void describeStruct(DataDescriptor data) {
///     super.describeStruct(data);
///     sprite = data.hasObject(texture);          // usable as a row default
///   }
/// }
/// ```
///
/// The two types are deliberately distinct: `playerTexture` is a
/// `GameAsset<Texture>` (a *key* - where bytes come from and how to decode
/// them) and `texture` is a `Texture` (a `GameAssetInstance` - the addressed
/// thing a row can point at). So `sprite[e] = playerTexture` does not
/// compile and `sprite[e] = texture` does, which is the whole point of
/// routing every asset through this pass.
abstract class AssetDescriptor {
  /// Declares [key] and returns the instance handle to keep in a field.
  ///
  /// Idempotent per key: calling it twice with the same [GameAsset] - from
  /// two prefabs sharing one texture, or from a second scene that needs the
  /// same UI atlas - returns the *identical* instance, so a shared asset is
  /// one decode and one address, never two.
  T has<T extends GameAssetInstance>(GameAsset<T> key);
}

/// The process-global asset table: which [GameAsset] keys have been
/// declared, the [GameAssetInstance] each one produced, and whether that
/// instance's payload has actually been decoded yet.
///
/// Static rather than an injected instance, matching [ArchetypeRegistry],
/// `ComponentTypeRegistry`, [GlobalObjectRegistry] and `HeapObjectRegistry`
/// - and for the same reason they are. A `DataPointer<Texture>` read has
/// nothing but the `Uint32` address in the row to work with; it cannot reach
/// back to "which manager loaded this". One table, addressed by a key both
/// isolate copies produce identically, is the only shape that works.
///
/// # Declaring and loading are two separate steps
///
/// **Declaring** ([AssetDescriptor.has], which routes here through [declare])
/// creates the instance and assigns its [GlobalObjectRegistry] address. It is
/// synchronous, allocation-cheap, and runs on **both** isolate copies, in the
/// same order, because that order *is* the address assignment - exactly the
/// argument that makes archetype ids agree (see `GameState.loadScene`).
///
/// **Loading** ([load]) reads the key's [GameAssetSource] and decodes it into
/// the already-addressed instance. Decoding generally needs Flutter and
/// `dart:ui`, so it happens on the main isolate only. The game isolate ends
/// up holding a declared, addressed, *unloaded* instance - which is exactly
/// right: it never reads a payload, it only ever writes the address into a
/// component row, and the main isolate resolves that address into the
/// decoded thing when it draws.
///
/// Reading a payload on a copy that never loaded it fails loudly and by name
/// (see [GameAssetInstance.requireLoaded]) rather than null-dereferencing.
final class GameAssets {
  final List<GlobalObject?> _addresses = <GlobalObject?>[];

  /// Registers [object] and returns its new address. Called once, by
  /// [GameAssets.declare] - never call this directly on an object you didn't
  /// just declare; a [GameAssetInstance] refuses a second binding.
  ///
  /// Append-only and never recycled, which is what keeps the two isolate
  /// copies in agreement: both run the same `describeAssets` passes in the
  /// same order, so both hand out the same address for the same asset, and
  /// an [unregister] on one side (which only nulls a slot) cannot shift any
  /// address the other side already assigned.
  int _register(GlobalObject object) {
    final address = _addresses.length;
    _addresses.add(object);
    return address;
  }

  /// Frees [address] and drops the strong reference this registry held -
  /// called by [GameAssets.unload]. The slot becomes `null`, not removed, so
  /// every other address stays stable; [resolve] on a freed address fails
  /// loudly instead of resolving to whatever was registered next.
  /// Frees an address without going through a key - the "this asset was
  /// unloaded out from under a row that still names it" case, which
  /// [resolve] then reports loudly instead of silently resolving.
  @visibleForTesting
  void unregisterAddress(int address) => _unregister(address);

  void _unregister(int address) {
    if (address < 0 || address >= _addresses.length) return;
    _addresses[address] = null;
  }

  /// Resolves [address] to the live object, `null` if nothing is currently
  /// registered there (including a freed one - see [unregister]) or if it's
  /// not a [T].
  T? tryResolve<T extends GlobalObject>(int address) {
    if (address < 0 || address >= _addresses.length) return null;
    final object = _addresses[address];
    return object is T ? object : null;
  }

  /// [tryResolve], but throws instead of returning `null` - what a
  /// `DataPointer<T>` read uses, since a row holding a stale or
  /// never-registered address is a real bug worth failing loudly on, the
  /// same call [Entity.get] makes for a missing component.
  T resolve<T extends GlobalObject>(int address) {
    final object = tryResolve<T>(address);
    if (object == null) {
      throw StateError(
        'No $T registered at asset address $address - either it was never '
        'declared, was unloaded, or the row holds a stale/corrupt value.',
      );
    }
    return object;
  }

  /// Test-only escape hatch, matching [ArchetypeRegistry.reset]/
  /// [ComponentTypeRegistry.reset]: this registry is process-global, so a
  /// test suite that declares many throwaway assets needs a way to start
  /// over. Pair it with [GameAssets.reset], which owns the other half of an
  /// asset's identity (the key -> instance table).
  /// Key -> instance, for every currently declared asset. Identity-keyed:
  /// two separate [GameAsset] instances describing the same underlying file
  /// are two assets, not one (construct a single shared `static final` key if
  /// that is not what you want - which is the intended style, see
  /// [AssetDescriptor]).
  final Map<GameAsset, GameAssetInstance> _instances =
      <GameAsset, GameAssetInstance>{};

  /// In-flight decodes, so two overlapping [load] calls for one key await the
  /// same decode instead of running it twice and leaking whichever payload
  /// loses the race.
  final Map<GameAsset, Future<GameAssetInstance>> _loading =
      <GameAsset, Future<GameAssetInstance>>{};

  /// Declares [key] and returns its instance, creating and addressing it on
  /// first call and returning the identical instance on every later one.
  ///
  /// Internal because [AssetDescriptor.has] is the user-facing spelling: an
  /// asset declared outside a `describeAssets` pass would be declared on
  /// whichever copy happened to run that code, and a declaration that runs on
  /// one copy and not the other is precisely what breaks address agreement.
  @internal
  T declare<T extends GameAssetInstance>(GameAsset<T> key) {
    final existing = _instances[key];
    if (existing != null) return existing as T;
    final instance = key.createInstance();
    instance._bindDeclaration(key, _register(instance));
    _instances[key] = instance;
    return instance;
  }

  /// Reads [key]'s source and decodes it into the instance declared for it,
  /// completing with that instance. A no-op returning the same instance if it
  /// is already loaded.
  ///
  /// Throws if [key] was never declared. That is deliberate rather than a
  /// convenience lazy-declare: declaring here would assign an address on this
  /// copy alone, and the two copies would silently disagree about every
  /// address after it. Declare in a `describeAssets` pass, which both copies
  /// run.
  ///
  /// Call this only on the isolate that can decode - `GameState.loadScene`
  /// already does exactly that for a scene's declared set, which is the
  /// normal way an asset gets loaded.
  /// Every declared key, in the order their addresses were assigned - what
  /// `Game` carries across the spawn instead of the instances themselves.
  ///
  /// **Keys, not instances, and that is the whole point.** A decoded
  /// [GameAssetInstance] holds a native payload (a `dart:ui.Image` for a
  /// texture), which is not sendable and would fail the spawn outright -
  /// verified in `tool/spawn_registry_spike.dart`. A key is plain data. The
  /// spawned copy calls [declare] on each in order, which runs
  /// `createInstance()` - synchronous, payload-free, and the call whose
  /// ordering assigns addresses - so both copies end up with an instance at
  /// the same address and only the decoding copy ever holds bytes.
  ///
  Future<T> load<T extends GameAssetInstance>(GameAsset<T> key) {
    final instance = _instances[key];
    if (instance == null) {
      throw StateError(
        '${key.debugLabel} has not been declared, so there is nothing to load '
        'into. Declare it from a describeAssets pass '
        '(`descriptor.has(theKey)`) on a prefab or a SceneStruct: declaring is '
        'what assigns the asset its process-global address, and it has to '
        'happen on both isolate copies in the same order for that address to '
        'mean the same thing on both sides.',
      );
    }
    final typed = instance as T;
    if (typed._loaded) return Future<T>.value(typed);
    final inFlight = _loading[key];
    if (inFlight != null) return inFlight.then((instance) => instance as T);
    final future = _decode(key, typed);
    _loading[key] = future;
    return future.then((instance) => instance as T);
  }

  Future<GameAssetInstance> _decode<T extends GameAssetInstance>(
    GameAsset<T> key,
    T instance,
  ) async {
    try {
      await key.loadInto(instance);
      instance._loaded = true;
      return instance;
    } finally {
      _loading.remove(key);
    }
  }

  /// The instance declared for [key], or `null` if nothing has declared it
  /// (or it has since been [unload]ed) - a non-throwing peek.
  ///
  /// Declared, not necessarily *loaded*: the returned instance may still be
  /// waiting on its bytes, which is the normal steady state on the game
  /// isolate. [GameAssetInstance.isLoaded] is the separate question, kept
  /// separate because the address is usable long before the payload is.
  T? tryGet<T extends GameAssetInstance>(GameAsset<T> key) =>
      _instances[key] as T?;

  /// Unloads [key]: frees its address in [GlobalObjectRegistry] (any
  /// `DataPointer<T>` row still holding it will fail loudly on next read, per
  /// [GlobalObjectRegistry.resolve] - unloading something still referenced is
  /// a caller bug, not something this silently tolerates), releases whatever
  /// native resources the instance holds via
  /// [GameAssetInstance.onUnloaded], and drops the declaration. A no-op if
  /// [key] isn't currently declared.
  ///
  /// Runs on **both** isolate copies, like declaring - see
  /// `GameState.loadScene`. Only the decode is main-isolate-only; dropping a
  /// declaration on one copy but not the other would leave the two disagreeing
  /// about what is declared, and re-declaring later would then hand out two
  /// different addresses for one asset.
  void unload(GameAsset key) {
    final instance = _instances.remove(key);
    if (instance == null) return;
    _unregister(instance.address);
    instance.onUnloaded();
  }

  /// Unloads everything currently declared - app shutdown, or a test
  /// starting over.
  void unloadAll() {
    for (final instance in _instances.values) {
      _unregister(instance.address);
      instance.onUnloaded();
    }
    _instances.clear();
  }

  /// Test-only escape hatch, matching [GlobalObjectRegistry.reset] /
  /// [ArchetypeRegistry.reset] / `HeapObjectRegistry.reset`: this table is
  /// process-global, so a test suite that declares many throwaway assets
  /// needs a way to start over or every test after the first would see the
  /// previous one's declarations and its decode counters.
  ///
  /// Drops every declaration and calls [GameAssetInstance.onUnloaded] on each
  /// (so a `ui.Image` or other native handle is released rather than leaked),
  /// and forgets any in-flight decode, addresses included.
  @visibleForTesting
  void reset() {
    for (final instance in _instances.values) {
      instance.onUnloaded();
    }
    _instances.clear();
    _loading.clear();
    _addresses.clear();
  }
}

/// One loadable asset **key**: where its bytes come from ([source]), what
/// empty instance it produces ([createInstance]), and how to turn those bytes
/// into that instance's payload ([loadInto]).
///
/// Immutable and identity-compared, so the intended style is one shared
/// `static final` key per asset - two separately-constructed keys naming the
/// same file are two assets, two addresses and two decodes.
///
/// Not generic over its source's byte format: [loadInto] receives raw bytes
/// via `source.load()` and decodes them itself, so a concrete subclass (e.g.
/// `TextureAsset` in `goo2d`) owns the decode step, not this base class.
///
/// The two-method split ([createInstance] synchronous, [loadInto]
/// asynchronous) is what lets an asset be *addressed* on an isolate that
/// cannot decode it - see [GameAssets] for why that matters.
@immutable
abstract class GameAsset<T extends GameAssetInstance> {
  const GameAsset();

  GameAssetSource get source;

  /// Builds the empty, not-yet-decoded instance.
  ///
  /// Synchronous and side-effect-free: this runs during the `describeAssets`
  /// pass on **both** isolate copies, and it is the call whose ordering
  /// assigns every asset its address. It must not touch `dart:ui`, the asset
  /// bundle, or anything else that only exists on the main isolate - that all
  /// belongs in [loadInto].
  T createInstance();

  /// Reads [source] and fills [instance]'s payload.
  ///
  /// Runs only on the isolate that can decode (the main/Flutter one), only
  /// via [GameAssets.load], and exactly once per instance - [GameAssets]
  /// marks the instance loaded when this completes, and will not call it
  /// again for an instance that is already loaded.
  Future<void> loadInto(T instance);

  /// Diagnostics only - what an "asset was never loaded" or "asset was never
  /// declared" message names this asset by. Override when the type name alone
  /// is not enough to tell two keys apart (a path usually is).
  String get debugLabel => '$runtimeType(${source.description})';
}

/// A declared asset instance - what `DataPointer<T extends GlobalObject>`
/// fields actually store a reference to (as an address, see
/// [GlobalObjectRegistry]'s doc). Subclasses hold whatever the decoded
/// resource actually is (a `ui.Image`, a compiled shader, ...) behind a
/// getter that calls [requireLoaded] first.
///
/// An instance exists, and has a usable [address], from the moment it is
/// declared - well before, and possibly forever without, its payload
/// arriving. That is not a degenerate state to guard against; it is the
/// normal steady state on the game isolate, which writes asset addresses into
/// component rows and never decodes anything.
abstract class GameAssetInstance implements GlobalObject {
  GameAsset? _key;
  int? _address;
  bool _loaded = false;

  @override
  int get address {
    final address = _address;
    if (address == null) {
      throw StateError(
        '$runtimeType has not been declared yet - an address is only assigned '
        'by a describeAssets pass (`descriptor.has(theKey)`). A '
        'GameAssetInstance constructed by hand has nothing for a DataPointer '
        'row to point at.',
      );
    }
    return address;
  }

  /// Whether this copy has actually decoded the payload.
  ///
  /// False on the game isolate for every asset, always - see [GameAssets].
  /// [address] is usable either way.
  bool get isLoaded => _loaded;

  /// How diagnostics name this asset - the declaring key's
  /// [GameAsset.debugLabel] once declared.
  String get debugLabel => _key?.debugLabel ?? '$runtimeType (undeclared)';

  /// Called exactly once, by [GameAssets.declare], immediately after
  /// [GameAsset.createInstance] produces this instance.
  void _bindDeclaration(GameAsset key, int address) {
    if (_address != null) {
      throw StateError(
        '$runtimeType is already declared at address $_address. One key '
        'declares one instance; GameAssets.declare returns the existing one '
        'rather than binding a second time, so reaching here means an '
        'instance was passed to two declarations.',
      );
    }
    _key = key;
    _address = address;
  }

  /// What a subclass's payload getter calls before returning its field, so a
  /// read on a copy that never decoded this asset fails by name instead of
  /// null-dereferencing three frames deeper.
  ///
  /// ```dart
  /// ui.Image get image {
  ///   requireLoaded();
  ///   return _image!;
  /// }
  /// ```
  @protected
  void requireLoaded() {
    if (_loaded) return;
    throw StateError(
      '$debugLabel is declared (address $_address) but was never loaded on '
      'this isolate, so its payload cannot be read. Asset bytes are decoded '
      'only on the isolate that can decode them (the main/Flutter one); the '
      'game isolate holds the address and nothing else, by design. If this is '
      'the main isolate, the asset was never passed to GameAssets.load - '
      'declare it on a prefab or scene that GameState.loadScene brings up, '
      'which loads a scene\'s declared set for you.',
    );
  }

  /// Releases whatever the decode produced - a `ui.Image`, a native handle,
  /// a large `Uint8List`. Called by [GameAssets.unload]/[GameAssets.unloadAll]
  /// /[GameAssets.reset] after the address has been freed.
  ///
  /// The base implementation just marks the instance unloaded, so a later
  /// payload read reports "never loaded" rather than handing back a disposed
  /// resource.
  @mustCallSuper
  void onUnloaded() {
    _loaded = false;
  }
}

/// Where an asset's bytes come from - a bundle path, a file, a network
/// fetch, an in-memory blob in a test. Deliberately knows nothing about what
/// the bytes mean; decoding is [GameAsset.loadInto]'s job.
@immutable
abstract class GameAssetSource {
  const GameAssetSource();

  Future<Uint8List> load();

  /// Diagnostics only - what [GameAsset.debugLabel] embeds. Override with
  /// something that identifies the individual source (a path), since the type
  /// name alone is the same for every instance.
  String get description => '$runtimeType';
}
