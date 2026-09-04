import 'package:meta/meta.dart';

/// One entry of an asset list, in the shape Flutter's own `assets:` takes.
///
/// `flutter: assets:` and `good: assets:` are two lists. What a project puts
/// in the first is bundled and read by path; what it puts in the second goes
/// through good's pipeline. The rule between them is **transferability**: an
/// entry moves from one list to the other and loses nothing on the way. So
/// this parses what `AssetsEntry` parses
/// (`flutter_tools/lib/src/flutter_manifest.dart`), and [descriptor] writes
/// back what that one writes - a bare path string when there is nothing else
/// to say, a map otherwise. Either result can be pasted into either list.
///
/// A key Flutter takes and this drops would quietly change what a moved entry
/// means, so an unrecognised key is **refused by name**. Flutter ignores one;
/// being stricter is the direction that can be relaxed later without anyone's
/// build having silently meant something else in the meantime.
///
/// One deliberate widening: Flutter's parser insists on `YamlList` and
/// `YamlMap` for the nested sections, so it cannot read back its own
/// [descriptor], which is made of plain lists and maps. This reads either, so
/// parse and descriptor are actual inverses.
@immutable
class AssetEntry {
  const AssetEntry({
    required this.uri,
    this.flavors = const <String>{},
    this.platforms = const <String>{},
    this.transformers = const <AssetTransformer>[],
  });

  /// The path, held as a `Uri` the way Flutter holds it.
  final Uri uri;

  /// The build flavors that ship this entry. Empty ships in all of them.
  final Set<String> flavors;

  /// The target platforms that ship this entry. Empty ships on all of them.
  final Set<String> platforms;

  /// Transformers to run over the files, in the order written.
  ///
  /// Parsed and carried, not run. Under `good:` the bundling pipeline is
  /// itself the last transformer in the chain, and nothing runs usefully after
  /// a chunk.
  final List<AssetTransformer> transformers;

  /// The path as the pubspec writes it.
  String get path => uri.toString();

  static const String pathKey = 'path';
  static const String flavorsKey = 'flavors';
  static const String platformsKey = 'platforms';
  static const String transformersKey = 'transformers';

  /// Every key an entry may carry, which is exactly Flutter's four.
  static const Set<String> keys = <String>{
    pathKey,
    flavorsKey,
    platformsKey,
    transformersKey,
  };

  /// The platform names `platforms:` accepts.
  ///
  /// Flutter's `_kValidPluginPlatforms`. Refusing outside it here rather than
  /// carrying the value through means a typo is a message naming the six, not
  /// an entry that ships nowhere and says nothing.
  static const Set<String> validPlatforms = <String>{
    'android',
    'ios',
    'web',
    'windows',
    'linux',
    'macos',
  };

  /// Reads one entry, or throws saying which entry and which key.
  ///
  /// [context] names the list being read, so a message can say where to look
  /// in a pubspec that has two of them.
  factory AssetEntry.parse(Object? yaml, {String context = 'assets'}) {
    if (yaml == null || yaml == '') {
      throw ArgumentError('$context: an entry is null or empty.');
    }
    if (yaml is String) {
      return AssetEntry(uri: _uri(yaml, context));
    }
    if (yaml is! Map) {
      throw ArgumentError(
        '$context: an entry is a ${yaml.runtimeType}. An entry is either a '
        'path or a map with a `$pathKey:` in it.',
      );
    }

    final unknown = <String>[
      for (final key in yaml.keys)
        if (!keys.contains(key)) '$key',
    ]..sort();
    if (unknown.isNotEmpty) {
      // Named rather than ignored. The two lists are meant to be
      // interchangeable, and an entry moved here that quietly lost a key would
      // be a build doing less than the line in front of the reader says.
      throw ArgumentError(
        '$context: an entry carries ${unknown.join(', ')}, which is not one of '
        '${keys.join(', ')}.',
      );
    }

    final path = yaml[pathKey];
    if (path is! String || path.isEmpty) {
      throw ArgumentError(
        '$context: an entry has no `$pathKey:`. A map entry needs one; a plain '
        'path on its own line is the short form.',
      );
    }

    return AssetEntry(
      uri: _uri(path, context),
      flavors: _strings(yaml[flavorsKey], flavorsKey, path, context).toSet(),
      platforms: _platforms(yaml[platformsKey], path, context),
      transformers: _transformers(yaml[transformersKey], path, context),
    );
  }

  /// What this entry looks like written back into either list.
  ///
  /// A bare string when nothing but the path is set, which is both what
  /// Flutter emits and what almost every entry a person writes looks like.
  Object get descriptor {
    if (flavors.isEmpty && platforms.isEmpty && transformers.isEmpty) {
      return path;
    }
    return <String, Object?>{
      pathKey: path,
      if (flavors.isNotEmpty) flavorsKey: flavors.toList(),
      if (platforms.isNotEmpty) platformsKey: platforms.toList(),
      if (transformers.isNotEmpty)
        transformersKey: <Object?>[
          for (final transformer in transformers) transformer.descriptor,
        ],
    };
  }

  static Uri _uri(String path, String context) {
    try {
      return Uri.parse(path);
    } on FormatException {
      throw ArgumentError('$context: "$path" is not a path Flutter can read.');
    }
  }

  static List<String> _strings(
    Object? yaml,
    String key,
    String path,
    String context,
  ) {
    if (yaml == null) return const <String>[];
    if (yaml is! List) {
      throw ArgumentError(
        '$context: `$key:` on "$path" is a ${yaml.runtimeType}, not a list.',
      );
    }
    for (final value in yaml) {
      if (value is! String) {
        throw ArgumentError(
          '$context: `$key:` on "$path" holds a ${value.runtimeType}, and '
          'every entry in it has to be a string.',
        );
      }
    }
    return <String>[for (final value in yaml) value as String];
  }

  static Set<String> _platforms(Object? yaml, String path, String context) {
    final names = _strings(yaml, platformsKey, path, context);
    final invalid = names.where((n) => !validPlatforms.contains(n)).toList()
      ..sort();
    if (invalid.isNotEmpty) {
      throw ArgumentError(
        '$context: `$platformsKey:` on "$path" names ${invalid.join(', ')}. '
        'The platforms are ${validPlatforms.join(', ')}.',
      );
    }
    return names.toSet();
  }

  static List<AssetTransformer> _transformers(
    Object? yaml,
    String path,
    String context,
  ) {
    if (yaml == null) return const <AssetTransformer>[];
    if (yaml is! List) {
      throw ArgumentError(
        '$context: `$transformersKey:` on "$path" is a ${yaml.runtimeType}, '
        'not a list.',
      );
    }
    return <AssetTransformer>[
      for (final entry in yaml) AssetTransformer.parse(entry, path, context),
    ];
  }

  @override
  bool operator ==(Object other) =>
      other is AssetEntry &&
      uri == other.uri &&
      _sameSet(flavors, other.flavors) &&
      _sameSet(platforms, other.platforms) &&
      _sameList(transformers, other.transformers);

  @override
  int get hashCode => Object.hash(
    uri,
    Object.hashAllUnordered(flavors),
    Object.hashAllUnordered(platforms),
    Object.hashAll(transformers),
  );

  @override
  String toString() => 'AssetEntry($descriptor)';
}

/// One entry of an asset's `transformers:` list.
///
/// Mirrors Flutter's `AssetTransformerEntry`, down to [descriptor] writing
/// `args:` whether or not there are any - a round trip that dropped an empty
/// list would not be one.
@immutable
class AssetTransformer {
  const AssetTransformer({required this.package, this.args = const <String>[]});

  /// The package whose executable runs.
  final String package;

  /// What is passed to it, before the file arguments Flutter adds.
  final List<String> args;

  static const String packageKey = 'package';
  static const String argsKey = 'args';

  static const Set<String> keys = <String>{packageKey, argsKey};

  factory AssetTransformer.parse(Object? yaml, String path, String context) {
    if (yaml is! Map) {
      throw ArgumentError(
        '$context: a transformer on "$path" is a ${yaml.runtimeType}, not a '
        'map with a `$packageKey:` in it.',
      );
    }
    final unknown = <String>[
      for (final key in yaml.keys)
        if (!keys.contains(key)) '$key',
    ]..sort();
    if (unknown.isNotEmpty) {
      throw ArgumentError(
        '$context: a transformer on "$path" carries ${unknown.join(', ')}, '
        'which is not one of ${keys.join(', ')}.',
      );
    }
    final package = yaml[packageKey];
    if (package is! String || package.isEmpty) {
      throw ArgumentError(
        '$context: a transformer on "$path" has no `$packageKey:`.',
      );
    }
    return AssetTransformer(
      package: package,
      args: AssetEntry._strings(yaml[argsKey], argsKey, path, context),
    );
  }

  Map<String, Object?> get descriptor => <String, Object?>{
    packageKey: package,
    argsKey: args,
  };

  @override
  bool operator ==(Object other) =>
      other is AssetTransformer &&
      package == other.package &&
      _sameList(args, other.args);

  @override
  int get hashCode => Object.hash(package, Object.hashAll(args));

  @override
  String toString() => 'AssetTransformer($descriptor)';
}

bool _sameSet(Set<String> a, Set<String> b) =>
    a.length == b.length && a.containsAll(b);

bool _sameList<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
