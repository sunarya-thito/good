import 'dart:typed_data';

import 'package:good/src/scene_handle.dart';
import 'package:good/src/archetype.dart';
import 'package:good/src/asset.dart';
import 'package:good/src/data.dart';
import 'package:good/src/heap_object.dart';
import 'package:good/src/pool.dart';
import 'package:good/src/scene.dart';
import 'package:good/src/struct.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:good/src/declarations.g.dart';
import 'package:good/src/scannable.dart';

part 'data_layout_test.g.dart';

/// The payload type. Plain - it is not the addressed thing any more, so it
/// carries no address, no loaded flag and no base class.
class _Texture {}

class _NoBytes extends AssetSource {
  const _NoBytes(this.name);

  final String name;

  @override
  Future<Uint8List> load() async => Uint8List(0);

  @override
  Future<AssetAvailability> check() async => AssetAvailability.present;

  @override
  String get description => name;

  @override
  bool operator ==(Object other) => other is _NoBytes && other.name == name;

  @override
  int get hashCode => Object.hash(_NoBytes, name);
}

/// The table these ad-hoc fixtures declare into. Instance state - a `Game`
/// owns one; a fixture with no `Game` owns its own.
final Assets assets = Assets();

var _nextAsset = 0;

/// Declares a fresh asset and returns its handle - the same call
/// `AssetDescriptor.has` makes. These tests are about `hasPacked`/
/// `optPacked`'s field mechanics, and a field only ever stores the packed
/// int, so declaring (which is what assigns one) is all they need; decoding a
/// payload would be beside the point.
///
/// Each call uses a distinct source name, because an asset's identity is
/// `(payload type, source)` - two fixtures sharing a name would be one asset
/// and these tests need distinct addresses.
Asset<_Texture> _loaded() =>
    assets.declare(AssetKey<_Texture>(_NoBytes('fixture-${_nextAsset++}')));

/// Fixtures for the `hasEnum` group, sized to land on three different rungs
/// of the width ladder: two members fit one bit, three fit two, five fit four.
enum _Toggle { off, on }

enum _Phase { rising, holding, falling }

enum _Element { none, fire, water, earth, air }

/// One struct type reused for every ad-hoc layout below, so this file's
/// many cases cost `ComponentTypeRegistry` exactly one of its 64 bits.
class _AdHoc extends EntityStruct {
  _AdHoc(this._build);

  final void Function(DataDescriptor data) _build;

  @override
  void describeStruct(DataDescriptor data) {
    super.describeStruct(data);
    _build(data);
  }
}

class _AdHocScene extends SceneStruct {
  /// This fixture's loaded handle. Entity creation lives on `Scene` now (one
  /// `SceneStruct` can back several loaded scenes), so a headless fixture
  /// registers itself and forwards.
  late final Scene handle;

  Entity addEntity<T extends EntityStruct>(T prefab, {Entity? parent}) =>
      handle.addEntity(prefab, parent: parent);

  _AdHocScene(this._prefabOf);

  /// A tear-off rather than the prefab itself, because a field typed as an
  /// `EntityStruct` is a declaration and a declaration is the field's own
  /// initialiser. This scene does not declare its prefab - the harness built
  /// it, and the scene registers the one it was handed.
  final _AdHoc Function() _prefabOf;

  @override
  void describeScene(SceneDescriptor descriptor) {
    super.describeScene(descriptor);
    descriptor.has(_prefabOf);
  }
}

/// Registers one throwaway archetype and gives the test a spawner for it.
class _Harness {
  _Harness(void Function(DataDescriptor data) build, {int pageSize = 4096})
    : pool = MemoryPool(pageSize: pageSize),
      prefab = _AdHoc(build) {
    scene = _AdHocScene(() => prefab)..initializeScene(pool, assets: assets);
    scene.handle = SceneRegistry.register(scene);
  }

  final MemoryPool pool;
  final _AdHoc prefab;
  late final _AdHocScene scene;

  int get strideBytes => prefab.archetype.strideBytes;
  int get bitLength => prefab.archetype.bitLength;

  Entity spawn() => scene.addEntity(prefab);

  void dispose() => pool.dispose();
}

void main() {
  _installDeclarations();

  // Both registries are process-global (deliberately - see their docs), so
  // each test gets a clean slate rather than accumulating archetype ids and
  // component bits across the file.
  tearDown(() {
    SceneRegistry.reset();
    ArchetypeRegistry.reset();
    ComponentTypeRegistry.reset();
    assets.reset();
    HeapObjectRegistry.reset();
  });

  group('bit packing', () {
    test(
      'four 2-bit fields share a single byte without corrupting each other',
      () {
        late DataPointer<int> a, b, c, d;
        final h = _Harness((data) {
          a = data.hasUint2();
          b = data.hasUint2();
          c = data.hasUint2();
          d = data.hasUint2();
        });
        addTearDown(h.dispose);

        expect(h.bitLength, 8);
        expect(h.strideBytes, 1, reason: '4 x 2 bits must fit in one byte');

        final e = h.spawn();
        a[e] = 3;
        b[e] = 1;
        c[e] = 2;
        d[e] = 0;
        expect([a[e], b[e], c[e], d[e]], [3, 1, 2, 0]);

        // Rewriting one field must leave its byte-mates alone.
        c[e] = 3;
        expect([a[e], b[e], c[e], d[e]], [3, 1, 3, 0]);
        a[e] = 0;
        expect([a[e], b[e], c[e], d[e]], [0, 1, 3, 0]);
      },
    );

    test('1-bit + 4-bit + 1-bit pack into one byte', () {
      late DataPointer<int> flag, nibble, flag2;
      final h = _Harness((data) {
        flag = data.hasUint1();
        nibble = data.hasUint4();
        flag2 = data.hasUint1();
      });
      addTearDown(h.dispose);

      expect(h.bitLength, 6);
      expect(h.strideBytes, 1);

      final e = h.spawn();
      flag[e] = 1;
      nibble[e] = 0xD;
      flag2[e] = 1;
      expect([flag[e], nibble[e], flag2[e]], [1, 0xD, 1]);

      nibble[e] = 0;
      expect([flag[e], nibble[e], flag2[e]], [1, 0, 1]);
    });

    test(
      'a sub-byte field that would straddle a byte jumps to the next one',
      () {
        late DataPointer<int> nibble;
        final h = _Harness((data) {
          for (var i = 0; i < 6; i++) {
            data.hasUint1(); // cursor -> bit 6
          }
          nibble = data.hasUint4(); // 6 + 4 > 8, so it must start at bit 8
        });
        addTearDown(h.dispose);

        expect(h.bitLength, 12, reason: '6 flag bits, 2 wasted, then 4 bits');
        expect(h.strideBytes, 2);

        final e = h.spawn();
        nibble[e] = 0xF;
        expect(nibble[e], 0xF);
      },
    );

    test(
      'a wide field after a sub-byte field is byte-aligned and round-trips',
      () {
        late DataPointer<int> tag;
        late DataPointer<double> value;
        late DataPointer<int> wide;
        final h = _Harness((data) {
          tag = data.hasUint2();
          value = data.hasFloat64(); // must start at byte 1, not bit 2
          wide = data.hasUint32();
        });
        addTearDown(h.dispose);

        // 2 bits + 6 padding + 64 + 32 = 104 bits = 13 bytes.
        expect(h.bitLength, 104);
        expect(h.strideBytes, 13);

        final e = h.spawn();
        tag[e] = 3;
        value[e] = 1234.5678;
        wide[e] = 0xDEADBEEF;
        expect(tag[e], 3);
        expect(value[e], 1234.5678);
        expect(wide[e], 0xDEADBEEF);

        // The wide writes must not have clobbered the leading bits...
        tag[e] = 1;
        expect(value[e], 1234.5678);
        expect(wide[e], 0xDEADBEEF);
        expect(tag[e], 1);
      },
    );

    test('wide fields survive rows that are not naturally aligned', () {
      // Stride 13 means consecutive rows start at byte 0, 13, 26, ... so
      // the float64 at row-relative byte 1 lands at absolute 1, 14, 27:
      // never 8-byte aligned. declareField only promises byte alignment
      // (see its doc); this proves that is actually enough.
      late DataPointer<int> tag;
      late DataPointer<double> value;
      final h = _Harness((data) {
        tag = data.hasUint2();
        value = data.hasFloat64();
        data.hasUint32();
      });
      addTearDown(h.dispose);
      expect(h.strideBytes, 13);

      final entities = <Entity>[];
      for (var i = 0; i < 8; i++) {
        final e = h.spawn();
        entities.add(e);
        expect(e.rowOffset, i * 13);
        tag[e] = i % 4;
        value[e] = i + 0.5;
      }
      for (var i = 0; i < 8; i++) {
        expect(value[entities[i]], i + 0.5, reason: 'row $i');
        expect(tag[entities[i]], i % 4, reason: 'row $i');
      }
    });

    test('every scalar width round-trips its own range', () {
      late DataPointer<int> u8, i8, u16, i16, u32, i32;
      late DataPointer<double> f32, f64;
      final h = _Harness((data) {
        u8 = data.hasUint8();
        i8 = data.hasInt8();
        u16 = data.hasUint16();
        i16 = data.hasInt16();
        u32 = data.hasUint32();
        i32 = data.hasInt32();
        f32 = data.hasFloat32();
        f64 = data.hasFloat64();
      });
      addTearDown(h.dispose);
      expect(h.strideBytes, 1 + 1 + 2 + 2 + 4 + 4 + 4 + 8);

      final e = h.spawn();
      u8[e] = 255;
      i8[e] = -128;
      u16[e] = 65535;
      i16[e] = -32768;
      u32[e] = 0xFFFFFFFF;
      i32[e] = -2147483648;
      f32[e] = 0.5; // exactly representable, so no float32 rounding noise
      f64[e] = -1.0e300;

      expect(u8[e], 255);
      expect(i8[e], -128);
      expect(u16[e], 65535);
      expect(i16[e], -32768);
      expect(u32[e], 0xFFFFFFFF);
      expect(i32[e], -2147483648);
      expect(f32[e], 0.5);
      expect(f64[e], -1.0e300);
    });

    test('sub-byte signed fields sign-extend', () {
      late DataPointer<int> i4, i2, i1;
      final h = _Harness((data) {
        i4 = data.hasInt4();
        i2 = data.hasInt2();
        i1 = data.hasInt1();
      });
      addTearDown(h.dispose);

      final e = h.spawn();
      i4[e] = -8;
      i2[e] = -2;
      i1[e] = -1; // a 1-bit two's-complement int holds -1 or 0
      expect([i4[e], i2[e], i1[e]], [-8, -2, -1]);

      i4[e] = 7;
      i2[e] = 1;
      i1[e] = 0;
      expect([i4[e], i2[e], i1[e]], [7, 1, 0]);

      i4[e] = -1;
      expect([i4[e], i2[e], i1[e]], [-1, 1, 0]);
    });

    test('declareField rejects widths the layout cannot express', () {
      // Registered but not sealed, so the width check is what fires. 3 bits
      // has no load/store form under the packing rule; only 1/2/4/8/16/32/64
      // do.
      final pool = MemoryPool(pageSize: 64);
      addTearDown(pool.dispose);
      final storage = ArchetypeRegistry.registerDetached(pool, _AdHoc((_) {}));
      expect(() => storage.declareField(3), throwsArgumentError);
      expect(() => storage.declareField(0), throwsArgumentError);
      expect(() => storage.declareField(128), throwsArgumentError);
      expect(storage.bitLength, 0, reason: 'a rejected field reserves nothing');
    });

    test('a sealed archetype refuses further fields', () {
      final h = _Harness((data) => data.hasUint8());
      addTearDown(h.dispose);
      expect(h.prefab.archetype.isSealed, isTrue);
      expect(() => h.prefab.archetype.declareField(8), throwsStateError);
    });

    test('a field-less struct still gets a non-zero stride', () {
      // A zero stride would let MemoryPage hand out unlimited rows all at
      // offset 0, every entity aliasing the same (empty) row.
      final h = _Harness((data) {});
      addTearDown(h.dispose);
      expect(h.bitLength, 0);
      expect(h.strideBytes, 1);
      expect(h.spawn().rowOffset, 0);
      expect(h.spawn().rowOffset, 1);
    });
  });

  group('presence flags reuse stranded bits', () {
    // `declareField`'s byte-rounding skips the rest of the current byte
    // whenever a wide field follows a sub-byte one. Nothing can reach those
    // bits through the cursor, which only moves forward, so an optional wide
    // field used to cost a whole byte for its one-bit flag.
    // `ArchetypeStorage.declareFlagBit` hands them to the next presence flag
    // instead. These tests pin that, and pin that a recycled bit does not
    // alias whatever else lives in the byte it came from.

    test('optional wide fields share one flag byte between them', () {
      late DataPointer<int?> a, b, c;
      final h = _Harness((data) {
        a = data.optInt64();
        b = data.optInt64();
        c = data.optInt64();
      });
      addTearDown(h.dispose);

      // One byte of flags, then three 8-byte values - not three separate
      // flag bytes, which would make this 27.
      expect(h.bitLength, (1 + 7) + 3 * 64);
      expect(h.strideBytes, 25);

      final e = h.spawn();
      a[e] = -1;
      b[e] = 0x7FFFFFFFFFFFFFFF;
      c[e] = null;
      expect([a[e], b[e], c[e]], [-1, 0x7FFFFFFFFFFFFFFF, null]);

      // Clearing one flag must leave its byte-mates present.
      a[e] = null;
      expect([a[e], b[e], c[e]], [null, 0x7FFFFFFFFFFFFFFF, null]);
      c[e] = 5;
      expect([a[e], b[e], c[e]], [null, 0x7FFFFFFFFFFFFFFF, 5]);
    });

    test('a recycled flag bit does not alias the value field it shares a byte with', () {
      // The stranded bits here come from the rounding *after* `nibble`,
      // so the byte holding them also holds a real value field. A flag
      // given one of those bits writes with a read-modify-write, same as
      // any sub-byte field, so neither can disturb the other.
      late DataPointer<int> nibble;
      late DataPointer<double?> x, y;
      final h = _Harness((data) {
        nibble = data.hasUint4();
        x = data.optFloat64();
        y = data.optFloat64();
      });
      addTearDown(h.dispose);

      // 4 bits of nibble, x's flag at bit 4, 3 bits stranded (y's flag
      // takes one), then the two values.
      expect(h.bitLength, (4 + 1 + 3) + 2 * 64);
      expect(h.strideBytes, 17);

      final e = h.spawn();
      nibble[e] = 0xF;
      x[e] = 1.5;
      y[e] = -2.5;
      expect([nibble[e], x[e], y[e]], [0xF, 1.5, -2.5]);

      nibble[e] = 0;
      expect([nibble[e], x[e], y[e]], [0, 1.5, -2.5]);
      x[e] = null;
      expect([nibble[e], x[e], y[e]], [0, null, -2.5]);
      nibble[e] = 0xA;
      expect([nibble[e], x[e], y[e]], [0xA, null, -2.5]);
    });

    test('an optional array packs its per-element flags together too', () {
      late DataArrayPointer<double?> slots;
      final h = _Harness((data) {
        slots = data.optArray(.float64, 4);
      });
      addTearDown(h.dispose);

      expect(h.bitLength, (1 + 7) + 4 * 64);
      expect(h.strideBytes, 33);

      final e = h.spawn();
      for (var i = 0; i < 4; i++) {
        slots.set(e, i, i.isEven ? i + 0.5 : null);
      }
      expect(
        [for (var i = 0; i < 4; i++) slots.get(e, i)],
        [0.5, null, 2.5, null],
      );
      slots.set(e, 1, 11.5);
      expect(
        [for (var i = 0; i < 4; i++) slots.get(e, i)],
        [0.5, 11.5, 2.5, null],
      );
    });

    test('a declared default is stamped through a recycled flag bit', () {
      // Every new row is memcpy'd from a prototype built at seal time, and
      // each field stamps its own default into it. Flags sharing a byte
      // means those stamps overlap, so a present-by-default field must not
      // be cleared by a later absent-by-default one landing beside it.
      late DataPointer<int?> present, absent, alsoPresent;
      final h = _Harness((data) {
        present = data.optInt64(7);
        absent = data.optInt64();
        alsoPresent = data.optInt64(-9);
      });
      addTearDown(h.dispose);

      expect(h.strideBytes, 25);
      final e = h.spawn();
      expect([present[e], absent[e], alsoPresent[e]], [7, null, -9]);
    });
  });

  group('nullable (opt*) fields', () {
    test('null / value / null / value round-trips', () {
      late DataPointer<int?> maybe;
      final h = _Harness((data) => maybe = data.optInt32());
      addTearDown(h.dispose);

      final e = h.spawn();
      expect(maybe[e], isNull, reason: 'no default was declared');

      maybe[e] = -12345;
      expect(maybe[e], -12345);

      maybe[e] = null;
      expect(maybe[e], isNull);

      maybe[e] = 7;
      expect(maybe[e], 7);

      maybe[e] = 0;
      expect(maybe[e], 0, reason: '0 is a value, not absence');
    });

    test(
      'the has-bit costs a bit, not a byte, and packs with its neighbours',
      () {
        late DataPointer<int?> a, b;
        late DataPointer<int> tag;
        final h = _Harness((data) {
          a = data.optUint2();
          b = data.optUint2();
          tag = data.hasUint1();
        });
        addTearDown(h.dispose);

        // (1 + 2) * 2 + 1 = 7 bits, all inside one byte.
        expect(h.bitLength, 7);
        expect(h.strideBytes, 1);

        final e = h.spawn();
        a[e] = 3;
        b[e] = null;
        tag[e] = 1;
        expect([a[e], b[e], tag[e]], [3, null, 1]);

        b[e] = 2;
        expect([a[e], b[e], tag[e]], [3, 2, 1]);

        a[e] = null;
        expect([a[e], b[e], tag[e]], [null, 2, 1]);

        tag[e] = 0;
        expect([a[e], b[e], tag[e]], [null, 2, 0]);
      },
    );

    test('nulling one optional field does not disturb another', () {
      late DataPointer<double?> x, y;
      final h = _Harness((data) {
        x = data.optFloat64();
        y = data.optFloat64();
      });
      addTearDown(h.dispose);

      final e = h.spawn();
      x[e] = 1.5;
      y[e] = 2.5;
      x[e] = null;
      expect(x[e], isNull);
      expect(y[e], 2.5);
      y[e] = null;
      x[e] = 3.5;
      expect(x[e], 3.5);
      expect(y[e], isNull);
    });
  });

  group('declared defaults', () {
    test('are stamped into every new row, including recycled ones', () {
      late DataPointer<int> count;
      late DataPointer<double> scale;
      late DataPointer<int> nibble;
      late DataPointer<int> signedNibble;
      late DataPointer<int?> present, absent;
      final h = _Harness((data) {
        count = data.hasUint8(7);
        scale = data.hasFloat64(3.5);
        nibble = data.hasUint4(0xA);
        // A negative default has to survive being truncated into 4 bits on
        // the way in and sign-extended on the way out.
        signedNibble = data.hasInt4(-3);
        present = data.optInt32(-42);
        absent = data.optInt32();
      });
      addTearDown(h.dispose);

      final first = h.spawn();
      expect(count[first], 7);
      expect(scale[first], 3.5);
      expect(nibble[first], 0xA);
      expect(signedNibble[first], -3);
      expect(present[first], -42);
      expect(absent[first], isNull);

      // Dirty the row, hand it back, and confirm the next tenant does not
      // inherit it - MemoryPage recycles rows and the triple buffer copies
      // the previous tick forward, so "fresh" memory is not zeroed.
      count[first] = 1;
      scale[first] = 99.0;
      present[first] = null;
      absent[first] = 5;
      final page = h.prefab.archetype.pageAt(first.pageIndex);
      page!.free(first.rowOffset);

      final second = h.spawn();
      expect(second.rowOffset, first.rowOffset, reason: 'the row was recycled');
      expect(count[second], 7);
      expect(scale[second], 3.5);
      expect(nibble[second], 0xA);
      expect(signedNibble[second], -3);
      expect(present[second], -42);
      expect(absent[second], isNull);
    });
  });

  group('entity handle (hasEntity) fields', () {
    test('a stored handle round-trips, top bits included', () {
      late DataPointer<Entity> target;
      final h = _Harness((data) => target = data.hasEntity());
      addTearDown(h.dispose);

      final holder = h.spawn();
      final other = h.spawn();
      target[holder] = other;
      expect(target[holder], other);
      expect(target[holder].archetypeId, other.archetypeId);
      expect(target[holder].rowOffset, other.rowOffset);

      // A high archetype id puts bits in the top half of the handle, up to
      // and including bit 63 - `Entity.pack` shifts the id up 48. These
      // fixtures never get past archetype 0, so the pattern is written
      // directly to prove the whole 64 bits come back.
      const packed = Entity.pack(0xFFFF, 0xFFFF, 0xFFFFFFFF);
      expect(packed.value < 0, isTrue, reason: 'the fixture must be negative');
      target[holder] = packed;
      expect(target[holder].value, packed.value);
      expect(target[holder].archetypeId, 0xFFFF);
      expect(target[holder].pageIndex, 0xFFFF);
      expect(target[holder].rowOffset, 0xFFFFFFFF);
    });

    test(
      'the declared default is stamped into new rows, recycled ones too',
      () {
        const fallback = Entity.pack(3, 2, 128);
        late DataPointer<Entity> target;
        late DataPointer<Entity> undeclared;
        final h = _Harness((data) {
          target = data.hasEntity(fallback);
          undeclared = data.hasEntity();
        });
        addTearDown(h.dispose);

        final first = h.spawn();
        expect(target[first], fallback);
        // No default given: the row starts at the handle 0 packs, which is a
        // real address (archetype 0, page 0, row 0) rather than a "none".
        expect(undeclared[first], const Entity(0));

        target[first] = h.spawn();
        undeclared[first] = const Entity(77);
        final page = h.prefab.archetype.pageAt(first.pageIndex);
        page!.free(first.rowOffset);

        final recycled = h.spawn();
        expect(
          recycled.rowOffset,
          first.rowOffset,
          reason: 'the row was recycled',
        );
        expect(target[recycled], fallback);
        expect(undeclared[recycled], const Entity(0));
      },
    );

    test('each row holds its own handle', () {
      late DataPointer<Entity> target;
      final h = _Harness((data) => target = data.hasEntity());
      addTearDown(h.dispose);

      final a = h.spawn();
      final b = h.spawn();
      final c = h.spawn();
      target[a] = c;
      target[b] = a;
      target[c] = b;

      expect([target[a], target[b], target[c]], [c, a, b]);
    });
  });

  group('nullable entity handle (optEntity) fields', () {
    test('a stored handle round-trips, and null is not Entity(0)', () {
      late DataPointer<Entity?> target;
      final h = _Harness((data) => target = data.optEntity());
      addTearDown(h.dispose);

      final holder = h.spawn();
      final other = h.spawn();
      target[holder] = other;
      expect(target[holder], other);

      const packed = Entity.pack(0xFFFF, 0xFFFF, 0xFFFFFFFF);
      expect(packed.value < 0, isTrue, reason: 'the fixture must be negative');
      target[holder] = packed;
      expect(target[holder]?.value, packed.value);

      // The reason this type exists: `Entity(0)` is a real handle (archetype
      // 0, page 0, row 0), so "no target" cannot be spelled as a reserved
      // value. Stored, it reads back as itself; the flag beside the value is
      // what tells it apart from `null`.
      target[holder] = const Entity(0);
      expect(target[holder], isNotNull);
      expect(target[holder], const Entity(0));
      target[holder] = null;
      expect(target[holder], isNull);
    });

    test(
      'the declared default is stamped into new rows, recycled ones too',
      () {
        const fallback = Entity.pack(3, 2, 128);
        late DataPointer<Entity?> target;
        late DataPointer<Entity?> undeclared;
        final h = _Harness((data) {
          target = data.optEntity(fallback);
          undeclared = data.optEntity();
        });
        addTearDown(h.dispose);

        final first = h.spawn();
        expect(target[first], fallback);
        // No default given means absent, not the handle 0 packs.
        expect(undeclared[first], isNull);

        target[first] = null;
        undeclared[first] = const Entity(77);
        final page = h.prefab.archetype.pageAt(first.pageIndex);
        page!.free(first.rowOffset);

        final recycled = h.spawn();
        expect(
          recycled.rowOffset,
          first.rowOffset,
          reason: 'the row was recycled',
        );
        expect(target[recycled], fallback);
        expect(undeclared[recycled], isNull);
      },
    );

    test('each row holds its own handle, null included', () {
      late DataPointer<Entity?> target;
      final h = _Harness((data) => target = data.optEntity());
      addTearDown(h.dispose);

      final a = h.spawn();
      final b = h.spawn();
      final c = h.spawn();
      target[a] = c;
      target[b] = null;
      target[c] = a;

      expect([target[a], target[b], target[c]], [c, null, a]);
    });

    test(
      'the presence flag costs a byte, or nothing after a sub-byte field',
      () {
        final has = _Harness((data) => data.hasEntity());
        addTearDown(has.dispose);
        final opt = _Harness((data) => data.optEntity());
        addTearDown(opt.dispose);
        // The flag is declared ahead of the handle and the handle then rounds
        // up to its own byte, so on a byte-aligned row the flag takes a whole
        // one.
        expect(opt.bitLength - has.bitLength, 8);

        // Those seven spare bits sit in front of the handle, so only a field
        // declared before the flag can claim them - anything after starts
        // past the handle, byte-aligned already.
        final shared = _Harness((data) {
          data.hasUint4();
          data.optEntity();
        });
        addTearDown(shared.dispose);
        expect(shared.bitLength, opt.bitLength);
      },
    );
  });

  group('enum (hasEnum) fields', () {
    test('every member round-trips', () {
      late DataPointer<_Element> target;
      final h = _Harness((data) => target = data.hasEnum(_Element.values));
      addTearDown(h.dispose);

      final e = h.spawn();
      for (final element in _Element.values) {
        target[e] = element;
        expect(target[e], element);
      }
    });

    test(
      'the declared default is stamped into new rows, recycled ones too',
      () {
        late DataPointer<_Phase> target;
        late DataPointer<_Phase> undeclared;
        final h = _Harness((data) {
          target = data.hasEnum(_Phase.values, _Phase.falling);
          undeclared = data.hasEnum(_Phase.values);
        });
        addTearDown(h.dispose);

        final first = h.spawn();
        expect(target[first], _Phase.falling);
        // No default given: the row starts at index 0, which is the member
        // declared first rather than any kind of "unset".
        expect(undeclared[first], _Phase.rising);

        target[first] = _Phase.rising;
        undeclared[first] = _Phase.holding;
        final page = h.prefab.archetype.pageAt(first.pageIndex);
        page!.free(first.rowOffset);

        final recycled = h.spawn();
        expect(
          recycled.rowOffset,
          first.rowOffset,
          reason: 'the row was recycled',
        );
        expect(target[recycled], _Phase.falling);
        expect(undeclared[recycled], _Phase.rising);
      },
    );

    test('each row holds its own member', () {
      late DataPointer<_Element> target;
      final h = _Harness((data) => target = data.hasEnum(_Element.values));
      addTearDown(h.dispose);

      final a = h.spawn();
      final b = h.spawn();
      final c = h.spawn();
      target[a] = _Element.fire;
      target[b] = _Element.air;
      target[c] = _Element.none;

      expect(
        [target[a], target[b], target[c]],
        [_Element.fire, _Element.air, _Element.none],
      );
    });

    // The next three read the chosen width off the row itself. The point of
    // the ladder is that a three-member enum costs the two bits `hasUint2`
    // cost when callers packed the index by hand, not a whole byte.
    test('two members take one bit', () {
      final h = _Harness((data) => data.hasEnum(_Toggle.values));
      addTearDown(h.dispose);
      expect(h.bitLength, 1);
    });

    test('three members take two bits, as BodyType2D does', () {
      final h = _Harness((data) => data.hasEnum(_Phase.values));
      addTearDown(h.dispose);
      expect(h.bitLength, 2);
    });

    test('five members take four bits', () {
      final h = _Harness((data) => data.hasEnum(_Element.values));
      addTearDown(h.dispose);
      expect(h.bitLength, 4);
    });

    test('a field declared after the enum column starts at its end', () {
      // The width seen from the other side: a flag behind a three-member
      // enum lands at bit 2, and neither field can reach the other's bits.
      late DataPointer<_Phase> phase;
      late DataPointer<int> flag;
      final h = _Harness((data) {
        phase = data.hasEnum(_Phase.values);
        flag = data.hasUint1(1);
      });
      addTearDown(h.dispose);

      expect(h.bitLength, 3, reason: '2 bits for the enum, 1 for the flag');

      final e = h.spawn();
      // The last member sets both of the enum's bits, so a flag overlapping
      // either would read back wrong here - and the enum would read back
      // wrong when the flag is cleared below.
      phase[e] = _Phase.values.last;
      expect(flag[e], 1);
      flag[e] = 0;
      expect(phase[e], _Phase.values.last);
    });

    test('a list that is not the whole values list is rejected', () {
      // Writing stores `Enum.index`, so a partial list reads back a
      // different member than was written - silent, and only at run time.
      late Object? error;
      final h = _Harness((data) {
        try {
          data.hasEnum(_Element.values.sublist(1));
        } catch (e) {
          error = e;
        }
      });
      addTearDown(h.dispose);
      expect(error, isA<AssertionError>());
    });
  });

  group('tick semantics', () {
    test('reads see the last published tick while writes land in this one', () {
      late DataPointer<double> x;
      final h = _Harness((data) => x = data.hasFloat64());
      addTearDown(h.dispose);

      h.pool.beginTick();
      final e = h.spawn();
      x[e] = 10.0;
      h.pool.commitTick();
      expect(x[e], 10.0);

      // The fixed-tick pattern: read-modify-write in place, once per tick,
      // resolving the same row through its stable offset every time.
      for (var tick = 0; tick < 5; tick++) {
        h.pool.beginTick();
        x[e] += 1.0;
        h.pool.commitTick();
      }
      expect(x[e], 15.0);
    });

    test('rows spill onto a second page and stay distinct', () {
      late DataPointer<int> id;
      // 4 bytes per row, 40 byte page => 10 rows per page.
      final h = _Harness((data) => id = data.hasUint32(), pageSize: 40);
      addTearDown(h.dispose);
      expect(h.strideBytes, 4);

      h.pool.beginTick();
      final entities = <Entity>[];
      for (var i = 0; i < 25; i++) {
        final e = h.spawn();
        entities.add(e);
        id[e] = 1000 + i;
      }
      h.pool.commitTick();

      expect(h.prefab.archetype.pageCount, 3);
      expect(entities[0].pageIndex, 0);
      expect(entities[9].pageIndex, 0);
      expect(entities[10].pageIndex, 1);
      expect(entities[20].pageIndex, 2);
      for (var i = 0; i < 25; i++) {
        expect(id[entities[i]], 1000 + i, reason: 'entity $i');
      }
    });
  });

  // `DataPointer.readPending` is public API and partial: three column kinds
  // answer and every other throws. Nothing here measured which was which, and
  // the two ways it was wrong are the two halves of this group - a kind that
  // reported its failure under the wrong class, and the outside-a-tick
  // fallback the base doc states that one implementation did not make.
  group('readPending', () {
    test('float64 answers the slot this tick is writing', () {
      late DataPointer<double> x;
      final h = _Harness((data) => x = data.hasFloat64());
      addTearDown(h.dispose);

      h.pool.beginTick();
      final e = h.spawn();
      x[e] = 1.0;
      h.pool.commitTick();

      h.pool.beginTick();
      x[e] = 2.0;
      expect(x[e], 1.0, reason: 'an ordinary read stays on the published slot');
      expect(x.readPending(e), 2.0);
      h.pool.commitTick();
    });

    test('optInt64 answers the slot this tick is writing', () {
      late DataPointer<int?> x;
      final h = _Harness((data) => x = data.optInt64());
      addTearDown(h.dispose);

      h.pool.beginTick();
      final e = h.spawn();
      x[e] = 1;
      h.pool.commitTick();

      h.pool.beginTick();
      x[e] = 2;
      expect(x[e], 1);
      expect(x.readPending(e), 2);
      // The flag and the value come from one slot, so a column cleared this
      // tick reads back absent rather than as the published 1.
      x[e] = null;
      expect(x.readPending(e), isNull);
      expect(x[e], 1);
      h.pool.commitTick();
    });

    test('optEntity answers the slot this tick is writing', () {
      late DataPointer<Entity?> link;
      final h = _Harness((data) => link = data.optEntity());
      addTearDown(h.dispose);

      h.pool.beginTick();
      final a = h.spawn();
      final b = h.spawn();
      h.pool.commitTick();

      h.pool.beginTick();
      link[a] = b;
      expect(link[a], isNull, reason: 'nothing published into this column');
      expect(link.readPending(a), b);
      h.pool.commitTick();
    });

    // Stated on `DataPointer.readPending`: outside a tick the write slot holds
    // whatever sat there before `beginWrite` copied, so an implementation
    // answers with the published read instead. `_OptionalField` guarded;
    // `_Float64Field` reached for the write slot, which on a page that has
    // published trips the lost-write assertion - reporting a write this call
    // never makes.
    test('outside a tick float64 answers the published slot', () {
      late DataPointer<double> x;
      final h = _Harness((data) => x = data.hasFloat64());
      addTearDown(h.dispose);

      h.pool.beginTick();
      final e = h.spawn();
      x[e] = 1.0;
      h.pool.commitTick();

      h.pool.beginTick();
      x[e] = 2.0;
      h.pool.commitTick();

      expect(x.readPending(e), 2.0);
    });

    test('outside a tick optInt64 answers the published slot', () {
      late DataPointer<int?> x;
      final h = _Harness((data) => x = data.optInt64());
      addTearDown(h.dispose);

      h.pool.beginTick();
      final e = h.spawn();
      x[e] = 1;
      h.pool.commitTick();

      h.pool.beginTick();
      x[e] = 2;
      h.pool.commitTick();

      expect(x.readPending(e), 2);
    });

    // A kind that cannot answer names the column the caller declared.
    // `hasBool` forwarded the call into the one-bit field it wraps, so the
    // failure arrived under `_SubByteUintField` - a name no declaration
    // writes and no caller can act on.
    test('a column kind that cannot answer names itself', () {
      late DataPointer<bool> flag;
      final h = _Harness((data) => flag = data.hasBool());
      addTearDown(h.dispose);

      h.pool.beginTick();
      final e = h.spawn();
      expect(
        () => flag.readPending(e),
        throwsA(
          isA<UnsupportedError>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('_BoolField'),
              contains('readPending'),
              isNot(contains('_SubByteUintField')),
            ),
          ),
        ),
      );
      h.pool.commitTick();
    });

    test('an unsupported width refuses rather than answering published', () {
      late DataPointer<double> x;
      final h = _Harness((data) => x = data.hasFloat32());
      addTearDown(h.dispose);

      h.pool.beginTick();
      final e = h.spawn();
      x[e] = 3.5;
      expect(
        () => x.readPending(e),
        throwsA(
          isA<UnsupportedError>().having(
            (e) => e.message,
            'message',
            contains('_Float32Field'),
          ),
        ),
      );
      h.pool.commitTick();
    });
  });

  group('array fields', () {
    test('a byte-aligned int array round-trips every index independently', () {
      late DataArrayPointer<int> values;
      final h = _Harness((data) => values = data.hasArray(.uint16, 4));
      addTearDown(h.dispose);

      expect(values.length, 4);
      expect(h.strideBytes, 8, reason: '4 x 16 bits, no padding between them');

      final e = h.spawn();
      for (var i = 0; i < 4; i++) {
        values.set(e, i, 1000 + i);
      }
      for (var i = 0; i < 4; i++) {
        expect(values.get(e, i), 1000 + i, reason: 'element $i');
      }

      // The point of the whole packing exercise: one element's store must
      // not reach into its neighbours' bytes.
      values.set(e, 2, 65535);
      expect(
        [
          values.get(e, 0),
          values.get(e, 1),
          values.get(e, 2),
          values.get(e, 3),
        ],
        [1000, 1001, 65535, 1003],
      );
    });

    test('a sub-byte array packs tight and elements stay independent', () {
      // Eight 1-bit elements must occupy exactly one byte, and the field
      // declared after them must start at bit 8 - i.e. `declareField`'s
      // byte-rounding never fires mid-array, because 8 is divisible by 1.
      // If any gap crept in, `bitLength` would exceed 12 immediately.
      late DataArrayPointer<int> flags;
      late DataPointer<int> nibble;
      final h = _Harness((data) {
        flags = data.hasArray(.uint1, 8);
        nibble = data.hasUint4();
      });
      addTearDown(h.dispose);

      expect(h.bitLength, 12, reason: '8 x 1 bit with no gaps, then 4 bits');
      expect(h.strideBytes, 2);

      final e = h.spawn();
      for (var i = 0; i < 8; i++) {
        flags.set(e, i, 1);
      }
      nibble[e] = 0xF;
      flags.set(e, 3, 0);
      for (var i = 0; i < 8; i++) {
        expect(flags.get(e, i), i == 3 ? 0 : 1, reason: 'element $i');
      }
      expect(nibble[e], 0xF, reason: 'the array must not spill past bit 7');
    });

    test('4-bit elements pack two to a byte', () {
      late DataArrayPointer<int> nibbles;
      final h = _Harness((data) => nibbles = data.hasArray(.uint4, 4));
      addTearDown(h.dispose);

      expect(h.bitLength, 16, reason: '4 x 4 bits, two per byte, no padding');
      expect(h.strideBytes, 2);

      final e = h.spawn();
      for (var i = 0; i < 4; i++) {
        nibbles.set(e, i, 0xF - i);
      }
      for (var i = 0; i < 4; i++) {
        expect(nibbles.get(e, i), 0xF - i, reason: 'element $i');
      }
    });

    test(
      'a sub-byte array declared at a misaligned cursor still round-trips',
      () {
        // The case that breaks naive `baseBit + i * bitWidth` addressing. After
        // one 1-bit field the cursor sits at bit 1, where element 0 fits
        // (1 + 4 <= 8) but element 1 would straddle the byte and get pushed to
        // bit 8 - a gap the arithmetic cannot see, which would make elements
        // 1..3 alias their neighbours and overrun the array. The declaration
        // pads to a multiple of the element width first, so the elements are
        // evenly spaced from bit 4 on.
        late DataPointer<int> flag;
        late DataArrayPointer<int> nibbles;
        late DataPointer<int> trailer;
        final h = _Harness((data) {
          flag = data.hasUint1();
          nibbles = data.hasArray(.uint4, 4);
          trailer = data.hasUint4();
        });
        addTearDown(h.dispose);

        // 1 flag bit + 3 padding bits + 4 x 4 element bits + 4 trailer bits.
        expect(h.bitLength, 24);
        expect(h.strideBytes, 3);

        final e = h.spawn();
        flag[e] = 1;
        trailer[e] = 0xC;
        for (var i = 0; i < 4; i++) {
          nibbles.set(e, i, 0xA + i);
        }
        for (var i = 0; i < 4; i++) {
          expect(nibbles.get(e, i), 0xA + i, reason: 'element $i');
        }
        expect(flag[e], 1, reason: 'the array must not have run backwards');
        expect(trailer[e], 0xC, reason: 'the array must not have overrun');

        // And one element's write still leaves the others alone at this base.
        nibbles.set(e, 1, 0x3);
        expect(
          [
            nibbles.get(e, 0),
            nibbles.get(e, 1),
            nibbles.get(e, 2),
            nibbles.get(e, 3),
          ],
          [0xA, 0x3, 0xC, 0xD],
        );
      },
    );

    test(
      'signed array elements sign-extend, sub-byte and byte-aligned alike',
      () {
        late DataArrayPointer<int> nibbles, bytes;
        final h = _Harness((data) {
          nibbles = data.hasArray(.int4, 3);
          bytes = data.hasArray(.int16, 2);
        });
        addTearDown(h.dispose);

        final e = h.spawn();
        nibbles.set(e, 0, -8);
        nibbles.set(e, 1, 7);
        nibbles.set(e, 2, -1);
        bytes.set(e, 0, -32768);
        bytes.set(e, 1, 32767);
        expect(
          [nibbles.get(e, 0), nibbles.get(e, 1), nibbles.get(e, 2)],
          [-8, 7, -1],
        );
        expect([bytes.get(e, 0), bytes.get(e, 1)], [-32768, 32767]);
      },
    );

    test('float arrays round-trip both widths', () {
      late DataArrayPointer<double> f32, f64;
      final h = _Harness((data) {
        f32 = data.hasArray(.float32, 3);
        f64 = data.hasArray(.float64, 2);
      });
      addTearDown(h.dispose);
      expect(h.strideBytes, 3 * 4 + 2 * 8);

      final e = h.spawn();
      // 0.5/0.25/0.125 are exactly representable, so no float32 rounding
      // noise muddies the comparison.
      f32.set(e, 0, 0.5);
      f32.set(e, 1, 0.25);
      f32.set(e, 2, 0.125);
      f64.set(e, 0, -1.0e300);
      f64.set(e, 1, 1234.5678);
      expect([f32.get(e, 0), f32.get(e, 1), f32.get(e, 2)], [0.5, 0.25, 0.125]);
      expect([f64.get(e, 0), f64.get(e, 1)], [-1.0e300, 1234.5678]);
    });

    test(
      'an index outside 0..length-1 throws instead of corrupting a neighbour',
      () {
        // Silently addressing element -1 or element `length` would reach into
        // an adjacent field or - past the end of the row - the next entity's
        // row entirely, since rows are packed back to back in a page.
        late DataArrayPointer<int> values;
        final h = _Harness((data) => values = data.hasArray(.uint8, 3));
        addTearDown(h.dispose);

        final e = h.spawn();
        expect(() => values.get(e, -1), throwsRangeError);
        expect(() => values.get(e, 3), throwsRangeError);
        expect(() => values.set(e, -1, 1), throwsRangeError);
        expect(() => values.set(e, 3, 1), throwsRangeError);
        expect(
          values.get(e, 2),
          isNotNull,
          reason: 'the last valid index is fine',
        );
      },
    );

    test('every array width checks its own bounds', () {
      // The bounds check is one method, but each width calls it from its own
      // `get` and `set` - 22 call sites. One left out is invisible until an
      // array of exactly that width is indexed past its end, and then it is
      // silent corruption rather than an error. So walk every width rather
      // than trusting the one above to stand for all of them.
      late List<DataArrayPointer<Object?>> widths;
      final h = _Harness((data) {
        widths = <DataArrayPointer<Object?>>[
          data.hasArray(.uint2, 3), // sub-byte unsigned
          data.hasArray(.int2, 3), // sub-byte signed
          data.hasArray(.uint8, 3),
          data.hasArray(.int8, 3),
          data.hasArray(.uint16, 3),
          data.hasArray(.int16, 3),
          data.hasArray(.uint32, 3),
          data.hasArray(.int32, 3),
          data.hasArray(.float32, 3),
          data.hasArray(.float64, 3),
          data.hasArray(assets.of<_Texture>(), 3, _loaded()),
          data.optArray(.uint8, 3),
        ];
      });
      addTearDown(h.dispose);

      final e = h.spawn();
      for (final column in widths) {
        final what = column.runtimeType;
        expect(() => column.get(e, -1), throwsRangeError, reason: '$what get');
        expect(() => column.get(e, 3), throwsRangeError, reason: '$what get');
        expect(
          () => column.set(e, -1, column.get(e, 0)),
          throwsRangeError,
          reason: '$what set',
        );
        expect(
          () => column.set(e, 3, column.get(e, 0)),
          throwsRangeError,
          reason: '$what set',
        );
      }
    });

    test('a zero-length array is rejected at declare time', () {
      // Every index into it would be out of range, so it can only ever be a
      // caller mistake - better one failure at describe time than a
      // RangeError from every access.
      late Object? error;
      final h = _Harness((data) {
        try {
          data.hasArray(.uint8, 0);
        } catch (e) {
          error = e;
        }
      });
      addTearDown(h.dispose);

      // On the message, for the reason the per-element case above gives.
      expect(error, isA<ArgumentError>());
      expect(
        (error! as ArgumentError).message.toString(),
        contains('must be at least 1'),
      );
      expect((error! as ArgumentError).name, 'length');
    });

    test('nullable array elements carry their own has-bit', () {
      late DataArrayPointer<int?> maybe;
      final h = _Harness((data) => maybe = data.optArray(.int32, 4));
      addTearDown(h.dispose);

      final e = h.spawn();
      expect(
        [maybe.get(e, 0), maybe.get(e, 1), maybe.get(e, 2), maybe.get(e, 3)],
        [null, null, null, null],
        reason: 'no default was declared',
      );

      maybe.set(e, 0, -12345);
      maybe.set(e, 2, 0);
      expect(
        [maybe.get(e, 0), maybe.get(e, 1), maybe.get(e, 2), maybe.get(e, 3)],
        [-12345, null, 0, null],
        reason: '0 is a value, not absence',
      );

      // Clearing one element's flag must not clear anyone else's.
      maybe.set(e, 0, null);
      expect(
        [maybe.get(e, 0), maybe.get(e, 1), maybe.get(e, 2), maybe.get(e, 3)],
        [null, null, 0, null],
      );

      maybe.set(e, 3, 7);
      expect([maybe.get(e, 2), maybe.get(e, 3)], [0, 7]);
    });

    test(
      'nullable sub-byte elements stay independent despite interleaved flags',
      () {
        // 1 flag bit + 2 value bits per element does not tile a byte evenly,
        // so this is the case where the per-element declaration order matters
        // most - each element's flag and value are found through their own
        // recorded offsets, not a uniform stride.
        late DataArrayPointer<int?> maybe;
        final h = _Harness((data) => maybe = data.optArray(.uint2, 5));
        addTearDown(h.dispose);

        final e = h.spawn();
        for (var i = 0; i < 5; i++) {
          maybe.set(e, i, i % 4);
        }
        for (var i = 0; i < 5; i++) {
          expect(maybe.get(e, i), i % 4, reason: 'element $i');
        }
        maybe.set(e, 2, null);
        for (var i = 0; i < 5; i++) {
          expect(maybe.get(e, i), i == 2 ? null : i % 4, reason: 'element $i');
        }
      },
    );

    test('declared defaults are stamped into every element of a fresh row', () {
      late DataArrayPointer<int> plain;
      late DataArrayPointer<int> nibbles;
      late DataArrayPointer<double> floats;
      late DataArrayPointer<int?> present, absent;
      final h = _Harness((data) {
        plain = data.hasArray(.uint8, 3, 7);
        // A negative default has to survive truncation into 4 bits on the
        // way in and sign extension on the way out, per element.
        nibbles = data.hasArray(.int4, 3, -3);
        floats = data.hasArray(.float64, 2, 3.5);
        present = data.optArray(.int32, 3, -42);
        absent = data.optArray(.int32, 3);
      });
      addTearDown(h.dispose);

      final e = h.spawn();
      for (var i = 0; i < 3; i++) {
        expect(plain.get(e, i), 7, reason: 'element $i');
        expect(nibbles.get(e, i), -3, reason: 'element $i');
        expect(present.get(e, i), -42, reason: 'element $i');
        expect(absent.get(e, i), isNull, reason: 'element $i');
      }
      expect([floats.get(e, 0), floats.get(e, 1)], [3.5, 3.5]);

      // Dirty the row, hand it back, and confirm the next tenant gets the
      // declared defaults again - rows are recycled and are never zeroed.
      plain.set(e, 1, 99);
      present.set(e, 1, null);
      absent.set(e, 1, 5);
      h.prefab.archetype.pageAt(e.pageIndex)!.free(e.rowOffset);

      final second = h.spawn();
      expect(second.rowOffset, e.rowOffset, reason: 'the row was recycled');
      for (var i = 0; i < 3; i++) {
        expect(plain.get(second, i), 7, reason: 'element $i');
        expect(present.get(second, i), -42, reason: 'element $i');
        expect(absent.get(second, i), isNull, reason: 'element $i');
      }
    });

    test('per-element defaults start each element at its own value', () {
      late DataArrayPointer<double> outline;
      late DataArrayPointer<double> narrow;
      final h = _Harness((data) {
        // Four slots for three values - the tail is room a caller reserved
        // for elements it writes per entity later.
        outline = data.hasArrayOf(.float64, 4, const [1.5, -2.5, 3.25]);
        narrow = data.hasArrayOf(.float32, 2, const [0.5, 0.25]);
      });
      addTearDown(h.dispose);

      final e = h.spawn();
      expect(
        [outline.get(e, 0), outline.get(e, 1), outline.get(e, 2)],
        [1.5, -2.5, 3.25],
      );
      expect(outline.get(e, 3), 0.0, reason: 'the reserved slot');
      expect([narrow.get(e, 0), narrow.get(e, 1)], [0.5, 0.25]);

      // Same recycling question as the broadcast defaults above: the row
      // carries no memory of its last tenant.
      outline.set(e, 0, 99);
      h.prefab.archetype.pageAt(e.pageIndex)!.free(e.rowOffset);

      final second = h.spawn();
      expect(second.rowOffset, e.rowOffset, reason: 'the row was recycled');
      expect(outline.get(second, 0), 1.5);
    });

    test('per-element initial values work for an integer element too', () {
      // The `...Of` form used to exist for the two float widths only, because
      // that is what `hasPolygonCollider` needed. The element being an
      // argument is what makes one method cover every width, so this is the
      // case #35 asked for: an int array whose elements start apart.
      late DataArrayPointer<int> ramp;
      late DataArrayPointer<int> nibbles;
      final h = _Harness((data) {
        ramp = data.hasArrayOf(.int16, 4, const [-2, 0, 5, 300]);
        nibbles = data.hasArrayOf(.uint4, 3, const [1, 2]);
      });
      addTearDown(h.dispose);

      final e = h.spawn();
      expect(
        [ramp.get(e, 0), ramp.get(e, 1), ramp.get(e, 2), ramp.get(e, 3)],
        [-2, 0, 5, 300],
      );
      expect(
        [nibbles.get(e, 0), nibbles.get(e, 1), nibbles.get(e, 2)],
        [1, 2, 0],
        reason: 'the slot past the values given starts at the element zero',
      );
    });

    test('a representation element without an initial value is refused at '
        'declare time', () {
      // The bits an unwritten element holds are 0, and a representation is
      // under no obligation to have a value for 0 - so the alternative to
      // this throw is a read that blows up out of `unpack`, per entity, a
      // long way from the declaration that caused it.
      late Object? error;
      final h = _Harness((data) {
        try {
          data.hasArray(assets.of<_Texture>(), 2);
        } catch (e) {
          error = e;
        }
      });
      addTearDown(h.dispose);

      expect(error, isA<ArgumentError>());
      expect((error! as ArgumentError).name, 'initialValue');
      expect(
        (error! as ArgumentError).message.toString(),
        contains('optArray'),
        reason: 'the message has to name the way out, not just refuse',
      );
    });

    test('a nullable representation element needs no initial value', () {
      // The discriminating half of the test above: the same element, the same
      // absent value, and no throw - because a clear flag means the value
      // bits are never read.
      late DataArrayPointer<Asset<_Texture>?> textures;
      final h = _Harness(
        (data) => textures = data.optArray(assets.of<_Texture>(), 2),
      );
      addTearDown(h.dispose);
      expect(textures.get(h.spawn(), 0), isNull);
    });

    test('more values than the array holds is rejected at declare time', () {
      late Object? error;
      final h = _Harness((data) {
        try {
          data.hasArrayOf(.float64, 2, const [1.0, 2.0, 3.0]);
        } catch (e) {
          error = e;
        }
      });
      addTearDown(h.dispose);

      // Not `isA<ArgumentError>()` on its own: `RangeError` is an
      // `ArgumentError`, and with this guard removed the `setRange` behind it
      // throws one - so the type alone cannot tell the guard from the failure
      // it exists to pre-empt. The message is what discriminates.
      expect(error, isA<ArgumentError>());
      expect(
        (error! as ArgumentError).message.toString(),
        contains('more values than the array holds (2)'),
      );
      expect((error! as ArgumentError).name, 'initialValues');
    });

    test(
      'a representation element round-trips through its declared table',
      () {
        final placeholder = _loaded();
        final grass = _loaded();
        final stone = _loaded();

        late DataArrayPointer<Asset<_Texture>> textures;
        final h = _Harness(
          (data) => textures = data.hasArray(
            assets.of<_Texture>(),
            3,
            placeholder,
          ),
        );
        addTearDown(h.dispose);

        final e = h.spawn();
        for (var i = 0; i < 3; i++) {
          expect(
            textures.get(e, i),
            same(placeholder),
            reason: 'declared default, element $i',
          );
        }

        h.pool.beginTick();
        textures.set(e, 0, grass);
        textures.set(e, 2, stone);
        h.pool.commitTick();
        expect(textures.get(e, 0), same(grass));
        expect(
          textures.get(e, 1),
          same(placeholder),
          reason: 'untouched element',
        );
        expect(textures.get(e, 2), same(stone));
      },
    );

    test(
      'a nullable representation element starts null and round-trips it',
      () {
        final grass = _loaded();

        late DataArrayPointer<Asset<_Texture>?> textures;
        final h = _Harness(
          (data) => textures = data.optArray(assets.of<_Texture>(), 2),
        );
        addTearDown(h.dispose);

        final e = h.spawn();
        expect([textures.get(e, 0), textures.get(e, 1)], [null, null]);

        h.pool.beginTick();
        textures.set(e, 1, grass);
        h.pool.commitTick();
        expect(textures.get(e, 0), isNull);
        expect(textures.get(e, 1), same(grass));

        h.pool.beginTick();
        textures.set(e, 1, null);
        h.pool.commitTick();
        expect(textures.get(e, 1), isNull);
      },
    );
  });

  group('heap object (hasHeapObject/optHeapObject) fields', () {
    test(
      'hasHeapObject round-trips a plain closure - no IntRepresentable needed',
      () {
        // A closure is the sharpest example of what hasPacked cannot store:
        // it has no `pack()` of its own and never will.
        void defaultCallback() {}
        void replacement() {}

        late DataPointer<void Function()> callback;
        final h = _Harness(
          (data) => callback = data.hasHeapObject<void Function()>(
            () => defaultCallback,
          ),
        );
        addTearDown(h.dispose);

        final e = h.spawn();
        expect(
          callback[e],
          same(defaultCallback),
          reason: 'the factory default',
        );

        callback[e] = replacement;
        expect(callback[e], same(replacement));
      },
    );

    test('the declared default is one shared instance, not one per entity', () {
      // writeInitialValue runs once, to build the prototype row, and allocateRow
      // memcpys that row into every spawn - copying the 4-byte address, not
      // the object. So a factory default is shared, exactly as
      // hasPacked<T extends IntRepresentable>(T initialValue) already is. This
      // test exists to pin that semantic down rather than leave a future
      // reader guessing which way it went.
      var factoryCalls = 0;
      final shared = <int>[];

      late DataPointer<List<int>> list;
      final h = _Harness(
        (data) => list = data.hasHeapObject<List<int>>(() {
          factoryCalls++;
          return shared;
        }),
      );
      addTearDown(h.dispose);

      final first = h.spawn();
      final second = h.spawn();
      expect(factoryCalls, 1, reason: 'the factory runs once, at seal');
      expect(list[first], same(shared));
      expect(
        list[second],
        same(list[first]),
        reason: 'one shared default instance',
      );
    });

    test(
      'optHeapObject is null until written, and round-trips back to null',
      () {
        final value = <String>['a'];

        late DataPointer<List<String>?> maybe;
        final h = _Harness(
          (data) => maybe = data.optHeapObject<List<String>>(),
        );
        addTearDown(h.dispose);

        final e = h.spawn();
        expect(maybe[e], isNull, reason: 'no default is possible or needed');

        maybe[e] = value;
        expect(maybe[e], same(value));

        maybe[e] = null;
        expect(maybe[e], isNull);
      },
    );

    test(
      'reading a stale/unregistered heap address fails loudly, not silently',
      () {
        void callback() {}
        late DataPointer<void Function()> field;
        final h = _Harness(
          (data) => field = data.hasHeapObject<void Function()>(() => callback),
        );
        addTearDown(h.dispose);
        final e = h.spawn();

        HeapObjectRegistry.reset();
        expect(() => field[e], throwsStateError);
      },
    );

    test(
      'HeapObjectRegistry reuses a freed address instead of growing forever',
      () {
        // The concrete difference from the asset table, which only ever
        // appends and nulls out. Heap-object fields are written at arbitrary
        // runtime moments, so an append-only table would grow without bound.
        final first = Object();
        final second = Object();

        final addressA = HeapObjectRegistry.register(first);
        expect(HeapObjectRegistry.resolve<Object>(addressA), same(first));
        expect(HeapObjectRegistry.slotCount, 1);

        HeapObjectRegistry.unregister(addressA);
        expect(
          HeapObjectRegistry.tryResolve<Object>(addressA),
          isNull,
          reason: 'a freed address resolves to nothing, it does not linger',
        );

        final addressB = HeapObjectRegistry.register(second);
        expect(addressB, addressA, reason: 'the freed slot was reused');
        expect(
          HeapObjectRegistry.slotCount,
          1,
          reason: 'the table did not grow',
        );
        expect(HeapObjectRegistry.resolve<Object>(addressB), same(second));
      },
    );

    test('unregistering twice does not hand one slot to two objects', () {
      // A duplicate free-list entry would be the nastiest possible bug here:
      // two live objects sharing one address, each silently overwriting the
      // other.
      final first = Object();
      final address = HeapObjectRegistry.register(first);
      HeapObjectRegistry.unregister(address);
      HeapObjectRegistry.unregister(address);
      HeapObjectRegistry.unregister(9999); // out of range, also a no-op

      final a = HeapObjectRegistry.register(Object());
      final b = HeapObjectRegistry.register(Object());
      expect(a, isNot(b), reason: 'two registrations, two distinct addresses');
    });
  });

  group('packed value (hasPacked/optPacked) fields', () {
    test('hasPacked round-trips through its declared table, by address', () {
      final placeholder = _loaded();
      final grass = _loaded();

      late final DataPointer<Asset<_Texture>> texture;
      final h = _Harness(
        (data) => texture = data.hasPacked(assets.of<_Texture>(), placeholder),
      );
      addTearDown(h.dispose);

      final e = h.spawn();
      expect(texture[e], same(placeholder), reason: 'declared default');

      h.pool.beginTick();
      texture[e] = grass;
      h.pool.commitTick();
      expect(texture[e], same(grass));
    });

    test('optPacked defaults to null when no default is given, and round-trips null', () {
      final grass = _loaded();

      late final DataPointer<Asset<_Texture>?> texture;
      final h = _Harness(
        (data) => texture = data.optPacked(assets.of<_Texture>()),
      );
      addTearDown(h.dispose);

      final e = h.spawn();
      expect(texture[e], isNull);

      h.pool.beginTick();
      texture[e] = grass;
      h.pool.commitTick();
      expect(texture[e], same(grass));

      h.pool.beginTick();
      texture[e] = null;
      h.pool.commitTick();
      expect(texture[e], isNull);
    });

    test('reading a stale/unregistered address fails loudly, not silently', () {
      final grass = _loaded();

      late final DataPointer<Asset<_Texture>> texture;
      final h = _Harness(
        (data) => texture = data.hasPacked(assets.of<_Texture>(), grass),
      );
      addTearDown(h.dispose);
      final e = h.spawn();

      assets.unregisterAddress(grass.pack());
      expect(() => texture[e], throwsStateError);
    });

    test('an address means nothing outside the table that issued it', () {
      // The whole point of `IntRepresentation`. Two independent tables, each
      // numbering from zero, so both of these get address 0 - and a field
      // declared against one unpacks to *its* object, never the other's.
      // Under the single shared registry this design replaced, these two
      // could not have coexisted at the same address at all, and every new
      // population had to be poured into the one asset table to be readable.
      //
      // Note both use the *same* key here, which is the sharper version of the
      // test: identity is `(payload type, source)`, so these two tables are
      // being asked about an asset that is, by identity, the same one - and
      // they still number it independently.
      final left = Assets();
      final right = Assets();
      const key = AssetKey<_Texture>(_NoBytes('shared-fixture'));
      final mine = left.declare(key);
      final theirs = right.declare(key);
      expect(
        mine.pack(),
        theirs.pack(),
        reason: 'independent tables collide freely, by design',
      );

      late final DataPointer<Asset<_Texture>> texture;
      final h = _Harness(
        (data) => texture = data.hasPacked(left.of<_Texture>(), mine),
      );
      addTearDown(h.dispose);

      final e = h.spawn();
      expect(texture[e], same(mine));
      expect(texture[e], isNot(same(theirs)));

      // And a table that never issued the address says so rather than
      // handing back whatever happens to sit there.
      right.unregisterAddress(theirs.pack());
      expect(
        () => right.of<_Texture>().unpack(theirs.pack()),
        throwsStateError,
      );
      expect(
        texture[e],
        same(mine),
        reason:
            'the other table being emptied is none of this field\'s '
            'business - separate populations, separate numbering',
      );
    });
  });

  group('a column indexed with an entity of another archetype', () {
    // Nothing on the access path reads `entity.archetypeId` - `rowRead` and
    // `rowWrite` use the page index and the row offset only - so a foreign
    // entity addresses whatever row happens to sit at that page and offset
    // in this archetype's storage. That is a live entity of the wrong
    // prefab, overwritten with no error and noticed hours later. The guard
    // is the only thing that names it, and it is debug-only - these cases
    // pass because the test runner runs with asserts on, which is where a
    // game is developed.

    test('a write is rejected, naming both archetypes and the column', () {
      late DataPointer<int> mine;
      final ours = _Harness((data) => mine = data.hasUint32(11));
      addTearDown(ours.dispose);
      final theirs = _Harness((data) => data.hasUint32(22));
      addTearDown(theirs.dispose);

      final foreign = theirs.spawn();
      final victim = ours.spawn();
      expect(
        foreign.pageIndex,
        victim.pageIndex,
        reason:
            'the two rows collide - which is exactly why the write lands '
            'somewhere real instead of failing on its own',
      );
      expect(foreign.rowOffset, victim.rowOffset);

      expect(
        () => mine[foreign] = 999,
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('archetype ${foreign.archetypeId}'),
              contains('archetype ${ours.prefab.archetypeId}'),
              contains('_AdHoc'),
              contains('Uint32'),
            ),
          ),
        ),
      );
      expect(
        mine[victim],
        11,
        reason: 'and the entity that would have been overwritten is intact',
      );
    });

    test('a read is rejected too - it used to answer 0', () {
      late DataPointer<int> mine;
      final ours = _Harness((data) => mine = data.hasUint32(100));
      addTearDown(ours.dispose);
      final theirs = _Harness((data) => data.hasUint32(0));
      addTearDown(theirs.dispose);

      final foreign = theirs.spawn();
      expect(() => mine[foreign], throwsStateError);
    });

    test('array columns are guarded on the same path', () {
      late DataArrayPointer<int> mine;
      final ours = _Harness((data) => mine = data.hasArray(.uint16, 4, 7));
      addTearDown(ours.dispose);
      final theirs = _Harness((data) => data.hasArray(.uint16, 4, 0));
      addTearDown(theirs.dispose);

      final foreign = theirs.spawn();
      expect(() => mine.get(foreign, 0), throwsStateError);
      expect(() => mine.set(foreign, 0, 5), throwsStateError);
    });

    test('an entity of the declaring archetype still passes', () {
      late DataPointer<int> mine;
      final ours = _Harness((data) => mine = data.hasUint32(3));
      addTearDown(ours.dispose);

      final e = ours.spawn();
      expect(mine[e], 3);
      mine[e] = 4;
      expect(mine[e], 4);
    });
  });
}
