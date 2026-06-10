import 'dart:typed_data';

import 'package:goo2d/src/data/component.dart';
import 'package:goo2d/src/data/object.dart';

// ---------------------------------------------------------------------------
// Storage backing
// ---------------------------------------------------------------------------

abstract class _AbstractStorage {
  void grow(int newCapacity);
  void compact(Map<int, int> remap);
}

// ---------------------------------------------------------------------------
// _FieldStorage — numeric typed-data storage; implements FieldStorage
// ---------------------------------------------------------------------------

class _FieldStorage<N extends num, L extends List<N>>
    implements FieldStorage, _AbstractStorage {
  L list;
  int capacity;
  final L Function(int) _create;
  final int _byteOffset;
  final int _elementSize;
  final void Function(ByteData bd, int offset, N v) _writeBytesImpl;
  final N Function(ByteData bd, int offset) _readBytesImpl;
  final N? _initialValue;

  _FieldStorage(
    int initialCapacity,
    this._create,
    this._byteOffset,
    this._elementSize,
    this._writeBytesImpl,
    this._readBytesImpl, {
    N? initialValue,
  }) : _initialValue = initialValue,
       list = _create(initialCapacity),
       capacity = initialCapacity;

  @override
  int get byteOffset => _byteOffset;

  @override
  int get elementSize => _elementSize;

  @override
  void writeAt(int slot, Object? value) => list[slot] = value as N;

  @override
  Object? readFrom(int slot) => list[slot];

  @override
  void writeBytes(ByteData bd, int offset, Object? value) =>
      _writeBytesImpl(bd, offset, value as N);

  @override
  Object? readBytes(ByteData bd, int offset) => _readBytesImpl(bd, offset);

  @override
  void initSlot(int slot) {
    final v = _initialValue;
    if (v != null) list[slot] = v;
  }

  @override
  void initBytes(ByteData bd) {
    final v = _initialValue;
    if (v != null) _writeBytesImpl(bd, _byteOffset, v);
  }

  @override
  void grow(int newCapacity) {
    final next = _create(newCapacity);
    next.setRange(0, capacity, list);
    list = next;
    capacity = newCapacity;
  }

  @override
  void compact(Map<int, int> remap) {
    final next = _create(capacity);
    for (final e in remap.entries) {
      next[e.value] = list[e.key];
    }
    list = next;
  }
}

// ---------------------------------------------------------------------------
// _PackedBitsStorage — packs multiple sub-byte fields into shared Uint8 bytes
// ---------------------------------------------------------------------------

class _PackedBitsStorage implements _AbstractStorage {
  int _totalBits = 0;
  int _bytesPerSlot = 0;
  Uint8List bytes = Uint8List(0);
  int capacity;

  _PackedBitsStorage(this.capacity);

  // Called once per sub-byte field during describe().
  // Returns the bit-start offset for that field.
  int reserveBits(int width) {
    final rem = _totalBits & 7;
    if (rem != 0 && rem + width > 8) _totalBits += 8 - rem;
    final start = _totalBits;
    _totalBits += width;
    final needed = (_totalBits + 7) >> 3;
    if (needed > _bytesPerSlot) {
      bytes = Uint8List(capacity * needed);
      _bytesPerSlot = needed;
    }
    return start;
  }

  @override
  void grow(int newCapacity) {
    if (_bytesPerSlot == 0) {
      capacity = newCapacity;
      return;
    }
    final next = Uint8List(newCapacity * _bytesPerSlot);
    next.setRange(0, capacity * _bytesPerSlot, bytes);
    bytes = next;
    capacity = newCapacity;
  }

  @override
  void compact(Map<int, int> remap) {
    if (_bytesPerSlot == 0) return;
    final next = Uint8List(capacity * _bytesPerSlot);
    for (final e in remap.entries) {
      next.setRange(
        e.value * _bytesPerSlot,
        (e.value + 1) * _bytesPerSlot,
        bytes,
        e.key * _bytesPerSlot,
      );
    }
    bytes = next;
  }
}

// ---------------------------------------------------------------------------
// _PackedIntStorage / _PackedBoolStorage — FieldStorage wrappers for packed fields
// ---------------------------------------------------------------------------

class _PackedIntStorage implements FieldStorage {
  final _PackedBitsStorage _s;
  final int _byteOff;
  final int _bitOff;
  final int _mask;
  final int _signBit;
  final int _byteOffset; // absolute offset within type's capture layout
  final int? _initialValue;

  _PackedIntStorage(
    this._s,
    this._byteOff,
    this._bitOff,
    this._mask,
    this._signBit,
    this._byteOffset, {
    int? initialValue,
  }) : _initialValue = initialValue;

  @override
  int get byteOffset => _byteOffset;

  @override
  int get elementSize => 1;

  @override
  void writeAt(int slot, Object? value) {
    final v = value as int;
    final idx = slot * _s._bytesPerSlot + _byteOff;
    _s.bytes[idx] =
        (_s.bytes[idx] & ~(_mask << _bitOff)) | ((v & _mask) << _bitOff);
  }

  @override
  Object? readFrom(int slot) {
    final v =
        (_s.bytes[slot * _s._bytesPerSlot + _byteOff] >>> _bitOff) & _mask;
    return (_signBit != 0 && v >= _signBit) ? v - (_mask + 1) : v;
  }

  @override
  void writeBytes(ByteData bd, int offset, Object? value) {
    final v = value as int;
    final cur = bd.getUint8(offset);
    bd.setUint8(offset, (cur & ~(_mask << _bitOff)) | ((v & _mask) << _bitOff));
  }

  @override
  Object? readBytes(ByteData bd, int offset) {
    final v = (bd.getUint8(offset) >>> _bitOff) & _mask;
    return (_signBit != 0 && v >= _signBit) ? v - (_mask + 1) : v;
  }

  @override
  void initSlot(int slot) {
    final v = _initialValue;
    if (v == null) return;
    final idx = slot * _s._bytesPerSlot + _byteOff;
    _s.bytes[idx] =
        (_s.bytes[idx] & ~(_mask << _bitOff)) | ((v & _mask) << _bitOff);
  }

  @override
  void initBytes(ByteData bd) {
    final v = _initialValue;
    if (v == null) return;
    final cur = bd.getUint8(_byteOffset);
    bd.setUint8(
      _byteOffset,
      (cur & ~(_mask << _bitOff)) | ((v & _mask) << _bitOff),
    );
  }
}

class _PackedBoolStorage implements FieldStorage {
  final _PackedBitsStorage _s;
  final int _byteOff;
  final int _bitOff;
  final int _byteOffset;
  final bool? _initialValue;

  _PackedBoolStorage(
    this._s,
    this._byteOff,
    this._bitOff,
    this._byteOffset, {
    bool? initialValue,
  }) : _initialValue = initialValue;

  @override
  int get byteOffset => _byteOffset;

  @override
  int get elementSize => 1;

  @override
  void writeAt(int slot, Object? value) {
    final idx = slot * _s._bytesPerSlot + _byteOff;
    if (value as bool) {
      _s.bytes[idx] |= 1 << _bitOff;
    } else {
      _s.bytes[idx] &= ~(1 << _bitOff);
    }
  }

  @override
  Object? readFrom(int slot) =>
      (_s.bytes[slot * _s._bytesPerSlot + _byteOff] >>> _bitOff) & 1 != 0;

  @override
  void writeBytes(ByteData bd, int offset, Object? value) {
    final cur = bd.getUint8(offset);
    bd.setUint8(
      offset,
      (value as bool) ? cur | (1 << _bitOff) : cur & ~(1 << _bitOff),
    );
  }

  @override
  Object? readBytes(ByteData bd, int offset) =>
      (bd.getUint8(offset) >>> _bitOff) & 1 != 0;

  @override
  void initSlot(int slot) {
    if (_initialValue != true) return;
    _s.bytes[slot * _s._bytesPerSlot + _byteOff] |= 1 << _bitOff;
  }

  @override
  void initBytes(ByteData bd) {
    if (_initialValue != true) return;
    bd.setUint8(_byteOffset, bd.getUint8(_byteOffset) | (1 << _bitOff));
  }
}

// ---------------------------------------------------------------------------
// _NullableInterleavedStorage — double-stride int array (tag at s*2, value at s*2+1)
// ---------------------------------------------------------------------------

class _NullableInterleavedStorage<N extends num, L extends List<N>>
    implements FieldStorage, _AbstractStorage {
  L list; // length = capacity * 2; list[s*2]=tag (0=null), list[s*2+1]=value
  int capacity;
  final L Function(int) _create;
  final int _byteOffset;
  final int _elementSize; // 2 × valueSize
  final int _valueSize;
  final N _zeroTag;
  final N _oneTag;
  final void Function(ByteData bd, int offset, N v) _writeBytesImpl;
  final N Function(ByteData bd, int offset) _readBytesImpl;

  final N? _initialValue;

  _NullableInterleavedStorage(
    int initialCapacity,
    this._create,
    this._byteOffset,
    this._elementSize,
    this._valueSize,
    this._zeroTag,
    this._oneTag,
    this._writeBytesImpl,
    this._readBytesImpl, {
    N? initialValue,
  }) : _initialValue = initialValue,
       list = _create(initialCapacity * 2),
       capacity = initialCapacity;

  @override
  int get byteOffset => _byteOffset;
  @override
  int get elementSize => _elementSize;

  @override
  void writeAt(int slot, Object? value) {
    if (value == null) {
      list[slot * 2] = _zeroTag;
    } else {
      list[slot * 2] = _oneTag;
      list[slot * 2 + 1] = value as N;
    }
  }

  @override
  Object? readFrom(int slot) =>
      list[slot * 2] == _zeroTag ? null : list[slot * 2 + 1];

  @override
  void writeBytes(ByteData bd, int offset, Object? value) {
    if (value == null) {
      _writeBytesImpl(bd, offset, _zeroTag);
    } else {
      _writeBytesImpl(bd, offset, _oneTag);
      _writeBytesImpl(bd, offset + _valueSize, value as N);
    }
  }

  @override
  Object? readBytes(ByteData bd, int offset) {
    final tag = _readBytesImpl(bd, offset);
    return tag == _zeroTag ? null : _readBytesImpl(bd, offset + _valueSize);
  }

  @override
  void initSlot(int slot) {
    final v = _initialValue;
    if (v == null) return;
    list[slot * 2] = _oneTag;
    list[slot * 2 + 1] = v;
  }

  @override
  void initBytes(ByteData bd) {
    final v = _initialValue;
    if (v == null) return;
    _writeBytesImpl(bd, _byteOffset, _oneTag);
    _writeBytesImpl(bd, _byteOffset + _valueSize, v);
  }

  @override
  void grow(int newCapacity) {
    final next = _create(newCapacity * 2);
    next.setRange(0, capacity * 2, list);
    list = next;
    capacity = newCapacity;
  }

  @override
  void compact(Map<int, int> remap) {
    final next = _create(capacity * 2);
    for (final e in remap.entries) {
      next[e.value * 2] = list[e.key * 2];
      next[e.value * 2 + 1] = list[e.key * 2 + 1];
    }
    list = next;
  }
}

// ---------------------------------------------------------------------------
// _StolenBitStorage — sentinel encodes null; no extra storage
// ---------------------------------------------------------------------------

class _StolenBitStorage<N extends num, L extends List<N>>
    implements FieldStorage, _AbstractStorage {
  L list;
  int capacity;
  final L Function(int) _create;
  final int _byteOffset;
  final int _elementSize;
  final N _sentinel; // null is encoded as this value
  final void Function(ByteData bd, int offset, N v) _writeBytesImpl;
  final N Function(ByteData bd, int offset) _readBytesImpl;

  final N? _initialValue;

  _StolenBitStorage(
    int initialCapacity,
    this._create,
    this._byteOffset,
    this._elementSize,
    this._sentinel,
    this._writeBytesImpl,
    this._readBytesImpl, {
    N? initialValue,
  }) : _initialValue = initialValue,
       list = _create(initialCapacity),
       capacity = initialCapacity;

  @override
  int get byteOffset => _byteOffset;
  @override
  int get elementSize => _elementSize;

  @override
  void writeAt(int slot, Object? value) =>
      list[slot] = value == null ? _sentinel : value as N;

  @override
  Object? readFrom(int slot) => list[slot] == _sentinel ? null : list[slot];

  @override
  void writeBytes(ByteData bd, int offset, Object? value) =>
      _writeBytesImpl(bd, offset, value == null ? _sentinel : value as N);

  @override
  Object? readBytes(ByteData bd, int offset) {
    final v = _readBytesImpl(bd, offset);
    return v == _sentinel ? null : v;
  }

  @override
  void initSlot(int slot) {
    final v = _initialValue;
    list[slot] = v ?? _sentinel;
  }

  @override
  void initBytes(ByteData bd) {
    final v = _initialValue;
    _writeBytesImpl(bd, _byteOffset, v ?? _sentinel);
  }

  @override
  void grow(int newCapacity) {
    final next = _create(newCapacity);
    next.setRange(0, capacity, list);
    list = next;
    capacity = newCapacity;
  }

  @override
  void compact(Map<int, int> remap) {
    final next = _create(capacity);
    for (final e in remap.entries) {
      next[e.value] = list[e.key];
    }
    list = next;
  }
}

// ---------------------------------------------------------------------------
// _NullTagStorage — bit-packed null flags; one bit per entity per tagged field
// ---------------------------------------------------------------------------

class _NullTagStorage implements _AbstractStorage {
  int _totalBits = 0;
  int _bytesPerSlot = 0;
  Uint8List bytes = Uint8List(0);
  int capacity;

  _NullTagStorage(this.capacity);

  int reserveTag() {
    final bitIndex = _totalBits++;
    final needed = (_totalBits + 7) >> 3;
    if (needed > _bytesPerSlot) {
      bytes = Uint8List(capacity * needed);
      _bytesPerSlot = needed;
    }
    return bitIndex;
  }

  void setTagAt(int slot, int tagBitIndex, bool present) {
    if (_bytesPerSlot == 0) return;
    final idx = slot * _bytesPerSlot + (tagBitIndex >> 3);
    final bit = 1 << (tagBitIndex & 7);
    if (present) {
      bytes[idx] |= bit;
    } else {
      bytes[idx] &= ~bit;
    }
  }

  bool getTagAt(int slot, int tagBitIndex) {
    if (_bytesPerSlot == 0) return false;
    final idx = slot * _bytesPerSlot + (tagBitIndex >> 3);
    return (bytes[idx] >>> (tagBitIndex & 7)) & 1 != 0;
  }

  @override
  void grow(int newCapacity) {
    if (_bytesPerSlot == 0) {
      capacity = newCapacity;
      return;
    }
    final next = Uint8List(newCapacity * _bytesPerSlot);
    next.setRange(0, capacity * _bytesPerSlot, bytes);
    bytes = next;
    capacity = newCapacity;
  }

  @override
  void compact(Map<int, int> remap) {
    if (_bytesPerSlot == 0) return;
    final next = Uint8List(capacity * _bytesPerSlot);
    for (final e in remap.entries) {
      next.setRange(
        e.value * _bytesPerSlot,
        (e.value + 1) * _bytesPerSlot,
        bytes,
        e.key * _bytesPerSlot,
      );
    }
    bytes = next;
  }
}

// ---------------------------------------------------------------------------
// _TaggedStorage — value in typed list + null flag in _NullTagStorage
// Capture layout: [value: N bytes][flag: 1 byte]
// ---------------------------------------------------------------------------

class _TaggedStorage<N extends num, L extends List<N>>
    implements FieldStorage, _AbstractStorage {
  L list;
  int capacity;
  final L Function(int) _create;
  final int _byteOffset;
  final int _elementSize; // valueSize + 1
  final int _valueSize;
  final _NullTagStorage _nullTags;
  final int _tagBitIndex;
  final void Function(ByteData bd, int offset, N v) _writeBytesImpl;
  final N Function(ByteData bd, int offset) _readBytesImpl;

  final Object? _initialValue;

  _TaggedStorage(
    int initialCapacity,
    this._create,
    this._byteOffset,
    this._elementSize,
    this._valueSize,
    this._nullTags,
    this._tagBitIndex,
    this._writeBytesImpl,
    this._readBytesImpl, {
    Object? initialValue,
  }) : _initialValue = initialValue,
       list = _create(initialCapacity),
       capacity = initialCapacity;

  @override
  int get byteOffset => _byteOffset;
  @override
  int get elementSize => _elementSize;

  @override
  void writeAt(int slot, Object? value) {
    _nullTags.setTagAt(slot, _tagBitIndex, value != null);
    if (value != null) list[slot] = value as N;
  }

  @override
  Object? readFrom(int slot) =>
      _nullTags.getTagAt(slot, _tagBitIndex) ? list[slot] : null;

  @override
  void writeBytes(ByteData bd, int offset, Object? value) {
    if (value == null) {
      bd.setUint8(offset + _valueSize, 0);
    } else {
      _writeBytesImpl(bd, offset, value as N);
      bd.setUint8(offset + _valueSize, 1);
    }
  }

  @override
  Object? readBytes(ByteData bd, int offset) {
    final flag = bd.getUint8(offset + _valueSize);
    return flag == 0 ? null : _readBytesImpl(bd, offset);
  }

  @override
  void initSlot(int slot) {
    final v = _initialValue;
    if (v == null) return;
    _nullTags.setTagAt(slot, _tagBitIndex, true);
    list[slot] = v as N;
  }

  @override
  void initBytes(ByteData bd) {
    final v = _initialValue;
    if (v == null) return;
    _writeBytesImpl(bd, _byteOffset, v as N);
    bd.setUint8(_byteOffset + _valueSize, 1);
  }

  @override
  void grow(int newCapacity) {
    final next = _create(newCapacity);
    next.setRange(0, capacity, list);
    list = next;
    capacity = newCapacity;
  }

  @override
  void compact(Map<int, int> remap) {
    final next = _create(capacity);
    for (final e in remap.entries) {
      next[e.value] = list[e.key];
    }
    list = next;
  }
}

// ---------------------------------------------------------------------------
// _BoolTaggedStorage — nullable bool with _NullTagStorage flag + Uint8List value
// ---------------------------------------------------------------------------

class _BoolTaggedStorage implements FieldStorage, _AbstractStorage {
  Uint8List list; // 0=false, 1=true (only read when tag is present)
  int capacity;
  final int _byteOffset;
  final _NullTagStorage _nullTags;
  final int _tagBitIndex;

  final bool? _initialValue;

  _BoolTaggedStorage(
    int initialCapacity,
    this._byteOffset,
    this._nullTags,
    this._tagBitIndex, {
    bool? initialValue,
  }) : _initialValue = initialValue,
       list = Uint8List(initialCapacity),
       capacity = initialCapacity;

  @override
  int get byteOffset => _byteOffset;
  @override
  int get elementSize => 2; // 1 value byte + 1 flag byte

  @override
  void writeAt(int slot, Object? value) {
    _nullTags.setTagAt(slot, _tagBitIndex, value != null);
    if (value != null) list[slot] = (value as bool) ? 1 : 0;
  }

  @override
  Object? readFrom(int slot) {
    if (!_nullTags.getTagAt(slot, _tagBitIndex)) return null;
    return list[slot] != 0;
  }

  @override
  void writeBytes(ByteData bd, int offset, Object? value) {
    if (value == null) {
      bd.setUint8(offset + 1, 0);
    } else {
      bd.setUint8(offset, (value as bool) ? 1 : 0);
      bd.setUint8(offset + 1, 1);
    }
  }

  @override
  Object? readBytes(ByteData bd, int offset) {
    if (bd.getUint8(offset + 1) == 0) return null;
    return bd.getUint8(offset) != 0;
  }

  @override
  void initSlot(int slot) {
    final v = _initialValue;
    if (v == null) return;
    _nullTags.setTagAt(slot, _tagBitIndex, true);
    list[slot] = v ? 1 : 0;
  }

  @override
  void initBytes(ByteData bd) {
    final v = _initialValue;
    if (v == null) return;
    bd.setUint8(_byteOffset, v ? 1 : 0);
    bd.setUint8(_byteOffset + 1, 1);
  }

  @override
  void grow(int newCapacity) {
    final next = Uint8List(newCapacity);
    next.setRange(0, capacity, list);
    list = next;
    capacity = newCapacity;
  }

  @override
  void compact(Map<int, int> remap) {
    final next = Uint8List(capacity);
    for (final e in remap.entries) {
      next[e.value] = list[e.key];
    }
    list = next;
  }
}

// ---------------------------------------------------------------------------
// _NullablePackedStorage — nullable int in packed bits (value+tag share same byte)
// ---------------------------------------------------------------------------

class _NullablePackedStorage implements FieldStorage {
  final _PackedBitsStorage _s;
  final int _byteOff;
  final int _valueBitOff;
  final int _valueMask;
  final int _valueSignBit;
  final int _tagBitOff;
  final int _tagMask;
  final int _byteOffset; // absolute capture byte offset

  final int? _initialValue;

  _NullablePackedStorage(
    this._s,
    this._byteOff,
    this._valueBitOff,
    this._valueMask,
    this._valueSignBit,
    this._tagBitOff,
    this._tagMask,
    this._byteOffset, {
    int? initialValue,
  }) : _initialValue = initialValue;

  @override
  int get byteOffset => _byteOffset;
  @override
  int get elementSize => 1;

  @override
  void writeAt(int slot, Object? value) {
    final idx = slot * _s._bytesPerSlot + _byteOff;
    if (value == null) {
      _s.bytes[idx] &= ~(_tagMask << _tagBitOff);
    } else {
      final v = value as int;
      _s.bytes[idx] =
          (_s.bytes[idx] &
              ~((_valueMask << _valueBitOff) | (_tagMask << _tagBitOff))) |
          ((v & _valueMask) << _valueBitOff) |
          (1 << _tagBitOff);
    }
  }

  @override
  Object? readFrom(int slot) {
    final b = _s.bytes[slot * _s._bytesPerSlot + _byteOff];
    final tag = (b >>> _tagBitOff) & _tagMask;
    if (tag == 0) return null;
    final v = (b >>> _valueBitOff) & _valueMask;
    return (_valueSignBit != 0 && v >= _valueSignBit)
        ? v - (_valueMask + 1)
        : v;
  }

  @override
  void writeBytes(ByteData bd, int offset, Object? value) {
    final cur = bd.getUint8(offset);
    if (value == null) {
      bd.setUint8(offset, cur & ~(_tagMask << _tagBitOff));
    } else {
      final v = value as int;
      bd.setUint8(
        offset,
        (cur & ~((_valueMask << _valueBitOff) | (_tagMask << _tagBitOff))) |
            ((v & _valueMask) << _valueBitOff) |
            (1 << _tagBitOff),
      );
    }
  }

  @override
  Object? readBytes(ByteData bd, int offset) {
    final b = bd.getUint8(offset);
    final tag = (b >>> _tagBitOff) & _tagMask;
    if (tag == 0) return null;
    final v = (b >>> _valueBitOff) & _valueMask;
    return (_valueSignBit != 0 && v >= _valueSignBit)
        ? v - (_valueMask + 1)
        : v;
  }

  @override
  void initSlot(int slot) {
    final v = _initialValue;
    if (v == null) return;
    final idx = slot * _s._bytesPerSlot + _byteOff;
    _s.bytes[idx] =
        (_s.bytes[idx] &
            ~((_valueMask << _valueBitOff) | (_tagMask << _tagBitOff))) |
        ((v & _valueMask) << _valueBitOff) |
        (1 << _tagBitOff);
  }

  @override
  void initBytes(ByteData bd) {
    final v = _initialValue;
    if (v == null) return;
    final cur = bd.getUint8(_byteOffset);
    bd.setUint8(
      _byteOffset,
      (cur & ~((_valueMask << _valueBitOff) | (_tagMask << _tagBitOff))) |
          ((v & _valueMask) << _valueBitOff) |
          (1 << _tagBitOff),
    );
  }
}

// ---------------------------------------------------------------------------
// _NullablePackedBoolStorage — nullable bool in packed bits (bool null tri-state)
// ---------------------------------------------------------------------------

class _NullablePackedBoolStorage implements FieldStorage {
  final _PackedBitsStorage _s;
  final int _byteOff;
  final int _valueBitOff; // bit 0=false, bit 1=true
  final int _tagBitOff; // 0=null, 1=present
  final int _byteOffset;

  final bool? _initialValue;

  _NullablePackedBoolStorage(
    this._s,
    this._byteOff,
    this._valueBitOff,
    this._tagBitOff,
    this._byteOffset, {
    bool? initialValue,
  }) : _initialValue = initialValue;

  @override
  int get byteOffset => _byteOffset;
  @override
  int get elementSize => 1;

  @override
  void writeAt(int slot, Object? value) {
    final idx = slot * _s._bytesPerSlot + _byteOff;
    if (value == null) {
      _s.bytes[idx] &= ~(1 << _tagBitOff);
    } else {
      final b = value as bool;
      _s.bytes[idx] =
          (_s.bytes[idx] & ~((1 << _valueBitOff) | (1 << _tagBitOff))) |
          ((b ? 1 : 0) << _valueBitOff) |
          (1 << _tagBitOff);
    }
  }

  @override
  Object? readFrom(int slot) {
    final b = _s.bytes[slot * _s._bytesPerSlot + _byteOff];
    if ((b >>> _tagBitOff) & 1 == 0) return null;
    return (b >>> _valueBitOff) & 1 != 0;
  }

  @override
  void writeBytes(ByteData bd, int offset, Object? value) {
    final cur = bd.getUint8(offset);
    if (value == null) {
      bd.setUint8(offset, cur & ~(1 << _tagBitOff));
    } else {
      final b = value as bool;
      bd.setUint8(
        offset,
        (cur & ~((1 << _valueBitOff) | (1 << _tagBitOff))) |
            ((b ? 1 : 0) << _valueBitOff) |
            (1 << _tagBitOff),
      );
    }
  }

  @override
  Object? readBytes(ByteData bd, int offset) {
    final b = bd.getUint8(offset);
    if ((b >>> _tagBitOff) & 1 == 0) return null;
    return (b >>> _valueBitOff) & 1 != 0;
  }

  @override
  void initSlot(int slot) {
    final v = _initialValue;
    if (v == null) return;
    final idx = slot * _s._bytesPerSlot + _byteOff;
    _s.bytes[idx] =
        (_s.bytes[idx] & ~((1 << _valueBitOff) | (1 << _tagBitOff))) |
        ((v ? 1 : 0) << _valueBitOff) |
        (1 << _tagBitOff);
  }

  @override
  void initBytes(ByteData bd) {
    final v = _initialValue;
    if (v == null) return;
    final cur = bd.getUint8(_byteOffset);
    bd.setUint8(
      _byteOffset,
      (cur & ~((1 << _valueBitOff) | (1 << _tagBitOff))) |
          ((v ? 1 : 0) << _valueBitOff) |
          (1 << _tagBitOff),
    );
  }
}

// ---------------------------------------------------------------------------
// _PackedIntField / _PackedBoolField — thin Field wrappers dispatching to cursor
// ---------------------------------------------------------------------------

class _PackedIntField implements Field<int> {
  final _PackedIntStorage _s;

  _PackedIntField(this._s);

  @pragma('vm:prefer-inline')
  @override
  int get(QueryResult c) => c.getField(_s) as int;

  @pragma('vm:prefer-inline')
  @override
  void set(QueryResult c, int v) => c.setField(_s, v);
  @pragma('vm:prefer-inline')
  @override
  int getSlot(int slot) => _s.readFrom(slot) as int;
  @pragma('vm:prefer-inline')
  @override
  void setSlot(int slot, int v) => _s.writeAt(slot, v);
}

class _PackedBoolField implements Field<bool> {
  final _PackedBoolStorage _s;

  _PackedBoolField(this._s);

  @pragma('vm:prefer-inline')
  @override
  bool get(QueryResult c) => c.getField(_s) as bool;

  @pragma('vm:prefer-inline')
  @override
  void set(QueryResult c, bool v) => c.setField(_s, v);
  @pragma('vm:prefer-inline')
  @override
  bool getSlot(int slot) => _s.readFrom(slot) as bool;
  @pragma('vm:prefer-inline')
  @override
  void setSlot(int slot, bool v) => _s.writeAt(slot, v);
}

// ---------------------------------------------------------------------------
// Custom-field storage
// ---------------------------------------------------------------------------

class _ByteDataStorage implements _AbstractStorage {
  Uint8List bytes;
  final int stride;
  int capacity;

  _ByteDataStorage(int initialCapacity, this.stride)
    : bytes = Uint8List(initialCapacity * stride),
      capacity = initialCapacity;

  @override
  void grow(int newCapacity) {
    final next = Uint8List(newCapacity * stride);
    next.setRange(0, capacity * stride, bytes);
    bytes = next;
    capacity = newCapacity;
  }

  @override
  void compact(Map<int, int> remap) {
    final next = Uint8List(capacity * stride);
    for (final e in remap.entries) {
      next.setRange(
        e.value * stride,
        (e.value + 1) * stride,
        bytes,
        e.key * stride,
      );
    }
    bytes = next;
  }

  ByteData viewAt(int slot) =>
      ByteData.sublistView(bytes, slot * stride, (slot + 1) * stride);
}

// ---------------------------------------------------------------------------
// _HeapFieldStorage — per-slot Object? refs outside the typed-data pool.
//
// Capture layout: 4 bytes (Int32, host endian) = index into the descriptor's
// _heapMap.  Real storage: List<Object?> _list, one entry per slot.
// ---------------------------------------------------------------------------

class _HeapFieldStorage<T> extends _AbstractStorage implements FieldStorage {
  final T _initialValue;
  final int _byteOffset;
  final List<Object?>
  _heapMap; // shared with _ComponentDataDescriptor; cleared after flush

  List<Object?> _list;
  int _capacity;

  _HeapFieldStorage(
    int initialCapacity,
    this._initialValue,
    this._byteOffset,
    this._heapMap,
  ) : _list = List<Object?>.filled(initialCapacity, _initialValue),
      _capacity = initialCapacity;

  @override
  int get byteOffset => _byteOffset;
  @override
  int get elementSize => 4;

  @override
  Object? readFrom(int slot) => _list[slot];
  @override
  void writeAt(int slot, Object? value) => _list[slot] = value;
  @override
  void initSlot(int slot) => _list[slot] = _initialValue;

  @override
  void writeBytes(ByteData bd, int offset, Object? value) {
    _heapMap.add(value);
    bd.setInt32(offset, _heapMap.length - 1, Endian.host);
  }

  @override
  Object? readBytes(ByteData bd, int offset) =>
      _heapMap[bd.getInt32(offset, Endian.host)];

  @override
  void initBytes(ByteData bd) {
    _heapMap.add(_initialValue);
    bd.setInt32(_byteOffset, _heapMap.length - 1, Endian.host);
  }

  @override
  void grow(int newCapacity) {
    final next = List<Object?>.filled(newCapacity, _initialValue);
    for (var i = 0; i < _capacity; i++) {
      next[i] = _list[i];
    }
    _list = next;
    _capacity = newCapacity;
  }

  @override
  void compact(Map<int, int> remap) {
    final next = List<Object?>.filled(_capacity, _initialValue);
    for (final e in remap.entries) {
      next[e.value] = _list[e.key];
    }
    _list = next;
  }

  T getSlot(int slot) => _list[slot] as T;
  void setSlot(int slot, T value) => _list[slot] = value;
}

class _HeapField<T> implements Field<T> {
  final _HeapFieldStorage<T> _storage;
  _HeapField(this._storage);

  @override
  T get(QueryResult r) => r.getField(_storage) as T;
  @override
  void set(QueryResult r, T value) => r.setField(_storage, value);
  @override
  T getSlot(int slot) => _storage.getSlot(slot);
  @override
  void setSlot(int slot, T value) => _storage.setSlot(slot, value);
}

class _CustomFieldStorage<T> implements FieldStorage {
  final FieldParser<T> _parser;
  final _ByteDataStorage _storage;
  final int _byteOffset;
  final T _initialValue;

  _CustomFieldStorage(
    this._parser,
    this._storage,
    this._byteOffset,
    this._initialValue,
  );

  @override
  int get byteOffset => _byteOffset;

  @override
  int get elementSize => _storage.stride;

  @override
  void writeAt(int slot, Object? value) =>
      _parser.write(value as T, _ByteDataWriter(_storage.viewAt(slot)));

  @override
  Object? readFrom(int slot) =>
      _parser.read(_ByteDataReader(_storage.viewAt(slot)));

  @override
  void writeBytes(ByteData bd, int offset, Object? value) {
    final view = ByteData.view(
      bd.buffer,
      bd.offsetInBytes + offset,
      _storage.stride,
    );
    _parser.write(value as T, _ByteDataWriter(view));
  }

  @override
  Object? readBytes(ByteData bd, int offset) {
    final view = ByteData.view(
      bd.buffer,
      bd.offsetInBytes + offset,
      _storage.stride,
    );
    return _parser.read(_ByteDataReader(view));
  }

  @override
  void initSlot(int slot) {
    _parser.write(_initialValue, _ByteDataWriter(_storage.viewAt(slot)));
  }

  @override
  void initBytes(ByteData bd) {
    final view = ByteData.view(
      bd.buffer,
      bd.offsetInBytes + _byteOffset,
      _storage.stride,
    );
    _parser.write(_initialValue, _ByteDataWriter(view));
  }
}

// ---------------------------------------------------------------------------
// _StrideCalculator — measures byte stride for custom FieldParser layouts
// ---------------------------------------------------------------------------

class _StrideCalculator implements FieldDescriptor {
  int stride = 0;
  int _packBits = 0;

  void _flushPack() {
    if (_packBits > 0) {
      stride += 1;
      _packBits = 0;
    }
  }

  void _addSubBit(int width) {
    if (_packBits > 0 && _packBits + width > 8) {
      stride += 1;
      _packBits = 0;
    }
    _packBits += width;
    if (_packBits == 8) {
      stride += 1;
      _packBits = 0;
    }
  }

  @override
  void addInt8() {
    _flushPack();
    stride += 1;
  }

  @override
  void addInt16() {
    _flushPack();
    stride += 2;
  }

  @override
  void addInt32() {
    _flushPack();
    stride += 4;
  }

  @override
  void addInt64() {
    _flushPack();
    stride += 8;
  }

  @override
  void addUint8() {
    _flushPack();
    stride += 1;
  }

  @override
  void addUint16() {
    _flushPack();
    stride += 2;
  }

  @override
  void addUint32() {
    _flushPack();
    stride += 4;
  }

  @override
  void addUint64() {
    _flushPack();
    stride += 8;
  }

  @override
  void addFloat32() {
    _flushPack();
    stride += 4;
  }

  @override
  void addFloat64() {
    _flushPack();
    stride += 8;
  }

  @override
  void addField<T>(FieldParser<T> parser) {
    _flushPack();
    final nested = _StrideCalculator();
    parser.describe(nested);
    nested._flushPack();
    stride += nested.stride;
  }

  @override
  void addBit() => _addSubBit(1);
  @override
  void addBool() => _addSubBit(1);
  @override
  void addInt2() => _addSubBit(2);
  @override
  void addUint2() => _addSubBit(2);
  @override
  void addInt4() => _addSubBit(4);
  @override
  void addUint4() => _addSubBit(4);

  // Nullable double-stride word types (tag N bytes + value N bytes = 2N)
  @override
  void addInt8Nullable() {
    _flushPack();
    stride += 2;
  }

  @override
  void addInt16Nullable() {
    _flushPack();
    stride += 4;
  }

  @override
  void addInt32Nullable() {
    _flushPack();
    stride += 8;
  }

  @override
  void addInt64Nullable() {
    _flushPack();
    stride += 16;
  }

  @override
  void addUint8Nullable() {
    _flushPack();
    stride += 2;
  }

  @override
  void addUint16Nullable() {
    _flushPack();
    stride += 4;
  }

  @override
  void addUint32Nullable() {
    _flushPack();
    stride += 8;
  }

  @override
  void addUint64Nullable() {
    _flushPack();
    stride += 16;
  }

  // Stolen-bit nullable (same bytes as underlying type)
  @override
  void addInt7Nullable() {
    _flushPack();
    stride += 1;
  }

  @override
  void addInt15Nullable() {
    _flushPack();
    stride += 2;
  }

  @override
  void addInt31Nullable() {
    _flushPack();
    stride += 4;
  }

  @override
  void addInt63Nullable() {
    _flushPack();
    stride += 8;
  }

  @override
  void addUint7Nullable() {
    _flushPack();
    stride += 1;
  }

  @override
  void addUint15Nullable() {
    _flushPack();
    stride += 2;
  }

  @override
  void addUint31Nullable() {
    _flushPack();
    stride += 4;
  }

  @override
  void addUint63Nullable() {
    _flushPack();
    stride += 8;
  }

  // Tagged nullable (value N bytes + 1 flag byte)
  @override
  void addInt8Tagged() {
    _flushPack();
    stride += 2;
  }

  @override
  void addInt16Tagged() {
    _flushPack();
    stride += 3;
  }

  @override
  void addInt32Tagged() {
    _flushPack();
    stride += 5;
  }

  @override
  void addInt64Tagged() {
    _flushPack();
    stride += 9;
  }

  @override
  void addUint8Tagged() {
    _flushPack();
    stride += 2;
  }

  @override
  void addUint16Tagged() {
    _flushPack();
    stride += 3;
  }

  @override
  void addUint32Tagged() {
    _flushPack();
    stride += 5;
  }

  @override
  void addUint64Tagged() {
    _flushPack();
    stride += 9;
  }

  @override
  void addFloat32Tagged() {
    _flushPack();
    stride += 5;
  }

  @override
  void addFloat64Tagged() {
    _flushPack();
    stride += 9;
  }

  // Packed nullable (value bits + tag bits in same byte, total = 2×width bits)
  @override
  void addBoolNullable() => _addSubBit(2);
  @override
  void addBitNullable() => _addSubBit(2);
  @override
  void addInt2Nullable() => _addSubBit(4);
  @override
  void addUint2Nullable() => _addSubBit(4);
  @override
  void addInt4Nullable() => _addSubBit(8);
  @override
  void addUint4Nullable() => _addSubBit(8);

  @override
  void addNullableField<T>(FieldParser<T> parser) {
    _flushPack();
    final nested = _StrideCalculator();
    parser.describe(nested);
    nested._flushPack();
    stride += 1 + nested.stride; // 1 tag byte + value bytes
  }

  @override
  void addInt8ListView(int n) {
    _flushPack();
    stride += n;
  }

  @override
  void addInt8ListViewNullable(int n) {
    _flushPack();
    stride += 1 + n;
  }

  @override
  void addInt16ListView(int n) {
    _flushPack();
    stride += n * 2;
  }

  @override
  void addInt16ListViewNullable(int n) {
    _flushPack();
    stride += 1 + n * 2;
  }

  @override
  void addInt32ListView(int n) {
    _flushPack();
    stride += n * 4;
  }

  @override
  void addInt32ListViewNullable(int n) {
    _flushPack();
    stride += 1 + n * 4;
  }

  @override
  void addInt64ListView(int n) {
    _flushPack();
    stride += n * 8;
  }

  @override
  void addInt64ListViewNullable(int n) {
    _flushPack();
    stride += 1 + n * 8;
  }

  @override
  void addUint8ListView(int n) {
    _flushPack();
    stride += n;
  }

  @override
  void addUint8ListViewNullable(int n) {
    _flushPack();
    stride += 1 + n;
  }

  @override
  void addUint16ListView(int n) {
    _flushPack();
    stride += n * 2;
  }

  @override
  void addUint16ListViewNullable(int n) {
    _flushPack();
    stride += 1 + n * 2;
  }

  @override
  void addUint32ListView(int n) {
    _flushPack();
    stride += n * 4;
  }

  @override
  void addUint32ListViewNullable(int n) {
    _flushPack();
    stride += 1 + n * 4;
  }

  @override
  void addUint64ListView(int n) {
    _flushPack();
    stride += n * 8;
  }

  @override
  void addUint64ListViewNullable(int n) {
    _flushPack();
    stride += 1 + n * 8;
  }

  @override
  void addFloat32ListView(int n) {
    _flushPack();
    stride += n * 4;
  }

  @override
  void addFloat32ListViewNullable(int n) {
    _flushPack();
    stride += 1 + n * 4;
  }

  @override
  void addFloat64ListView(int n) {
    _flushPack();
    stride += n * 8;
  }

  @override
  void addFloat64ListViewNullable(int n) {
    _flushPack();
    stride += 1 + n * 8;
  }
}

// ---------------------------------------------------------------------------
// _ByteDataReader / _ByteDataWriter
// ---------------------------------------------------------------------------

class _ByteDataReader implements FieldReader {
  final ByteData _d;
  int _off = 0;
  int _bitsUsed = 0;

  _ByteDataReader(this._d);

  void _flushSubByte() {
    if (_bitsUsed > 0) {
      _off += 1;
      _bitsUsed = 0;
    }
  }

  int _readSubBits(int width, int mask) {
    if (_bitsUsed > 0 && _bitsUsed + width > 8) {
      _off += 1;
      _bitsUsed = 0;
    }
    final v = (_d.getUint8(_off) >>> _bitsUsed) & mask;
    _bitsUsed += width;
    if (_bitsUsed == 8) {
      _off += 1;
      _bitsUsed = 0;
    }
    return v;
  }

  @override
  int readInt8() {
    _flushSubByte();
    final v = _d.getInt8(_off);
    _off += 1;
    return v;
  }

  @override
  int readInt16() {
    _flushSubByte();
    final v = _d.getInt16(_off);
    _off += 2;
    return v;
  }

  @override
  int readInt32() {
    _flushSubByte();
    final v = _d.getInt32(_off);
    _off += 4;
    return v;
  }

  @override
  int readInt64() {
    _flushSubByte();
    final v = _d.getInt64(_off);
    _off += 8;
    return v;
  }

  @override
  int readUint8() {
    _flushSubByte();
    final v = _d.getUint8(_off);
    _off += 1;
    return v;
  }

  @override
  int readUint16() {
    _flushSubByte();
    final v = _d.getUint16(_off);
    _off += 2;
    return v;
  }

  @override
  int readUint32() {
    _flushSubByte();
    final v = _d.getUint32(_off);
    _off += 4;
    return v;
  }

  @override
  int readUint64() {
    _flushSubByte();
    final v = _d.getUint64(_off);
    _off += 8;
    return v;
  }

  @override
  double readFloat32() {
    _flushSubByte();
    final v = _d.getFloat32(_off);
    _off += 4;
    return v;
  }

  @override
  double readFloat64() {
    _flushSubByte();
    final v = _d.getFloat64(_off);
    _off += 8;
    return v;
  }

  @override
  T readField<T>(FieldParser<T> parser) {
    _flushSubByte();
    return parser.read(this);
  }

  @override
  T? readNullableField<T>(FieldParser<T> parser) {
    _flushSubByte();
    final nested = _StrideCalculator();
    parser.describe(nested);
    nested._flushPack();
    final stride = nested.stride;
    final tag = _d.getUint8(_off);
    _off += 1;
    if (tag == 0) {
      _off += stride;
      return null;
    }
    final view = ByteData.view(_d.buffer, _d.offsetInBytes + _off, stride);
    final result = parser.read(_ByteDataReader(view));
    _off += stride;
    return result;
  }

  @override
  int readBit() => _readSubBits(1, 0x1);
  @override
  bool readBool() => _readSubBits(1, 0x1) != 0;
  @override
  int readUint2() => _readSubBits(2, 0x3);
  @override
  int readInt2() {
    final v = _readSubBits(2, 0x3);
    return (v & 0x2) != 0 ? v - 4 : v;
  }

  @override
  int readUint4() => _readSubBits(4, 0xF);
  @override
  int readInt4() {
    final v = _readSubBits(4, 0xF);
    return (v & 0x8) != 0 ? v - 16 : v;
  }

  // Nullable double-stride: [tag: N bytes][value: N bytes]
  @override
  int? readInt8Nullable() {
    _flushSubByte();
    final t = _d.getInt8(_off);
    final v = _d.getInt8(_off + 1);
    _off += 2;
    return t == 0 ? null : v;
  }

  @override
  int? readInt16Nullable() {
    _flushSubByte();
    final t = _d.getInt16(_off);
    final v = _d.getInt16(_off + 2);
    _off += 4;
    return t == 0 ? null : v;
  }

  @override
  int? readInt32Nullable() {
    _flushSubByte();
    final t = _d.getInt32(_off);
    final v = _d.getInt32(_off + 4);
    _off += 8;
    return t == 0 ? null : v;
  }

  @override
  int? readInt64Nullable() {
    _flushSubByte();
    final t = _d.getInt64(_off);
    final v = _d.getInt64(_off + 8);
    _off += 16;
    return t == 0 ? null : v;
  }

  @override
  int? readUint8Nullable() {
    _flushSubByte();
    final t = _d.getUint8(_off);
    final v = _d.getUint8(_off + 1);
    _off += 2;
    return t == 0 ? null : v;
  }

  @override
  int? readUint16Nullable() {
    _flushSubByte();
    final t = _d.getUint16(_off);
    final v = _d.getUint16(_off + 2);
    _off += 4;
    return t == 0 ? null : v;
  }

  @override
  int? readUint32Nullable() {
    _flushSubByte();
    final t = _d.getUint32(_off);
    final v = _d.getUint32(_off + 4);
    _off += 8;
    return t == 0 ? null : v;
  }

  @override
  int? readUint64Nullable() {
    _flushSubByte();
    final t = _d.getUint64(_off);
    final v = _d.getUint64(_off + 8);
    _off += 16;
    return t == 0 ? null : v;
  }

  // Stolen-bit nullable (same bytes as underlying, sentinel=null)
  @override
  int? readInt7Nullable() {
    _flushSubByte();
    final v = _d.getInt8(_off);
    _off += 1;
    return v == -128 ? null : v;
  }

  @override
  int? readInt15Nullable() {
    _flushSubByte();
    final v = _d.getInt16(_off);
    _off += 2;
    return v == -32768 ? null : v;
  }

  @override
  int? readInt31Nullable() {
    _flushSubByte();
    final v = _d.getInt32(_off);
    _off += 4;
    return v == -2147483648 ? null : v;
  }

  @override
  int? readInt63Nullable() {
    _flushSubByte();
    final v = _d.getInt64(_off);
    _off += 8;
    return v == (-9223372036854775807 - 1) ? null : v;
  }

  @override
  int? readUint7Nullable() {
    _flushSubByte();
    final v = _d.getUint8(_off);
    _off += 1;
    return v == 255 ? null : v;
  }

  @override
  int? readUint15Nullable() {
    _flushSubByte();
    final v = _d.getUint16(_off);
    _off += 2;
    return v == 65535 ? null : v;
  }

  @override
  int? readUint31Nullable() {
    _flushSubByte();
    final v = _d.getUint32(_off);
    _off += 4;
    return v == 4294967295 ? null : v;
  }

  @override
  int? readUint63Nullable() {
    _flushSubByte();
    final v = _d.getUint64(_off);
    _off += 8;
    return v == -1 ? null : v;
  }

  // Tagged nullable: [value: N bytes][flag: 1 byte]
  @override
  int? readInt8Tagged() {
    _flushSubByte();
    final v = _d.getInt8(_off);
    final f = _d.getUint8(_off + 1);
    _off += 2;
    return f == 0 ? null : v;
  }

  @override
  int? readInt16Tagged() {
    _flushSubByte();
    final v = _d.getInt16(_off);
    final f = _d.getUint8(_off + 2);
    _off += 3;
    return f == 0 ? null : v;
  }

  @override
  int? readInt32Tagged() {
    _flushSubByte();
    final v = _d.getInt32(_off);
    final f = _d.getUint8(_off + 4);
    _off += 5;
    return f == 0 ? null : v;
  }

  @override
  int? readInt64Tagged() {
    _flushSubByte();
    final v = _d.getInt64(_off);
    final f = _d.getUint8(_off + 8);
    _off += 9;
    return f == 0 ? null : v;
  }

  @override
  int? readUint8Tagged() {
    _flushSubByte();
    final v = _d.getUint8(_off);
    final f = _d.getUint8(_off + 1);
    _off += 2;
    return f == 0 ? null : v;
  }

  @override
  int? readUint16Tagged() {
    _flushSubByte();
    final v = _d.getUint16(_off);
    final f = _d.getUint8(_off + 2);
    _off += 3;
    return f == 0 ? null : v;
  }

  @override
  int? readUint32Tagged() {
    _flushSubByte();
    final v = _d.getUint32(_off);
    final f = _d.getUint8(_off + 4);
    _off += 5;
    return f == 0 ? null : v;
  }

  @override
  int? readUint64Tagged() {
    _flushSubByte();
    final v = _d.getUint64(_off);
    final f = _d.getUint8(_off + 8);
    _off += 9;
    return f == 0 ? null : v;
  }

  @override
  double? readFloat32Tagged() {
    _flushSubByte();
    final v = _d.getFloat32(_off);
    final f = _d.getUint8(_off + 4);
    _off += 5;
    return f == 0 ? null : v;
  }

  @override
  double? readFloat64Tagged() {
    _flushSubByte();
    final v = _d.getFloat64(_off);
    final f = _d.getUint8(_off + 8);
    _off += 9;
    return f == 0 ? null : v;
  }

  // helpers shared by view and copy variants
  Uint8List _rawBytes(int byteLen) {
    _flushSubByte();
    final raw = Uint8List.view(_d.buffer, _d.offsetInBytes + _off, byteLen);
    _off += byteLen;
    return raw;
  }

  Uint8List? _rawBytesNullable(int byteLen) {
    _flushSubByte();
    final tag = _d.getUint8(_off);
    _off += 1;
    if (tag == 0) {
      _off += byteLen;
      return null;
    }
    return _rawBytes(byteLen);
  }

  @override
  Int8List readInt8ListView(int n) {
    final r = _rawBytes(n);
    return Int8List.sublistView(r);
  }

  @override
  Int8List? readInt8ListViewNullable(int n) {
    final r = _rawBytesNullable(n);
    return r == null ? null : Int8List.sublistView(r);
  }

  @override
  Int8List readInt8List(int n) {
    return Int8List.fromList(readInt8ListView(n));
  }

  @override
  Int8List? readInt8ListNullable(int n) {
    final v = readInt8ListViewNullable(n);
    return v == null ? null : Int8List.fromList(v);
  }

  @override
  Int16List readInt16ListView(int n) {
    final r = _rawBytes(n * 2);
    return Int16List.sublistView(r);
  }

  @override
  Int16List? readInt16ListViewNullable(int n) {
    final r = _rawBytesNullable(n * 2);
    return r == null ? null : Int16List.sublistView(r);
  }

  @override
  Int16List readInt16List(int n) {
    return Int16List.fromList(readInt16ListView(n));
  }

  @override
  Int16List? readInt16ListNullable(int n) {
    final v = readInt16ListViewNullable(n);
    return v == null ? null : Int16List.fromList(v);
  }

  @override
  Int32List readInt32ListView(int n) {
    final r = _rawBytes(n * 4);
    return Int32List.sublistView(r);
  }

  @override
  Int32List? readInt32ListViewNullable(int n) {
    final r = _rawBytesNullable(n * 4);
    return r == null ? null : Int32List.sublistView(r);
  }

  @override
  Int32List readInt32List(int n) {
    return Int32List.fromList(readInt32ListView(n));
  }

  @override
  Int32List? readInt32ListNullable(int n) {
    final v = readInt32ListViewNullable(n);
    return v == null ? null : Int32List.fromList(v);
  }

  @override
  Int64List readInt64ListView(int n) {
    final r = _rawBytes(n * 8);
    return Int64List.sublistView(r);
  }

  @override
  Int64List? readInt64ListViewNullable(int n) {
    final r = _rawBytesNullable(n * 8);
    return r == null ? null : Int64List.sublistView(r);
  }

  @override
  Int64List readInt64List(int n) {
    return Int64List.fromList(readInt64ListView(n));
  }

  @override
  Int64List? readInt64ListNullable(int n) {
    final v = readInt64ListViewNullable(n);
    return v == null ? null : Int64List.fromList(v);
  }

  @override
  Uint8List readUint8ListView(int n) {
    final r = _rawBytes(n);
    return Uint8List.sublistView(r);
  }

  @override
  Uint8List? readUint8ListViewNullable(int n) {
    final r = _rawBytesNullable(n);
    return r == null ? null : Uint8List.sublistView(r);
  }

  @override
  Uint8List readUint8List(int n) {
    return Uint8List.fromList(readUint8ListView(n));
  }

  @override
  Uint8List? readUint8ListNullable(int n) {
    final v = readUint8ListViewNullable(n);
    return v == null ? null : Uint8List.fromList(v);
  }

  @override
  Uint16List readUint16ListView(int n) {
    final r = _rawBytes(n * 2);
    return Uint16List.sublistView(r);
  }

  @override
  Uint16List? readUint16ListViewNullable(int n) {
    final r = _rawBytesNullable(n * 2);
    return r == null ? null : Uint16List.sublistView(r);
  }

  @override
  Uint16List readUint16List(int n) {
    return Uint16List.fromList(readUint16ListView(n));
  }

  @override
  Uint16List? readUint16ListNullable(int n) {
    final v = readUint16ListViewNullable(n);
    return v == null ? null : Uint16List.fromList(v);
  }

  @override
  Uint32List readUint32ListView(int n) {
    final r = _rawBytes(n * 4);
    return Uint32List.sublistView(r);
  }

  @override
  Uint32List? readUint32ListViewNullable(int n) {
    final r = _rawBytesNullable(n * 4);
    return r == null ? null : Uint32List.sublistView(r);
  }

  @override
  Uint32List readUint32List(int n) {
    return Uint32List.fromList(readUint32ListView(n));
  }

  @override
  Uint32List? readUint32ListNullable(int n) {
    final v = readUint32ListViewNullable(n);
    return v == null ? null : Uint32List.fromList(v);
  }

  @override
  Uint64List readUint64ListView(int n) {
    final r = _rawBytes(n * 8);
    return Uint64List.sublistView(r);
  }

  @override
  Uint64List? readUint64ListViewNullable(int n) {
    final r = _rawBytesNullable(n * 8);
    return r == null ? null : Uint64List.sublistView(r);
  }

  @override
  Uint64List readUint64List(int n) {
    return Uint64List.fromList(readUint64ListView(n));
  }

  @override
  Uint64List? readUint64ListNullable(int n) {
    final v = readUint64ListViewNullable(n);
    return v == null ? null : Uint64List.fromList(v);
  }

  @override
  Float32List readFloat32ListView(int n) {
    final r = _rawBytes(n * 4);
    return Float32List.sublistView(r);
  }

  @override
  Float32List? readFloat32ListViewNullable(int n) {
    final r = _rawBytesNullable(n * 4);
    return r == null ? null : Float32List.sublistView(r);
  }

  @override
  Float32List readFloat32List(int n) {
    return Float32List.fromList(readFloat32ListView(n));
  }

  @override
  Float32List? readFloat32ListNullable(int n) {
    final v = readFloat32ListViewNullable(n);
    return v == null ? null : Float32List.fromList(v);
  }

  @override
  Float64List readFloat64ListView(int n) {
    final r = _rawBytes(n * 8);
    return Float64List.sublistView(r);
  }

  @override
  Float64List? readFloat64ListViewNullable(int n) {
    final r = _rawBytesNullable(n * 8);
    return r == null ? null : Float64List.sublistView(r);
  }

  @override
  Float64List readFloat64List(int n) {
    return Float64List.fromList(readFloat64ListView(n));
  }

  @override
  Float64List? readFloat64ListNullable(int n) {
    final v = readFloat64ListViewNullable(n);
    return v == null ? null : Float64List.fromList(v);
  }
}

class _ByteDataWriter implements FieldWriter {
  final ByteData _d;
  int _off = 0;
  int _bitsUsed = 0;

  _ByteDataWriter(this._d);

  void _flushSubByte() {
    if (_bitsUsed > 0) {
      _off += 1;
      _bitsUsed = 0;
    }
  }

  void _writeSubBits(int value, int width, int mask) {
    if (_bitsUsed > 0 && _bitsUsed + width > 8) {
      _off += 1;
      _bitsUsed = 0;
    }
    final cur = _d.getUint8(_off);
    _d.setUint8(
      _off,
      (cur & ~(mask << _bitsUsed)) | ((value & mask) << _bitsUsed),
    );
    _bitsUsed += width;
    if (_bitsUsed == 8) {
      _off += 1;
      _bitsUsed = 0;
    }
  }

  @override
  void writeInt8(int v) {
    _flushSubByte();
    _d.setInt8(_off, v);
    _off += 1;
  }

  @override
  void writeInt16(int v) {
    _flushSubByte();
    _d.setInt16(_off, v);
    _off += 2;
  }

  @override
  void writeInt32(int v) {
    _flushSubByte();
    _d.setInt32(_off, v);
    _off += 4;
  }

  @override
  void writeInt64(int v) {
    _flushSubByte();
    _d.setInt64(_off, v);
    _off += 8;
  }

  @override
  void writeUint8(int v) {
    _flushSubByte();
    _d.setUint8(_off, v);
    _off += 1;
  }

  @override
  void writeUint16(int v) {
    _flushSubByte();
    _d.setUint16(_off, v);
    _off += 2;
  }

  @override
  void writeUint32(int v) {
    _flushSubByte();
    _d.setUint32(_off, v);
    _off += 4;
  }

  @override
  void writeUint64(int v) {
    _flushSubByte();
    _d.setUint64(_off, v);
    _off += 8;
  }

  @override
  void writeFloat32(double v) {
    _flushSubByte();
    _d.setFloat32(_off, v);
    _off += 4;
  }

  @override
  void writeFloat64(double v) {
    _flushSubByte();
    _d.setFloat64(_off, v);
    _off += 8;
  }

  @override
  void writeField<T>(T value, FieldParser<T> parser) {
    _flushSubByte();
    if (parser is MutableFieldParser && value is TypedData) {
      final vd = value as TypedData;
      if (identical(vd.buffer, _d.buffer) &&
          vd.offsetInBytes == _d.offsetInBytes + _off) {
        _off += vd.lengthInBytes; // already in place — skip copy
        return;
      }
    }
    parser.write(value, this);
  }

  @override
  void writeNullableField<T>(T? value, FieldParser<T> parser) {
    _flushSubByte();
    final nested = _StrideCalculator();
    parser.describe(nested);
    nested._flushPack();
    final stride = nested.stride;
    if (value == null) {
      _d.setUint8(_off, 0);
      _off += 1 + stride;
    } else {
      _d.setUint8(_off, 1);
      _off += 1;
      final view = ByteData.view(_d.buffer, _d.offsetInBytes + _off, stride);
      parser.write(value, _ByteDataWriter(view));
      _off += stride;
    }
  }

  @override
  void writeBit(int v) => _writeSubBits(v, 1, 0x1);
  @override
  void writeBool(bool v) => _writeSubBits(v ? 1 : 0, 1, 0x1);
  @override
  void writeUint2(int v) => _writeSubBits(v, 2, 0x3);
  @override
  void writeInt2(int v) => _writeSubBits(v, 2, 0x3);
  @override
  void writeUint4(int v) => _writeSubBits(v, 4, 0xF);
  @override
  void writeInt4(int v) => _writeSubBits(v, 4, 0xF);

  // Nullable double-stride: [tag: N bytes][value: N bytes]
  @override
  void writeInt8Nullable(int? v) {
    _flushSubByte();
    if (v == null) {
      _d.setInt8(_off, 0);
    } else {
      _d.setInt8(_off, 1);
      _d.setInt8(_off + 1, v);
    }
    _off += 2;
  }

  @override
  void writeInt16Nullable(int? v) {
    _flushSubByte();
    if (v == null) {
      _d.setInt16(_off, 0);
    } else {
      _d.setInt16(_off, 1);
      _d.setInt16(_off + 2, v);
    }
    _off += 4;
  }

  @override
  void writeInt32Nullable(int? v) {
    _flushSubByte();
    if (v == null) {
      _d.setInt32(_off, 0);
    } else {
      _d.setInt32(_off, 1);
      _d.setInt32(_off + 4, v);
    }
    _off += 8;
  }

  @override
  void writeInt64Nullable(int? v) {
    _flushSubByte();
    if (v == null) {
      _d.setInt64(_off, 0);
    } else {
      _d.setInt64(_off, 1);
      _d.setInt64(_off + 8, v);
    }
    _off += 16;
  }

  @override
  void writeUint8Nullable(int? v) {
    _flushSubByte();
    if (v == null) {
      _d.setUint8(_off, 0);
    } else {
      _d.setUint8(_off, 1);
      _d.setUint8(_off + 1, v);
    }
    _off += 2;
  }

  @override
  void writeUint16Nullable(int? v) {
    _flushSubByte();
    if (v == null) {
      _d.setUint16(_off, 0);
    } else {
      _d.setUint16(_off, 1);
      _d.setUint16(_off + 2, v);
    }
    _off += 4;
  }

  @override
  void writeUint32Nullable(int? v) {
    _flushSubByte();
    if (v == null) {
      _d.setUint32(_off, 0);
    } else {
      _d.setUint32(_off, 1);
      _d.setUint32(_off + 4, v);
    }
    _off += 8;
  }

  @override
  void writeUint64Nullable(int? v) {
    _flushSubByte();
    if (v == null) {
      _d.setUint64(_off, 0);
    } else {
      _d.setUint64(_off, 1);
      _d.setUint64(_off + 8, v);
    }
    _off += 16;
  }

  // Stolen-bit nullable (same bytes as underlying)
  @override
  void writeInt7Nullable(int? v) {
    _flushSubByte();
    _d.setInt8(_off, v ?? -128);
    _off += 1;
  }

  @override
  void writeInt15Nullable(int? v) {
    _flushSubByte();
    _d.setInt16(_off, v ?? -32768);
    _off += 2;
  }

  @override
  void writeInt31Nullable(int? v) {
    _flushSubByte();
    _d.setInt32(_off, v ?? -2147483648);
    _off += 4;
  }

  @override
  void writeInt63Nullable(int? v) {
    _flushSubByte();
    _d.setInt64(_off, v ?? (-9223372036854775807 - 1));
    _off += 8;
  }

  @override
  void writeUint7Nullable(int? v) {
    _flushSubByte();
    _d.setUint8(_off, v ?? 255);
    _off += 1;
  }

  @override
  void writeUint15Nullable(int? v) {
    _flushSubByte();
    _d.setUint16(_off, v ?? 65535);
    _off += 2;
  }

  @override
  void writeUint31Nullable(int? v) {
    _flushSubByte();
    _d.setUint32(_off, v ?? 4294967295);
    _off += 4;
  }

  @override
  void writeUint63Nullable(int? v) {
    _flushSubByte();
    _d.setUint64(_off, v ?? -1);
    _off += 8;
  }

  // Tagged nullable: [value: N bytes][flag: 1 byte]
  @override
  void writeInt8Tagged(int? v) {
    _flushSubByte();
    if (v == null) {
      _d.setUint8(_off + 1, 0);
    } else {
      _d.setInt8(_off, v);
      _d.setUint8(_off + 1, 1);
    }
    _off += 2;
  }

  @override
  void writeInt16Tagged(int? v) {
    _flushSubByte();
    if (v == null) {
      _d.setUint8(_off + 2, 0);
    } else {
      _d.setInt16(_off, v);
      _d.setUint8(_off + 2, 1);
    }
    _off += 3;
  }

  @override
  void writeInt32Tagged(int? v) {
    _flushSubByte();
    if (v == null) {
      _d.setUint8(_off + 4, 0);
    } else {
      _d.setInt32(_off, v);
      _d.setUint8(_off + 4, 1);
    }
    _off += 5;
  }

  @override
  void writeInt64Tagged(int? v) {
    _flushSubByte();
    if (v == null) {
      _d.setUint8(_off + 8, 0);
    } else {
      _d.setInt64(_off, v);
      _d.setUint8(_off + 8, 1);
    }
    _off += 9;
  }

  @override
  void writeUint8Tagged(int? v) {
    _flushSubByte();
    if (v == null) {
      _d.setUint8(_off + 1, 0);
    } else {
      _d.setUint8(_off, v);
      _d.setUint8(_off + 1, 1);
    }
    _off += 2;
  }

  @override
  void writeUint16Tagged(int? v) {
    _flushSubByte();
    if (v == null) {
      _d.setUint8(_off + 2, 0);
    } else {
      _d.setUint16(_off, v);
      _d.setUint8(_off + 2, 1);
    }
    _off += 3;
  }

  @override
  void writeUint32Tagged(int? v) {
    _flushSubByte();
    if (v == null) {
      _d.setUint8(_off + 4, 0);
    } else {
      _d.setUint32(_off, v);
      _d.setUint8(_off + 4, 1);
    }
    _off += 5;
  }

  @override
  void writeUint64Tagged(int? v) {
    _flushSubByte();
    if (v == null) {
      _d.setUint8(_off + 8, 0);
    } else {
      _d.setUint64(_off, v);
      _d.setUint8(_off + 8, 1);
    }
    _off += 9;
  }

  @override
  void writeFloat32Tagged(double? v) {
    _flushSubByte();
    if (v == null) {
      _d.setUint8(_off + 4, 0);
    } else {
      _d.setFloat32(_off, v);
      _d.setUint8(_off + 4, 1);
    }
    _off += 5;
  }

  @override
  void writeFloat64Tagged(double? v) {
    _flushSubByte();
    if (v == null) {
      _d.setUint8(_off + 8, 0);
    } else {
      _d.setFloat64(_off, v);
      _d.setUint8(_off + 8, 1);
    }
    _off += 9;
  }

  void _writeRawBytes(TypedData src, int byteLen) {
    _flushSubByte();
    Uint8List.view(_d.buffer, _d.offsetInBytes + _off, byteLen).setRange(
      0,
      byteLen,
      Uint8List.view(src.buffer, src.offsetInBytes, byteLen),
    );
    _off += byteLen;
  }

  void _writeRawBytesNullable(TypedData? src, int byteLen) {
    _flushSubByte();
    if (src == null) {
      _d.setUint8(_off, 0);
      _off += 1 + byteLen;
    } else {
      _d.setUint8(_off, 1);
      _off += 1;
      _writeRawBytes(src, byteLen);
    }
  }

  @override
  void writeInt8ListView(Int8List v, int n) {
    _writeRawBytes(v, n);
  }

  @override
  void writeInt8ListViewNullable(Int8List? v, int n) {
    _writeRawBytesNullable(v, n);
  }

  @override
  void writeInt8List(Int8List v, int n) {
    _writeRawBytes(v, n);
  }

  @override
  void writeInt8ListNullable(Int8List? v, int n) {
    _writeRawBytesNullable(v, n);
  }

  @override
  void writeInt16ListView(Int16List v, int n) {
    _writeRawBytes(v, n * 2);
  }

  @override
  void writeInt16ListViewNullable(Int16List? v, int n) {
    _writeRawBytesNullable(v, n * 2);
  }

  @override
  void writeInt16List(Int16List v, int n) {
    _writeRawBytes(v, n * 2);
  }

  @override
  void writeInt16ListNullable(Int16List? v, int n) {
    _writeRawBytesNullable(v, n * 2);
  }

  @override
  void writeInt32ListView(Int32List v, int n) {
    _writeRawBytes(v, n * 4);
  }

  @override
  void writeInt32ListViewNullable(Int32List? v, int n) {
    _writeRawBytesNullable(v, n * 4);
  }

  @override
  void writeInt32List(Int32List v, int n) {
    _writeRawBytes(v, n * 4);
  }

  @override
  void writeInt32ListNullable(Int32List? v, int n) {
    _writeRawBytesNullable(v, n * 4);
  }

  @override
  void writeInt64ListView(Int64List v, int n) {
    _writeRawBytes(v, n * 8);
  }

  @override
  void writeInt64ListViewNullable(Int64List? v, int n) {
    _writeRawBytesNullable(v, n * 8);
  }

  @override
  void writeInt64List(Int64List v, int n) {
    _writeRawBytes(v, n * 8);
  }

  @override
  void writeInt64ListNullable(Int64List? v, int n) {
    _writeRawBytesNullable(v, n * 8);
  }

  @override
  void writeUint8ListView(Uint8List v, int n) {
    _writeRawBytes(v, n);
  }

  @override
  void writeUint8ListViewNullable(Uint8List? v, int n) {
    _writeRawBytesNullable(v, n);
  }

  @override
  void writeUint8List(Uint8List v, int n) {
    _writeRawBytes(v, n);
  }

  @override
  void writeUint8ListNullable(Uint8List? v, int n) {
    _writeRawBytesNullable(v, n);
  }

  @override
  void writeUint16ListView(Uint16List v, int n) {
    _writeRawBytes(v, n * 2);
  }

  @override
  void writeUint16ListViewNullable(Uint16List? v, int n) {
    _writeRawBytesNullable(v, n * 2);
  }

  @override
  void writeUint16List(Uint16List v, int n) {
    _writeRawBytes(v, n * 2);
  }

  @override
  void writeUint16ListNullable(Uint16List? v, int n) {
    _writeRawBytesNullable(v, n * 2);
  }

  @override
  void writeUint32ListView(Uint32List v, int n) {
    _writeRawBytes(v, n * 4);
  }

  @override
  void writeUint32ListViewNullable(Uint32List? v, int n) {
    _writeRawBytesNullable(v, n * 4);
  }

  @override
  void writeUint32List(Uint32List v, int n) {
    _writeRawBytes(v, n * 4);
  }

  @override
  void writeUint32ListNullable(Uint32List? v, int n) {
    _writeRawBytesNullable(v, n * 4);
  }

  @override
  void writeUint64ListView(Uint64List v, int n) {
    _writeRawBytes(v, n * 8);
  }

  @override
  void writeUint64ListViewNullable(Uint64List? v, int n) {
    _writeRawBytesNullable(v, n * 8);
  }

  @override
  void writeUint64List(Uint64List v, int n) {
    _writeRawBytes(v, n * 8);
  }

  @override
  void writeUint64ListNullable(Uint64List? v, int n) {
    _writeRawBytesNullable(v, n * 8);
  }

  @override
  void writeFloat32ListView(Float32List v, int n) {
    _writeRawBytes(v, n * 4);
  }

  @override
  void writeFloat32ListViewNullable(Float32List? v, int n) {
    _writeRawBytesNullable(v, n * 4);
  }

  @override
  void writeFloat32List(Float32List v, int n) {
    _writeRawBytes(v, n * 4);
  }

  @override
  void writeFloat32ListNullable(Float32List? v, int n) {
    _writeRawBytesNullable(v, n * 4);
  }

  @override
  void writeFloat64ListView(Float64List v, int n) {
    _writeRawBytes(v, n * 8);
  }

  @override
  void writeFloat64ListViewNullable(Float64List? v, int n) {
    _writeRawBytesNullable(v, n * 8);
  }

  @override
  void writeFloat64List(Float64List v, int n) {
    _writeRawBytes(v, n * 8);
  }

  @override
  void writeFloat64ListNullable(Float64List? v, int n) {
    _writeRawBytesNullable(v, n * 8);
  }
}

// ---------------------------------------------------------------------------
// _CustomField — dispatches get/set through QueryResult
// ---------------------------------------------------------------------------

class _CustomField<T> implements Field<T> {
  final _CustomFieldStorage<T> _s;

  _CustomField(this._s);

  @pragma('vm:prefer-inline')
  @override
  T get(QueryResult c) => c.getField(_s) as T;

  @pragma('vm:prefer-inline')
  @override
  void set(QueryResult c, T value) => c.setField(_s, value);
  @pragma('vm:prefer-inline')
  @override
  T getSlot(int slot) => _s.readFrom(slot) as T;
  @pragma('vm:prefer-inline')
  @override
  void setSlot(int slot, T v) => _s.writeAt(slot, v);
}

// ---------------------------------------------------------------------------
// _NumField — dispatches get/set through QueryResult
// ---------------------------------------------------------------------------

class _NumField<N extends num, L extends List<N>> implements Field<N> {
  final _FieldStorage<N, L> _s;

  _NumField(this._s);

  @pragma('vm:prefer-inline')
  @override
  N get(QueryResult c) => c.getField(_s) as N;

  @pragma('vm:prefer-inline')
  @override
  void set(QueryResult c, N v) => c.setField(_s, v);
  @pragma('vm:prefer-inline')
  @override
  N getSlot(int slot) => _s.readFrom(slot) as N;
  @pragma('vm:prefer-inline')
  @override
  void setSlot(int slot, N v) => _s.writeAt(slot, v);
}

// ---------------------------------------------------------------------------
// _NullableField — dispatches nullable get/set through QueryResult
// ---------------------------------------------------------------------------

class _NullableField<T> implements Field<T?> {
  final FieldStorage _s;

  _NullableField(this._s);

  @pragma('vm:prefer-inline')
  @override
  T? get(QueryResult c) => c.getField(_s) as T?;

  @pragma('vm:prefer-inline')
  @override
  void set(QueryResult c, T? v) => c.setField(_s, v);
  @pragma('vm:prefer-inline')
  @override
  T? getSlot(int slot) => _s.readFrom(slot) as T?;
  @pragma('vm:prefer-inline')
  @override
  void setSlot(int slot, T? v) => _s.writeAt(slot, v);
}

// ---------------------------------------------------------------------------
// _NullableCustomFieldStorage — custom parser field with tagged nullability
// Pool: _NullTagStorage bit; capture: [1 tag byte][parser value bytes]
// ---------------------------------------------------------------------------

class _NullableCustomFieldStorage<T> implements FieldStorage {
  final FieldParser<T> _parser;
  final _ByteDataStorage _storage; // pool value bytes, stride = parser.stride
  final int _byteOffset; // capture byte offset of tag byte
  final int _stride; // parser.stride (value bytes only)
  final _NullTagStorage _nullTags;
  final int _tagBitIndex;
  final T? _initialValue;

  _NullableCustomFieldStorage(
    this._parser,
    this._storage,
    this._byteOffset,
    this._stride,
    this._nullTags,
    this._tagBitIndex,
    this._initialValue,
  );

  @override
  int get byteOffset => _byteOffset;
  @override
  int get elementSize => 1 + _stride;

  @override
  void writeAt(int slot, Object? value) {
    _nullTags.setTagAt(slot, _tagBitIndex, value != null);
    if (value != null) {
      _parser.write(value as T, _ByteDataWriter(_storage.viewAt(slot)));
    }
  }

  @override
  Object? readFrom(int slot) {
    if (!_nullTags.getTagAt(slot, _tagBitIndex)) return null;
    return _parser.read(_ByteDataReader(_storage.viewAt(slot)));
  }

  @override
  void writeBytes(ByteData bd, int offset, Object? value) {
    if (value == null) {
      bd.setUint8(offset, 0);
    } else {
      bd.setUint8(offset, 1);
      final view = ByteData.view(
        bd.buffer,
        bd.offsetInBytes + offset + 1,
        _stride,
      );
      _parser.write(value as T, _ByteDataWriter(view));
    }
  }

  @override
  Object? readBytes(ByteData bd, int offset) {
    if (bd.getUint8(offset) == 0) return null;
    final view = ByteData.view(
      bd.buffer,
      bd.offsetInBytes + offset + 1,
      _stride,
    );
    return _parser.read(_ByteDataReader(view));
  }

  @override
  void initSlot(int slot) {
    final v = _initialValue;
    if (v == null) return;
    _nullTags.setTagAt(slot, _tagBitIndex, true);
    _parser.write(v, _ByteDataWriter(_storage.viewAt(slot)));
  }

  @override
  void initBytes(ByteData bd) {
    final v = _initialValue;
    if (v == null) return;
    bd.setUint8(_byteOffset, 1);
    final view = ByteData.view(
      bd.buffer,
      bd.offsetInBytes + _byteOffset + 1,
      _stride,
    );
    _parser.write(v, _ByteDataWriter(view));
  }
}

class _NullableCustomField<T> implements Field<T?> {
  final _NullableCustomFieldStorage<T> _s;

  _NullableCustomField(this._s);

  @pragma('vm:prefer-inline')
  @override
  T? get(QueryResult c) => c.getField(_s) as T?;

  @pragma('vm:prefer-inline')
  @override
  void set(QueryResult c, T? v) => c.setField(_s, v);
  @pragma('vm:prefer-inline')
  @override
  T? getSlot(int slot) => _s.readFrom(slot) as T?;
  @pragma('vm:prefer-inline')
  @override
  void setSlot(int slot, T? v) => _s.writeAt(slot, v);
}

// ---------------------------------------------------------------------------
// _ListStorage / _NullableListStorage — typed-array fields
// ---------------------------------------------------------------------------

class _ListStorage<L extends TypedData> implements FieldStorage {
  final _ByteDataStorage _storage;
  final int _byteOffset;
  final int _count;
  final int _elementSize;
  final bool _returnView;
  final L? _initialValue;
  final L Function(Uint8List, int, int) _view;
  final L Function(L) _copy;

  _ListStorage({
    required _ByteDataStorage storage,
    required int byteOffset,
    required int count,
    required int elementSize,
    required bool returnView,
    L? initialValue,
    required L Function(Uint8List, int, int) view,
    required L Function(L) copy,
  }) : _storage = storage,
       _byteOffset = byteOffset,
       _count = count,
       _elementSize = elementSize,
       _returnView = returnView,
       _initialValue = initialValue,
       _view = view,
       _copy = copy;

  int get _byteLen => _count * _elementSize;

  @override
  int get byteOffset => _byteOffset;
  @override
  int get elementSize => _byteLen;

  @override
  Object? readFrom(int slot) {
    final v = _view(_storage.bytes, slot * _byteLen, (slot + 1) * _byteLen);
    return _returnView ? v : _copy(v);
  }

  @override
  void writeAt(int slot, Object? value) {
    final src = value as L;
    final bl = _byteLen;
    Uint8List.sublistView(
      _storage.bytes,
      slot * bl,
      (slot + 1) * bl,
    ).setRange(0, bl, Uint8List.view(src.buffer, src.offsetInBytes, bl));
  }

  @override
  void writeBytes(ByteData bd, int offset, Object? value) {
    final src = value as L;
    final bl = _byteLen;
    Uint8List.view(
      bd.buffer,
      bd.offsetInBytes + offset,
      bl,
    ).setRange(0, bl, Uint8List.view(src.buffer, src.offsetInBytes, bl));
  }

  @override
  Object? readBytes(ByteData bd, int offset) {
    final bl = _byteLen;
    final raw = Uint8List.view(bd.buffer, bd.offsetInBytes + offset, bl);
    final v = _view(raw, 0, bl);
    return _returnView ? v : _copy(v);
  }

  @override
  void initSlot(int slot) {
    final v = _initialValue;
    if (v == null) return;
    writeAt(slot, v);
  }

  @override
  void initBytes(ByteData bd) {
    final v = _initialValue;
    if (v == null) return;
    writeBytes(bd, _byteOffset, v);
  }
}

class _NullableListStorage<L extends TypedData> implements FieldStorage {
  final _ByteDataStorage _storage;
  final int _byteOffset;
  final int _count;
  final int _elementSize;
  final bool _returnView;
  final L? _initialValue;
  final _NullTagStorage _nullTags;
  final int _tagBitIndex;
  final L Function(Uint8List, int, int) _view;
  final L Function(L) _copy;

  _NullableListStorage({
    required _ByteDataStorage storage,
    required int byteOffset,
    required int count,
    required int elementSize,
    required bool returnView,
    L? initialValue,
    required _NullTagStorage nullTags,
    required int tagBitIndex,
    required L Function(Uint8List, int, int) view,
    required L Function(L) copy,
  }) : _storage = storage,
       _byteOffset = byteOffset,
       _count = count,
       _elementSize = elementSize,
       _returnView = returnView,
       _initialValue = initialValue,
       _nullTags = nullTags,
       _tagBitIndex = tagBitIndex,
       _view = view,
       _copy = copy;

  int get _byteLen => _count * _elementSize;

  @override
  int get byteOffset => _byteOffset;
  @override
  int get elementSize => 1 + _byteLen;

  @override
  Object? readFrom(int slot) {
    if (!_nullTags.getTagAt(slot, _tagBitIndex)) return null;
    final v = _view(_storage.bytes, slot * _byteLen, (slot + 1) * _byteLen);
    return _returnView ? v : _copy(v);
  }

  @override
  void writeAt(int slot, Object? value) {
    _nullTags.setTagAt(slot, _tagBitIndex, value != null);
    if (value != null) {
      final src = value as L;
      final bl = _byteLen;
      Uint8List.sublistView(
        _storage.bytes,
        slot * bl,
        (slot + 1) * bl,
      ).setRange(0, bl, Uint8List.view(src.buffer, src.offsetInBytes, bl));
    }
  }

  @override
  void writeBytes(ByteData bd, int offset, Object? value) {
    if (value == null) {
      bd.setUint8(offset, 0);
    } else {
      bd.setUint8(offset, 1);
      final src = value as L;
      final bl = _byteLen;
      Uint8List.view(
        bd.buffer,
        bd.offsetInBytes + offset + 1,
        bl,
      ).setRange(0, bl, Uint8List.view(src.buffer, src.offsetInBytes, bl));
    }
  }

  @override
  Object? readBytes(ByteData bd, int offset) {
    if (bd.getUint8(offset) == 0) return null;
    final bl = _byteLen;
    final raw = Uint8List.view(bd.buffer, bd.offsetInBytes + offset + 1, bl);
    final v = _view(raw, 0, bl);
    return _returnView ? v : _copy(v);
  }

  @override
  void initSlot(int slot) {
    final v = _initialValue;
    if (v == null) return;
    _nullTags.setTagAt(slot, _tagBitIndex, true);
    final bl = _byteLen;
    Uint8List.sublistView(
      _storage.bytes,
      slot * bl,
      (slot + 1) * bl,
    ).setRange(0, bl, Uint8List.view(v.buffer, v.offsetInBytes, bl));
  }

  @override
  void initBytes(ByteData bd) {
    final v = _initialValue;
    if (v == null) return;
    bd.setUint8(_byteOffset, 1);
    final bl = _byteLen;
    Uint8List.view(
      bd.buffer,
      bd.offsetInBytes + _byteOffset + 1,
      bl,
    ).setRange(0, bl, Uint8List.view(v.buffer, v.offsetInBytes, bl));
  }
}

class _ListField<L extends TypedData> implements Field<L> {
  final _ListStorage<L> _s;
  _ListField(this._s);
  @pragma('vm:prefer-inline')
  @override
  L get(QueryResult c) => c.getField(_s) as L;
  @pragma('vm:prefer-inline')
  @override
  void set(QueryResult c, L v) => c.setField(_s, v);
  @pragma('vm:prefer-inline')
  @override
  L getSlot(int slot) => _s.readFrom(slot) as L;
  @pragma('vm:prefer-inline')
  @override
  void setSlot(int slot, L v) => _s.writeAt(slot, v);
}

class _NullableListField<L extends TypedData> implements Field<L?> {
  final _NullableListStorage<L> _s;
  _NullableListField(this._s);
  @pragma('vm:prefer-inline')
  @override
  L? get(QueryResult c) => c.getField(_s) as L?;
  @pragma('vm:prefer-inline')
  @override
  void set(QueryResult c, L? v) => c.setField(_s, v);
  @pragma('vm:prefer-inline')
  @override
  L? getSlot(int slot) => _s.readFrom(slot) as L?;
  @pragma('vm:prefer-inline')
  @override
  void setSlot(int slot, L? v) => _s.writeAt(slot, v);
}

// ---------------------------------------------------------------------------
// DataDescriptor implementation
// ---------------------------------------------------------------------------

class _ComponentDataDescriptor implements DataDescriptor {
  final int _initialCapacity;
  final List<_AbstractStorage> _storages = [];
  final List<FieldStorage> _fieldStorages = [];
  final List<Object?> _heapMap = [];
  _PackedBitsStorage? _packed;
  int _nextByteOffset = 0;
  int _packedBase =
      0; // byte offset where packed section starts in capture layout

  _ComponentDataDescriptor(this._initialCapacity);

  void clearHeapCapture() => _heapMap.clear();

  int get bytesPerSlot => _nextByteOffset;

  void growAll(int newCapacity) {
    for (final s in _storages) {
      s.grow(newCapacity);
    }
  }

  void compactAll(Map<int, int> remap) {
    for (final s in _storages) {
      s.compact(remap);
    }
  }

  void initSlot(int slot) {
    for (final fs in _fieldStorages) {
      fs.initSlot(slot);
    }
  }

  void initBytes(ByteData bd) {
    for (final fs in _fieldStorages) {
      fs.initBytes(bd);
    }
  }

  // Copy init data from capture region into pool storage at realSlot.
  void unpackFrom(Int64List buf, int initWordBase, int realSlot) {
    if (_fieldStorages.isEmpty) return;
    final bd = ByteData.view(buf.buffer, buf.offsetInBytes + initWordBase * 8);
    for (final fs in _fieldStorages) {
      fs.writeAt(realSlot, fs.readBytes(bd, fs.byteOffset));
    }
  }

  _FieldStorage<N, L> _register<N extends num, L extends List<N>>(
    L Function(int) create,
    int elementSize,
    void Function(ByteData bd, int offset, N v) writeBytesImpl,
    N Function(ByteData bd, int offset) readBytesImpl, {
    N? initialValue,
  }) {
    final byteOffset = _nextByteOffset;
    _nextByteOffset += elementSize;
    final storage = _FieldStorage<N, L>(
      _initialCapacity,
      create,
      byteOffset,
      elementSize,
      writeBytesImpl,
      readBytesImpl,
      initialValue: initialValue,
    );
    _storages.add(storage);
    _fieldStorages.add(storage);
    return storage;
  }

  _PackedBitsStorage _packedStorage() {
    if (_packed == null) {
      _packedBase = _nextByteOffset;
      _packed = _PackedBitsStorage(_initialCapacity);
      _storages.add(_packed!);
    }
    return _packed!;
  }

  // Called after reserveBits to update _nextByteOffset if packed section grew.
  void _syncPackedOffset() {
    final newEnd = _packedBase + _packed!._bytesPerSlot;
    if (newEnd > _nextByteOffset) _nextByteOffset = newEnd;
  }

  // ---- numeric fields ----

  @override
  Field<int> newInt8({int initialValue = 0}) => _NumField(
    _register<int, Int8List>(
      (n) => Int8List(n),
      1,
      (bd, o, v) => bd.setInt8(o, v),
      (bd, o) => bd.getInt8(o),
      initialValue: initialValue != 0 ? initialValue : null,
    ),
  );

  @override
  Field<int> newInt16({int initialValue = 0}) => _NumField(
    _register<int, Int16List>(
      (n) => Int16List(n),
      2,
      (bd, o, v) => bd.setInt16(o, v),
      (bd, o) => bd.getInt16(o),
      initialValue: initialValue != 0 ? initialValue : null,
    ),
  );

  @override
  Field<int> newInt32({int initialValue = 0}) => _NumField(
    _register<int, Int32List>(
      (n) => Int32List(n),
      4,
      (bd, o, v) => bd.setInt32(o, v),
      (bd, o) => bd.getInt32(o),
      initialValue: initialValue != 0 ? initialValue : null,
    ),
  );

  @override
  Field<int> newInt64({int initialValue = 0}) => _NumField(
    _register<int, Int64List>(
      (n) => Int64List(n),
      8,
      (bd, o, v) => bd.setInt64(o, v),
      (bd, o) => bd.getInt64(o),
      initialValue: initialValue != 0 ? initialValue : null,
    ),
  );

  @override
  Field<int> newUint8({int initialValue = 0}) => _NumField(
    _register<int, Uint8List>(
      (n) => Uint8List(n),
      1,
      (bd, o, v) => bd.setUint8(o, v),
      (bd, o) => bd.getUint8(o),
      initialValue: initialValue != 0 ? initialValue : null,
    ),
  );

  @override
  Field<int> newUint16({int initialValue = 0}) => _NumField(
    _register<int, Uint16List>(
      (n) => Uint16List(n),
      2,
      (bd, o, v) => bd.setUint16(o, v),
      (bd, o) => bd.getUint16(o),
      initialValue: initialValue != 0 ? initialValue : null,
    ),
  );

  @override
  Field<int> newUint32({int initialValue = 0}) => _NumField(
    _register<int, Uint32List>(
      (n) => Uint32List(n),
      4,
      (bd, o, v) => bd.setUint32(o, v),
      (bd, o) => bd.getUint32(o),
      initialValue: initialValue != 0 ? initialValue : null,
    ),
  );

  @override
  Field<int> newUint64({int initialValue = 0}) => _NumField(
    _register<int, Uint64List>(
      (n) => Uint64List(n),
      8,
      (bd, o, v) => bd.setUint64(o, v),
      (bd, o) => bd.getUint64(o),
      initialValue: initialValue != 0 ? initialValue : null,
    ),
  );

  @override
  Field<double> newFloat32({double initialValue = 0.0}) => _NumField(
    _register<double, Float32List>(
      (n) => Float32List(n),
      4,
      (bd, o, v) => bd.setFloat32(o, v),
      (bd, o) => bd.getFloat32(o),
      initialValue: initialValue != 0.0 ? initialValue : null,
    ),
  );

  @override
  Field<double> newFloat64({double initialValue = 0.0}) => _NumField(
    _register<double, Float64List>(
      (n) => Float64List(n),
      8,
      (bd, o, v) => bd.setFloat64(o, v),
      (bd, o) => bd.getFloat64(o),
      initialValue: initialValue != 0.0 ? initialValue : null,
    ),
  );

  @override
  Field<T> newField<T>(FieldParser<T> parser, {required T initialValue}) {
    final calc = _StrideCalculator();
    parser.describe(calc);
    calc._flushPack();
    final byteOffset = _nextByteOffset;
    _nextByteOffset += calc.stride;
    final storage = _ByteDataStorage(_initialCapacity, calc.stride);
    _storages.add(storage);
    final fs = _CustomFieldStorage<T>(
      parser,
      storage,
      byteOffset,
      initialValue,
    );
    _fieldStorages.add(fs);
    return _CustomField(fs);
  }

  @override
  Field<T?> newFieldNullable<T>(FieldParser<T> parser, {T? initialValue}) {
    final calc = _StrideCalculator();
    parser.describe(calc);
    calc._flushPack();
    final stride = calc.stride;
    final byteOffset = _nextByteOffset;
    _nextByteOffset += 1 + stride; // 1 tag byte + parser value bytes
    final storage = _ByteDataStorage(_initialCapacity, stride);
    _storages.add(storage);
    final nullTags = _nullTagStorage();
    final tagBitIndex = nullTags.reserveTag();
    final fs = _NullableCustomFieldStorage<T>(
      parser,
      storage,
      byteOffset,
      stride,
      nullTags,
      tagBitIndex,
      initialValue,
    );
    _fieldStorages.add(fs);
    return _NullableCustomField<T>(fs);
  }

  @override
  Field<T> newHeap<T>({required T initialValue}) {
    final byteOffset = _nextByteOffset;
    _nextByteOffset += 4;
    final storage = _HeapFieldStorage<T>(
      _initialCapacity,
      initialValue,
      byteOffset,
      _heapMap,
    );
    _storages.add(storage);
    _fieldStorages.add(storage);
    return _HeapField<T>(storage);
  }

  // ---- sub-byte packed fields ----

  Field<int> _newPacked(
    int width,
    int mask,
    int signBit, {
    int initialValue = 0,
  }) {
    final s = _packedStorage();
    final bitStart = s.reserveBits(width);
    _syncPackedOffset();
    final byteOff = bitStart >> 3;
    final bitOff = bitStart & 7;
    final fieldByteOffset = _packedBase + byteOff;
    final ps = _PackedIntStorage(
      s,
      byteOff,
      bitOff,
      mask,
      signBit,
      fieldByteOffset,
      initialValue: initialValue != 0 ? initialValue : null,
    );
    _fieldStorages.add(ps);
    return _PackedIntField(ps);
  }

  @override
  Field<int> newBit({int initialValue = 0}) =>
      _newPacked(1, 0x1, 0, initialValue: initialValue);

  @override
  Field<bool> newBool({bool initialValue = false}) {
    final s = _packedStorage();
    final bitStart = s.reserveBits(1);
    _syncPackedOffset();
    final byteOff = bitStart >> 3;
    final bitOff = bitStart & 7;
    final fieldByteOffset = _packedBase + byteOff;
    final ps = _PackedBoolStorage(
      s,
      byteOff,
      bitOff,
      fieldByteOffset,
      initialValue: initialValue ? true : null,
    );
    _fieldStorages.add(ps);
    return _PackedBoolField(ps);
  }

  @override
  Field<int> newUint2({int initialValue = 0}) =>
      _newPacked(2, 0x3, 0, initialValue: initialValue);

  @override
  Field<int> newInt2({int initialValue = 0}) =>
      _newPacked(2, 0x3, 0x2, initialValue: initialValue);

  @override
  Field<int> newUint4({int initialValue = 0}) =>
      _newPacked(4, 0xF, 0, initialValue: initialValue);

  @override
  Field<int> newInt4({int initialValue = 0}) =>
      _newPacked(4, 0xF, 0x8, initialValue: initialValue);

  // ---- nullable helper: lazy _NullTagStorage ----

  _NullTagStorage? _nullTags;

  _NullTagStorage _nullTagStorage() {
    if (_nullTags == null) {
      _nullTags = _NullTagStorage(_initialCapacity);
      _storages.add(_nullTags!);
    }
    return _nullTags!;
  }

  // ---- Form 1: interleaved double-stride helpers ----

  _NullableInterleavedStorage<N, L>
  _registerInterleaved<N extends num, L extends List<N>>(
    L Function(int) create,
    int valueSize,
    N zeroTag,
    N oneTag,
    void Function(ByteData bd, int offset, N v) writeBytesImpl,
    N Function(ByteData bd, int offset) readBytesImpl, {
    N? initialValue,
  }) {
    final elementSize = valueSize * 2;
    final byteOffset = _nextByteOffset;
    _nextByteOffset += elementSize;
    final storage = _NullableInterleavedStorage<N, L>(
      _initialCapacity,
      create,
      byteOffset,
      elementSize,
      valueSize,
      zeroTag,
      oneTag,
      writeBytesImpl,
      readBytesImpl,
      initialValue: initialValue,
    );
    _storages.add(storage);
    _fieldStorages.add(storage);
    return storage;
  }

  Field<int?> _makeInterleavedField<N extends int, L extends List<N>>(
    L Function(int) create,
    int valueSize,
    void Function(ByteData bd, int offset, N v) writeBytesImpl,
    N Function(ByteData bd, int offset) readBytesImpl, {
    int? initialValue,
  }) {
    final s = _registerInterleaved<N, L>(
      create,
      valueSize,
      0 as N,
      1 as N,
      writeBytesImpl,
      readBytesImpl,
      initialValue: initialValue != null ? initialValue as N : null,
    );
    return _NullableField<int>(s);
  }

  // ---- Form 2: stolen-bit sentinel helpers ----

  _StolenBitStorage<N, L> _registerStolenBit<N extends num, L extends List<N>>(
    L Function(int) create,
    int elementSize,
    N sentinel,
    void Function(ByteData bd, int offset, N v) writeBytesImpl,
    N Function(ByteData bd, int offset) readBytesImpl, {
    int? initialValue,
  }) {
    final byteOffset = _nextByteOffset;
    _nextByteOffset += elementSize;
    final storage = _StolenBitStorage<N, L>(
      _initialCapacity,
      create,
      byteOffset,
      elementSize,
      sentinel,
      writeBytesImpl,
      readBytesImpl,
      initialValue: initialValue != null ? initialValue as N : null,
    );
    _storages.add(storage);
    _fieldStorages.add(storage);
    return storage;
  }

  // ---- Form 3: tagged helpers ----

  _TaggedStorage<N, L> _registerTagged<N extends num, L extends List<N>>(
    L Function(int) create,
    int valueSize,
    void Function(ByteData bd, int offset, N v) writeBytesImpl,
    N Function(ByteData bd, int offset) readBytesImpl, {
    Object? initialValue,
  }) {
    final nullTags = _nullTagStorage();
    final tagBitIndex = nullTags.reserveTag();
    final byteOffset = _nextByteOffset;
    _nextByteOffset += valueSize + 1;
    final storage = _TaggedStorage<N, L>(
      _initialCapacity,
      create,
      byteOffset,
      valueSize + 1,
      valueSize,
      nullTags,
      tagBitIndex,
      writeBytesImpl,
      readBytesImpl,
      initialValue: initialValue,
    );
    _storages.add(storage);
    _fieldStorages.add(storage);
    return storage;
  }

  // ---- Form 1 packed nullable ----

  Field<int?> _newPackedNullable(
    int width,
    int mask,
    int signBit, {
    int? initialValue,
  }) {
    final s = _packedStorage();
    final blockStart = s.reserveBits(2 * width);
    _syncPackedOffset();
    final byteOff = blockStart >> 3;
    final valueBitOff = blockStart & 7;
    final tagBitOff = (blockStart + width) & 7;
    final fieldByteOffset = _packedBase + byteOff;
    final ps = _NullablePackedStorage(
      s,
      byteOff,
      valueBitOff,
      mask,
      signBit,
      tagBitOff,
      mask,
      fieldByteOffset,
      initialValue: initialValue,
    );
    _fieldStorages.add(ps);
    return _NullableField<int>(ps);
  }

  Field<bool?> _newPackedBoolNullable({bool? initialValue}) {
    final s = _packedStorage();
    final blockStart = s.reserveBits(2);
    _syncPackedOffset();
    final byteOff = blockStart >> 3;
    final valueBitOff = blockStart & 7;
    final tagBitOff = (blockStart + 1) & 7;
    final fieldByteOffset = _packedBase + byteOff;
    final ps = _NullablePackedBoolStorage(
      s,
      byteOff,
      valueBitOff,
      tagBitOff,
      fieldByteOffset,
      initialValue: initialValue,
    );
    _fieldStorages.add(ps);
    return _NullableField<bool>(ps);
  }

  // ---- Form 1: newXNullable (interleaved double-stride, int only) ----

  @override
  Field<int?> newInt8Nullable({int? initialValue}) =>
      _makeInterleavedField<int, Int8List>(
        (n) => Int8List(n),
        1,
        (bd, o, v) => bd.setInt8(o, v),
        (bd, o) => bd.getInt8(o),
        initialValue: initialValue,
      );

  @override
  Field<int?> newInt16Nullable({int? initialValue}) =>
      _makeInterleavedField<int, Int16List>(
        (n) => Int16List(n),
        2,
        (bd, o, v) => bd.setInt16(o, v),
        (bd, o) => bd.getInt16(o),
        initialValue: initialValue,
      );

  @override
  Field<int?> newInt32Nullable({int? initialValue}) =>
      _makeInterleavedField<int, Int32List>(
        (n) => Int32List(n),
        4,
        (bd, o, v) => bd.setInt32(o, v),
        (bd, o) => bd.getInt32(o),
        initialValue: initialValue,
      );

  @override
  Field<int?> newInt64Nullable({int? initialValue}) =>
      _makeInterleavedField<int, Int64List>(
        (n) => Int64List(n),
        8,
        (bd, o, v) => bd.setInt64(o, v),
        (bd, o) => bd.getInt64(o),
        initialValue: initialValue,
      );

  @override
  Field<int?> newUint8Nullable({int? initialValue}) =>
      _makeInterleavedField<int, Uint8List>(
        (n) => Uint8List(n),
        1,
        (bd, o, v) => bd.setUint8(o, v),
        (bd, o) => bd.getUint8(o),
        initialValue: initialValue,
      );

  @override
  Field<int?> newUint16Nullable({int? initialValue}) =>
      _makeInterleavedField<int, Uint16List>(
        (n) => Uint16List(n),
        2,
        (bd, o, v) => bd.setUint16(o, v),
        (bd, o) => bd.getUint16(o),
        initialValue: initialValue,
      );

  @override
  Field<int?> newUint32Nullable({int? initialValue}) =>
      _makeInterleavedField<int, Uint32List>(
        (n) => Uint32List(n),
        4,
        (bd, o, v) => bd.setUint32(o, v),
        (bd, o) => bd.getUint32(o),
        initialValue: initialValue,
      );

  @override
  Field<int?> newUint64Nullable({int? initialValue}) =>
      _makeInterleavedField<int, Uint64List>(
        (n) => Uint64List(n),
        8,
        (bd, o, v) => bd.setUint64(o, v),
        (bd, o) => bd.getUint64(o),
        initialValue: initialValue,
      );

  @override
  Field<int?> newBitNullable({int? initialValue}) =>
      _newPackedNullable(1, 0x1, 0, initialValue: initialValue);
  @override
  Field<int?> newInt2Nullable({int? initialValue}) =>
      _newPackedNullable(2, 0x3, 0x2, initialValue: initialValue);
  @override
  Field<int?> newUint2Nullable({int? initialValue}) =>
      _newPackedNullable(2, 0x3, 0, initialValue: initialValue);
  @override
  Field<int?> newInt4Nullable({int? initialValue}) =>
      _newPackedNullable(4, 0xF, 0x8, initialValue: initialValue);
  @override
  Field<int?> newUint4Nullable({int? initialValue}) =>
      _newPackedNullable(4, 0xF, 0, initialValue: initialValue);
  @override
  Field<bool?> newBoolNullable({bool? initialValue}) =>
      _newPackedBoolNullable(initialValue: initialValue);

  // ---- Form 2: newXMinusBitNullable (stolen-bit sentinel) ----

  @override
  Field<int?> newInt7Nullable({int? initialValue}) => _NullableField<int>(
    _registerStolenBit<int, Int8List>(
      (n) => Int8List(n),
      1,
      -128,
      (bd, o, v) => bd.setInt8(o, v),
      (bd, o) => bd.getInt8(o),
      initialValue: initialValue,
    ),
  );

  @override
  Field<int?> newInt15Nullable({int? initialValue}) => _NullableField<int>(
    _registerStolenBit<int, Int16List>(
      (n) => Int16List(n),
      2,
      -32768,
      (bd, o, v) => bd.setInt16(o, v),
      (bd, o) => bd.getInt16(o),
      initialValue: initialValue,
    ),
  );

  @override
  Field<int?> newInt31Nullable({int? initialValue}) => _NullableField<int>(
    _registerStolenBit<int, Int32List>(
      (n) => Int32List(n),
      4,
      -2147483648,
      (bd, o, v) => bd.setInt32(o, v),
      (bd, o) => bd.getInt32(o),
      initialValue: initialValue,
    ),
  );

  @override
  Field<int?> newInt63Nullable({int? initialValue}) => _NullableField<int>(
    _registerStolenBit<int, Int64List>(
      (n) => Int64List(n),
      8,
      -9223372036854775808,
      (bd, o, v) => bd.setInt64(o, v),
      (bd, o) => bd.getInt64(o),
      initialValue: initialValue,
    ),
  );

  @override
  Field<int?> newUint7Nullable({int? initialValue}) => _NullableField<int>(
    _registerStolenBit<int, Uint8List>(
      (n) => Uint8List(n),
      1,
      255,
      (bd, o, v) => bd.setUint8(o, v),
      (bd, o) => bd.getUint8(o),
      initialValue: initialValue,
    ),
  );

  @override
  Field<int?> newUint15Nullable({int? initialValue}) => _NullableField<int>(
    _registerStolenBit<int, Uint16List>(
      (n) => Uint16List(n),
      2,
      65535,
      (bd, o, v) => bd.setUint16(o, v),
      (bd, o) => bd.getUint16(o),
      initialValue: initialValue,
    ),
  );

  @override
  Field<int?> newUint31Nullable({int? initialValue}) => _NullableField<int>(
    _registerStolenBit<int, Uint32List>(
      (n) => Uint32List(n),
      4,
      4294967295,
      (bd, o, v) => bd.setUint32(o, v),
      (bd, o) => bd.getUint32(o),
      initialValue: initialValue,
    ),
  );

  @override
  Field<int?> newUint63Nullable({int? initialValue}) => _NullableField<int>(
    _registerStolenBit<int, Uint64List>(
      (n) => Uint64List(n),
      8,
      -1,
      (bd, o, v) => bd.setUint64(o, v),
      (bd, o) => bd.getUint64(o),
      initialValue: initialValue,
    ),
  );

  // ---- Form 3: newXTagged (bit-tagged; pool=_NullTagStorage, capture=flag byte) ----

  @override
  Field<int?> newInt8Tagged({int? initialValue}) => _NullableField<int>(
    _registerTagged<int, Int8List>(
      (n) => Int8List(n),
      1,
      (bd, o, v) => bd.setInt8(o, v),
      (bd, o) => bd.getInt8(o),
      initialValue: initialValue,
    ),
  );

  @override
  Field<int?> newInt16Tagged({int? initialValue}) => _NullableField<int>(
    _registerTagged<int, Int16List>(
      (n) => Int16List(n),
      2,
      (bd, o, v) => bd.setInt16(o, v),
      (bd, o) => bd.getInt16(o),
      initialValue: initialValue,
    ),
  );

  @override
  Field<int?> newInt32Tagged({int? initialValue}) => _NullableField<int>(
    _registerTagged<int, Int32List>(
      (n) => Int32List(n),
      4,
      (bd, o, v) => bd.setInt32(o, v),
      (bd, o) => bd.getInt32(o),
      initialValue: initialValue,
    ),
  );

  @override
  Field<int?> newInt64Tagged({int? initialValue}) => _NullableField<int>(
    _registerTagged<int, Int64List>(
      (n) => Int64List(n),
      8,
      (bd, o, v) => bd.setInt64(o, v),
      (bd, o) => bd.getInt64(o),
      initialValue: initialValue,
    ),
  );

  @override
  Field<int?> newUint8Tagged({int? initialValue}) => _NullableField<int>(
    _registerTagged<int, Uint8List>(
      (n) => Uint8List(n),
      1,
      (bd, o, v) => bd.setUint8(o, v),
      (bd, o) => bd.getUint8(o),
      initialValue: initialValue,
    ),
  );

  @override
  Field<int?> newUint16Tagged({int? initialValue}) => _NullableField<int>(
    _registerTagged<int, Uint16List>(
      (n) => Uint16List(n),
      2,
      (bd, o, v) => bd.setUint16(o, v),
      (bd, o) => bd.getUint16(o),
      initialValue: initialValue,
    ),
  );

  @override
  Field<int?> newUint32Tagged({int? initialValue}) => _NullableField<int>(
    _registerTagged<int, Uint32List>(
      (n) => Uint32List(n),
      4,
      (bd, o, v) => bd.setUint32(o, v),
      (bd, o) => bd.getUint32(o),
      initialValue: initialValue,
    ),
  );

  @override
  Field<int?> newUint64Tagged({int? initialValue}) => _NullableField<int>(
    _registerTagged<int, Uint64List>(
      (n) => Uint64List(n),
      8,
      (bd, o, v) => bd.setUint64(o, v),
      (bd, o) => bd.getUint64(o),
      initialValue: initialValue,
    ),
  );

  @override
  Field<double?> newFloat32Tagged({double? initialValue}) =>
      _NullableField<double>(
        _registerTagged<double, Float32List>(
          (n) => Float32List(n),
          4,
          (bd, o, v) => bd.setFloat32(o, v),
          (bd, o) => bd.getFloat32(o),
          initialValue: initialValue,
        ),
      );

  @override
  Field<double?> newFloat64Tagged({double? initialValue}) =>
      _NullableField<double>(
        _registerTagged<double, Float64List>(
          (n) => Float64List(n),
          8,
          (bd, o, v) => bd.setFloat64(o, v),
          (bd, o) => bd.getFloat64(o),
          initialValue: initialValue,
        ),
      );

  @override
  Field<bool?> newBoolTagged({bool? initialValue}) {
    final nullTags = _nullTagStorage();
    final tagBitIndex = nullTags.reserveTag();
    final byteOffset = _nextByteOffset;
    _nextByteOffset += 2; // 1 value byte + 1 flag byte
    final storage = _BoolTaggedStorage(
      _initialCapacity,
      byteOffset,
      nullTags,
      tagBitIndex,
      initialValue: initialValue,
    );
    _storages.add(storage);
    _fieldStorages.add(storage);
    return _NullableField<bool>(storage);
  }

  @override
  Field<int?> newBitTagged({int? initialValue}) => _NullableField<int>(
    _registerTagged<int, Uint8List>(
      (n) => Uint8List(n),
      1,
      (bd, o, v) => bd.setUint8(o, v),
      (bd, o) => bd.getUint8(o),
      initialValue: initialValue,
    ),
  );

  @override
  Field<int?> newInt2Tagged({int? initialValue}) => _NullableField<int>(
    _registerTagged<int, Int8List>(
      (n) => Int8List(n),
      1,
      (bd, o, v) => bd.setInt8(o, v),
      (bd, o) => bd.getInt8(o),
      initialValue: initialValue,
    ),
  );

  @override
  Field<int?> newUint2Tagged({int? initialValue}) => _NullableField<int>(
    _registerTagged<int, Uint8List>(
      (n) => Uint8List(n),
      1,
      (bd, o, v) => bd.setUint8(o, v),
      (bd, o) => bd.getUint8(o),
      initialValue: initialValue,
    ),
  );

  @override
  Field<int?> newInt4Tagged({int? initialValue}) => _NullableField<int>(
    _registerTagged<int, Int8List>(
      (n) => Int8List(n),
      1,
      (bd, o, v) => bd.setInt8(o, v),
      (bd, o) => bd.getInt8(o),
      initialValue: initialValue,
    ),
  );

  @override
  Field<int?> newUint4Tagged({int? initialValue}) => _NullableField<int>(
    _registerTagged<int, Uint8List>(
      (n) => Uint8List(n),
      1,
      (bd, o, v) => bd.setUint8(o, v),
      (bd, o) => bd.getUint8(o),
      initialValue: initialValue,
    ),
  );

  // ---- typed-array list field helpers ----

  Field<L> _registerList<L extends TypedData>({
    required int count,
    required int elementSize,
    required bool returnView,
    required L? initialValue,
    required L Function(Uint8List, int, int) view,
    required L Function(L) copy,
    required int alignTo,
  }) {
    if (alignTo > 1) {
      _nextByteOffset = (_nextByteOffset + alignTo - 1) & ~(alignTo - 1);
    }
    final bl = count * elementSize;
    final byteOffset = _nextByteOffset;
    _nextByteOffset += bl;
    final storage = _ByteDataStorage(_initialCapacity, bl);
    _storages.add(storage);
    final fs = _ListStorage<L>(
      storage: storage,
      byteOffset: byteOffset,
      count: count,
      elementSize: elementSize,
      returnView: returnView,
      initialValue: initialValue,
      view: view,
      copy: copy,
    );
    _fieldStorages.add(fs);
    return _ListField<L>(fs);
  }

  Field<L?> _registerNullableList<L extends TypedData>({
    required int count,
    required int elementSize,
    required bool returnView,
    required L? initialValue,
    required L Function(Uint8List, int, int) view,
    required L Function(L) copy,
    required int alignTo,
  }) {
    if (alignTo > 1) {
      _nextByteOffset = (_nextByteOffset + alignTo - 1) & ~(alignTo - 1);
    }
    final bl = count * elementSize;
    final byteOffset = _nextByteOffset;
    _nextByteOffset += 1 + bl;
    final storage = _ByteDataStorage(_initialCapacity, bl);
    _storages.add(storage);
    final nullTags = _nullTagStorage();
    final tagBitIndex = nullTags.reserveTag();
    final fs = _NullableListStorage<L>(
      storage: storage,
      byteOffset: byteOffset,
      count: count,
      elementSize: elementSize,
      returnView: returnView,
      initialValue: initialValue,
      nullTags: nullTags,
      tagBitIndex: tagBitIndex,
      view: view,
      copy: copy,
    );
    _fieldStorages.add(fs);
    return _NullableListField<L>(fs);
  }

  // ---- Int8List ----
  @override
  Field<Int8List> newInt8ListView(int n, {Int8List? initialValue}) =>
      _registerList(
        count: n,
        elementSize: 1,
        returnView: true,
        initialValue: initialValue,
        view: (b, s, e) => Int8List.sublistView(b, s, e),
        copy: (v) => Int8List.fromList(v),
        alignTo: 1,
      );
  @override
  Field<Int8List> newInt8List(int n, {Int8List? initialValue}) => _registerList(
    count: n,
    elementSize: 1,
    returnView: false,
    initialValue: initialValue,
    view: (b, s, e) => Int8List.sublistView(b, s, e),
    copy: (v) => Int8List.fromList(v),
    alignTo: 1,
  );
  @override
  Field<Int8List?> newInt8ListViewNullable(int n, {Int8List? initialValue}) =>
      _registerNullableList(
        count: n,
        elementSize: 1,
        returnView: true,
        initialValue: initialValue,
        view: (b, s, e) => Int8List.sublistView(b, s, e),
        copy: (v) => Int8List.fromList(v),
        alignTo: 1,
      );
  @override
  Field<Int8List?> newInt8ListNullable(int n, {Int8List? initialValue}) =>
      _registerNullableList(
        count: n,
        elementSize: 1,
        returnView: false,
        initialValue: initialValue,
        view: (b, s, e) => Int8List.sublistView(b, s, e),
        copy: (v) => Int8List.fromList(v),
        alignTo: 1,
      );

  // ---- Int16List ----
  @override
  Field<Int16List> newInt16ListView(int n, {Int16List? initialValue}) =>
      _registerList(
        count: n,
        elementSize: 2,
        returnView: true,
        initialValue: initialValue,
        view: (b, s, e) => Int16List.sublistView(b, s, e),
        copy: (v) => Int16List.fromList(v),
        alignTo: 2,
      );
  @override
  Field<Int16List> newInt16List(int n, {Int16List? initialValue}) =>
      _registerList(
        count: n,
        elementSize: 2,
        returnView: false,
        initialValue: initialValue,
        view: (b, s, e) => Int16List.sublistView(b, s, e),
        copy: (v) => Int16List.fromList(v),
        alignTo: 2,
      );
  @override
  Field<Int16List?> newInt16ListViewNullable(
    int n, {
    Int16List? initialValue,
  }) => _registerNullableList(
    count: n,
    elementSize: 2,
    returnView: true,
    initialValue: initialValue,
    view: (b, s, e) => Int16List.sublistView(b, s, e),
    copy: (v) => Int16List.fromList(v),
    alignTo: 2,
  );
  @override
  Field<Int16List?> newInt16ListNullable(int n, {Int16List? initialValue}) =>
      _registerNullableList(
        count: n,
        elementSize: 2,
        returnView: false,
        initialValue: initialValue,
        view: (b, s, e) => Int16List.sublistView(b, s, e),
        copy: (v) => Int16List.fromList(v),
        alignTo: 2,
      );

  // ---- Int32List ----
  @override
  Field<Int32List> newInt32ListView(int n, {Int32List? initialValue}) =>
      _registerList(
        count: n,
        elementSize: 4,
        returnView: true,
        initialValue: initialValue,
        view: (b, s, e) => Int32List.sublistView(b, s, e),
        copy: (v) => Int32List.fromList(v),
        alignTo: 4,
      );
  @override
  Field<Int32List> newInt32List(int n, {Int32List? initialValue}) =>
      _registerList(
        count: n,
        elementSize: 4,
        returnView: false,
        initialValue: initialValue,
        view: (b, s, e) => Int32List.sublistView(b, s, e),
        copy: (v) => Int32List.fromList(v),
        alignTo: 4,
      );
  @override
  Field<Int32List?> newInt32ListViewNullable(
    int n, {
    Int32List? initialValue,
  }) => _registerNullableList(
    count: n,
    elementSize: 4,
    returnView: true,
    initialValue: initialValue,
    view: (b, s, e) => Int32List.sublistView(b, s, e),
    copy: (v) => Int32List.fromList(v),
    alignTo: 4,
  );
  @override
  Field<Int32List?> newInt32ListNullable(int n, {Int32List? initialValue}) =>
      _registerNullableList(
        count: n,
        elementSize: 4,
        returnView: false,
        initialValue: initialValue,
        view: (b, s, e) => Int32List.sublistView(b, s, e),
        copy: (v) => Int32List.fromList(v),
        alignTo: 4,
      );

  // ---- Int64List ----
  @override
  Field<Int64List> newInt64ListView(int n, {Int64List? initialValue}) =>
      _registerList(
        count: n,
        elementSize: 8,
        returnView: true,
        initialValue: initialValue,
        view: (b, s, e) => Int64List.sublistView(b, s, e),
        copy: (v) => Int64List.fromList(v),
        alignTo: 8,
      );
  @override
  Field<Int64List> newInt64List(int n, {Int64List? initialValue}) =>
      _registerList(
        count: n,
        elementSize: 8,
        returnView: false,
        initialValue: initialValue,
        view: (b, s, e) => Int64List.sublistView(b, s, e),
        copy: (v) => Int64List.fromList(v),
        alignTo: 8,
      );
  @override
  Field<Int64List?> newInt64ListViewNullable(
    int n, {
    Int64List? initialValue,
  }) => _registerNullableList(
    count: n,
    elementSize: 8,
    returnView: true,
    initialValue: initialValue,
    view: (b, s, e) => Int64List.sublistView(b, s, e),
    copy: (v) => Int64List.fromList(v),
    alignTo: 8,
  );
  @override
  Field<Int64List?> newInt64ListNullable(int n, {Int64List? initialValue}) =>
      _registerNullableList(
        count: n,
        elementSize: 8,
        returnView: false,
        initialValue: initialValue,
        view: (b, s, e) => Int64List.sublistView(b, s, e),
        copy: (v) => Int64List.fromList(v),
        alignTo: 8,
      );

  // ---- Uint8List ----
  @override
  Field<Uint8List> newUint8ListView(int n, {Uint8List? initialValue}) =>
      _registerList(
        count: n,
        elementSize: 1,
        returnView: true,
        initialValue: initialValue,
        view: (b, s, e) => Uint8List.sublistView(b, s, e),
        copy: (v) => Uint8List.fromList(v),
        alignTo: 1,
      );
  @override
  Field<Uint8List> newUint8List(int n, {Uint8List? initialValue}) =>
      _registerList(
        count: n,
        elementSize: 1,
        returnView: false,
        initialValue: initialValue,
        view: (b, s, e) => Uint8List.sublistView(b, s, e),
        copy: (v) => Uint8List.fromList(v),
        alignTo: 1,
      );
  @override
  Field<Uint8List?> newUint8ListViewNullable(
    int n, {
    Uint8List? initialValue,
  }) => _registerNullableList(
    count: n,
    elementSize: 1,
    returnView: true,
    initialValue: initialValue,
    view: (b, s, e) => Uint8List.sublistView(b, s, e),
    copy: (v) => Uint8List.fromList(v),
    alignTo: 1,
  );
  @override
  Field<Uint8List?> newUint8ListNullable(int n, {Uint8List? initialValue}) =>
      _registerNullableList(
        count: n,
        elementSize: 1,
        returnView: false,
        initialValue: initialValue,
        view: (b, s, e) => Uint8List.sublistView(b, s, e),
        copy: (v) => Uint8List.fromList(v),
        alignTo: 1,
      );

  // ---- Uint16List ----
  @override
  Field<Uint16List> newUint16ListView(int n, {Uint16List? initialValue}) =>
      _registerList(
        count: n,
        elementSize: 2,
        returnView: true,
        initialValue: initialValue,
        view: (b, s, e) => Uint16List.sublistView(b, s, e),
        copy: (v) => Uint16List.fromList(v),
        alignTo: 2,
      );
  @override
  Field<Uint16List> newUint16List(int n, {Uint16List? initialValue}) =>
      _registerList(
        count: n,
        elementSize: 2,
        returnView: false,
        initialValue: initialValue,
        view: (b, s, e) => Uint16List.sublistView(b, s, e),
        copy: (v) => Uint16List.fromList(v),
        alignTo: 2,
      );
  @override
  Field<Uint16List?> newUint16ListViewNullable(
    int n, {
    Uint16List? initialValue,
  }) => _registerNullableList(
    count: n,
    elementSize: 2,
    returnView: true,
    initialValue: initialValue,
    view: (b, s, e) => Uint16List.sublistView(b, s, e),
    copy: (v) => Uint16List.fromList(v),
    alignTo: 2,
  );
  @override
  Field<Uint16List?> newUint16ListNullable(int n, {Uint16List? initialValue}) =>
      _registerNullableList(
        count: n,
        elementSize: 2,
        returnView: false,
        initialValue: initialValue,
        view: (b, s, e) => Uint16List.sublistView(b, s, e),
        copy: (v) => Uint16List.fromList(v),
        alignTo: 2,
      );

  // ---- Uint32List ----
  @override
  Field<Uint32List> newUint32ListView(int n, {Uint32List? initialValue}) =>
      _registerList(
        count: n,
        elementSize: 4,
        returnView: true,
        initialValue: initialValue,
        view: (b, s, e) => Uint32List.sublistView(b, s, e),
        copy: (v) => Uint32List.fromList(v),
        alignTo: 4,
      );
  @override
  Field<Uint32List> newUint32List(int n, {Uint32List? initialValue}) =>
      _registerList(
        count: n,
        elementSize: 4,
        returnView: false,
        initialValue: initialValue,
        view: (b, s, e) => Uint32List.sublistView(b, s, e),
        copy: (v) => Uint32List.fromList(v),
        alignTo: 4,
      );
  @override
  Field<Uint32List?> newUint32ListViewNullable(
    int n, {
    Uint32List? initialValue,
  }) => _registerNullableList(
    count: n,
    elementSize: 4,
    returnView: true,
    initialValue: initialValue,
    view: (b, s, e) => Uint32List.sublistView(b, s, e),
    copy: (v) => Uint32List.fromList(v),
    alignTo: 4,
  );
  @override
  Field<Uint32List?> newUint32ListNullable(int n, {Uint32List? initialValue}) =>
      _registerNullableList(
        count: n,
        elementSize: 4,
        returnView: false,
        initialValue: initialValue,
        view: (b, s, e) => Uint32List.sublistView(b, s, e),
        copy: (v) => Uint32List.fromList(v),
        alignTo: 4,
      );

  // ---- Uint64List ----
  @override
  Field<Uint64List> newUint64ListView(int n, {Uint64List? initialValue}) =>
      _registerList(
        count: n,
        elementSize: 8,
        returnView: true,
        initialValue: initialValue,
        view: (b, s, e) => Uint64List.sublistView(b, s, e),
        copy: (v) => Uint64List.fromList(v),
        alignTo: 8,
      );
  @override
  Field<Uint64List> newUint64List(int n, {Uint64List? initialValue}) =>
      _registerList(
        count: n,
        elementSize: 8,
        returnView: false,
        initialValue: initialValue,
        view: (b, s, e) => Uint64List.sublistView(b, s, e),
        copy: (v) => Uint64List.fromList(v),
        alignTo: 8,
      );
  @override
  Field<Uint64List?> newUint64ListViewNullable(
    int n, {
    Uint64List? initialValue,
  }) => _registerNullableList(
    count: n,
    elementSize: 8,
    returnView: true,
    initialValue: initialValue,
    view: (b, s, e) => Uint64List.sublistView(b, s, e),
    copy: (v) => Uint64List.fromList(v),
    alignTo: 8,
  );
  @override
  Field<Uint64List?> newUint64ListNullable(int n, {Uint64List? initialValue}) =>
      _registerNullableList(
        count: n,
        elementSize: 8,
        returnView: false,
        initialValue: initialValue,
        view: (b, s, e) => Uint64List.sublistView(b, s, e),
        copy: (v) => Uint64List.fromList(v),
        alignTo: 8,
      );

  // ---- Float32List ----
  @override
  Field<Float32List> newFloat32ListView(int n, {Float32List? initialValue}) =>
      _registerList(
        count: n,
        elementSize: 4,
        returnView: true,
        initialValue: initialValue,
        view: (b, s, e) => Float32List.sublistView(b, s, e),
        copy: (v) => Float32List.fromList(v),
        alignTo: 4,
      );
  @override
  Field<Float32List> newFloat32List(int n, {Float32List? initialValue}) =>
      _registerList(
        count: n,
        elementSize: 4,
        returnView: false,
        initialValue: initialValue,
        view: (b, s, e) => Float32List.sublistView(b, s, e),
        copy: (v) => Float32List.fromList(v),
        alignTo: 4,
      );
  @override
  Field<Float32List?> newFloat32ListViewNullable(
    int n, {
    Float32List? initialValue,
  }) => _registerNullableList(
    count: n,
    elementSize: 4,
    returnView: true,
    initialValue: initialValue,
    view: (b, s, e) => Float32List.sublistView(b, s, e),
    copy: (v) => Float32List.fromList(v),
    alignTo: 4,
  );
  @override
  Field<Float32List?> newFloat32ListNullable(
    int n, {
    Float32List? initialValue,
  }) => _registerNullableList(
    count: n,
    elementSize: 4,
    returnView: false,
    initialValue: initialValue,
    view: (b, s, e) => Float32List.sublistView(b, s, e),
    copy: (v) => Float32List.fromList(v),
    alignTo: 4,
  );

  // ---- Float64List ----
  @override
  Field<Float64List> newFloat64ListView(int n, {Float64List? initialValue}) =>
      _registerList(
        count: n,
        elementSize: 8,
        returnView: true,
        initialValue: initialValue,
        view: (b, s, e) => Float64List.sublistView(b, s, e),
        copy: (v) => Float64List.fromList(v),
        alignTo: 8,
      );
  @override
  Field<Float64List> newFloat64List(int n, {Float64List? initialValue}) =>
      _registerList(
        count: n,
        elementSize: 8,
        returnView: false,
        initialValue: initialValue,
        view: (b, s, e) => Float64List.sublistView(b, s, e),
        copy: (v) => Float64List.fromList(v),
        alignTo: 8,
      );
  @override
  Field<Float64List?> newFloat64ListViewNullable(
    int n, {
    Float64List? initialValue,
  }) => _registerNullableList(
    count: n,
    elementSize: 8,
    returnView: true,
    initialValue: initialValue,
    view: (b, s, e) => Float64List.sublistView(b, s, e),
    copy: (v) => Float64List.fromList(v),
    alignTo: 8,
  );
  @override
  Field<Float64List?> newFloat64ListNullable(
    int n, {
    Float64List? initialValue,
  }) => _registerNullableList(
    count: n,
    elementSize: 8,
    returnView: false,
    initialValue: initialValue,
    view: (b, s, e) => Float64List.sublistView(b, s, e),
    copy: (v) => Float64List.fromList(v),
    alignTo: 8,
  );
}

// ---------------------------------------------------------------------------
// MemoryPool
// ---------------------------------------------------------------------------

typedef _TypeEntry = ({
  _ComponentDataDescriptor descriptor,
  EntityData singleton,
  int bitIndex,
});

class MemoryPool {
  static const int _initialCapacity = 64;
  static const int _initialFreeCapacity = 16;
  static const int growthFactor = 2;

  final int _bitmaskWords;
  final int _stride;

  Int64List _entities;
  Int32List _freeStack = Int32List(_initialFreeCapacity);
  int _freeTop = 0;

  int _count = 0;
  int _capacity = _initialCapacity;

  final Map<Type, _TypeEntry> _types = {};
  int _nextBitIndex = 0;

  MemoryPool({int bitmaskWords = 2})
    : _bitmaskWords = bitmaskWords,
      _stride = 1 + bitmaskWords,
      _entities = Int64List(_initialCapacity * (1 + bitmaskWords));

  int get count => _count;
  int get bitmaskWords => _bitmaskWords;

  Int64List get rawEntities => _entities;
  int get stride => _stride;

  @pragma('vm:prefer-inline')
  int bitIndexOf(Type type) => _types[type]!.bitIndex;

  @pragma('vm:prefer-inline')
  int? tryBitIndexOf(Type type) => _types[type]?.bitIndex;

  @pragma('vm:prefer-inline')
  int generationAt(int slot) => _entities[slot * _stride];

  @pragma('vm:prefer-inline')
  bool isAlive(int slot) => _entities[slot * _stride] >= 0;

  Type ensureDescribedRuntime(DataFactory factory) {
    final singleton = factory();
    final type = singleton.runtimeType;
    if (_types.containsKey(type)) return type;

    final bit = _nextBitIndex++;
    assert(
      bit < _bitmaskWords * 64,
      'Component type limit exceeded: bitmaskWords=$_bitmaskWords allows ${_bitmaskWords * 64} types',
    );
    entityDataAssignBitmask(singleton, bit);
    final descriptor = _ComponentDataDescriptor(_capacity);
    singleton.describe(descriptor);
    _types[type] = (
      descriptor: descriptor,
      singleton: singleton,
      bitIndex: bit,
    );
    return type;
  }

  @pragma('vm:prefer-inline')
  T getSingleton<T extends EntityData>() => _types[T]!.singleton as T;

  EntityData getSingletonByType(Type type) => _types[type]!.singleton;

  int _allocateSlot() {
    int slot;
    if (_freeTop > 0) {
      slot = _freeStack[--_freeTop];
      _entities[slot * _stride] = -_entities[slot * _stride];
    } else {
      slot = _count++;
      if (slot >= _capacity) _grow();
      if (_entities[slot * _stride] < 0) {
        _entities[slot * _stride] = -_entities[slot * _stride];
      }
    }
    _clearAllBits(slot);
    return slot;
  }

  int allocate(List<Type> componentTypes) {
    final slot = _allocateSlot();
    for (final type in componentTypes) {
      _setBit(slot, _types[type]!.bitIndex);
      _types[type]!.descriptor.initSlot(slot);
    }
    return slot;
  }

  int allocateWithBits(Int64List buf, int wordOffset) {
    final slot = _allocateSlot();
    for (int w = 0; w < _bitmaskWords; w++) {
      _entities[slot * _stride + 1 + w] |= buf[wordOffset + w];
    }
    for (final entry in _types.values) {
      final bit = entry.bitIndex;
      if ((buf[wordOffset + (bit >> 6)] & (1 << (bit & 63))) != 0) {
        entry.descriptor.initSlot(slot);
      }
    }
    return slot;
  }

  // allocateWithBits variant that skips initSlot for types covered by init data
  // (those types are unpacked from the buffer directly after allocation).
  int allocateWithBitsAndInit(
    Int64List buf,
    int wordOffset,
    Int64List initBitmaskBuf,
    int initBitmaskOffset,
  ) {
    final slot = _allocateSlot();
    for (int w = 0; w < _bitmaskWords; w++) {
      _entities[slot * _stride + 1 + w] |= buf[wordOffset + w];
    }
    for (final entry in _types.values) {
      final bit = entry.bitIndex;
      if ((buf[wordOffset + (bit >> 6)] & (1 << (bit & 63))) == 0) continue;
      // Skip initSlot for types that have captured init data.
      if ((initBitmaskBuf[initBitmaskOffset + (bit >> 6)] &
              (1 << (bit & 63))) !=
          0) {
        continue;
      }
      entry.descriptor.initSlot(slot);
    }
    return slot;
  }

  void addBits(int slot, Int64List buf, int wordOffset) {
    for (int w = 0; w < _bitmaskWords; w++) {
      _entities[slot * _stride + 1 + w] |= buf[wordOffset + w];
    }
    for (final entry in _types.values) {
      final bit = entry.bitIndex;
      if ((buf[wordOffset + (bit >> 6)] & (1 << (bit & 63))) != 0) {
        entry.descriptor.initSlot(slot);
      }
    }
  }

  void addBitsAndInit(
    int slot,
    Int64List buf,
    int wordOffset,
    Int64List initBitmaskBuf,
    int initBitmaskOffset,
  ) {
    for (int w = 0; w < _bitmaskWords; w++) {
      _entities[slot * _stride + 1 + w] |= buf[wordOffset + w];
    }
    for (final entry in _types.values) {
      final bit = entry.bitIndex;
      if ((buf[wordOffset + (bit >> 6)] & (1 << (bit & 63))) == 0) continue;
      if ((initBitmaskBuf[initBitmaskOffset + (bit >> 6)] &
              (1 << (bit & 63))) !=
          0) {
        continue;
      }
      entry.descriptor.initSlot(slot);
    }
  }

  void removeBits(int slot, Int64List buf, int wordOffset) {
    for (int w = 0; w < _bitmaskWords; w++) {
      _entities[slot * _stride + 1 + w] &= ~buf[wordOffset + w];
    }
  }

  void free(int slot) {
    assert(isAlive(slot), 'Attempted to free already-dead slot $slot');
    final base = slot * _stride;
    _entities[base] = -(_entities[base] + 1);
    _clearAllBits(slot);

    if (slot == _count - 1) {
      _count--;
    } else {
      if (_freeTop >= _freeStack.length) {
        final next = Int32List(_freeStack.length * growthFactor);
        next.setRange(0, _freeStack.length, _freeStack);
        _freeStack = next;
      }
      _freeStack[_freeTop++] = slot;
    }
  }

  @pragma('vm:prefer-inline')
  bool hasComponent(int slot, Type type) {
    final entry = _types[type];
    if (entry == null) return false;
    final bit = entry.bitIndex;
    return (_entities[slot * _stride + 1 + (bit >> 6)] & (1 << (bit & 63))) !=
        0;
  }

  void addComponent(int slot, Type type) {
    _setBit(slot, _types[type]!.bitIndex);
    _types[type]!.descriptor.initSlot(slot);
  }

  void removeComponent(int slot, Type type) {
    final entry = _types[type];
    if (entry == null) return;
    _clearBit(slot, entry.bitIndex);
  }

  Set<Type> componentsOf(int slot) {
    final result = <Type>{};
    for (final entry in _types.entries) {
      if (hasComponent(slot, entry.key)) result.add(entry.key);
    }
    return result;
  }

  void compact() {
    final remap = <int, int>{};
    int dst = 0;
    for (int src = 0; src < _count; src++) {
      if (isAlive(src)) remap[src] = dst++;
    }
    final newCount = dst;
    if (newCount == _count) return;

    final newEntities = Int64List(_capacity * _stride);
    for (int i = newCount; i < _count; i++) {
      newEntities[i * _stride] = -1;
    }
    for (final e in remap.entries) {
      final srcBase = e.key * _stride;
      final dstBase = e.value * _stride;
      for (int w = 0; w < _stride; w++) {
        newEntities[dstBase + w] = _entities[srcBase + w];
      }
    }
    _entities = newEntities;

    for (final entry in _types.values) {
      entry.descriptor.compactAll(remap);
    }

    _freeTop = 0;
    _count = newCount;
  }

  @pragma('vm:prefer-inline')
  void _setBit(int slot, int bit) {
    _entities[slot * _stride + 1 + (bit >> 6)] |= (1 << (bit & 63));
  }

  @pragma('vm:prefer-inline')
  void _clearBit(int slot, int bit) {
    _entities[slot * _stride + 1 + (bit >> 6)] &= ~(1 << (bit & 63));
  }

  @pragma('vm:prefer-inline')
  void _clearAllBits(int slot) {
    final base = slot * _stride + 1;
    for (int w = 0; w < _bitmaskWords; w++) {
      _entities[base + w] = 0;
    }
  }

  // ---- init-capture helpers (used by command_buffer.dart via world.dart) ----

  /// Number of Int64 words needed to capture init data for [types].
  int initDataWordCount(Set<Type> types) {
    int total = 0;
    for (final kv in _types.entries) {
      if (types.contains(kv.key)) {
        total += (kv.value.descriptor.bytesPerSlot + 7) ~/ 8;
      }
    }
    return total;
  }

  /// Iterates [types] in registration order.
  /// For each type: zeros its capture region via [initBytes], stamps [buf] at
  /// [initBitmaskBase], then calls [callback] with (type, singleton, initByteBase)
  /// where [initByteBase] is the byte offset from start of [buf]'s data.
  void foreachInitType(
    Set<Type> types,
    Int64List buf,
    int initBitmaskBase,
    int initDataWordBase,
    void Function(Type type, EntityData singleton, int initByteBase) callback,
  ) {
    int wordOffset = 0;
    for (final kv in _types.entries) {
      if (!types.contains(kv.key)) continue;
      final entry = kv.value;
      final bit = entry.bitIndex;
      buf[initBitmaskBase + (bit >> 6)] |= (1 << (bit & 63));
      final initByteBase = (initDataWordBase + wordOffset) * 8;
      final bd = ByteData.view(buf.buffer, buf.offsetInBytes + initByteBase);
      entry.descriptor.initBytes(bd);
      callback(kv.key, entry.singleton, initByteBase);
      wordOffset += (entry.descriptor.bytesPerSlot + 7) ~/ 8;
    }
  }

  /// Unpacks captured init data from [buf] into pool storage at [slot].
  void unpackInitData(
    Int64List buf,
    int initBitmaskBase,
    int initDataWordBase,
    int slot,
  ) {
    int wordOffset = 0;
    for (final entry in _types.values) {
      final bit = entry.bitIndex;
      if ((buf[initBitmaskBase + (bit >> 6)] & (1 << (bit & 63))) == 0) {
        continue;
      }
      entry.descriptor.unpackFrom(buf, initDataWordBase + wordOffset, slot);
      wordOffset += (entry.descriptor.bytesPerSlot + 7) ~/ 8;
    }
  }

  void clearHeapCapture() {
    for (final entry in _types.values) {
      entry.descriptor.clearHeapCapture();
    }
  }

  void _grow() {
    final newCapacity = _capacity * growthFactor;
    final newEntities = Int64List(newCapacity * _stride);
    newEntities.setRange(0, _capacity * _stride, _entities);
    _entities = newEntities;

    for (final entry in _types.values) {
      entry.descriptor.growAll(newCapacity);
    }

    _capacity = newCapacity;
  }
}
