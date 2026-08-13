import 'package:meta/meta.dart';

/// Process-global table backing `DataDescriptor.hasHeapObject`/
/// `optHeapObject`: it hands an arbitrary Dart object a plain integer
/// address so a component row - which is native memory and cannot hold a
/// Dart heap pointer (RULES.md rule 1) - can refer to it as a `Uint32`.
///
/// The sibling of `GlobalObjectRegistry` (asset.dart), and deliberately
/// *not* the same table, for two reasons:
///
///  * **No `GlobalObject` requirement.** Entries here are ordinary objects -
///    a closure, a `List`, an instance of a class you don't own - that carry
///    no address of their own. `GlobalObjectRegistry` exists to hand out the
///    describe-time address a `GlobalObject` then remembers; nothing here
///    remembers anything, the address lives only in the row.
///  * **Real slot reuse.** `GlobalObjectRegistry` only ever appends and
///    nulls out, never reclaims an index - fine for assets, which are few
///    and long-lived. Heap-object fields are written dynamically at runtime,
///    so an append-only table would grow without bound. This one keeps an
///    explicit free list and reuses freed addresses.
///
/// Addresses are meaningful **only on the isolate that produced them**.
/// Two isolates running the same scene registration agree on every
/// `GlobalObject` address because both re-ran the same registration in the
/// same order; they agree on nothing here, because registration happens at
/// arbitrary times in response to whatever each isolate happened to write.
/// A heap-object field read from a second isolate is a bug, not a feature.
///
// TODO(despawn): nothing frees a heap-object slot when the entity holding
// its address is destroyed, because this engine has no despawn/entity
// destruction API yet (see ArchetypeStorage.allocateRow's note that
// "recycling across an archetype's older pages lands with the despawn API,
// which does not exist yet"). Until that lands, a row's heap-object slot is
// only reclaimed by an explicit `unregister` or by `reset`. When despawn
// arrives it must walk the destroyed row's heap-object fields and
// `unregister` each one; that hook is the missing half of this registry, and
// building it is out of scope here.
abstract final class HeapObjectRegistry {
  /// Marks a slot that is on the free list. A dedicated sentinel rather than
  /// `null`, because `null` is a value a caller may legitimately register -
  /// without this, "registered null" and "freed" would be indistinguishable
  /// and [unregister] could push the same address onto the free list twice,
  /// handing one slot to two different objects.
  static final Object _free = Object();

  static final List<Object?> _byAddress = <Object?>[];

  /// Addresses whose slots are free, newest first. A plain stack: [register]
  /// pops, [unregister] pushes, so a register/unregister/register cycle
  /// reuses one slot forever instead of growing the table.
  static final List<int> _freeAddresses = <int>[];

  /// The table and its free list, for `Game` to carry across the spawn - see
  /// `ComponentTypeRegistry.snapshot`. Closures are sendable; verified in
  /// `tool/spawn_registry_spike.dart`.
  @internal
  static List<Object?> snapshot() => List<Object?>.of(_byAddress);

  @internal
  static List<int> snapshotFree() => List<int>.of(_freeAddresses);

  @internal
  static void restore(List<Object?> byAddress, List<int> free) {
    _byAddress
      ..clear()
      ..addAll(byAddress);
    _freeAddresses
      ..clear()
      ..addAll(free);
  }

  /// Number of slots ever allocated, free ones included. Diagnostics and
  /// tests (a growing count across register/unregister cycles is the exact
  /// leak this registry exists to avoid).
  static int get slotCount => _byAddress.length;

  /// Registers [object] and returns the address a row should store.
  ///
  /// Reuses a freed address when one is available, otherwise appends.
  static int register(Object? object) {
    if (_freeAddresses.isNotEmpty) {
      final address = _freeAddresses.removeLast();
      _byAddress[address] = object;
      return address;
    }
    final address = _byAddress.length;
    _byAddress.add(object);
    return address;
  }

  /// Frees [address] for reuse and drops the strong reference held here.
  ///
  /// Idempotent and bounds-tolerant: unregistering an out-of-range or
  /// already-freed address does nothing, rather than corrupting the free
  /// list with a duplicate entry.
  static void unregister(int address) {
    if (address < 0 || address >= _byAddress.length) return;
    if (identical(_byAddress[address], _free)) return;
    _byAddress[address] = _free;
    _freeAddresses.add(address);
  }

  /// Resolves [address], or `null` if nothing is currently registered there
  /// (never registered, freed, or out of range) or the entry is not a [T].
  static T? tryResolve<T>(int address) {
    if (address < 0 || address >= _byAddress.length) return null;
    final object = _byAddress[address];
    if (identical(object, _free)) return null;
    return object is T ? object : null;
  }

  /// [tryResolve], but throws instead of returning `null` - what a
  /// non-nullable `hasHeapObject` read uses, matching
  /// `GlobalObjectRegistry.resolve`: a row holding a stale or
  /// never-registered address is a real bug worth failing loudly on.
  ///
  /// Written as an explicit `is!` test rather than `tryResolve(...) == null`
  /// so that registering a legitimate `null` under a nullable [T] resolves
  /// to `null` instead of throwing.
  static T resolve<T>(int address) {
    if (address < 0 || address >= _byAddress.length) {
      throw StateError(
        'No $T registered at heap object address $address - the address is '
        'outside the registry, so the row holds a stale or corrupt value.',
      );
    }
    final object = _byAddress[address];
    if (identical(object, _free) || object is! T) {
      throw StateError(
        'No $T registered at heap object address $address - it was either '
        'never registered on this isolate, has since been unregistered, or '
        'the row holds a stale/corrupt value. Note heap object addresses are '
        'isolate-local: a row written on another isolate will not resolve '
        'here.',
      );
    }
    return object;
  }

  /// Test-only escape hatch, matching `GlobalObjectRegistry.reset` /
  /// `ArchetypeRegistry.reset`: this registry is process-global, so a test
  /// suite registering many throwaway objects needs a way to start over.
  @visibleForTesting
  static void reset() {
    _byAddress.clear();
    _freeAddresses.clear();
  }
}
