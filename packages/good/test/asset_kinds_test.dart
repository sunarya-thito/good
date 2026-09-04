// #357: the three payload kinds a project ships that are not a texture and
// not a sound.
//
// Each is a payload type plus a loader and nothing else - `Asset<T>`,
// `AssetKey<T>` and `AssetLoaders` were already generic. So what is worth
// pinning here is the decode each loader performs and the type each one is
// registered under, because those are the two things a kind consists of.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:good/src/asset.dart';
import 'package:good/src/asset_kinds.dart';

/// Bytes with a name, so a key is a real identity and a diagnostic can say
/// which document it is talking about.
AssetKey<T> _key<T>(String name, List<int> bytes) =>
    AssetKey<T>(MemorySource(Uint8List.fromList(bytes), name: name));

AssetKey<T> _text<T>(String name, String content) =>
    _key<T>(name, utf8.encode(content));

/// A UTF-8 byte-order mark, which every Windows editor writes and neither
/// reader wants. `utf8.decode` discards one, so what these cases pin is that
/// both loaders go through it - a decoder that did not would ship the mark as
/// content.
const List<int> _bom = <int>[0xEF, 0xBB, 0xBF];

/// A project's own decoder for `String`, to show what registering one does.
class _ShoutingTextLoader extends AssetLoader<String> {
  const _ShoutingTextLoader();

  @override
  Future<String> load(AssetKey<String> key) async =>
      utf8.decode(await key.source.load()).toUpperCase();
}

/// The escape hatch a type-keyed registry leaves for a second text kind: a
/// payload type of its own, which is what [JsonValue] is.
class _Csv {
  const _Csv(this.rows);
  final List<List<String>> rows;
}

class _CsvLoader extends AssetLoader<_Csv> {
  const _CsvLoader();

  @override
  Future<_Csv> load(AssetKey<_Csv> key) async => _Csv(<List<String>>[
    for (final line in utf8.decode(await key.source.load()).split('\n'))
      line.split(','),
  ]);
}

void main() {
  late Assets assets;

  setUp(() {
    assets = Assets();
    AssetLoaders.register<JsonValue>(const JsonLoader());
    AssetLoaders.register<String>(const TextLoader());
    AssetLoaders.register<Uint8List>(const BytesLoader());
  });

  tearDown(() {
    assets.reset();
    AssetLoaders.reset();
  });

  group('JsonLoader', () {
    test(
      'decodes the bytes as JSON rather than handing back the text',
      () async {
        final key = _text<JsonValue>('balance', '{"damage": 7, "name": "axe"}');

        final value = await const JsonLoader().load(key);

        expect(value.asMap['damage'], 7);
        expect(value.asMap['name'], 'axe');
      },
    );

    test('a top-level array is a document, not a failure', () async {
      // The whole reason JsonValue is a class: a dialogue file is an array and
      // a payload type of Map<String, Object?> could not hold one at all.
      final key = _text<JsonValue>('lines', '["hello", "goodbye"]');

      final value = await const JsonLoader().load(key);

      expect(value.asList, <String>['hello', 'goodbye']);
    });

    test(
      'nested structure survives, so nothing re-encodes on the way',
      () async {
        final key = _text<JsonValue>(
          'level',
          '{"spawns": [{"x": 1.5, "y": -2}], "loop": true}',
        );

        final value = await const JsonLoader().load(key);
        final spawns = value.asMap['spawns']! as List<Object?>;

        expect((spawns.single as Map<String, Object?>)['x'], 1.5);
        expect(value.asMap['loop'], isTrue);
      },
    );

    test('a byte-order mark does not stop the document parsing', () async {
      // jsonDecode fails on U+FEFF before it reaches the first brace, so a
      // config saved by a Windows editor would not load at all if the bytes
      // reached it with the mark still on them.
      final key = _key<JsonValue>('bom', <int>[
        ..._bom,
        ...utf8.encode('{"ok": true}'),
      ]);

      final value = await const JsonLoader().load(key);

      expect(value.asMap['ok'], isTrue);
    });

    test('asMap on an array says what the top level is', () async {
      final key = _text<JsonValue>('lines', '[1, 2]');
      final value = await const JsonLoader().load(key);

      expect(
        () => value.asMap,
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            allOf(contains('an array'), contains('not an object')),
          ),
        ),
        reason:
            'a cast would report List<dynamic> against Map<String, Object?> '
            'from inside the game code and never say the file was the wrong '
            'shape',
      );
    });

    test('asList on an object says what the top level is', () async {
      final key = _text<JsonValue>('balance', '{"a": 1}');
      final value = await const JsonLoader().load(key);

      expect(
        () => value.asList,
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            allOf(contains('an object'), contains('not an array')),
          ),
        ),
      );
    });
  });

  group('TextLoader', () {
    test('decodes UTF-8, not the bytes one to one', () async {
      // Latin-1 would read this as four characters and pass a test that only
      // checked the string was non-empty.
      final key = _text<String>('credits', 'Asa — 東京');

      expect(await const TextLoader().load(key), 'Asa — 東京');
    });

    test('drops a leading byte-order mark', () async {
      final key = _key<String>('credits', <int>[
        ..._bom,
        ...utf8.encode('Thanks for playing'),
      ]);

      final text = await const TextLoader().load(key);

      expect(text, 'Thanks for playing');
      expect(
        text.codeUnitAt(0),
        'T'.codeUnitAt(0),
        reason:
            'an invisible leading character fails every comparison a project '
            'makes against the text and shows nothing in a debugger',
      );
    });

    test('refuses bytes that are not UTF-8 instead of substituting', () async {
      // allowMalformed would turn this into U+FFFD and ship it as content.
      final key = _key<String>('broken', <int>[0xC3, 0x28]);

      expect(
        () => const TextLoader().load(key),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('BytesLoader', () {
    test('hands back the file unchanged', () async {
      final bytes = <int>[0, 255, 13, 10, 0x1A, 127];
      final key = _key<Uint8List>('autosave', bytes);

      expect(await const BytesLoader().load(key), bytes);
    });
  });

  group('the registry keys each kind under its own type', () {
    // The one property the payload types have to have, and the reason
    // JsonValue is a class. `AssetLoaders` is a Map<Type, Object> keyed on the
    // reified argument, and a typedef or an extension type erases to its
    // representation there - so a JsonValue that was `Object?` underneath
    // would register over the top of every other kind and answer for all of
    // them.
    test('three registrations are three entries', () {
      expect(AssetLoaders.of<JsonValue>(), isA<JsonLoader>());
      expect(AssetLoaders.of<String>(), isA<TextLoader>());
      expect(AssetLoaders.of<Uint8List>(), isA<BytesLoader>());
    });

    test('a key finds its own decoder with no subclass', () {
      // AssetKey.loader falls back to the registry, which is what lets
      // `JsonKey(BundleSource('balance.json'))` be written inline.
      expect(_text<JsonValue>('a', '{}').loader, isA<JsonLoader>());
      expect(_text<String>('b', 'x').loader, isA<TextLoader>());
      expect(_key<Uint8List>('c', <int>[1]).loader, isA<BytesLoader>());
    });

    test('the payload type a key reports is the one it was written with', () {
      expect(_text<JsonValue>('a', '{}').payloadType, JsonValue);
      expect(
        _text<JsonValue>('a', '{}').payloadType,
        isNot(_text<String>('b', 'x').payloadType),
        reason:
            'an erased payload type would make every kind the same asset '
            'identity for one source',
      );
    });
  });

  group('what claiming String and Uint8List engine-wide costs', () {
    // AssetLoaders.register is a silent overwrite keyed by type, and the
    // kernel now claims two of the most general types in Dart. Neither of
    // these cases asserts that the design is good; they pin what it does, so
    // the doc on TextLoader is a statement someone measured.
    test('a project registering its own String decoder replaces the kernel', () async {
      AssetLoaders.register<String>(const _ShoutingTextLoader());

      expect(
        AssetLoaders.of<String>(),
        isA<_ShoutingTextLoader>(),
        reason: 'later wins, with nothing raised and nothing logged',
      );

      final key = _text<String>('credits', 'thanks');
      assets.declare(key);
      expect(
        (await assets.load(key)).value,
        'THANKS',
        reason:
            'and it answers for every TextAsset in the process, including the '
            'ones other packages declared - the claim is engine-wide, not '
            'scoped to the game that made it',
      );
    });

    test('two text kinds need two payload types, not two decoders', () async {
      // The typedef argument from the other side. One type is one entry, so
      // CSV cannot be `Asset<String>` with a different loader; it needs a
      // payload type of its own, which is exactly why JsonValue is a class.
      AssetLoaders.register<_Csv>(const _CsvLoader());

      final asText = _text<String>('table', 'a,b\nc,d');
      final asCsv = _text<_Csv>('table', 'a,b\nc,d');

      final text = assets.declare(asText);
      final csv = assets.declare(asCsv);
      await assets.load(asText);
      await assets.load(asCsv);

      expect(text.value, 'a,b\nc,d');
      expect(csv.value.rows, <List<String>>[
        <String>['a', 'b'],
        <String>['c', 'd'],
      ]);
      expect(
        AssetLoaders.of<String>(),
        isA<TextLoader>(),
        reason: 'and the plain text kind is untouched by the second one',
      );
    });
  });

  group('the whole path', () {
    test('a JSON asset declares to an address and then loads', () async {
      final key = _text<JsonValue>('balance', '{"damage": 7}');
      final handle = assets.declare(key);

      expect(handle.pack(), isNonNegative);
      expect(handle.isLoaded, isFalse);

      await assets.load(key);

      expect(handle.isLoaded, isTrue);
      expect(handle.value.asMap['damage'], 7);
      expect(
        handle.info,
        isNull,
        reason:
            'nothing about a decoded document is needed on a copy that cannot '
            'read it',
      );
    });

    test('text and bytes for one source are two assets', () async {
      // Identity is (payload type, source), so the same file read two ways is
      // two addresses and two decodes - the property that lets a kind be added
      // without renumbering anything.
      final bytes = utf8.encode('hi');
      final asText = _key<String>('note', bytes);
      final asBlob = _key<Uint8List>('note', bytes);

      final text = assets.declare(asText);
      final blob = assets.declare(asBlob);
      await assets.load(asText);
      await assets.load(asBlob);

      expect(text.pack(), isNot(blob.pack()));
      expect(text.value, 'hi');
      expect(blob.value, bytes);
    });
  });
}
