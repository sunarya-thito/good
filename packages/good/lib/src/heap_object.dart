import 'package:meta/meta.dart';

/// Process-global table backing `DataDescriptor.hasHeapObject`/
/// `optHeapObject`: it hands an arbitrary Dart object a plain integer
/// address so a component row - which is native memory and cannot hold a
/// Dart heap pointer (the no-allocation rule) - can refer to it as a `Uint32`.
///
/// The sibling of an [IntRepresentation] such as the [Assets] table
/// (asset.dart), and *not* the same table, for two reasons:
///
///  * **No [IntRepresentable] requirement.** Entries here are ordinary
///    objects - a closure, a `List`, an instance of a class you don't own -
///    that cannot pack themselves into an int. An [IntRepresentation] pairs
///    every value in its population with an int and reads it back; nothing
///    here remembers anything, the address lives only in the row.
///  * **Real slot reuse.** [Assets] only ever appends and
///    nulls out, never reclaims an index - fine for assets, which are few
///    and long-lived. Heap-object fields are written dynamically at runtime,
///    so an append-only table would grow without bound. This one keeps an
///    explicit free list and reuses freed addresses.
///
/// Addresses are meaningful **only on the isolate that produced them**.
/// Two isolates running the same scene registration agree on every asset
/// address because both re-ran the same declarations in the same order;
/// they agree on nothing here, because registration happens at
/// arbitrary times in response to whatever each isolate happened to write.
/// A heap-object field read from a second isolate is a bug, not a feature.
///
/// # What frees a slot
///
/// Destroying an entity does, through `ArchetypeStorage.releaseHeapSlots`:
/// every path that stops a row being an entity - `Entity.destroy()` for one
/// entity or a subtree, and `SceneStruct.unmountEntitiesOf` for a scene coming
/// down or a game stopping - walks the row's heap-object fields and
/// [unregister]s each. A row that never wrote the field is left alone, because
/// it carries the one address `writeInitialValue` registered at seal time and every
/// other entity of that archetype is still reading it.
///
/// This carried a `TODO(despawn)` for a long time saying the leak was
/// acceptable *because* there was no way to destroy an entity. `destroy()`
/// arrived, the hook the comment asked for did not, and the comment kept
/// explaining why a now-live leak was fine (#49). It is the second stale
/// premise in this codebase to hide a leak - the first claimed there was no
/// per-entity destroy, and the change that trusted it leaked a Box2D body per
/// destroyed entity. A comment saying "this is safe because X" is a claim
/// about X that stops being true when X does.
///
/// What is still **not** freed is a slot orphaned by overwriting a field:
/// `field[e] = a; field[e] = b` leaks `a`'s slot until the entity dies, since
/// noticing the overwrite would need an identity map on the write path. That
/// one is a real trade and is documented on `_HeapObjectField`; a destroyed
/// entity releases whatever address its row holds at the end.
abstract final class HeapObjectRegistry {
  /// Marks a slot that is on the free list. A dedicated sentinel and not
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

  // No `snapshot`/`restore` here any more - see the note in
  // `ComponentTypeRegistry`. A heap object is registered by a row write, rows
  // are written only on the game isolate, and only that copy reads one back.

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
  /// already-freed address does nothing and never corrupts the free list with
  /// a duplicate entry.
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
  /// [IntRepresentation.unpack]: a row holding a stale or
  /// never-registered address is a real bug worth failing loudly on.
  ///
  /// Written as an explicit `is!` test, not `tryResolve(...) == null`,
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

  /// Test-only escape hatch, matching [Assets.reset] and
  /// `ArchetypeRegistry.reset`: this registry is process-global, so a test
  /// suite registering many throwaway objects needs a way to start over.
  @visibleForTesting
  static void reset() {
    _byAddress.clear();
    _freeAddresses.clear();
  }
}
