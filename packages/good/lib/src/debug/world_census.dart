import 'dart:convert';
import 'dart:typed_data';

import 'package:meta/meta.dart';

import '../archetype.dart';
import '../game_state.dart';
import '../scene_handle.dart';

/// What the game isolate holds, counted: the loaded scenes, the registered
/// archetypes and how many entities are in each, and the declared systems
/// with their enabled bits.
///
/// This is the first half of an inspector, and the half that needs nothing new
/// from the kernel. Everything here is already known on the game isolate -
/// `SceneRegistry` knows which slots are loaded, `ArchetypeRegistry` knows
/// every archetype, an archetype knows its pages and a page knows how many
/// rows it has handed out. What was missing was a way to ask from the other
/// side, which is what [encode] and [decode] are for.
///
/// # It is asked for, never pushed
///
/// Nothing in the engine takes a census. There is no per-frame hook, no
/// buffer that fills whether or not anyone reads it, and no allocation on any
/// path a running game takes. A census exists only between the call that
/// takes one and the moment the caller drops it.
///
/// # Ask on the read-only lane
///
/// A census reads and answers, so it belongs on the lane built for that:
///
/// ```dart
/// // in Game.describeCommands
/// census = descriptor.has(TakeCensus.new);
///
/// // in GameState.describeCommands
/// descriptor.hasReadOnlySupplier(game.census, () => WorldCensus.of(this).encode());
/// ```
///
/// That lane is drained once per frame from `GameState.advance`, which runs
/// on a frame that afforded no fixed step - so the census answers while the
/// simulation is stopped, which is when a world is usually worth looking at.
/// See `CommandDescriptor.hasReadOnlySupplier`, and note the promise it makes:
/// a handler there may not write, and the engine throws if it tries. A census
/// writes nothing.
///
/// # What it costs
///
/// One census is O(archetypes + pages + scene slots + systems). It is **not**
/// O(entities): a page reports its row count as arithmetic over its bump
/// cursor and its free set (`MemoryPage.liveRowCount`), so a world of a
/// hundred thousand entities costs what a world of ten does. What it does
/// allocate is the answer - one object per scene, archetype and system, plus
/// the encoded bytes - which is why nothing takes one on its own.
///
/// The blob has to fit one record on the command ring, which `commandBufferBytes`
/// sizes at 64 KiB by default. A record is roughly 30 bytes plus a type name
/// per archetype and system, so the practical bound is a few hundred of each;
/// past that the transport refuses the batch and says so rather than
/// truncating.
///
/// # Type names are for reading, and nothing else
///
/// Every name here is a `runtimeType.toString()`, carried so a person can
/// tell one archetype from another. Nothing resolves by it - the identifiers
/// that mean something are [ArchetypeCensus.archetypeId],
/// [SceneCensus.slot] and [SystemCensus.index] - and a build that minifies
/// type names will show minified ones.
@immutable
final class WorldCensus {
  const WorldCensus({
    required this.tick,
    required this.scenes,
    required this.archetypes,
    required this.systems,
  });

  /// The wire format [encode] writes and [decode] reads. Bumped whenever the
  /// layout below changes, so two copies built from different sources report
  /// a mismatch instead of reading each other's bytes as their own.
  static const int formatVersion = 1;

  /// The fixed tick the census was taken on.
  ///
  /// Here because a census of a world that moves is only meaningful with a
  /// timestamp: two censuses reporting the same tick describe the same world,
  /// and a caller polling a paused game can see that nothing has advanced.
  final int tick;

  /// Every loaded scene, in slot order. A slot whose scene has been unloaded
  /// is absent, not present-and-empty.
  final List<SceneCensus> scenes;

  /// Every registered archetype, in id order - including one with no entities
  /// in it, which is a fact worth seeing rather than one to hide. Archetype
  /// ids are process-global and are never recycled, so an archetype whose
  /// scene has been unloaded stays here at zero.
  final List<ArchetypeCensus> archetypes;

  /// Every declared system, in execution order - which is post-sort order,
  /// not declaration order.
  final List<SystemCensus> systems;

  /// Entities across every archetype.
  int get entityCount {
    var total = 0;
    for (final archetype in archetypes) {
      total += archetype.entityCount;
    }
    return total;
  }

  /// Counts the world this [state] owns.
  ///
  /// **Game isolate only.** The main copy registers no archetypes, loads no
  /// scenes and holds no systems - by design, see `ArchetypeRegistry.byId` -
  /// so a census taken there would answer "empty world" about a world that is
  /// simply somewhere else. That is refused rather than reported.
  factory WorldCensus.of(GameState state) {
    if (!state.isSimulating) {
      throw StateError(
        'WorldCensus.of was given a GameState that does not own the '
        'simulation. The main isolate holds no archetypes, no scenes and no '
        'systems, so a census taken there is empty for a reason that has '
        'nothing to do with the world. Take it on the game isolate - a '
        'read-only command handler (hasReadOnlySupplier) is what carries it '
        'back.',
      );
    }

    // Per scene slot, filled by the same page walk that counts archetypes:
    // a page records `ownerSceneSlot` and nothing else, so which scene a row
    // belongs to is read off the page it sits in.
    final perScene = List<int>.filled(SceneRegistry.slotCount, 0);
    final archetypes = <ArchetypeCensus>[];

    for (var id = 0; id < ArchetypeRegistry.count; id++) {
      final storage = ArchetypeRegistry.byId(id);
      var entities = 0;
      var pages = 0;
      for (var p = 0; p < storage.pageCount; p++) {
        final page = storage.pageAt(p);
        // Null is a page whose scene was unloaded. The slot stays in the list
        // so a live `Entity`'s page index keeps addressing the right page.
        if (page == null) continue;
        pages++;
        final rows = page.liveRowCount;
        entities += rows;
        final slot = page.ownerSceneSlot;
        if (slot >= 0 && slot < perScene.length) perScene[slot] += rows;
      }
      archetypes.add(
        ArchetypeCensus(
          archetypeId: id,
          typeName: storage.prefab.runtimeType.toString(),
          entityCount: entities,
          pageCount: pages,
          strideBytes: storage.strideBytes,
          componentSignature: storage.componentSignature,
        ),
      );
    }

    final scenes = <SceneCensus>[];
    for (var slot = 0; slot < SceneRegistry.slotCount; slot++) {
      final handle = SceneRegistry.handleAt(slot);
      if (handle == null) continue;
      final struct = SceneRegistry.tryResolve(handle);
      if (struct == null) continue;
      scenes.add(
        SceneCensus(
          slot: slot,
          generation: handle.generation,
          typeName: struct.runtimeType.toString(),
          entityCount: perScene[slot],
        ),
      );
    }

    final declared = state.declaredSystems;
    final systems = <SystemCensus>[
      for (var i = 0; i < declared.length; i++)
        SystemCensus(
          index: i,
          typeName: declared[i].runtimeType.toString(),
          enabled: state.isSystemEnabledAt(i),
        ),
    ];

    return WorldCensus(
      tick: state.tick,
      scenes: scenes,
      archetypes: archetypes,
      systems: systems,
    );
  }

  /// Packs this census into the blob a `hasBytes` parameter carries.
  ///
  /// Little-endian throughout, counts and ids as `uint32`, a 64-bit value as
  /// two `uint32` words rather than one `uint64` - `ByteData` has no 64-bit
  /// integer accessor on the web, and a debug facility that works on three
  /// platforms out of four is a debug facility people stop trusting. Strings
  /// are a `uint16` byte length and UTF-8 behind it.
  Uint8List encode() {
    final writer = _CensusWriter();
    writer.uint8(formatVersion);
    writer.uint64(tick);

    writer.uint32(scenes.length);
    for (final scene in scenes) {
      writer
        ..uint32(scene.slot)
        ..uint32(scene.generation)
        ..uint32(scene.entityCount)
        ..string(scene.typeName);
    }

    writer.uint32(archetypes.length);
    for (final archetype in archetypes) {
      writer
        ..uint32(archetype.archetypeId)
        ..uint32(archetype.entityCount)
        ..uint32(archetype.pageCount)
        ..uint32(archetype.strideBytes)
        ..uint64(archetype.componentSignature)
        ..string(archetype.typeName);
    }

    writer.uint32(systems.length);
    for (final system in systems) {
      writer
        ..uint32(system.index)
        ..uint8(system.enabled ? 1 : 0)
        ..string(system.typeName);
    }

    return writer.takeBytes();
  }

  /// Reads back what [encode] wrote - on the main isolate, from the blob a
  /// read-only command answered with.
  ///
  /// Throws a `FormatException` on a version this build does not know, on a
  /// length that runs off the end, and on trailing bytes. A census is
  /// diagnostic output, so a wrong answer is worse than no answer.
  factory WorldCensus.decode(Uint8List bytes) {
    final reader = _CensusReader(bytes);
    final version = reader.uint8();
    if (version != formatVersion) {
      throw FormatException(
        'WorldCensus format version $version, and this build reads '
        '$formatVersion. The two copies were built from different sources.',
      );
    }
    final tick = reader.uint64();

    final sceneCount = reader.uint32();
    final scenes = <SceneCensus>[
      for (var i = 0; i < sceneCount; i++)
        SceneCensus(
          slot: reader.uint32(),
          generation: reader.uint32(),
          entityCount: reader.uint32(),
          typeName: reader.string(),
        ),
    ];

    final archetypeCount = reader.uint32();
    final archetypes = <ArchetypeCensus>[
      for (var i = 0; i < archetypeCount; i++)
        ArchetypeCensus(
          archetypeId: reader.uint32(),
          entityCount: reader.uint32(),
          pageCount: reader.uint32(),
          strideBytes: reader.uint32(),
          componentSignature: reader.uint64(),
          typeName: reader.string(),
        ),
    ];

    final systemCount = reader.uint32();
    final systems = <SystemCensus>[
      for (var i = 0; i < systemCount; i++)
        SystemCensus(
          index: reader.uint32(),
          enabled: reader.uint8() == 1,
          typeName: reader.string(),
        ),
    ];

    reader.expectEnd();
    return WorldCensus(
      tick: tick,
      scenes: scenes,
      archetypes: archetypes,
      systems: systems,
    );
  }

  @override
  String toString() =>
      'WorldCensus(tick: $tick, scenes: ${scenes.length}, '
      'archetypes: ${archetypes.length}, entities: $entityCount, '
      'systems: ${systems.length})';
}

/// One loaded scene.
@immutable
final class SceneCensus {
  const SceneCensus({
    required this.slot,
    required this.generation,
    required this.typeName,
    required this.entityCount,
  });

  /// The `SceneRegistry` slot this scene is loaded into.
  final int slot;

  /// The slot's generation, bumped on every reuse - the half of a `Scene`
  /// handle that tells this load apart from the one before it in the same
  /// slot.
  final int generation;

  /// The `SceneStruct` subclass's name, for reading.
  final String typeName;

  /// Entities across every page tagged with this scene's slot. A page
  /// allocated outside any scene belongs to no scene and is counted in no
  /// entry here, though it is counted in its archetype's.
  final int entityCount;

  @override
  String toString() => 'SceneCensus(#$slot.$generation $typeName: $entityCount)';
}

/// One registered archetype.
@immutable
final class ArchetypeCensus {
  const ArchetypeCensus({
    required this.archetypeId,
    required this.typeName,
    required this.entityCount,
    required this.pageCount,
    required this.strideBytes,
    required this.componentSignature,
  });

  /// The id `Entity` packs - process-global, assigned in registration order
  /// and never recycled.
  final int archetypeId;

  /// The `EntityStruct` subclass's name, for reading. Archetype identity is
  /// the subclass, not the field set, so two structs with byte-identical
  /// layouts show as two archetypes with two names.
  final String typeName;

  /// Rows currently allocated across this archetype's pages.
  final int entityCount;

  /// Pages this archetype currently holds. A page freed by a scene unload is
  /// not counted, though its slot stays in the archetype's list so a live
  /// `Entity`'s page index keeps addressing the right page.
  final int pageCount;

  /// One row's size in bytes - the bit cursor rounded up to a whole byte.
  final int strideBytes;

  /// The bitset of component types this archetype declared, as
  /// `ComponentTypeRegistry.bitFor` ORs them. One 64-bit word, so at most 64
  /// distinct component types; bit 63 makes the value negative, which is
  /// what the registry says to expect.
  final int componentSignature;

  @override
  String toString() =>
      'ArchetypeCensus(#$archetypeId $typeName: $entityCount in $pageCount '
      'pages)';
}

/// One declared system.
@immutable
final class SystemCensus {
  const SystemCensus({
    required this.index,
    required this.typeName,
    required this.enabled,
  });

  /// Where the system sits in execution order, after the declaration sort.
  final int index;

  /// The `GameSystem` subclass's name, for reading.
  final String typeName;

  /// Whether it currently receives events - what `GameState.enableSystem` and
  /// `disableSystem` toggle. A disabled system stays declared and stays here.
  final bool enabled;

  @override
  String toString() =>
      'SystemCensus(#$index $typeName${enabled ? '' : ' disabled'})';
}

/// Appends fixed-width little-endian fields into a growing buffer.
///
/// Hand-rolled rather than `BytesBuilder` plus a scratch `ByteData` per field:
/// this runs once per census, and one class that owns both the buffer and the
/// cursor is less to read than two that have to agree.
final class _CensusWriter {
  Uint8List _bytes = Uint8List(256);
  ByteData _view = ByteData(0);
  int _length = 0;

  _CensusWriter() {
    _view = ByteData.sublistView(_bytes);
  }

  void _reserve(int extra) {
    if (_length + extra <= _bytes.length) return;
    var capacity = _bytes.length * 2;
    while (capacity < _length + extra) {
      capacity *= 2;
    }
    final grown = Uint8List(capacity)..setRange(0, _length, _bytes);
    _bytes = grown;
    _view = ByteData.sublistView(grown);
  }

  void uint8(int value) {
    _reserve(1);
    _view.setUint8(_length, value);
    _length += 1;
  }

  void uint32(int value) {
    _reserve(4);
    _view.setUint32(_length, value, Endian.little);
    _length += 4;
  }

  /// Two `uint32` words, low first. See [WorldCensus.encode] for why not one
  /// `uint64`.
  void uint64(int value) {
    uint32(value & 0xFFFFFFFF);
    uint32((value >> 32) & 0xFFFFFFFF);
  }

  void string(String value) {
    final encoded = utf8.encode(value);
    if (encoded.length > 0xFFFF) {
      throw ArgumentError.value(
        value,
        'value',
        'a census string is a uint16 byte length and its bytes; this one is '
            '${encoded.length} bytes',
      );
    }
    _reserve(2 + encoded.length);
    _view.setUint16(_length, encoded.length, Endian.little);
    _length += 2;
    _bytes.setRange(_length, _length + encoded.length, encoded);
    _length += encoded.length;
  }

  Uint8List takeBytes() => Uint8List.sublistView(_bytes, 0, _length);
}

/// The read half of [_CensusWriter]. Every read bounds-checks, because the
/// bytes arrive from another isolate and a census that reads past its own
/// blob would report a world nobody has.
final class _CensusReader {
  _CensusReader(this._bytes) : _view = ByteData.sublistView(_bytes);

  final Uint8List _bytes;
  final ByteData _view;
  int _offset = 0;

  void _need(int count) {
    if (_offset + count > _bytes.length) {
      throw FormatException(
        'a WorldCensus blob ended early: $count more bytes wanted at offset '
        '$_offset, and it is ${_bytes.length} bytes long',
      );
    }
  }

  int uint8() {
    _need(1);
    final value = _view.getUint8(_offset);
    _offset += 1;
    return value;
  }

  int uint32() {
    _need(4);
    final value = _view.getUint32(_offset, Endian.little);
    _offset += 4;
    return value;
  }

  int uint64() {
    final low = uint32();
    final high = uint32();
    return (high << 32) | low;
  }

  String string() {
    _need(2);
    final length = _view.getUint16(_offset, Endian.little);
    _offset += 2;
    _need(length);
    final value = utf8.decode(
      Uint8List.sublistView(_bytes, _offset, _offset + length),
    );
    _offset += length;
    return value;
  }

  void expectEnd() {
    if (_offset != _bytes.length) {
      throw FormatException(
        'a WorldCensus blob had ${_bytes.length - _offset} bytes left over '
        'after the last field, so it is not what this build writes',
      );
    }
  }
}
