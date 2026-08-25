import 'dart:math';

import 'package:good_cli/src/generate/assets.dart';

/// The banner every generated file carries.
///
/// Says what regenerates it, so the first thing someone who edited one by
/// mistake reads is how to get their change into the right place.
String header(String command) =>
    '// GENERATED - do not edit.\n'
    '//\n'
    '// Regenerate with `$command`. Edits here are lost on the next run;\n'
    '// change the pubspec\'s `flutter: assets:` list instead.\n';

/// `good.generated/textures.dart` - one enum value per shipped image.
///
/// An enum, not a list of `static final` keys, because `LocalEnumAssetKey`
/// makes an enum value *be* an `AssetKey`: `Textures.planePlayerBlue` is
/// already the identity `descriptor.has` wants, with no lookup and nothing to
/// keep in sync. It also gives the set a `.values`, which is what lets the
/// readiness check below walk every asset the game ships.
String emitTextures(
  AssetScan scan, {
  required String command,
  required String package,
}) => _emitEnum(
  assets: scan.textures,
  enumName: 'Textures',
  payload: rendererPayloadType(package, 'Texture'),
  command: command,
  package: package,
  emptyNote: 'image',
);

/// `good.generated/audios.dart` - one enum value per shipped audio file.
///
/// Identical in shape to the texture enum, and that is the point: the asset
/// pipeline is uniform over asset *kinds*, so a second kind costs a payload
/// type, a loader, and one more call to the same emitter.
String emitAudios(
  AssetScan scan, {
  required String command,
  required String package,
}) => _emitEnum(
  assets: scan.audio,
  enumName: 'Audios',
  payload: 'AudioClip',
  command: command,
  package: package,
  emptyNote: 'audio',
);

/// What a **renderer's** asset kind loads to, named as the project's engine
/// package spells it - or `Object?` where that package has no name for it.
///
/// `Texture` is a `goo2d` type: it is what its loader produces, and it is a
/// `ui.Image` behind a handle, which is only meaningful to something that can
/// draw one. `goo3d` has no renderer until #43, so a 3D project has nothing
/// for a texture key to be typed to. Naming the 2D type anyway is what this
/// used to do, and it emitted four `Texture isn't a type` errors into the
/// first `flutter analyze` a 3D project ever ran.
///
/// `Object?` and not a refusal to generate: the keys still compile, `.values`
/// still walks them for the readiness check, and nothing claims a payload type
/// that does not exist. It narrows on its own the day `goo3d` can draw.
///
/// Audio does **not** come through here any more. `AudioClip` moved into the
/// kernel (#93), which every engine package re-exports, so an audio key is
/// typed for a 3D project exactly as it is for a 2D one - it is bytes and a
/// container name, with no canvas or dimension anywhere in it.
String rendererPayloadType(String package, String rendererType) =>
    package == 'goo2d' ? rendererType : 'Object?';

String _emitEnum({
  required List<DiscoveredAsset> assets,
  required String enumName,
  required String payload,
  required String command,
  required String package,
  required String emptyNote,
}) {
  final buffer = StringBuffer(header(command))
    ..writeln()
    ..writeln("import 'package:$package/$package.dart';")
    ..writeln();

  if (assets.isEmpty) {
    // Not an enum. Dart has no empty enum - `enum Textures { ; }` is a compile
    // error - and a fresh project declares nothing yet, so emitting one made
    // every new project fail to build on its first `flutter analyze`. A class
    // with no members compiles, keeps `import 'textures.dart'` working, and
    // becomes the enum the moment an asset is declared. Nothing can reference
    // a member of it in the meantime, because it has none.
    return (buffer
          ..writeln('/// No $emptyNote assets are declared in pubspec.yaml')
          ..writeln('/// under `flutter: assets:` yet.')
          ..writeln('///')
          ..writeln('/// A class rather than an enum only because Dart has no')
          ..writeln('/// empty enum. Declare an asset and this becomes')
          ..writeln('/// `enum $enumName with LocalEnumAssetKey<$payload>`,')
          ..writeln('/// with one value per file.')
          ..writeln('abstract final class $enumName {')
          ..writeln('  /// Every $emptyNote asset, which is none of them.')
          ..writeln('  ///')
          ..writeln('  /// Present so code that walks the list - the readiness')
          ..writeln('  /// check does - compiles before the first asset lands.')
          ..writeln(
            '  static const List<AssetKey<$payload>> values = '
            '<AssetKey<$payload>>[];',
          )
          ..writeln('}'))
        .toString();
  }

  buffer.writeln('enum $enumName with LocalEnumAssetKey<$payload> {');
  for (var i = 0; i < assets.length; i++) {
    final asset = assets[i];
    final terminator = i == assets.length - 1 ? ';' : ',';
    buffer.writeln("  ${asset.identifier}('${asset.path}')$terminator");
  }
  buffer
    ..writeln()
    ..writeln('  const $enumName(this.path);')
    ..writeln()
    ..writeln('  @override')
    ..writeln('  final String path;')
    ..writeln('}');
  return buffer.toString();
}

/// `good.generated/good.dart` - the startup check.
///
/// Answers the TODO the hand-written version carried: "ensure assets all exist
/// ... WITHOUT LOADING THE ASSET". `AssetSource.check` is exactly that - a
/// manifest lookup and at most a stat, never a decode - so this can run over
/// every shipped asset at startup without paying for any of them.
String emitReadiness({required String command, required String package}) =>
    '''
${header(command)}
import 'package:$package/$package.dart';

import 'asset_key.dart';
import 'audios.dart';
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
  for (final key in <AssetKey<Object?>>[
    ...Textures.values,
    ...Audios.values,
  ]) {
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
  // The pack first: everything below asks whether assets are *there*, and in a
  // release build that answer comes from the manifest rather than the bundle.
  // An empty mapping means a development build - assets are loose, and
  // mounting nothing is what makes BundleSource resolve straight through
  // rootBundle.
  //
  // Mount anything else - a DLC directory, a downloaded patch - *after* this
  // line: the mount table is ordered and the last mount to carry a logical
  // path is the one that answers for it.
  if (assetMapping.isNotEmpty) {
    AssetMounts.mount(
      AssetPack(mapping: assetMapping, key: assetKeyMaterial),
    );
  }

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

/// `good.generated/asset_key.dart` - the per-project encryption keys.
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
/// Filled by `good assets pack`, not by codegen: which chunk an asset lands in
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
