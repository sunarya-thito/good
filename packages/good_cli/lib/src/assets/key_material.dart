/// Reads and rewrites the generated `asset_key.dart`.
///
/// The keys and the manifest share that one file because that is the shape
/// `good generate` established, but they are produced by different commands on
/// different schedules: `generate` writes the keys once and never again, and
/// `pack` rewrites the mapping on every build. So packing edits *only* the
/// mapping and leaves every other line exactly as it found it - rewriting the
/// file wholesale would rotate the keys as a side effect of building, and
/// orphan every pack already shipped.
library;

import 'dart:io';

/// The 32 bytes of key material, assembled from the four parts.
///
/// Parsed out of generated Dart, not kept in a second file. That is a
/// regex over source, which is normally a bad idea - it is acceptable only
/// because good wrote the file itself, in a format it controls, and because the
/// alternative is a second copy of the keys on disk for the packer to read,
/// which is one more place for them to leak from.
List<int> readKeyMaterial(File assetKeyFile) {
  if (!assetKeyFile.existsSync()) {
    throw ArgumentError(
      'No ${assetKeyFile.path}. Run `good generate` first - that is what '
      'creates this project\'s asset keys, once.',
    );
  }
  final source = assetKeyFile.readAsStringSync();
  final material = <int>[];
  for (final name in const <String>[
    '_assetKey',
    '_assetKey2',
    '_assetKey3',
    '_assetKey4',
  ]) {
    final match = RegExp(
      r'List<int>\s+' + name + r'\s*=\s*\[([^\]]*)\]',
    ).firstMatch(source);
    if (match == null) {
      throw ArgumentError(
        'Could not find $name in ${assetKeyFile.path}. If you edited it by '
        'hand, restore it - or delete it and re-run `good generate`, which '
        'will mint new keys and orphan any existing pack.',
      );
    }
    for (final part in match.group(1)!.split(',')) {
      final text = part.trim();
      if (text.isEmpty) continue;
      final value = int.tryParse(text);
      if (value == null) {
        throw ArgumentError('Unparseable byte "$text" in $name.');
      }
      material.add(value);
    }
  }
  if (material.length != 32) {
    throw ArgumentError(
      'Expected 32 key bytes across the four parts, found ${material.length}. '
      'AES-256 needs exactly 32.',
    );
  }
  return material;
}

/// Replaces the `assetMapping` literal, leaving everything else untouched.
///
/// Returns false when the file has no mapping to replace, so the caller can
/// say so instead of silently producing a pack nothing can find.
bool writeAssetMapping(File assetKeyFile, Map<String, String> mapping) {
  if (!assetKeyFile.existsSync()) return false;
  final source = assetKeyFile.readAsStringSync();
  final pattern = RegExp(
    r'final Map<String, String> assetMapping = <String, String>\{[^}]*\};',
  );
  if (!pattern.hasMatch(source)) return false;

  final entries = mapping.keys.toList()..sort();
  final buffer = StringBuffer(
    'final Map<String, String> assetMapping = <String, String>{',
  );
  if (entries.isEmpty) {
    buffer.write('};');
  } else {
    buffer.writeln();
    for (final key in entries) {
      buffer.writeln("  '$key': '${mapping[key]}',");
    }
    buffer.write('};');
  }
  assetKeyFile.writeAsStringSync(
    source.replaceFirst(pattern, buffer.toString()),
  );
  return true;
}
