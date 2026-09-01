import 'dart:typed_data';

import 'package:flutter/foundation.dart' show FlutterError;
import 'package:flutter/services.dart' show AssetBundle, rootBundle;
import 'package:meta/meta.dart';
import 'package:good/src/data.dart';
import 'package:good/src/declare.dart';

// ---------------------------------------------------------------------------
// The three-way split
//
// An asset is three separable things, and keeping them apart is what lets one
// of them exist on an isolate that can never produce the others:
//
//   AssetKey   identity   every copy, always, plain sendable data
//   AssetInfo  shape      every copy, after load, plain sendable data
//   T          value      the decoding copy only, unsendable
//
// `Asset<T>` is the handle that binds the three together and carries the
// integer a component row stores.
// ---------------------------------------------------------------------------

/// Where an asset's bytes come from - a bundle path, a packed chunk, an
/// in-memory blob in a test. A source knows nothing about what the bytes
/// mean; decoding is [AssetLoader]'s job, and decryption or decompression
/// happen *here*, below [load], so a loader never learns the game shipped
/// encrypted.
///
/// **Value equality is required, not optional.** A source is half of an
/// asset's identity (see [Assets.declare]), so two separately-constructed
/// `BundleSource('a.png')` must be equal or the same file becomes two assets,
/// two addresses and two decodes. It also has to survive `Isolate.spawn`,
/// which copies: an identity-compared source arrives on the other side equal
/// to nothing, which is precisely the bug the old `GameAsset` worked around
/// with an address-keyed adopt path.
@immutable
abstract class AssetSource {
  const AssetSource();

  /// The plaintext bytes. Reads, decrypts and decompresses as needed.
  Future<Uint8List> load();

  /// Pre-flight: whether the bytes for this asset are there to be read.
  ///
  /// Never reads asset bytes and never decodes - this is what a startup
  /// readiness check calls over every declared asset, and it has to stay
  /// cheap enough to run over all of them. See [AssetAvailability] for what
  /// each answer does and does not promise.
  Future<AssetAvailability> check();

  /// Diagnostics only - what [AssetKey.debugLabel] embeds. Override with
  /// something that identifies the individual source (a path), since the type
  /// name alone is the same for every instance.
  String get description => '$runtimeType';
}

/// What a [AssetSource.check] found, and what it did not.
enum AssetAvailability {
  /// Nothing in the manifest names this. The build never knew about it -
  /// typically stale codegen naming an asset the packer never saw.
  unknown,

  /// The manifest has it, but its backing file is absent or the wrong size.
  /// A failed or partial install, or something deleted after the fact.
  missing,

  /// Manifest entry and backing bytes both present at the expected size.
  ///
  /// **Not a promise the bytes are intact.** Verifying that means reading and
  /// hashing everything, which is exactly what this check exists not to do.
  /// Corruption *within* a chunk surfaces at load: authenticated encryption
  /// fails its tag instead of yielding garbage, and an unencrypted build fails
  /// in the decoder.
  present,

  /// Cannot be answered without I/O this check refuses to perform - a network
  /// source. Neither a pass nor a failure; a readiness report should say so
  /// instead of counting it either way.
  unverifiable,
}

// --- the mount table -------------------------------------------------------

/// One tier of the mount table: bytes named by a logical asset path.
///
/// A mount answers for the paths it carries and returns `null` for the rest,
/// which is what lets several of them stack. The table is ordered and **a
/// later mount shadows an earlier one**, so the shipped content sits at the
/// bottom and a DLC directory, a mod folder, a downloaded patch or the source
/// tree during development go on top of it. Game code names one logical path
/// and cannot tell which tier answered - the same reason [BundleSource] kept
/// its path logical when packing arrived.
///
/// Unlike [AssetSource], a mount is **not** part of an asset's identity, so it
/// needs no value equality: it is process configuration, mounted once at
/// startup and removed by reference.
abstract class AssetMount {
  const AssetMount();

  /// The plaintext bytes at [path], or `null` if this mount does not carry it.
  ///
  /// `null` means *ask the tier below*, and nothing else. A mount that carries
  /// [path] and cannot produce it - a truncated file, a chunk that fails its
  /// authentication tag - **throws**, because falling through would quietly
  /// serve a stale copy from under a corrupt one and call that success.
  Future<Uint8List?> tryRead(String path);

  /// What can be said about [path] without reading it, or `null` if this mount
  /// does not carry it and cannot claim to.
  ///
  /// [AssetAvailability.unknown] is the one answer that does not end the
  /// search: it means *this mount has a manifest and [path] is not in it*,
  /// which is a finding worth reporting but not a reason to stop asking the
  /// tiers below. See [AssetMounts.check].
  Future<AssetAvailability?> check(String path);

  /// Drops whatever this mount is holding.
  ///
  /// Called at a scene boundary, where the engine knows a burst of loading has
  /// ended. A no-op for a mount that caches nothing.
  void release() {}

  /// Diagnostics only - what a "nothing carries this asset" message lists.
  /// Override with something that identifies the individual mount.
  String get description => '$runtimeType';
}

/// The process's ordered mount table: **later shadows earlier**.
///
/// A process-global, not something threaded through: [BundleSource] is a
/// `const` value object created wherever a key is declared, so there is nothing
/// to thread a table through. Mount at startup, before the first asset load.
///
/// The table has a floor it does not contain. [BundleSource] falls back to the
/// app's own [AssetBundle] when no mount answers, because on Android the
/// bundle is the only thing that can be read at all - assets are compressed
/// zip entries with no filesystem path - so what shipped inside the app can
/// never be unmounted, only shadowed.
abstract final class AssetMounts {
  static final List<AssetMount> _mounts = <AssetMount>[];

  /// The table, bottom tier first. A copy; mutate through [mount].
  static List<AssetMount> get mounts => List<AssetMount>.unmodifiable(_mounts);

  /// Adds [mount] on top, shadowing everything already mounted.
  static void mount(AssetMount mount) => _mounts.add(mount);

  /// Removes [mount] and releases it. Returns whether it was mounted.
  static bool unmount(AssetMount mount) {
    if (!_mounts.remove(mount)) return false;
    mount.release();
    return true;
  }

  /// Empties the table, releasing every mount.
  static void clear() {
    release();
    _mounts.clear();
  }

  /// Releases every mount without unmounting any - the scene-boundary call.
  ///
  /// A scene load is a burst of reads that all want the same few chunks, and
  /// the moment it ends those chunks are dead weight: what the game needs from
  /// there on is the decoded `ui.Image`, not the compressed bytes it came
  /// from. `GameState` is the one place that knows the burst is over, which is
  /// why no mount tries to guess it with a timer.
  static void release() {
    for (final mount in _mounts) {
      mount.release();
    }
  }

  /// The bytes at [path] from the topmost mount that carries it, or `null`.
  ///
  /// Walked top down, so the last mount wins. This is a load-time path - once
  /// per asset, behind [Assets.load]'s in-flight dedupe and followed by an
  /// image or audio decode - so the walk is written for the shadowing rule to
  /// be obvious, not for the table to be traversed cheaply.
  static Future<Uint8List?> tryRead(String path) async {
    for (var i = _mounts.length - 1; i >= 0; i--) {
      final bytes = await _mounts[i].tryRead(path);
      if (bytes != null) return bytes;
    }
    return null;
  }

  /// What the table can say about [path] without reading it, or `null` if
  /// nothing mounted carries it.
  ///
  /// Top down, and the first mount with a real answer ends it.
  /// [AssetAvailability.unknown] is the exception: a mount that has a manifest
  /// and does not list [path] has found something worth reporting, but a tier
  /// below may still carry the asset - so the finding is remembered and the
  /// walk continues, and it is the answer only if nothing else claims [path].
  static Future<AssetAvailability?> check(String path) async {
    AssetAvailability? unlisted;
    for (var i = _mounts.length - 1; i >= 0; i--) {
      final answer = await _mounts[i].check(path);
      if (answer == null) continue;
      if (answer == AssetAvailability.unknown) {
        unlisted = answer;
        continue;
      }
      return answer;
    }
    return unlisted;
  }
}

/// A mount backed by a Flutter [AssetBundle] - what shipped inside the app.
///
/// Mounting one is only needed for a *second* bundle, or to give an
/// `AssetPack` somewhere other than `rootBundle` to read its chunks from. The
/// app's own bundle is already [BundleSource]'s floor and does not have to be
/// mounted to be reachable.
class BundleMount extends AssetMount {
  const BundleMount({this.bundle});

  /// The bundle to read from, or `null` for `rootBundle`.
  final AssetBundle? bundle;

  @override
  Future<Uint8List?> tryRead(String path) async {
    final ByteData data;
    try {
      data = await (bundle ?? rootBundle).load(path);
    } on FlutterError {
      // The only failure `AssetBundle` reports for a key it does not have, and
      // the only one `load` can raise at all - it reads bytes, it does not
      // decode them, so nothing here can be swallowing a real decode error.
      return null;
    }
    // A view, not a copy: `ByteData.buffer` may be larger than the asset when
    // the bundle packs several together, so the offset and length matter.
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }

  @override
  Future<AssetAvailability?> check(String path) async {
    // Never claims a path. A bundle entry cannot be stat-ed - `AssetBundle`
    // exposes only `load`, and loading *is* reading - so the honest answer is
    // that this tier cannot say, which leaves the tiers below free to.
    return null;
  }

  @override
  String get description => bundle == null ? 'the app bundle' : 'a bundle';
}

/// One loadable asset's **identity**: which asset this is, and nothing else.
///
/// Identity is `(T, source)` - the payload type and where the bytes come from.
/// Nothing about the *shape* or *value* of the decoded asset belongs here. An
/// image's pixel size is discovered by decoding it ([AssetInfo]); how a sprite
/// samples it is a property of the sprite. Put either on the key and a build
/// pipeline that repacks or recompresses an asset rewrites its identity.
///
/// Plain, immutable, sendable data with a phantom type parameter - it makes
/// nothing and fills nothing. That is what lets a key cross `Isolate.spawn`
/// while the decoded payload, which owns a `ui.Image` or a native handle,
/// stays on the copy that made it.
///
/// Instantiable as-is; subclass only to override [loader]:
///
/// ```dart
/// const AssetKey<Texture>(BundleSource('player.png'))
/// ```
@immutable
class AssetKey<T> {
  const AssetKey(this.source);

  final AssetSource source;

  /// The payload type this key names, as a runtime value.
  ///
  /// Half of an asset's identity, and it has to come from the *instance*, not
  /// from a call site's type argument. A declared set is held as
  /// `List<AssetKey<Object?>>` - one list, many payload types - so a
  /// `_identityOf<T>(key)` keyed on the static `T` would compute
  /// `(Object?, source)` there and `(Texture, source)` at the declare site,
  /// and the same asset would fail to match itself. Dart reifies type
  /// arguments, so `T` read here is the real one either way.
  Type get payloadType => T;

  /// Builds this key's handle at [address].
  ///
  /// Lives here and not in [Assets] for the same reason [payloadType] does.
  /// `Assets.adoptAt` receives its key as `AssetKey<Object?>` - the
  /// request that crossed the isolate boundary carries a heterogeneous list -
  /// so constructing `Asset<T>` there would bind `T` to `Object?` and produce
  /// a handle that `Assets.of<Texture>()` then refuses to unpack, because
  /// `Asset<Object?>` is not an `Asset<Texture>`. Constructed here, `T` is the
  /// instance's reified argument and the handle comes out correctly typed
  /// whatever the call site's static view of the key.
  @internal
  Asset<T> newAsset(int address) => Asset<T>._(this, address);

  /// What turns this key's bytes into a [T].
  ///
  /// Defaults to the loader registered for [T], which is what makes the bare
  /// `AssetKey<Texture>(...)` above work with no subclass. Override on a key
  /// subclass in the one case the registry cannot express: two asset kinds
  /// that decode to the same payload type.
  ///
  /// Consulted **only on the isolate that decodes**. Declaring and adopting
  /// build an `Asset<T>` directly, so a game isolate never touches the
  /// registry and cannot fail on an unregistered one.
  AssetLoader<T> get loader => AssetLoaders.of<T>();

  /// Diagnostics only - what an "asset was never loaded" or "asset was never
  /// declared" message names this asset by.
  String get debugLabel => '$T(${source.description})';
}

/// Turns an [AssetKey]'s bytes into a [T], and releases it again.
///
/// One per payload type, registered once with [AssetLoaders]. Decoding lives
/// here and not on the key, which is what leaves [AssetKey] as pure identity
/// and lets a key be constructed without subclassing anything.
///
/// Every member runs **only on the isolate that can decode** (the
/// main/Flutter one), via [Assets.load]. A `dart:ui` call here is correct and
/// expected; the game isolate never reaches this class.
abstract class AssetLoader<T> {
  const AssetLoader();

  /// Reads [key]'s source and produces the decoded payload.
  ///
  /// Called at most once per asset - [Assets] records the result and collapses
  /// overlapping requests for one key into a single call.
  Future<T> load(AssetKey<T> key);

  /// Releases what [load] produced - a `ui.Image`, a native handle, a large
  /// `Uint8List`. Called only on the copy that actually loaded.
  ///
  /// The base implementation does nothing, which is right for a payload the
  /// Dart GC can reclaim on its own.
  void unload(T value) {}

  /// A sendable summary of [value], replicated to every copy - **including
  /// the ones that can never hold [value] itself**.
  ///
  /// This is how a fact discovered by decoding reaches an isolate that cannot
  /// decode. An image's true pixel size is the reference case: the game
  /// isolate needs it and cannot find it out, so it is discovered on the copy
  /// that can decode and shipped to the copy that cannot. Declare a size on the
  /// key instead and you have a second copy of a fact that can be wrong.
  ///
  /// Null when nothing about the decoded asset is needed off-isolate.
  AssetInfo? describe(T value) => null;
}

/// A plain-data summary of a decoded asset - see [AssetLoader.describe].
///
/// Must be sendable: it crosses the isolate boundary in the load-completion
/// message. Keep it to numbers, strings and typed data.
@immutable
abstract class AssetInfo {
  const AssetInfo();
}

/// The registry [AssetKey.loader] falls back to: one [AssetLoader] per payload
/// type.
///
/// Register from library bring-up on the decoding isolate. Nothing on the
/// declare path consults it - `declare` and `adoptAt` build an `Asset<T>`
/// without a loader - so a game isolate that never registers anything is a
/// supported configuration, not a latent crash.
final class AssetLoaders {
  AssetLoaders._();

  static final Map<Type, Object> _loaders = <Type, Object>{};

  /// Registers [loader] as the decoder for payload type [T], replacing any
  /// previous registration.
  ///
  /// **Replaces, so the last registration for a type wins.** That is what
  /// makes `Game.describeAssetLoaders` work the way the rest of the `describeX`
  /// family does: a subclass calls `super` first and then registers, so its own
  /// decoder for a type the engine already covers takes over. Overriding an
  /// engine decoder is a supported thing to do, and this is how.
  static void register<T>(AssetLoader<T> loader) => _loaders[T] = loader;

  /// Whether a decoder for [T] is registered on this isolate.
  ///
  /// [of] answers the same question by throwing, which is right for a decode
  /// path and useless for anything that needs to *ask* - a test proving the
  /// game isolate registered nothing, most of all.
  static bool isRegistered<T>() => _loaders.containsKey(T);

  /// The loader for [T], or a `StateError` naming what is missing.
  static AssetLoader<T> of<T>() {
    final loader = _loaders[T];
    if (loader == null) {
      throw StateError(
        'No AssetLoader<$T> is registered on this isolate, so an asset of that '
        'type cannot be decoded here. Call AssetLoaders.register<$T>(...) '
        'during bring-up on the isolate that decodes. If this fired on a game '
        'isolate, something reached a decode path that should never run there '
        '- declaring and adopting do not need a loader.',
      );
    }
    return loader as AssetLoader<T>;
  }

  /// Test-only: drops every registration, so one suite's throwaway loaders
  /// cannot answer for the next one's assets.
  @visibleForTesting
  static void reset() => _loaders.clear();
}

/// What `Game.describeAssetLoaders` hands each layer to register into.
///
/// A one-method view of [AssetLoaders], for the reason every other `describeX`
/// pass takes a descriptor: the hook is a declaration, and what it declares
/// into is the framework's business. It also keeps the pass honest - a hook
/// that was handed the static registry directly could just as easily read it,
/// reset it, or run at a moment nothing constrains.
abstract interface class AssetLoaderRegistrar {
  /// Registers [loader] as this game's decoder for payload type [T].
  ///
  /// Later wins, so a subclass registering after its `super` call replaces
  /// whatever the layer below registered for [T]. See [AssetLoaders.register].
  void register<T>(AssetLoader<T> loader);
}

/// A declared asset: its identity, its address, and - on the copy that loaded
/// it - its payload.
///
/// **Concrete, generic, and never subclassed**, and that is the property the
/// whole design turns on. Because [Assets] can name this type outright it can
/// construct one itself, synchronously, at declare time, with no factory and
/// no bytes. That is what lets [AssetLoader] have a single `load` method
/// instead of the `createInstance`/`loadInto` pair this replaces: nothing has
/// to manufacture an empty payload-typed instance, because the payload type is
/// no longer the addressed thing.
///
/// Name the handle, not the payload, in a field:
///
/// ```dart
/// typedef TextureAsset = Asset<Texture>;
///
/// late final TextureAsset texture;                // Asset<Texture>
/// late final DataPointer<TextureAsset> sprite;
/// ```
///
/// # It is normal for this to hold no payload
///
/// An asset is *declared* - and therefore addressed - on both isolate copies,
/// but only *decoded* on the one with Flutter attached. The game isolate's
/// copy holds the address and the key, forever, and that is exactly what it
/// needs: it writes the address into component rows and never draws. Reading
/// [value] there throws by name instead of null-dereferencing.
final class Asset<T> implements IntRepresentable {
  Asset._(this.key, this._address);

  /// Declares [key] against the scene being brought up and hands back its
  /// handle, so a prefab names an asset in the field that holds it instead of
  /// in a `describeAssets` pass and a `late final`.
  ///
  /// ```dart
  /// class Player extends EntityStruct with Transform2D, Renderable2D {
  ///   final texture = Asset.of(Textures.player);
  /// }
  /// ```
  ///
  /// This is [AssetDescriptor.has] reached without being handed the
  /// descriptor - the same call, doing the same registration, so a scene
  /// loads the asset exactly as it did before. What changes is who writes the
  /// call, not what it does. `Field.float64` is the same move made for
  /// columns, and the descriptor it reaches is [DeclarationContext.assets].
  ///
  /// **Idempotent per identity**, because [AssetDescriptor.has] is: two
  /// prefabs writing `Asset.of(Textures.player)` get the *identical* handle,
  /// one address and one decode. That is what stops a declaration moving to
  /// the use site turning one shared texture into two.
  ///
  /// Throws when nothing is being brought up - a prefab constructed by hand,
  /// or a `late final` that runs on first read rather than during the pass
  /// both isolate copies run. A `SceneStruct`'s own field initialisers throw
  /// too: a scene is constructed by the caller and has no `Assets` until
  /// `initializeScene`, so a scene declares in `describeAssets`, which is
  /// handed the same descriptor this reads.
  static Asset<T> of<T>(AssetKey<T> key) =>
      DeclarationContext.assets.has<T>(key);

  /// What this asset is. Readable on every copy, loaded or not.
  final AssetKey<T> key;

  final int _address;

  T? _value;
  AssetInfo? _info;

  /// Its address in the [Assets] that declared it. Meaningful only there.
  @override
  int pack() => _address;

  /// Whether this copy has actually decoded the payload.
  ///
  /// False on the game isolate for every asset, always. [pack] is usable
  /// either way, which is the whole point.
  bool get isLoaded => _value != null;

  /// The decoded payload.
  ///
  /// Throws on a copy that never loaded this asset - which includes the game
  /// isolate always, and the decoding isolate before the asset's scene has
  /// finished loading.
  T get value {
    final value = _value;
    if (value == null) {
      throw StateError(
        '${key.debugLabel} is declared (address $_address) but was never '
        'loaded on this isolate, so its payload cannot be read. Asset bytes '
        'are decoded only on the isolate that can decode them (the '
        'main/Flutter one); the game isolate holds the address and the key and '
        'nothing else, by design. If this is the decoding isolate, the asset '
        'was never passed to Assets.load - declare it on a prefab or scene '
        'that GameState.loadScene brings up, which loads a scene\'s declared '
        'set for you.',
      );
    }
    return value;
  }

  /// What decoding this asset discovered about it, replicated to every copy -
  /// see [AssetLoader.describe]. Null before the load completes, and null for
  /// a loader that publishes nothing.
  AssetInfo? get info => _info;

  /// How diagnostics name this asset.
  String get debugLabel => key.debugLabel;

  @override
  String toString() => 'Asset($debugLabel @$_address)';
}

/// Declares [key] and returns the handle to keep in a field - the third
/// `describe*` hook alongside `describeType`/`describeStruct`, and the
/// typed-handle rule applied to assets.
///
/// There is no asset name and nothing to look up at use time: [has] returns
/// the handle, the declarer keeps it in a `late final` field, and that field
/// is the only thing an asset-typed component field will accept.
///
/// ```dart
/// class Player extends EntityStruct with Renderable2D {
///   static const playerTexture = AssetKey<Texture>(BundleSource('player.png'));
///
///   late final TextureAsset texture;
///   late final DataPointer<TextureAsset> sprite;
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
///     sprite = data.hasPacked(assets.of<Texture>(), texture);
///   }
/// }
/// ```
///
/// The two types are distinct: `playerTexture` is an
/// `AssetKey<Texture>` (identity - which asset) and `texture` is an
/// `Asset<Texture>` (the addressed handle a row can point at). So
/// `sprite[e] = playerTexture` does not compile and `sprite[e] = texture`
/// does, which is the whole point of routing every asset through this pass.
abstract class AssetDescriptor {
  /// Declares [key] and returns its handle.
  ///
  /// Idempotent per identity: calling it twice with equal keys - from two
  /// prefabs sharing one texture, or a second scene needing the same UI atlas
  /// - returns the *identical* handle, so a shared asset is one decode and one
  /// address, never two.
  Asset<T> has<T>(AssetKey<T> key);
}

/// One game's assets: which keys have been declared, the [Asset] handle each
/// one produced, and whether that handle's payload has been decoded yet.
///
/// Per-`Game` instance state (`Game.assets`), not a static - it rides the
/// `Isolate.spawn` deep copy, so both copies address the same asset by the
/// same integer without any snapshot/restore.
///
/// # Declaring and loading are two separate steps
///
/// **Declaring** ([AssetDescriptor.has], which routes here through [declare])
/// creates the handle and assigns its address **in this table**. It is
/// synchronous, allocation-cheap, needs no loader, and runs on **both** isolate
/// copies in the same order, because that order *is* the address assignment.
///
/// **Loading** ([load]) reads the key's [AssetSource] and hands the bytes to
/// the key's [AssetLoader]. Decoding generally needs Flutter and `dart:ui`, so
/// it happens on the main isolate only. The game isolate ends up holding a
/// declared, addressed, *unloaded* handle - which is exactly right: it never
/// reads a payload, it only ever writes the address into a component row, and
/// the main isolate unpacks that address into the decoded thing when it draws.
final class Assets {
  /// Address -> handle. Append-only and never recycled, which is what keeps
  /// the two isolate copies in agreement: both run the same `describeAssets`
  /// passes in the same order, so both hand out the same address for the same
  /// asset, and an [unload] on one side (which only nulls a slot) cannot shift
  /// any address the other side already assigned.
  final List<Asset<Object?>?> _addresses = <Asset<Object?>?>[];

  /// Identity -> handle, for every currently declared asset.
  ///
  /// Keyed on `(T, source)`, not on the key *object*, and that is load-bearing
  /// in two directions. It makes two separately-constructed keys naming one
  /// file into one asset, which is what a bare
  /// `AssetKey<Texture>(BundleSource('x'))` written at two call sites needs.
  /// And it survives `Isolate.spawn`, which copies a key into an object equal
  /// to nothing. An enum key works here too, and has to: Dart forbids an enum
  /// from overriding `==`.
  final Map<Object, Asset<Object?>> _byIdentity = <Object, Asset<Object?>>{};

  /// In-flight decodes, so two overlapping [load] calls for one asset await
  /// the same decode instead of running it twice and leaking whichever payload
  /// loses the race.
  final Map<Object, Future<void>> _loading = <Object, Future<void>>{};

  /// Typed views, one per payload type, cached so a repeated declaration does
  /// not allocate a fresh view per field.
  final Map<Type, Object> _views = <Type, Object>{};

  /// Non-generic - see [AssetKey.payloadType] for why.
  static Object _identityOf(AssetKey<Object?> key) =>
      (key.payloadType, key.source);

  /// The [IntRepresentation] a `DataPointer<Asset<T>>` field binds to.
  ///
  /// This table is not itself a representation, and cannot be: it holds
  /// `Asset<Texture>` and `Asset<AudioClip>` in one list, while a field is
  /// declared for one of them, and Dart's covariance runs the wrong way to
  /// make one object serve both. So it vends a typed view per payload type -
  /// which is more honest anyway, since the *view* is the codec and this is
  /// the store.
  IntRepresentation<Asset<T>> of<T>() =>
      _views.putIfAbsent(T, () => _AssetsView<T>(this))
          as IntRepresentation<Asset<T>>;

  Asset<Object?>? _at(int address) {
    if (address < 0 || address >= _addresses.length) return null;
    return _addresses[address];
  }

  /// Declares [key] and returns its handle, creating and addressing it on
  /// first call and returning the identical handle on every later one.
  ///
  /// Internal because [AssetDescriptor.has] is the user-facing spelling: an
  /// asset declared outside a `describeAssets` pass would be declared on
  /// whichever copy happened to run that code, and a declaration that runs on
  /// one copy and not the other is precisely what breaks address agreement.
  @internal
  Asset<T> declare<T>(AssetKey<T> key) {
    final identity = _identityOf(key);
    final existing = _byIdentity[identity];
    if (existing != null) return existing as Asset<T>;
    final asset = key.newAsset(_addresses.length);
    _addresses.add(asset);
    _byIdentity[identity] = asset;
    return asset;
  }

  /// Declares [key] at an address **chosen elsewhere** - the decoding
  /// isolate's half of a load request.
  ///
  /// Assets are declared by scenes and prefabs, which live on the game
  /// isolate, so that is the copy that assigns addresses. The address travels
  /// with the request and this copy *adopts* it. The list is padded rather
  /// than appended to, so an address always lands where the game isolate said
  /// it would, whatever order requests arrive in and however many addresses
  /// this copy has never been told about.
  ///
  /// Idempotent, so an asset a previous request already brought over keeps its
  /// payload instead of being replaced by an empty handle and re-decoded.
  @internal
  Asset<T> adoptAt<T>(int address, AssetKey<T> key) {
    final existing = _at(address);
    if (existing != null) return existing as Asset<T>;
    final asset = key.newAsset(address);
    while (_addresses.length <= address) {
      _addresses.add(null);
    }
    _addresses[address] = asset;
    _byIdentity[_identityOf(key)] = asset;
    return asset;
  }

  /// Reads [key]'s source, decodes it through the key's loader, and completes
  /// with the loaded handle. A no-op returning the same handle if it is
  /// already loaded.
  ///
  /// Throws if [key] was never declared, and does not lazily declare it for
  /// you: declaring here would assign an address on this copy alone, and the
  /// two copies would silently disagree about every address after it. Declare
  /// in a `describeAssets` pass, which both copies run.
  ///
  /// Call this only on the isolate that can decode - `GameState.loadScene`
  /// already does exactly that for a scene's declared set.
  Future<Asset<T>> load<T>(AssetKey<T> key) {
    final identity = _identityOf(key);
    final asset = _byIdentity[identity] as Asset<T>?;
    if (asset == null) {
      throw StateError(
        '${key.debugLabel} has not been declared, so there is nothing to load '
        'into. Declare it from a describeAssets pass '
        '(`descriptor.has(theKey)`) on a prefab or a SceneStruct: declaring is '
        'what assigns the asset its address, and it has to happen on both '
        'isolate copies in the same order for that address to mean the same '
        'thing on both sides.',
      );
    }
    if (asset.isLoaded) return Future<Asset<T>>.value(asset);
    final inFlight = _loading[identity];
    if (inFlight != null) return inFlight.then((_) => asset);
    final future = _decode(key, asset, identity);
    _loading[identity] = future;
    return future.then((_) => asset);
  }

  Future<void> _decode<T>(
    AssetKey<T> key,
    Asset<T> asset,
    Object identity,
  ) async {
    try {
      final loader = key.loader;
      final value = await loader.load(key);
      asset._value = value;
      asset._info = loader.describe(value);
    } finally {
      _loading.remove(identity);
    }
  }

  /// [load], but naming the asset by its address instead of by its key - the
  /// form that crosses an isolate boundary.
  ///
  /// Returns `null` if [address] names nothing declared instead of throwing:
  /// the request crossed a boundary, so a stale address is a message-ordering
  /// question and the caller reports it back to the asker.
  @internal
  Future<void>? loadAddress(int address) {
    final asset = _at(address);
    if (asset == null) return null;
    return load(asset.key);
  }

  /// Records what the *decoding* copy discovered about the asset at [address].
  ///
  /// The receiving half of [AssetLoader.describe]: this copy declared the
  /// asset and can never decode it, so the one fact it cannot derive - the
  /// decoded asset's shape - arrives in the load-completion message and lands
  /// here. A no-op for an address this copy does not know, which is the same
  /// message-ordering tolerance [loadAddress] has and for the same reason.
  ///
  /// [info] being null is meaningful and is *not* skipped: a loader that
  /// publishes nothing leaves [Asset.info] null, and re-loading an asset whose
  /// loader stopped publishing clears the stale value instead of keeping it.
  ///
  @internal
  void adoptInfo(int address, AssetInfo? info) {
    _at(address)?._info = info;
  }

  /// [adoptInfo], for a test in another package.
  ///
  /// A test for something that *reads* published shape - a nine-slicer, say -
  /// needs to supply it without standing up a second isolate and a real decode,
  /// and this is the same call the real arrangement makes.
  ///
  /// A separate member, not a second annotation on [adoptInfo]:
  /// `@visibleForTesting` there would forbid the one production call site that
  /// exists (`GameRuntime`'s load-completion handler), so the two audiences
  /// need two names.
  @visibleForTesting
  void publishInfoForTesting(int address, AssetInfo? info) =>
      adoptInfo(address, info);

  /// [unload], by address. The other half of [loadAddress]; same reasoning.
  @internal
  void unloadAddress(int address) {
    final asset = _at(address);
    if (asset != null) unload(asset.key);
  }

  /// The handle declared for [key], or `null` if nothing has declared it (or
  /// it has since been [unload]ed) - a non-throwing peek.
  ///
  /// Declared, not necessarily *loaded*: the returned handle may still be
  /// waiting on its bytes, which is the normal steady state on the game
  /// isolate. [Asset.isLoaded] is the separate question, kept separate because
  /// the address is usable long before the payload is.
  Asset<T>? tryGet<T>(AssetKey<T> key) =>
      _byIdentity[_identityOf(key)] as Asset<T>?;

  /// The handle at [address], or null - what a cross-isolate message resolves
  /// against, since it carries an address and not a key.
  Asset<Object?>? tryGetAt(int address) => _at(address);

  /// Unloads [key]: frees its address (any `DataPointer` row still holding it
  /// will fail loudly on next read - unloading something still referenced is a
  /// caller bug, not something this silently tolerates), releases whatever the
  /// decode produced, and drops the declaration. A no-op if [key] isn't
  /// currently declared.
  ///
  /// Runs on **both** isolate copies, like declaring. Only the decode is
  /// main-isolate-only; dropping a declaration on one copy but not the other
  /// would leave the two disagreeing about what is declared, and re-declaring
  /// later would then hand out two different addresses for one asset.
  void unload<T>(AssetKey<T> key) {
    final identity = _identityOf(key);
    final asset = _byIdentity.remove(identity) as Asset<T>?;
    if (asset == null) return;
    _release(asset);
  }

  /// Unloads everything currently declared - app shutdown, or a test starting
  /// over.
  void unloadAll() {
    for (final asset in _byIdentity.values) {
      _release(asset);
    }
    _byIdentity.clear();
  }

  void _release<T>(Asset<T> asset) {
    final address = asset.pack();
    if (address >= 0 && address < _addresses.length) {
      _addresses[address] = null;
    }
    final value = asset._value;
    if (value != null) {
      // Only the copy that loaded has a payload, and only it has a reason to
      // hold a loader. The game isolate takes the early exit and never
      // consults the registry - which is what lets it not have one.
      asset.key.loader.unload(value);
      asset._value = null;
    }
    asset._info = null;
  }

  /// Frees an address without going through a key - the "this asset was
  /// unloaded out from under a row that still names it" case, which [of]'s
  /// view then reports loudly instead of silently unpacking to whatever was
  /// registered next.
  @visibleForTesting
  void unregisterAddress(int address) {
    if (address < 0 || address >= _addresses.length) return;
    final asset = _addresses[address];
    _addresses[address] = null;
    if (asset != null) _byIdentity.remove(_identityOf(asset.key));
  }

  /// Test-only escape hatch: drops every declaration, releases every payload,
  /// and forgets any in-flight decode, addresses included.
  @visibleForTesting
  void reset() {
    for (final asset in _byIdentity.values) {
      final value = asset._value;
      if (value != null) {
        asset.key.loader.unload(value);
        asset._value = null;
      }
      asset._info = null;
    }
    _byIdentity.clear();
    _loading.clear();
    _addresses.clear();
    _views.clear();
  }
}

/// One payload type's view of an [Assets] - see [Assets.of].
final class _AssetsView<T> implements IntRepresentation<Asset<T>> {
  const _AssetsView(this._assets);

  final Assets _assets;

  /// Four bytes. An asset address indexes a table a game fills at declare
  /// time; unlike a camera view there is no small ceiling worth betting a
  /// game's content budget on.
  @override
  int get bitWidth => 32;

  @override
  Asset<T>? tryUnpack(int bits) {
    final asset = _assets._at(bits);
    return asset is Asset<T> ? asset : null;
  }

  @override
  Asset<T> unpack(int bits) {
    final asset = tryUnpack(bits);
    if (asset == null) {
      throw StateError(
        'No Asset<$T> at asset address $bits - either it was never declared, '
        'was unloaded, or the row holds a stale or corrupt value.',
      );
    }
    return asset;
  }
}

// --- enum keys -------------------------------------------------------------

/// Lets an `enum` be an [AssetKey] outright.
///
/// The enum value *is* the key - there is no delegate, no lazily-parsed real
/// key behind it, and no per-type parser registry to register into. That is a
/// straight consequence of [AssetKey] being pure data: there is nothing left
/// for a delegate to do.
///
/// Supply [AssetKey.source] yourself, or mix in [LocalEnumAssetKey] for the
/// bundle case.
mixin EnumAssetKey<T> implements AssetKey<T> {
  @override
  Type get payloadType => T;

  @override
  Asset<T> newAsset(int address) => Asset<T>._(this, address);

  @override
  AssetLoader<T> get loader => AssetLoaders.of<T>();

  @override
  String get debugLabel => '$T($this)';
}

/// An [EnumAssetKey] whose bytes come from the asset bundle under [path] -
/// what `good_cli`'s codegen emits.
///
/// ```dart
/// enum Textures with LocalEnumAssetKey<Texture> {
///   planePlayerBlue('plane_player_blue');
///
///   const Textures(this.path);
///   @override
///   final String path;
/// }
/// ```
mixin LocalEnumAssetKey<T> implements EnumAssetKey<T> {
  /// The logical asset path - what the pubspec declares in a loose build and
  /// what the manifest translates in a packed one.
  String get path;

  @override
  AssetSource get source => BundleSource(path);

  @override
  Type get payloadType => T;

  @override
  Asset<T> newAsset(int address) => Asset<T>._(this, address);

  @override
  AssetLoader<T> get loader => AssetLoaders.of<T>();

  @override
  String get debugLabel => '$T($this)';
}

// --- sources ---------------------------------------------------------------

/// Bytes named by a **logical** asset path - the ordinary way a shipped game
/// names its content.
///
/// The path is not necessarily a file. In a loose development build it is the
/// pubspec-declared bundle path and resolves straight through [AssetBundle].
/// In a packed build the same path names a byte range inside an encrypted
/// chunk, and resolution goes through the manifest a build mounts at startup.
/// With DLC or a mod folder mounted it is a file that was never in the app at
/// all. Every case is one `BundleSource('player.png')` in game code, which is
/// exactly why the *path* is identity and the chunk assignment - build output
/// that changes every pack - is not.
///
/// Resolution walks [AssetMounts] top down and falls back to the app's own
/// bundle, so the last mount carrying a path is the one that answers for it.
class BundleSource extends AssetSource {
  const BundleSource(this.path, {this.bundle});

  /// The logical asset path, e.g. `assets/player.png`.
  final String path;

  /// Which bundle is the floor under the mount table, or `null` for
  /// `rootBundle`. Injectable purely so a test (or a game shipping a second
  /// bundle) can supply its own; it is part of this source's identity, so two
  /// `BundleSource`s naming different bundles are different assets.
  final AssetBundle? bundle;

  @override
  Future<Uint8List> load() async {
    // The mount table first, top down, and the app bundle underneath it - the
    // *same* path either way, which is the whole reason this stayed a logical
    // name. A release build mounts a pack at startup and this resolves through
    // its manifest; a development build mounts nothing and the path is a
    // bundle entry; a game with DLC mounts a directory on top and the same key
    // now reads a file that was never in the app. Nothing above here changes
    // between the three.
    final mounted = await AssetMounts.tryRead(path);
    if (mounted != null) return mounted;

    // The floor. Not a mount, because it cannot be absent: on Android an asset
    // is a compressed zip entry with no filesystem path, so whatever shipped
    // inside the app is readable through the bundle and through nothing else.
    // A missing asset surfaces as the bundle's own `FlutterError`, naming the
    // path, which is what it did before there was a table at all.
    final data = await (bundle ?? rootBundle).load(path);
    // A view, not a copy: `ByteData.buffer` may be larger than the asset when
    // the bundle packs several together, so the offset and length matter.
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }

  @override
  Future<AssetAvailability> check() async {
    // A mounted pack can at least say whether its manifest has ever heard of
    // this path, which catches the real failure - a build declaring an asset
    // the pack was never given. See `AssetPack.check` for why it cannot do
    // better than `unverifiable` for one it has, and `AssetPack.verifyChunks`
    // for the deep pass that can.
    final mounted = await AssetMounts.check(path);
    if (mounted != null) return mounted;

    // Nothing mounted carries it, and the floor has no manifest to consult and
    // no way to stat a bundle entry - `AssetBundle` exposes only `load`, and
    // loading is reading. So the only honest answer short of reading the asset
    // is that this could not be checked.
    return AssetAvailability.unverifiable;
  }

  @override
  String get description => path;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BundleSource && other.path == path && other.bundle == bundle;

  @override
  int get hashCode => Object.hash(BundleSource, path, bundle);
}

/// Bytes already in memory - a procedurally generated asset, something that
/// arrived over the network, a fixture in a test. Carries no I/O of its own.
class MemorySource extends AssetSource {
  const MemorySource(this.bytes, {this.name = 'in-memory'});

  final Uint8List bytes;

  /// What identifies this source, and what diagnostics call it.
  ///
  /// **Identity is the name, not the bytes.** An asset's identity is consulted
  /// on every declare, and content-hashing a buffer there would be a real cost
  /// for no benefit. Two `MemorySource`s with the same name are the same asset
  /// even if their bytes differ - give them distinct names.
  final String name;

  @override
  Future<Uint8List> load() async => bytes;

  @override
  Future<AssetAvailability> check() async => AssetAvailability.present;

  @override
  String get description => name;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is MemorySource && other.name == name;

  @override
  int get hashCode => Object.hash(MemorySource, name);
}
