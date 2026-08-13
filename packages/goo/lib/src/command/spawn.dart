import 'package:goo/src/command/command.dart';
import 'package:goo/src/command/param.dart';
import 'package:goo/src/struct.dart';

/// The framework's own command: "spawn one entity of this prefab, and tell me
/// which one".
///
/// The canonical case the whole command lane exists for - a HUD button on the
/// Flutter isolate that adds an enemy to a world it does not own. The prefab
/// is named by `EntityStruct.archetypeId` rather than by instance, because a
/// prefab is a Dart object belonging to the game isolate's scene and cannot
/// cross; the id is the same integer on both copies, assigned in
/// first-registration order by `ArchetypeRegistry`.
///
/// Declared by `Game` itself, before any user command, so it always has index
/// 0 on both copies - and handed back as `Game.spawnEntity` rather than
/// registered by name (RULES.md rule 6):
///
/// ```dart
/// final enemy = await game.spawnEntity(scene.enemyPrefab.archetypeId);
/// ```
///
/// The result travels back, which the old encode/apply lane could not do: the
/// handler ran on the game isolate and left the created entity in a field
/// only that isolate could read. Now the spawning side gets an [Entity] it
/// can immediately store, hand to a later command, or read component data
/// through.
///
/// Despawn, spawn-under-parent, and spawn-with-initial-field-values are the
/// obvious next commands and are deliberately still not written: despawn
/// needs row recycling semantics that `ArchetypeStorage` flags as absent, and
/// initial field values need a wire encoding for a *field set*, which is a
/// design question of its own. One framework command proves the mechanism;
/// `Game.describeCommands` is what keeps it from being the only one.
final class SpawnEntityCommand extends GameCommand<int, Entity> {
  /// The prefab to spawn. 16 bits because that is exactly what an `Entity`
  /// reserves for the archetype id (see `Entity.pack`), so a value this field
  /// cannot hold is one no entity could have carried anyway.
  late final ParamPointer<int> archetypeId;

  /// The entity the handler created, packed as the plain int an [Entity] is.
  late final ParamPointer<int> spawned;

  @override
  void describeParams(ParamDescriptor descriptor) {
    archetypeId = descriptor.hasUint16();
    spawned = descriptor.hasInt64();
  }

  @override
  void bufferFromParams(CommandBuffer call, int params) =>
      archetypeId[call] = params;

  @override
  int paramsFromBuffer(CommandBuffer call) => archetypeId[call];

  // Signed, and it has to be: `Entity.pack` shifts the archetype id up by 48
  // bits, which puts a high id straight into the sign position of Dart's
  // 64-bit int. getInt64/setInt64 round-trip every bit pattern; a uint64 read
  // of the same bytes would not survive the trip back into an int.
  @override
  void bufferFromResult(CommandBuffer call, Entity result) =>
      spawned[call] = result.value;

  @override
  Entity resultFromBuffer(CommandBuffer call) => Entity(spawned[call]);
}
