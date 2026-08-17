import 'dart:math';

import 'package:goo_cli/src/generate/assets.dart';

/// The banner every generated file carries.
///
/// Says what regenerates it, so the first thing someone who edited one by
/// mistake reads is how to get their change into the right place.
String header(String command) =>
    '// GENERATED - do not edit.\n'
    '//\n'
    '// Regenerate with `$command`. Edits here are lost on the next run;\n'
    '// change the pubspec\'s `flutter: assets:` list instead.\n';

/// `goo.generated/textures.dart` - one enum value per shipped image.
///
/// An enum, not a list of `static final` keys, because `LocalEnumAssetKey`
/// makes an enum value *be* an `AssetKey`: `Textures.planePlayerBlue` is
/// already the identity `descriptor.has` wants, with no lookup and nothing to
/// keep in sync. It also gives the set a `.values`, which is what lets the
/// readiness check below walk every asset the game ships.
String emitTextures(AssetScan scan, {required String command}) {
  final buffer = StringBuffer(header(command))
    ..writeln()
    ..writeln("import 'package:goo2d/goo2d.dart';")
    ..writeln();

  if (scan.textures.isEmpty) {
    buffer
      ..writeln('// No image assets are declared in pubspec.yaml under')
      ..writeln('// `flutter: assets:`, so this enum is empty. It exists so')
      ..writeln('// that code importing it keeps compiling.')
      ..writeln('enum Textures with LocalEnumAssetKey<Texture> {')
      ..writeln('  ;')
      ..writeln()
      ..writeln('  const Textures(this.path);')
      ..writeln()
      ..writeln('  @override')
      ..writeln('  final String path;')
      ..writeln('}');
    return buffer.toString();
  }

  buffer.writeln('enum Textures with LocalEnumAssetKey<Texture> {');
  for (var i = 0; i < scan.textures.length; i++) {
    final asset = scan.textures[i];
    final terminator = i == scan.textures.length - 1 ? ';' : ',';
    buffer.writeln("  ${asset.identifier}('${asset.path}')$terminator");
  }
  buffer
    ..writeln()
    ..writeln('  const Textures(this.path);')
    ..writeln()
    ..writeln('  @override')
    ..writeln('  final String path;')
    ..writeln('}');
  return buffer.toString();
}

/// `goo.generated/goo.dart` - the startup check.
///
/// Answers the TODO the hand-written version carried: "ensure assets all exist
/// ... WITHOUT LOADING THE ASSET". `AssetSource.check` is exactly that - a
/// manifest lookup and at most a stat, never a decode - so this can run over
/// every shipped asset at startup without paying for any of them.
String emitReadiness({required String command}) =>
    '''
${header(command)}
import 'package:goo/goo.dart';

import 'textures.dart';

/// Every asset that is declared but will not be there at run time.
///
/// Checked **without loading anything**: [AssetSource.check] consults the
/// manifest and at most stats a file, so this is cheap enough to run over a
/// whole game at startup - which is the point. A missing asset found here is a
/// clear message before the first frame; the same asset found later is a
/// failure in the middle of play, with a scene half-loaded.
///
/// [AssetAvailability.unverifiable] is *not* counted as a failure. A loose
/// development build cannot stat a bundle entry, and a network source cannot
/// be checked offline; reporting those as missing would make the check cry
/// wolf everywhere it is most useful.
Future<List<AssetKey<Object?>>> findMissingAssets() async {
  final missing = <AssetKey<Object?>>[];
  for (final key in <AssetKey<Object?>>[...Textures.values]) {
    final availability = await key.source.check();
    if (availability == AssetAvailability.missing ||
        availability == AssetAvailability.unknown) {
      missing.add(key);
    }
  }
  return missing;
}

/// Call before starting the game.
///
/// Throws rather than returning a flag: a game that starts with assets missing
/// will fail anyway, later, somewhere less explicable.
Future<void> ensureGameReady() async {
  final missing = await findMissingAssets();
  if (missing.isEmpty) return;
  throw StateError(
    'Missing \${missing.length} asset(s) this build declares:\\n'
    '\${missing.map((k) => '  \\\${k.source.description}').join('\\n')}\\n'
    'The install may be incomplete, or the pubspec may declare an asset that '
    'was never shipped. Re-running `$command` refreshes the declared set.',
  );
}
''';

/// `goo.generated/asset_key.dart` - the per-project encryption keys.
///
/// Written **once** and never rewritten, which is why it is separate from the
/// other two: the keys decrypt assets that were already packed with them, so
/// regenerating on every run would orphan every shipped build. See
/// `GenerateCommand` for the flag that rotates them deliberately.
///
/// Not `const`, on purpose. A `const` list is folded into the binary's
/// constant pool where `strings` finds it; a `final` one is assembled at run
/// time. Neither stops someone with a debugger - the key has to exist in
/// memory for the game to draw anything - and the README is honest that this
/// deters casual extraction rather than defeating reverse engineering.
String emitAssetKeys({required String command, required Random random}) {
  String line(String name) {
    final bytes = <String>[
      for (var i = 0; i < 8; i++)
        '0x${random.nextInt(256).toRadixString(16).toUpperCase().padLeft(2, '0')}',
    ];
    return 'final List<int> $name = [${bytes.join(', ')}];';
  }

  return '''
${header(command)}
// These keys are deliberately not `const`: a const list is folded into the
// binary's constant pool, where `strings` finds it. They are combined at run
// time to derive the key the asset pack was encrypted with.
//
// This file is generated **once** and then left alone. Regenerating it would
// change the keys and orphan every asset pack already built with the old ones,
// which is why `$command` refuses to overwrite it without --rotate-keys.
${line('_assetKey')}
${line('_assetKey2')}
${line('_assetKey3')}
${line('_assetKey4')}

/// Logical asset path -> the chunk that holds it, e.g.
/// `assets/plane.png` -> `assets/chunk_0.dat`.
///
/// Filled by `goo assets pack`, not by codegen: which chunk an asset lands in
/// is a property of a particular pack, and chunks are grouped by scene so that
/// loading a scene reads as few of them as possible. Empty until a pack has
/// run, which is the loose development build - there `BundleSource` resolves
/// its path straight through `rootBundle`.
final Map<String, String> assetMapping = <String, String>{};

/// The four key parts, combined. Named so the runtime has one place to reach
/// for rather than four.
List<int> get assetKeyMaterial => <int>[
  ..._assetKey,
  ..._assetKey2,
  ..._assetKey3,
  ..._assetKey4,
];
''';
}
