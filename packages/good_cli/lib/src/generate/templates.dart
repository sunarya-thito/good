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
  required bool drawsTextures,
}) => _emitEnum(
  assets: scan.textures,
  enumName: 'Textures',
  payload: rendererPayloadType(drawsTextures, 'Texture'),
  command: command,
  package: package,
  emptyNote: 'image',
  sizeClassName: 'TextureSize',
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
/// package spells it - or `Object?` where that package cannot draw.
///
/// `Texture` is declared in `goo2d` and exported from `package:goo2d/goo2d.dart`.
/// It is what the texture loader produces, and it is a `ui.Image` behind a
/// handle, so it is only meaningful to something that can draw one. `goo3d`
/// has no renderer until #43, and it depends on `good` alone, so a 3D project
/// has nothing for a texture key to be typed to. Naming the 2D type anyway
/// puts four `Texture isn't a type` errors into the first `flutter analyze` a
/// 3D project runs.
///
/// [drawsTextures] is that question answered from the dependency graph, by
/// `enginePackageDrawsTextures`, and not from the entry package's name. A
/// renderer somebody else publishes on top of `goo2d` gets a typed key the
/// same way `goo2d` does.
///
/// `Object?` and not a refusal to generate: the keys still compile, `.values`
/// still walks them for the readiness check, and nothing claims a payload type
/// that does not exist. It narrows on its own the day `goo3d` can draw.
///
/// The sizes below are emitted either way. A pixel dimension is an `int` and
/// names no engine type, and a project that cannot draw still ships images
/// and still has code that wants to know how big they are.
///
/// Audio does **not** come through here. `AudioClip` moved into the kernel
/// (#93), which every engine package re-exports, so an audio key is typed for
/// a 3D project exactly as it is for a 2D one - it is bytes and a container
/// name, with no canvas or dimension anywhere in it.
String rendererPayloadType(bool drawsTextures, String rendererType) =>
    drawsTextures ? rendererType : 'Object?';

/// The one file both asset kinds are emitted from.
///
/// [sizeClassName] is the class the pixel sizes go in, and passing it is what
/// makes this the texture emitter: an audio file has no dimensions, so audio
/// passes `null` and gets none of it.
///
/// The sizes are emitted twice, in two forms, because the two forms are not
/// interchangeable. Instance-field access is never a constant expression, so
/// `Textures.sheet.width` cannot appear in the `static const List<SpriteFrame>`
/// the rendering guide teaches; a `static const int` can, and cannot be
/// reached from an enum value. Enum values and static members share one
/// namespace, so the constants live in their own class, where the only way to
/// collide is two textures with the same identifier - which `scanAssets`
/// already refuses by name.
String _emitEnum({
  required List<DiscoveredAsset> assets,
  required String enumName,
  required String payload,
  required String command,
  required String package,
  required String emptyNote,
  String? sizeClassName,
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
        .toString() +
        (sizeClassName == null ? '' : _emptySizeClass(sizeClassName));
  }

  final sized = sizeClassName != null;
  buffer.writeln('enum $enumName with LocalEnumAssetKey<$payload> {');
  for (var i = 0; i < assets.length; i++) {
    final asset = assets[i];
    final terminator = i == assets.length - 1 ? ';' : ',';
    final size = sized ? ', ${_width(asset)}, ${_height(asset)}' : '';
    buffer.writeln("  ${asset.identifier}('${asset.path}'$size)$terminator");
  }
  buffer
    ..writeln()
    ..writeln(
      sized
          ? '  const $enumName(this.path, this.width, this.height);'
          : '  const $enumName(this.path);',
    )
    ..writeln()
    ..writeln('  @override')
    ..writeln('  final String path;');
  if (sized) {
    buffer
      ..writeln()
      ..writeln("  /// The image's width in pixels, read from its header when")
      ..writeln('  /// this file was generated.')
      ..writeln('  ///')
      ..writeln('  /// `0` where the header could not be read - `$command`')
      ..writeln('  /// names the file when that happens.')
      ..writeln('  ///')
      ..writeln('  /// Not usable in a `const` expression: field access on an')
      ..writeln('  /// enum value never is. Name `$sizeClassName.<asset>Width`')
      ..writeln('  /// where a constant is wanted.')
      ..writeln('  final int width;')
      ..writeln()
      ..writeln("  /// The image's height in pixels. See [width].")
      ..writeln('  final int height;');
  }
  buffer.writeln('}');
  if (sized) {
    buffer
      ..writeln()
      ..writeln("/// Every texture's pixel size, as constants.")
      ..writeln('///')
      ..writeln('/// The same numbers [$enumName] carries, in the one form')
      ..writeln('/// that can appear in a `const` expression - a')
      ..writeln('/// `static const List<SpriteFrame>` table, or a')
      ..writeln('/// `SpriteFrame.pixels` divisor. Re-exporting the art at a')
      ..writeln('/// different size changes these and nothing else.')
      ..writeln('abstract final class $sizeClassName {');
    for (var i = 0; i < assets.length; i++) {
      final asset = assets[i];
      final name = asset.identifier;
      if (i > 0) buffer.writeln();
      buffer
        ..writeln('  /// `${asset.path}` is ${_width(asset)} pixels wide.')
        ..writeln('  static const int ${name}Width = ${_width(asset)};')
        ..writeln()
        ..writeln('  /// `${asset.path}` is ${_height(asset)} pixels tall.')
        ..writeln('  static const int ${name}Height = ${_height(asset)};');
    }
    buffer.writeln('}');
  }
  return buffer.toString();
}

/// The width to write, and `0` where the header did not state one.
///
/// A number and not an omission because every enum value has to pass one to
/// the same constructor. `good generate` prints the file it could not read, so
/// the zero is never the first anybody hears of it.
int _width(DiscoveredAsset asset) => asset.size?.width ?? 0;

/// The height to write. See [_width].
int _height(DiscoveredAsset asset) => asset.size?.height ?? 0;

/// The size class for a project that ships no images yet.
///
/// Emitted so the name resolves from the first run. It has no members, and
/// gains one pair per texture as soon as one is declared.
String _emptySizeClass(String name) => (StringBuffer()
      ..writeln()
      ..writeln('/// No texture sizes, because no images are declared yet.')
      ..writeln('///')
      ..writeln('/// Declare one and this gains a `static const int')
      ..writeln('/// <asset>Width` and `<asset>Height` pair for it.')
      ..writeln('abstract final class $name {}'))
    .toString();

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
/// Written **once** and never rewritten, so it is separate from the other
/// two: the keys decrypt assets that were already packed with them, and
/// regenerating on every run would orphan every shipped build. See
/// `GenerateCommand` for the flag that replaces them.
///
/// Not `const`. A `const` list is folded into the binary's
/// constant pool where `strings` finds it; a `final` one is assembled at run
/// time. Neither stops someone with a debugger - the key has to exist in
/// memory for the game to draw anything - and the README is honest that this
/// deters casual extraction and does not defeat reverse engineering.
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
