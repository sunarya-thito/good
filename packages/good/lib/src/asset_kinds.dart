import 'dart:convert';
import 'dart:typed_data';

import 'package:good/src/asset.dart';

/// A decoded JSON document, whatever its top level turned out to be.
///
/// # Why this is a class and not `Map<String, Object?>`
///
/// Two mechanical reasons, neither of them taste.
///
/// JSON's top level is an object, an array, a string, a number, a boolean or
/// null. A level layout is normally an object and a dialogue file is normally
/// an array, so a payload type that *is* a map cannot hold half of what a
/// project ships - and adding `Asset<List<Object?>>` beside it would turn one
/// file format into two asset kinds that share a decoder.
///
/// And [AssetLoaders] is keyed on the reified payload type, so
/// `Asset<Map<String, Object?>>` would claim a **structural** type: any
/// map-shaped payload anyone else declares resolves to this decoder, and a
/// project that wants its own decode for its own map has to replace JSON's to
/// get it. A named class claims one name. The argument does not reach
/// [TextAsset] or [UnknownAsset] - bytes decode to a `String` exactly one way
/// and to a `Uint8List` no way at all - which is why those two are bare.
///
/// A `typedef` or an extension type would do neither job. Both erase to their
/// representation as a type argument, so `AssetLoaders.register<JsonValue>`
/// would key on `Object?` and answer for every payload type in the process.
final class JsonValue {
  const JsonValue(this.value);

  /// What `jsonDecode` produced: a `Map<String, Object?>`, a `List<Object?>`,
  /// a `String`, a `num`, a `bool`, or null.
  final Object? value;

  /// [value] as a JSON object.
  ///
  /// Throws naming the top level it found instead of casting. A cast reports
  /// `List<dynamic> is not a subtype of Map<String, Object?>` from inside the
  /// game's own code, which says nothing about the file being the wrong shape.
  Map<String, Object?> get asMap {
    final value = this.value;
    if (value is Map<String, Object?>) return value;
    throw StateError(
      'this JSON document is ${_shape(value)} at its top level, not an '
      'object, so it has no keys to read. Use asList for an array, or value '
      'for whatever else it holds.',
    );
  }

  /// [value] as a JSON array. Throws the way [asMap] does.
  List<Object?> get asList {
    final value = this.value;
    if (value is List<Object?>) return value;
    throw StateError(
      'this JSON document is ${_shape(value)} at its top level, not an array, '
      'so it has no elements to read. Use asMap for an object, or value for '
      'whatever else it holds.',
    );
  }

  static String _shape(Object? value) => switch (value) {
    null => 'null',
    Map<String, Object?>() => 'an object',
    List<Object?>() => 'an array',
    String() => 'a string',
    num() => 'a number',
    bool() => 'a boolean',
    _ => 'a ${value.runtimeType}',
  };

  @override
  String toString() => 'JsonValue(${_shape(value)})';
}

/// The handle a component field points at, for a JSON document.
typedef JsonAsset = Asset<JsonValue>;

/// A JSON document's identity: where its bytes come from, and nothing else.
typedef JsonKey = AssetKey<JsonValue>;

/// The handle a component field points at, for a UTF-8 text file.
typedef TextAsset = Asset<String>;

/// A text file's identity: where its bytes come from, and nothing else.
typedef TextKey = AssetKey<String>;

/// The handle a component field points at, for a file the engine knows
/// nothing about - a save blob, a binary level format, something a project's
/// own code parses.
typedef UnknownAsset = Asset<Uint8List>;

/// Such a file's identity: where its bytes come from, and nothing else.
typedef UnknownKey = AssetKey<Uint8List>;

/// Reads a UTF-8 file and parses it as JSON.
///
/// Registered by `Game.describeAssetLoaders`, so every game has it without
/// declaring anything - there is no canvas, no device and no dimension in a
/// JSON document, the same argument that puts `AudioLoader` in the kernel.
///
/// Publishes no [AssetInfo]. Info exists to carry a fact discovered by
/// decoding to a copy that cannot decode, and there is no such fact here: the
/// game isolate cannot read the document either way, and the one number it
/// could be told - a byte count - has no reader.
class JsonLoader extends AssetLoader<JsonValue> {
  const JsonLoader();

  @override
  Future<JsonValue> load(AssetKey<JsonValue> key) async =>
      JsonValue(jsonDecode(_decodeUtf8(await key.source.load())));
}

/// Reads a UTF-8 file as a [String].
///
/// Registered by `Game.describeAssetLoaders` for the reason [JsonLoader] is.
///
/// The whole file, decoded once. Line splitting, front matter and templating
/// are the project's business - this is the payload, and a loader that
/// interpreted it would be a second file format nobody declared.
class TextLoader extends AssetLoader<String> {
  const TextLoader();

  @override
  Future<String> load(AssetKey<String> key) async =>
      _decodeUtf8(await key.source.load());
}

/// Hands back a file's bytes.
///
/// Registered by `Game.describeAssetLoaders` for the reason [JsonLoader] is.
///
/// Named for what it produces rather than for [UnknownAsset], because
/// "unknown" describes what the *project* knows about the file and this class
/// knows exactly what it is doing.
///
/// Does not copy, so the payload is the buffer the source produced -
/// `AudioLoader` has always worked that way, and copying every blob would
/// double peak memory for the one asset kind with no size bound.
class BytesLoader extends AssetLoader<Uint8List> {
  const BytesLoader();

  @override
  Future<Uint8List> load(AssetKey<Uint8List> key) => key.source.load();
}

/// Decodes [bytes] as UTF-8, strictly.
///
/// Strict, so malformed input throws instead of becoming U+FFFD. A text asset
/// that is not UTF-8 is a build mistake, and the substitution character would
/// ship it as content.
///
/// Nothing here strips a byte-order mark, because `utf8.decode` already
/// discards one leading U+FEFF - measured, not assumed, after a strip written
/// here turned out to fire only on a second mark. It matters that something
/// does: every Windows editor writes one, and `jsonDecode` fails on U+FEFF
/// before it reaches the first brace.
String _decodeUtf8(Uint8List bytes) => utf8.decode(bytes);
