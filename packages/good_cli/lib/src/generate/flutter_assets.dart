import 'package:good_cli/src/assets/entry.dart';
import 'package:good_cli/src/config.dart';
import 'package:yaml/yaml.dart';

/// The `flutter: assets:` entries good owns, flavor by flavor.
///
/// This is the whole of the development/release split. Every flavor the
/// project declares ships one of two things - the originals, or the chunks -
/// and Flutter's own bundler is what leaves the other one out:
///
/// ```yaml
/// # good: assets: - assets/game/,  good: flavors: {development: raw,
/// #                                                staging: bundled,
/// #                                                production: bundled}
/// flutter:
///   assets:
///     - path: assets/game/
///       flavors: [development]
///     - path: assets/packed/
///       flavors: [staging, production]
/// ```
///
/// `matchesFlavor` (`flutter_tools/lib/src/asset.dart`) ships an entry with
/// no `flavors:` always, and excludes a flavoured one from a build that named
/// no flavor - so a `production` build never sees the originals and nothing
/// has to delete them afterwards. That is what replaced stripping: there is no
/// moment at which both copies are in one bundle.
///
/// An entry that declares flavors of its own is intersected with the raw set
/// rather than replaced by it, and **an empty intersection emits nothing**.
/// Empty is not "ships everywhere" here: it is an asset whose flavors and the
/// raw flavors have no build in common, so there is no raw copy to ship.
///
/// `platforms:` and `transformers:` are carried onto the raw copy verbatim,
/// which is what makes it the same entry. The transformers run in a
/// development build because Flutter runs them; in a bundled one good's
/// pipeline is the last transformer in the chain.
List<AssetEntry> goodFlutterAssets(GoodConfig config) {
  final raw = config.rawFlavors;
  final entries = <AssetEntry>[];
  for (final entry in config.assets) {
    // The chunk directory is not a source even when someone lists it as one:
    // it is made *from* the sources, and it ships under the bundled flavors
    // below.
    if (entry.path == config.packOutput) continue;
    final flavors = <String>[
      for (final flavor in raw)
        if (entry.flavors.isEmpty || entry.flavors.contains(flavor)) flavor,
    ];
    if (flavors.isEmpty) continue;
    entries.add(
      AssetEntry(
        uri: entry.uri,
        flavors: flavors.toSet(),
        platforms: entry.platforms,
        transformers: entry.transformers,
      ),
    );
  }
  final bundled = config.bundledFlavors;
  if (bundled.isNotEmpty) {
    entries.add(
      AssetEntry(uri: Uri.parse(config.packOutput), flavors: bundled.toSet()),
    );
  }
  return entries;
}

/// The paths in `flutter: assets:` that good writes and rewrites.
///
/// Everything else in that list is the project's and is left where it is -
/// `flutter: assets:` is not good's list, and a project bundling its own UI
/// art through `Image.asset` must not lose it because good regenerated.
Set<String> goodOwnedAssetPaths(GoodConfig config) => <String>{
  for (final entry in config.assets) entry.path,
  config.packOutput,
};

/// What to tell someone whose pubspec this cannot edit - the same shape
/// `pubspecPatch` prints, for the same reason.
String flutterAssetsPatch(GoodConfig config) => <String>[
  'flutter:',
  '  assets:',
  for (final entry in goodFlutterAssets(config))
    ...assetEntryLines(entry, '    '),
].join('\n');

/// One entry as pubspec lines, indented to [indent] and starting with `- `.
///
/// Block style throughout, and every scalar quoted unless it is plainly safe.
/// These lines are read back by Flutter's own parser, so a path with a space
/// or a colon in it has to survive the round trip - an entry that parsed as
/// something else would bundle something else.
List<String> assetEntryLines(AssetEntry entry, String indent) {
  final descriptor = entry.descriptor;
  if (descriptor is String) return <String>['$indent- ${_scalar(descriptor)}'];
  final map = descriptor as Map<String, Object?>;
  final lines = <String>['$indent- path: ${_scalar(entry.path)}'];
  for (final key in <String>[AssetEntry.flavorsKey, AssetEntry.platformsKey]) {
    final values = map[key];
    if (values is! List || values.isEmpty) continue;
    lines.add('$indent  $key: ${_flow(values.cast<String>())}');
  }
  if (entry.transformers.isNotEmpty) {
    lines.add('$indent  ${AssetEntry.transformersKey}:');
    for (final transformer in entry.transformers) {
      lines.add(
        '$indent    - ${AssetTransformer.packageKey}: '
        '${_scalar(transformer.package)}',
      );
      if (transformer.args.isNotEmpty) {
        lines.add(
          '$indent      ${AssetTransformer.argsKey}: ${_flow(transformer.args)}',
        );
      }
    }
  }
  return lines;
}

String _flow(List<String> values) => '[${values.map(_scalar).join(', ')}]';

/// [value] as YAML, quoted where a plain scalar would not read back the same.
///
/// The safe set is deliberately narrow. A path is a path and a flavor name is
/// letters and digits; anything else goes in double quotes, which costs two
/// characters and removes the whole class of "this parsed as a map".
String _scalar(String value) {
  if (RegExp(r'^[A-Za-z0-9_./-]+$').hasMatch(value)) return value;
  final escaped = value.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
  return '"$escaped"';
}

/// [lines] with good's entries in `flutter: assets:` replaced by what
/// [goodFlutterAssets] says they are now, or null if the pubspec is not a
/// shape this can edit safely.
///
/// Null and not a best guess, the rule every other patcher here follows: the
/// caller prints [flutterAssetsPatch], and a wrong edit to somebody's pubspec
/// is worse than an instruction to make the right one by hand.
///
/// Textual, so the comments a project wrote survive - and **surgical**, so the
/// entries that are not good's survive too. Only the lines an entry good owns
/// occupies are removed, and the replacement block goes where the first of
/// them was, which keeps a hand-ordered list in its order.
///
/// What makes that safe is the last step: the result is parsed again and every
/// entry read back out of the document. A patch that produced a pubspec saying
/// something other than what was intended never reaches the caller.
List<String>? patchedFlutterAssetLines(List<String> lines, GoodConfig config) {
  final YamlNode doc;
  try {
    doc = loadYamlNode(lines.join('\n'));
  } on YamlException {
    return null;
  }
  if (doc is! YamlMap) return null;
  final flutter = doc['flutter'];
  if (flutter is! YamlMap) return null;
  final list = flutter.nodes['assets'];
  if (list is! YamlList) return null;

  final owned = goodOwnedAssetPaths(config);
  final wanted = goodFlutterAssets(config);

  // Which lines belong to which entry, and which of those entries are good's.
  // A flow-style list puts two entries on one line, so there is no line to
  // remove that belongs to just one of them - refused rather than mangled.
  final kept = <AssetEntry?>[];
  final remove = <int>{};
  var insertAt = -1;
  var previousEnd = -1;
  String? indent;
  for (final node in list.nodes) {
    final start = node.span.start.line;
    if (start <= previousEnd || start >= lines.length) return null;
    final dash = lines[start].indexOf('- ');
    if (dash < 0) return null;
    indent ??= lines[start].substring(0, dash);
    // The item's own lines, measured by indentation rather than taken from
    // the span. A block map's span runs on past its last line to wherever the
    // next token begins, so two neighbouring map entries report overlapping
    // ranges and deleting by span would take the next entry's `- ` with it.
    // A continuation line is indented past the dash; anything at or before it
    // is the next entry, and a blank line ends the item.
    var end = start;
    for (var line = start + 1; line < lines.length; line++) {
      final text = lines[line];
      if (text.trim().isEmpty) break;
      if (text.length - text.trimLeft().length <= dash) break;
      end = line;
    }
    previousEnd = end;

    final AssetEntry entry;
    try {
      entry = AssetEntry.parse(node.value, context: 'flutter: assets');
    } on ArgumentError {
      // Not something good wrote and not something it can read. Left alone,
      // which is the right answer for a list good does not own; the null
      // stands for it in the read-back count below.
      kept.add(null);
      continue;
    }
    if (!owned.contains(entry.path)) {
      kept.add(entry);
      continue;
    }
    if (insertAt < 0) insertAt = start;
    for (var line = start; line <= end; line++) {
      remove.add(line);
    }
  }

  indent ??= '    ';
  final block = <String>[
    for (final entry in wanted) ...assetEntryLines(entry, indent),
  ];
  if (insertAt < 0) {
    // Nothing of good's is in the list yet. The block goes after the last
    // entry, so a project that already lists its own art keeps it first.
    insertAt = previousEnd < 0 ? list.span.start.line : previousEnd + 1;
  }

  final patched = <String>[];
  for (var i = 0; i < lines.length; i++) {
    if (i == insertAt) patched.addAll(block);
    if (remove.contains(i)) continue;
    patched.add(lines[i]);
  }
  if (insertAt >= lines.length) patched.addAll(block);

  // Read back from the document, never from the text. `assets:` is a list in
  // the middle of somebody else's file, and an insertion at the wrong
  // indentation nests under whatever came before it.
  final YamlNode check;
  try {
    check = loadYamlNode(patched.join('\n'));
  } on YamlException {
    return null;
  }
  if (check is! YamlMap) return null;
  final checkedFlutter = check['flutter'];
  if (checkedFlutter is! YamlMap) return null;
  final checkedAssets = checkedFlutter['assets'];
  if (checkedAssets is! YamlList) return null;
  final read = <AssetEntry?>[];
  for (final node in checkedAssets) {
    try {
      read.add(AssetEntry.parse(node, context: 'flutter: assets'));
    } on ArgumentError {
      read.add(null);
    }
  }
  final readGood = <AssetEntry>[
    for (final entry in read)
      if (entry != null && owned.contains(entry.path)) entry,
  ];
  if (!_same(readGood, wanted)) return null;
  final readOther = <AssetEntry?>[
    for (final entry in read)
      if (entry == null || !owned.contains(entry.path)) entry,
  ];
  if (!_same(readOther, kept)) return null;
  return patched;
}

bool _same(List<AssetEntry?> a, List<AssetEntry?> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
