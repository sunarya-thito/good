import 'dart:typed_data';

import 'package:goo/src/scene_handle.dart';
import 'package:goo/src/archetype.dart';
import 'package:goo/src/asset.dart';
import 'package:goo/src/data.dart';
import 'package:goo/src/heap_object.dart';
import 'package:goo/src/pool.dart';
import 'package:goo/src/scene.dart';
import 'package:goo/src/struct.dart';
import 'package:flutter_test/flutter_test.dart';

class _Texture extends GameAssetInstance {}

class _NoBytes extends GameAssetSource {
  @override
  Future<Uint8List> load() async => Uint8List(0);
}

class _TextureAsset extends GameAsset<_Texture> {
  @override
  final GameAssetSource source = _NoBytes();

  @override
  _Texture createInstance() => _Texture();

  @override
  Future<void> loadInto(_Texture instance) async {}
}

/// Declares a fresh asset and returns its addressed instance - the same call
/// `AssetDescriptor.has` makes. These tests are about `hasObject`/
/// `optObject`'s field mechanics, and a field only ever stores the *address*,
/// so declaring (which is what assigns one) is all they need; decoding a
/// payload would be beside the point.
/// The table these ad-hoc fixtures declare into. Instance state now - a
/// `Game` owns one; a fixture with no `Game` owns its own.
final GameAssets assets = GameAssets();

_Texture _loaded() => assets.declare(_TextureAsset());

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

  _AdHocScene(this._prefab);

  final _AdHoc _prefab;

  @override
  void describeScene(SceneDescriptor descriptor) => descriptor.has(_prefab);
}

/// Registers one throwaway archetype and gives the test a spawner for it.
class _Harness {
  _Harness(void Function(DataDescriptor data) build, {int pageSize = 4096})
    : pool = MemoryPool(pageSize: pageSize),
      prefab = _AdHoc(build) {
    scene = _AdHocScene(prefab)..initializeScene(pool, assets: assets);
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
    test('four 2-bit fields share a single byte without corrupting each other', () {
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
    });

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

    test('a sub-byte field that would straddle a byte jumps to the next one', () {
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
    });

    test('a wide field after a sub-byte field is byte-aligned and round-trips', () {
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
    });

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
      final storage =
          ArchetypeRegistry.register(pool, assets, _AdHoc((_) {}));
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

    test('the has-bit costs a bit, not a byte, and packs with its neighbours', () {
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
    });

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

      // The Transform2DSystem pattern: read-modify-write in place, once per
      // tick, resolving the same row through its stable offset every time.
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

  group('array fields', () {
    test('a byte-aligned int array round-trips every index independently', () {
      late DataArrayPointer<int> values;
      final h = _Harness((data) => values = data.hasUint16Array(4));
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
      expect([
        values.get(e, 0),
        values.get(e, 1),
        values.get(e, 2),
        values.get(e, 3),
      ], [1000, 1001, 65535, 1003]);
    });

    test('a sub-byte array packs tight and elements stay independent', () {
      // Eight 1-bit elements must occupy exactly one byte, and the field
      // declared after them must start at bit 8 - i.e. `declareField`'s
      // byte-rounding never fires mid-array, because 8 is divisible by 1.
      // If any gap crept in, `bitLength` would exceed 12 immediately.
      late DataArrayPointer<int> flags;
      late DataPointer<int> nibble;
      final h = _Harness((data) {
        flags = data.hasUint1Array(8);
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
      final h = _Harness((data) => nibbles = data.hasUint4Array(4));
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

    test('a sub-byte array declared at a misaligned cursor still round-trips', () {
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
        nibbles = data.hasUint4Array(4);
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
      expect([
        nibbles.get(e, 0),
        nibbles.get(e, 1),
        nibbles.get(e, 2),
        nibbles.get(e, 3),
      ], [0xA, 0x3, 0xC, 0xD]);
    });

    test('signed array elements sign-extend, sub-byte and byte-aligned alike', () {
      late DataArrayPointer<int> nibbles, bytes;
      final h = _Harness((data) {
        nibbles = data.hasInt4Array(3);
        bytes = data.hasInt16Array(2);
      });
      addTearDown(h.dispose);

      final e = h.spawn();
      nibbles.set(e, 0, -8);
      nibbles.set(e, 1, 7);
      nibbles.set(e, 2, -1);
      bytes.set(e, 0, -32768);
      bytes.set(e, 1, 32767);
      expect([nibbles.get(e, 0), nibbles.get(e, 1), nibbles.get(e, 2)], [-8, 7, -1]);
      expect([bytes.get(e, 0), bytes.get(e, 1)], [-32768, 32767]);
    });

    test('float arrays round-trip both widths', () {
      late DataArrayPointer<double> f32, f64;
      final h = _Harness((data) {
        f32 = data.hasFloat32Array(3);
        f64 = data.hasFloat64Array(2);
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

    test('an index outside 0..length-1 throws instead of corrupting a neighbour', () {
      // Silently addressing element -1 or element `length` would reach into
      // an adjacent field or - past the end of the row - the next entity's
      // row entirely, since rows are packed back to back in a page.
      late DataArrayPointer<int> values;
      final h = _Harness((data) => values = data.hasUint8Array(3));
      addTearDown(h.dispose);

      final e = h.spawn();
      expect(() => values.get(e, -1), throwsRangeError);
      expect(() => values.get(e, 3), throwsRangeError);
      expect(() => values.set(e, -1, 1), throwsRangeError);
      expect(() => values.set(e, 3, 1), throwsRangeError);
      expect(values.get(e, 2), isNotNull, reason: 'the last valid index is fine');
    });

    test('a zero-length array is rejected at declare time', () {
      // Every index into it would be out of range, so it can only ever be a
      // caller mistake - better one failure at describe time than a
      // RangeError from every access.
      late Object? error;
      final h = _Harness((data) {
        try {
          data.hasUint8Array(0);
        } catch (e) {
          error = e;
        }
      });
      addTearDown(h.dispose);
      expect(error, isA<ArgumentError>());
    });

    test('nullable array elements carry their own has-bit', () {
      late DataArrayPointer<int?> maybe;
      final h = _Harness((data) => maybe = data.optInt32Array(4));
      addTearDown(h.dispose);

      final e = h.spawn();
      expect([
        maybe.get(e, 0),
        maybe.get(e, 1),
        maybe.get(e, 2),
        maybe.get(e, 3),
      ], [null, null, null, null], reason: 'no default was declared');

      maybe.set(e, 0, -12345);
      maybe.set(e, 2, 0);
      expect([
        maybe.get(e, 0),
        maybe.get(e, 1),
        maybe.get(e, 2),
        maybe.get(e, 3),
      ], [-12345, null, 0, null], reason: '0 is a value, not absence');

      // Clearing one element's flag must not clear anyone else's.
      maybe.set(e, 0, null);
      expect([
        maybe.get(e, 0),
        maybe.get(e, 1),
        maybe.get(e, 2),
        maybe.get(e, 3),
      ], [null, null, 0, null]);

      maybe.set(e, 3, 7);
      expect([maybe.get(e, 2), maybe.get(e, 3)], [0, 7]);
    });

    test('nullable sub-byte elements stay independent despite interleaved flags', () {
      // 1 flag bit + 2 value bits per element does not tile a byte evenly,
      // so this is the case where the per-element declaration order matters
      // most - each element's flag and value are found through their own
      // recorded offsets, not a uniform stride.
      late DataArrayPointer<int?> maybe;
      final h = _Harness((data) => maybe = data.optUint2Array(5));
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
    });

    test('declared defaults are stamped into every element of a fresh row', () {
      late DataArrayPointer<int> plain;
      late DataArrayPointer<int> nibbles;
      late DataArrayPointer<double> floats;
      late DataArrayPointer<int?> present, absent;
      final h = _Harness((data) {
        plain = data.hasUint8Array(3, 7);
        // A negative default has to survive truncation into 4 bits on the
        // way in and sign extension on the way out, per element.
        nibbles = data.hasInt4Array(3, -3);
        floats = data.hasFloat64Array(2, 3.5);
        present = data.optInt32Array(3, -42);
        absent = data.optInt32Array(3);
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

    test('hasObjectArray round-trips through GlobalObjectRegistry, by address', () {
      final placeholder = _loaded();
      final grass = _loaded();
      final stone = _loaded();

      late DataArrayPointer<_Texture> textures;
      final h = _Harness((data) => textures = data.hasObjectArray<_Texture>(3, placeholder));
      addTearDown(h.dispose);

      final e = h.spawn();
      for (var i = 0; i < 3; i++) {
        expect(textures.get(e, i), same(placeholder), reason: 'declared default, element $i');
      }

      h.pool.beginTick();
      textures.set(e, 0, grass);
      textures.set(e, 2, stone);
      h.pool.commitTick();
      expect(textures.get(e, 0), same(grass));
      expect(textures.get(e, 1), same(placeholder), reason: 'untouched element');
      expect(textures.get(e, 2), same(stone));
    });

    test('optObjectArray defaults to null per element and round-trips null', () {
      final grass = _loaded();

      late DataArrayPointer<_Texture?> textures;
      final h = _Harness((data) => textures = data.optObjectArray<_Texture>(2));
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
    });
  });

  group('heap object (hasHeapObject/optHeapObject) fields', () {
    test('hasHeapObject round-trips a plain closure - no GlobalObject needed', () {
      // A closure is the sharpest example of what hasObject cannot store:
      // it has no `address` of its own and never will.
      void defaultCallback() {}
      void replacement() {}

      late DataPointer<void Function()> callback;
      final h = _Harness(
        (data) => callback = data.hasHeapObject<void Function()>(() => defaultCallback),
      );
      addTearDown(h.dispose);

      final e = h.spawn();
      expect(callback[e], same(defaultCallback), reason: 'the factory default');

      callback[e] = replacement;
      expect(callback[e], same(replacement));
    });

    test('the declared default is one shared instance, not one per entity', () {
      // writeDefault runs once, to build the prototype row, and allocateRow
      // memcpys that row into every spawn - copying the 4-byte address, not
      // the object. So a factory default is shared, exactly as
      // hasObject<T extends GlobalObject>(T defaultValue) already is. This
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
      expect(list[second], same(list[first]), reason: 'one shared default instance');
    });

    test('optHeapObject is null until written, and round-trips back to null', () {
      final value = <String>['a'];

      late DataPointer<List<String>?> maybe;
      final h = _Harness((data) => maybe = data.optHeapObject<List<String>>());
      addTearDown(h.dispose);

      final e = h.spawn();
      expect(maybe[e], isNull, reason: 'no default is possible or needed');

      maybe[e] = value;
      expect(maybe[e], same(value));

      maybe[e] = null;
      expect(maybe[e], isNull);
    });

    test('reading a stale/unregistered heap address fails loudly, not silently', () {
      void callback() {}
      late DataPointer<void Function()> field;
      final h = _Harness(
        (data) => field = data.hasHeapObject<void Function()>(() => callback),
      );
      addTearDown(h.dispose);
      final e = h.spawn();

      HeapObjectRegistry.reset();
      expect(() => field[e], throwsStateError);
    });

    test('HeapObjectRegistry reuses a freed address instead of growing forever', () {
      // The concrete difference from GlobalObjectRegistry, which only ever
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
      expect(HeapObjectRegistry.slotCount, 1, reason: 'the table did not grow');
      expect(HeapObjectRegistry.resolve<Object>(addressB), same(second));
    });

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

  group('object reference (hasObject/optObject) fields', () {
    test('hasObject round-trips through GlobalObjectRegistry, by address', () {
      final placeholder = _loaded();
      final grass = _loaded();

      late final DataPointer<_Texture> texture;
      final h = _Harness((data) => texture = data.hasObject<_Texture>(placeholder));
      addTearDown(h.dispose);

      final e = h.spawn();
      expect(texture[e], same(placeholder), reason: 'declared default');

      h.pool.beginTick();
      texture[e] = grass;
      h.pool.commitTick();
      expect(texture[e], same(grass));
    });

    test('optObject defaults to null when no default is given, and round-trips null', () {
      final grass = _loaded();

      late final DataPointer<_Texture?> texture;
      final h = _Harness((data) => texture = data.optObject<_Texture>());
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

      late final DataPointer<_Texture> texture;
      final h = _Harness((data) => texture = data.hasObject<_Texture>(grass));
      addTearDown(h.dispose);
      final e = h.spawn();

      assets.unregisterAddress(grass.address);
      expect(() => texture[e], throwsStateError);
    });
  });
}
