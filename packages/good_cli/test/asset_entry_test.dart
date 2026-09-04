import 'dart:io';

import 'package:good_cli/src/assets/entry.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

// `good: assets:` against `flutter: assets:`.
//
// The rule the two lists are built on is transferability: an entry moves from
// one to the other and loses nothing. So parity is a **property**, not a list
// somebody keeps in step by hand - and the property is checked against
// Flutter's own parser rather than against a copy of it. The keys and the
// platform names below are read out of `flutter_manifest.dart` in the SDK on
// this machine at run time, so a key Flutter adds is a failing test here
// instead of an option good drops in silence.
//
// The other half is that parse and descriptor are inverses. An entry that
// parses and then writes back something else is a moved entry that means
// something different in its new list, which is the same failure arriving by a
// different road.

/// `flutter_manifest.dart` in whichever SDK this machine runs.
///
/// Not skipped when it is missing. A test that quietly stops asking is exactly
/// the hand-kept checklist this file exists to avoid being.
File _flutterManifest() {
  for (final root in _candidateRoots()) {
    final file = File(
      '$root/packages/flutter_tools/lib/src/flutter_manifest.dart',
    );
    if (file.existsSync()) return file;
  }
  fail(
    'No Flutter SDK found, so the entry keys good must match cannot be read. '
    'Set FLUTTER_ROOT, or put `flutter` on PATH.',
  );
}

Iterable<String> _candidateRoots() sync* {
  final declared = Platform.environment['FLUTTER_ROOT'];
  if (declared != null && declared.isNotEmpty) yield declared;

  // A Dart from inside a Flutter SDK sits at <root>/bin/cache/dart-sdk/bin/.
  var dir = File(Platform.resolvedExecutable).parent;
  for (var i = 0; i < 5; i++) {
    yield dir.path;
    if (dir.parent.path == dir.path) break;
    dir = dir.parent;
  }

  final path = Platform.environment['PATH'] ?? '';
  for (final entry in path.split(Platform.isWindows ? ';' : ':')) {
    if (entry.isEmpty) continue;
    for (final name in const <String>['flutter', 'flutter.bat']) {
      if (File('$entry/$name').existsSync()) {
        yield Directory('$entry/..').absolute.path;
      }
    }
  }
}

/// The body of one class in [source], by brace counting.
String _classBody(String source, String name) {
  final start = source.indexOf(RegExp('class $name[ <{]'));
  if (start < 0) fail('flutter_manifest.dart declares no $name any more.');
  final open = source.indexOf('{', start);
  var depth = 0;
  for (var i = open; i < source.length; i++) {
    if (source[i] == '{') depth++;
    if (source[i] == '}') {
      depth--;
      if (depth == 0) return source.substring(open, i);
    }
  }
  fail('$name in flutter_manifest.dart has no closing brace.');
}

/// The string constants a class declares, which is how both of Flutter's
/// entry classes name their keys.
Set<String> _keyConstants(String name) {
  final body = _classBody(_flutterManifest().readAsStringSync(), name);
  final keys = <String>{
    for (final match in RegExp(
      r"static const \w+ = '([\w-]+)';",
    ).allMatches(body))
      match.group(1)!,
  };
  if (keys.isEmpty) {
    fail(
      '$name no longer declares its keys as `static const _x = \'y\';`, so '
      'this test cannot read them. Read the class and fix the pattern - do '
      'not delete the check.',
    );
  }
  return keys;
}

Set<String> _validPlatforms() {
  final source = _flutterManifest().readAsStringSync();
  final match = RegExp(
    r'_kValidPluginPlatforms = <String>\{([^}]*)\}',
  ).firstMatch(source);
  if (match == null) {
    fail('flutter_manifest.dart no longer declares _kValidPluginPlatforms.');
  }
  return <String>{
    for (final name in RegExp("'([\\w-]+)'").allMatches(match.group(1)!))
      name.group(1)!,
  };
}

Object? _yaml(String text) => loadYaml(text);

void main() {
  group('parity with Flutter', () {
    test('good takes the keys AssetsEntry takes, and no others', () {
      expect(
        AssetEntry.keys,
        _keyConstants('AssetsEntry'),
        reason:
            'an entry has to move between the two lists unchanged; a key on '
            'one side only is an option that goes missing on the way',
      );
    });

    test('good takes the keys AssetTransformerEntry takes', () {
      expect(AssetTransformer.keys, _keyConstants('AssetTransformerEntry'));
    });

    test('good takes the platform names Flutter accepts', () {
      expect(AssetEntry.validPlatforms, _validPlatforms());
    });

    test('an entry using every key Flutter declares round-trips unchanged', () {
      final declared = _keyConstants('AssetsEntry');
      const values = <String, Object?>{
        'path': 'assets/game/logo.png',
        'flavors': <String>['paid'],
        'platforms': <String>['android', 'ios'],
        'transformers': <Object?>[
          <String, Object?>{
            'package': 'vector_graphics_compiler',
            'args': <String>['--tessellate'],
          },
        ],
      };
      final unnamed = declared.difference(values.keys.toSet());
      expect(
        unnamed,
        isEmpty,
        reason:
            'AssetsEntry has grown $unnamed. good drops it, and this test has '
            'no value to give it - add the key to AssetEntry and a value here',
      );

      final descriptor = <String, Object?>{
        for (final key in declared) key: values[key],
      };
      expect(AssetEntry.parse(descriptor).descriptor, descriptor);
    });
  });

  group('round trip', () {
    final corpus = <String, Object>{
      'a bare path': 'assets/game/',
      'a map with only a path': <String, Object?>{'path': 'assets/game/'},
      'flavors': <String, Object?>{
        'path': 'assets/premium/',
        'flavors': <String>['paid', 'trial'],
      },
      'platforms': <String, Object?>{
        'path': 'assets/mobile/',
        'platforms': <String>['android', 'ios'],
      },
      'a transformer with no args': <String, Object?>{
        'path': 'assets/logo.svg',
        'transformers': <Object?>[
          <String, Object?>{'package': 'vector_graphics_compiler'},
        ],
      },
      'two transformers, in order': <String, Object?>{
        'path': 'assets/logo.svg',
        'transformers': <Object?>[
          <String, Object?>{
            'package': 'first',
            'args': <String>['--one'],
          },
          <String, Object?>{
            'package': 'second',
            'args': <String>['--two'],
          },
        ],
      },
      'every key at once': <String, Object?>{
        'path': 'assets/logo.svg',
        'flavors': <String>['paid'],
        'platforms': <String>['android'],
        'transformers': <Object?>[
          <String, Object?>{'package': 'vector_graphics_compiler'},
        ],
      },
    };

    corpus.forEach((name, yaml) {
      test('$name survives a parse and a write back', () {
        final once = AssetEntry.parse(yaml);
        final twice = AssetEntry.parse(once.descriptor);
        expect(twice, once);
        expect(twice.descriptor, once.descriptor);
      });

      test('$name reads the same out of real YAML', () {
        // Through the yaml package, because that is what a pubspec arrives
        // as: YamlMap and YamlList, not Map and List.
        final text = 'assets:\n  - ${_asYaml(yaml, 4)}\n';
        final list = (_yaml(text) as YamlMap)['assets'] as YamlList;
        expect(AssetEntry.parse(list.single), AssetEntry.parse(yaml));
      });
    });

    test('a path-only map writes back as a bare path', () {
      // Flutter's own normalisation, and it is the reason to keep it: an
      // entry moved to the other list should read the way someone would have
      // written it there by hand.
      expect(
        AssetEntry.parse(<String, Object?>{'path': 'assets/a.png'}).descriptor,
        'assets/a.png',
      );
    });

    test('an empty args list survives, because Flutter writes one', () {
      final entry = AssetEntry.parse(<String, Object?>{
        'path': 'assets/logo.svg',
        'transformers': <Object?>[
          <String, Object?>{'package': 'p', 'args': <String>[]},
        ],
      });
      expect(
        (entry.descriptor as Map<String, Object?>)['transformers'],
        <Object?>[
          <String, Object?>{'package': 'p', 'args': <String>[]},
        ],
      );
    });

    test('two entries differing only in their transformers are not equal', () {
      // The half a `==` that skipped transformers would hide, and with it
      // every round trip above that carries one.
      final a = AssetEntry.parse(<String, Object?>{
        'path': 'assets/logo.svg',
        'transformers': <Object?>[
          <String, Object?>{'package': 'first'},
        ],
      });
      final b = AssetEntry.parse(<String, Object?>{
        'path': 'assets/logo.svg',
        'transformers': <Object?>[
          <String, Object?>{'package': 'second'},
        ],
      });
      expect(a, isNot(b));
    });
  });

  group('refusals name what is wrong', () {
    void refuses(String name, Object? yaml, String says) {
      test(name, () {
        expect(
          () => AssetEntry.parse(yaml, context: 'good: assets'),
          throwsA(
            isA<ArgumentError>().having(
              (e) => '${e.message}',
              'message',
              contains(says),
            ),
          ),
        );
      });
    }

    refuses('a key that is not one of Flutter\'s', <String, Object?>{
      'path': 'assets/',
      'flavour': 'paid',
    }, 'flavour');
    refuses('a map with no path', <String, Object?>{
      'flavors': <String>[],
    }, 'path');
    refuses('a platform that does not exist', <String, Object?>{
      'path': 'assets/',
      'platforms': <String>['fuchsia'],
    }, 'fuchsia');
    refuses('flavors that are not a list', <String, Object?>{
      'path': 'assets/',
      'flavors': 'paid',
    }, 'not a list');
    refuses('a flavor that is not a string', <String, Object?>{
      'path': 'assets/',
      'flavors': <Object?>[3],
    }, 'has to be a string');
    refuses('a transformer with no package', <String, Object?>{
      'path': 'assets/',
      'transformers': <Object?>[<String, Object?>{}],
    }, 'package');
    refuses(
      'a transformer key that is not one of Flutter\'s',
      <String, Object?>{
        'path': 'assets/',
        'transformers': <Object?>[
          <String, Object?>{'package': 'p', 'arguments': <String>[]},
        ],
      },
      'arguments',
    );
    refuses('an empty entry', '', 'null or empty');
    refuses('a number', 3, 'int');
  });
}

/// One entry written back out as the YAML line a pubspec would carry.
String _asYaml(Object value, int indent) {
  final pad = ' ' * indent;
  if (value is String) return value;
  final map = value as Map<String, Object?>;
  final lines = <String>[];
  map.forEach((key, entry) {
    if (entry is String) {
      lines.add('$key: $entry');
    } else if (entry is List && entry.every((e) => e is String)) {
      lines.add('$key: [${entry.join(', ')}]');
    } else {
      lines.add('$key:');
      for (final item in entry! as List) {
        final fields = item as Map<String, Object?>;
        var first = true;
        fields.forEach((name, field) {
          final written = field is List ? '[${field.join(', ')}]' : '$field';
          lines.add('${first ? '  - ' : '    '}$name: $written');
          first = false;
        });
      }
    }
  });
  return lines.join('\n$pad');
}
