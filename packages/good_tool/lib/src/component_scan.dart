import 'dart:io';

// good_cli's `lib/src` is private by convention and this reaches into it, for
// the reason `accessor_scan.dart` states beside its own copy of this line.
// ignore: implementation_imports
import 'package:good_cli/src/generate/struct_scan.dart';
import 'package:good_tool/src/engine_packages.dart';
import 'package:good_tool/src/imports.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

/// How many bits a query signature holds, mirrored from
/// `ComponentTypeRegistry.maxComponentTypes`.
///
/// Written down rather than imported: `package:good` is a Flutter package, and
/// this tool runs under `dart run`. `component_scan_test.dart` reads the
/// constant out of `archetype.dart` and fails when the two disagree, so
/// widening the signature cannot leave this behind.
const int maxComponentTypes = 64;

/// One component type that gets its bit at build time instead of at run time.
@immutable
class ComponentBit {
  const ComponentBit({
    required this.type,
    required this.package,
    required this.sortKey,
    required this.import,
  });

  /// The type as written - `Transform2D`.
  final String type;

  /// The package declaring it, which is also the one its entry goes into.
  final String package;

  /// Its file, relative to that package's `lib/`, in posix form.
  ///
  /// The ordering key, posix for the reason `AccessorExtension.sortKey` gives:
  /// a Windows separator would sort `src/data/camera.dart` differently and
  /// reorder a committed file on the next person's machine.
  final String sortKey;

  /// The `package:` URI the generated file imports to name [type].
  final String import;
}

/// What one pass over the repository's component registrations produced.
@immutable
class ComponentBitScan {
  const ComponentBitScan({required this.bits, required this.skipped});

  /// Every scanned component type, in the order the bits are assigned.
  ///
  /// Package name, then declaring file, then type name. Nothing about it
  /// depends on the order the filesystem hands directories back, which is the
  /// whole property being bought: two machines that regenerate agree, and the
  /// signature a peer sends means the same thing to the peer that reads it.
  final List<ComponentBit> bits;

  /// Every type named by a `has<T>()` that got no entry, and why.
  ///
  /// Never fatal. A type with no entry is assigned a bit at run time on first
  /// sighting exactly as it is today, so a skip here costs a slot's stability
  /// and nothing else - which is also what a component in a package this tool
  /// never reads gets.
  final Map<String, String> skipped;

  /// [bits] grouped by the package their entry is written into, each keeping
  /// its order from [bits].
  Map<String, List<ComponentBit>> get byPackage {
    final grouped = <String, List<ComponentBit>>{};
    for (final bit in bits) {
      grouped.putIfAbsent(bit.package, () => <ComponentBit>[]).add(bit);
    }
    return grouped;
  }
}

/// Finds every component type this repository can assign a bit to at build
/// time.
///
/// # What this is
///
/// The component half of #18. `ComponentTypeRegistry` hands each component
/// type a bit the first time a `Component.type<T>()` field initialiser names
/// it, and the order that produces is the order scenes happen to declare
/// things in. That
/// is fine inside one process and meaningless outside it, which is why
/// `archetype.dart` says not to persist a signature. Assigning the same bits
/// here instead makes the assignment a property of the source rather than of a
/// run, so a signature is something two peers can exchange - what #230 and
/// #282 both need.
///
/// # What it reads, and what it deliberately does not
///
/// The `T` of every `Component.type<T>()` field initialiser in a published
/// package. Those are exactly the types `bitFor` is called with, and matching
/// that set exactly is the point: a table over some other set would be a
/// different numbering wearing the same name.
///
/// It is **not** every component mixin. `CollisionListener` is a mixin on
/// `Component` that registers nothing, and a bit for it would spend one of
/// sixty-four slots on a type no archetype signature ever carries.
///
/// It is also not a prefab's own type. That bit is ORed in by the framework
/// from `runtimeType` once the object is built, so it is the value of an
/// expression and is assigned when the program runs and always will be - see
/// [ComponentBitScan.skipped] for what that costs, which is nothing.
///
/// # No offset is produced here either
///
/// The same reason `accessor_scan.dart` gives. An offset is the running total
/// of a `declareField` sequence that reads values only a run can supply - a
/// prefab declares its own sprites, `TextLabel.of` sizes an array from the
/// capacity the prefab passed it, and `hasEnum` widens by `values.length`. A
/// bit index depends on none of those: it is a position in a sorted list of
/// names.
ComponentBitScan scanComponentBits(
{
  required List<EnginePackage> packages,
  ScanSources? sources,
}) {
  final read =
      sources ??
      readSources(
        Directory.current,
        rootOverride: <String>[for (final target in packages) target.libDir],
        exclude: <String>{
          for (final target in packages) target.accessorFile.path,
          for (final target in packages) target.componentBitsFile.path,
        },
      );

  final byLibDir = <String, EnginePackage>{
    for (final target in packages) target.libDir: target,
  };

  // Every type any scanned field initialiser names, deduplicated and sorted
  // before anything is decided about it. Sorted so that the skip notes come
  // out in one order too - `--verbose` is read by a person.
  final named = <String>{};
  for (final owners in read.byName.values) {
    for (final owner in owners) {
      if (packageOf(owner.file, byLibDir) == null) continue;
      named.addAll(owner.componentTypes);
    }
  }
  final wanted = named.toList()..sort();

  final bits = <ComponentBit>[];
  final skipped = <String, String>{};
  for (final type in wanted) {
    if (type.startsWith('_')) {
      skipped[type] =
          'private, so the generated file - a different library - cannot name '
          'it';
      continue;
    }
    final owners = read.byName[type];
    if (owners == null || owners.isEmpty) {
      skipped[type] =
          'not declared in any package this pass reads, so no import can be '
          'written for it';
      continue;
    }
    if (owners.length > 1) {
      // The case `struct_scan` already reports as `unresolved` rather than
      // guessing. A generated table has to emit a Dart type reference, and a
      // parsed scan cannot tell which library `Component.type<Velocity>()`
      // meant, so this produces no entry and the run-time path keeps the type.
      skipped[type] =
          'declared in more than one library, and a parsed scan cannot tell '
          'which one an import would reach';
      continue;
    }
    final owner = owners.single;
    final package = packageOf(owner.file, byLibDir);
    if (package == null) {
      skipped[type] =
          'declared outside every published package, which is not somewhere '
          'this tool writes';
      continue;
    }
    final sortKey = posix(p.relative(owner.file, from: package.libDir));
    bits.add(
      ComponentBit(
        type: type,
        package: package.name,
        sortKey: sortKey,
        import: 'package:${package.name}/$sortKey',
      ),
    );
  }

  bits.sort((a, b) {
    final byPackage = a.package.compareTo(b.package);
    if (byPackage != 0) return byPackage;
    final byPath = a.sortKey.compareTo(b.sortKey);
    return byPath != 0 ? byPath : a.type.compareTo(b.type);
  });

  return ComponentBitScan(bits: bits, skipped: skipped);
}

/// What `good_tool` prints when the repository alone would fill the registry.
///
/// The ceiling is `ComponentTypeRegistry.maxComponentTypes`, a query signature
/// being one 64-bit word. Reaching it at run time raises a `StateError` naming
/// the type that happened to arrive last, which is whichever scene was
/// declared last and says nothing about what filled the table. Reaching it
/// here names every competitor, which is the thing #18 asks for.
///
/// Off by one from the run-time meaning on purpose: a project has its own
/// components as well, so a repository that exactly fills the table has
/// already taken every slot a game had.
String componentBitCeilingMessage(ComponentBitScan scan, int ceiling) {
  final lines = StringBuffer()
    ..writeln(
      'The generated component-bit table has ${scan.bits.length} entries and '
      'a query signature holds $ceiling. Every one of these would be seeded '
      'before a game declares a single component of its own:',
    )
    ..writeln();
  for (var i = 0; i < scan.bits.length; i++) {
    final bit = scan.bits[i];
    lines.writeln('  $i  ${bit.type} - ${bit.package}/lib/${bit.sortKey}');
  }
  lines
    ..writeln()
    ..writeln(
      'Widening the signature past one word is the mechanical change '
      'maxComponentTypes names. Until it is made, the table cannot be seeded '
      'and the engine has more component types than a signature can hold.',
    );
  return lines.toString();
}
