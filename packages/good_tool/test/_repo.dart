import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// A directory for one test, taken away when that test finishes.
///
/// The same rule `good_cli`'s `_temp.dart` states: every fixture goes here and
/// nowhere else, and the teardown retries because Windows refuses to delete a
/// directory while a subprocess still holds a handle inside it.
Directory testTempDir(String prefix) {
  final dir = Directory.systemTemp.createTempSync(prefix);
  addTearDown(() => removeTempDir(dir));
  return dir;
}

void removeTempDir(Directory dir) {
  for (var attempt = 0; attempt < 5; attempt++) {
    if (!dir.existsSync()) return;
    try {
      dir.deleteSync(recursive: true);
      return;
    } on FileSystemException {
      sleep(const Duration(milliseconds: 50));
    }
  }
}

/// One package to write into a fixture repository.
class FakePackage {
  const FakePackage(
    this.name, {
    this.files = const <String, String>{},
    this.dependencies = const <String>[],
    this.published = true,
  });

  final String name;

  /// Paths under `lib/`, to their contents. The `<name>.dart` entry is the
  /// package's entry library.
  final Map<String, String> files;

  final List<String> dependencies;

  /// Whether the pubspec omits `publish_to: none`, which is what decides
  /// whether the tool writes into the package at all.
  final bool published;
}

/// Writes a repository the tool will recognise: `mkdocs.yml` beside
/// `packages/`, one directory per package.
///
/// A real tree and not a stub, because what is under test reads pubspecs,
/// walks `lib/` and follows `export` directives across package boundaries -
/// every one of which is a fact about a filesystem.
Directory fakeRepo(List<FakePackage> packages) {
  final dir = testTempDir('good_tool');
  File(p.join(dir.path, 'mkdocs.yml')).writeAsStringSync('site_name: fake\n');
  for (final package in packages) {
    final root = p.join(dir.path, 'packages', package.name);
    final lines = <String>[
      'name: ${package.name}',
      if (!package.published) 'publish_to: "none"',
      '',
      'environment:',
      '  sdk: ^3.12.1',
      '',
      'dependencies:',
      for (final dependency in package.dependencies) '  $dependency: ^1.0.0',
      '',
    ];
    File(p.join(root, 'pubspec.yaml'))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(lines.join('\n'));
    package.files.forEach((path, contents) {
      File(p.join(root, 'lib', path))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(contents);
    });
  }
  return dir;
}

/// The `good` stand-in every fixture repository needs.
///
/// Transcribed rather than imported. What the pass reads is the *source* of
/// `Entity`, `Accessor` and `Field`, and a fixture importing the real ones
/// would be testing this suite's package config instead of the scan. It is also
/// a working implementation, so a fixture can be compiled and run.
FakePackage kernelPackage({
  String name = 'good',
  Map<String, String> extra = const <String, String>{},
}) => FakePackage(
  name,
  files: <String, String>{
    '$name.dart': "export 'src/struct.dart';\nexport 'src/data.dart';\n",
    'src/struct.dart': kernelStruct,
    'src/data.dart': kernelData,
    ...extra,
  },
);

/// The `good` stand-in a component-bit fixture needs.
///
/// [kernelPackage] plus the two declarations table generation reads:
/// `ComponentDescriptor`, which a `describeType` body takes, and
/// `GeneratedComponentBits`, which the generated table is an instance of.
/// Separate from [kernelPackage] so the accessor fixtures keep reading exactly
/// what they always read.
FakePackage componentKernel({String name = 'good'}) => FakePackage(
  name,
  files: <String, String>{
    '$name.dart': _componentBarrel,
    'src/struct.dart': kernelStruct,
    'src/data.dart': kernelData,
    'src/archetype.dart': kernelArchetype,
  },
);

/// What [componentKernel]'s entry library exports.
const String _componentBarrel = '''
export 'src/struct.dart';
export 'src/data.dart';
export 'src/archetype.dart';
''';

const String kernelArchetype = '''
import 'struct.dart';

class GeneratedComponentBits {
  const GeneratedComponentBits({
    required this.package,
    required this.types,
    this.dependencies = const <GeneratedComponentBits>[],
  });

  final String package;
  final List<Type> types;
  final List<GeneratedComponentBits> dependencies;
}

abstract class ComponentDescriptor {
  void has<T extends Component>({Type? type});
}
''';

const String kernelStruct = '''
import 'data.dart';

abstract interface class Component {}

abstract class Prefab implements Component {}

/// What `Accessor.component` resolves to in this stand-in. The real engine
/// reaches the archetype registry; nothing under test depends on which.
Prefab? mounted;

extension type const Entity(int value) implements int {
  int get archetypeId => (value >> 48) & 0xFFFF;

  Accessor<T> call<T extends Component?>() => Accessor<T>(this);
}

extension type const Accessor<T extends Component?>(Entity entity)
    implements Entity {
  T get component => mounted as T;
}
''';

const String kernelData = '''
import 'struct.dart';

class DataPointer<T> {
  DataPointer(this.initialValue);

  final T initialValue;
  final Map<int, T> rows = <int, T>{};

  T operator [](Entity instance) =>
      rows.containsKey(instance.value) ? rows[instance.value] as T
                                       : initialValue;

  void operator []=(Entity instance, T newValue) {
    rows[instance.value] = newValue;
  }
}

class InitialPointer<T> extends DataPointer<T> {
  InitialPointer(super.initialValue);
}

class DataArrayPointer<T> {}

abstract final class Field {
  static InitialPointer<double> float64([double initialValue = 0.0]) =>
      InitialPointer<double>(initialValue);
  static InitialPointer<int> int32([int initialValue = 0]) =>
      InitialPointer<int>(initialValue);
  static InitialPointer<bool> boolean([bool initialValue = false]) =>
      InitialPointer<bool>(initialValue);
  static InitialPointer<Entity?> optEntity([Entity? initialValue]) =>
      InitialPointer<Entity?>(initialValue);
  static DataArrayPointer<int> array<T>(Object element, int length) =>
      DataArrayPointer<int>();
}
''';
