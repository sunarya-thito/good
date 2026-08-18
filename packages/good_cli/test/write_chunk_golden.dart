import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:good_cli/src/assets/options.dart';
import 'package:good_cli/src/assets/pack.dart';

/// Writes the golden chunk that both packages test against.
///
/// Run from the good_cli package root:
///
/// ```
/// dart run test/write_chunk_golden.dart
/// ```
///
/// Only ever run this deliberately. The whole value of the file is that it
/// does *not* move: `good_cli` checks that its packer still produces these
/// bytes, and `good` checks that its reader still gets the members back out of
/// them. Regenerating to make a failing test pass would delete the only thing
/// holding the two halves of the format together - so if a change here is
/// genuinely intended, bump `chunkVersion` with it.
Future<void> main() async {
  final body = buildChunkBody(<String, Uint8List>{
    for (final entry in goldenMembers.entries)
      entry.key: Uint8List.fromList(utf8.encode(entry.value)),
  });
  final sealed = await sealChunk(
    body: body,
    key: goldenKey,
    compression: AssetCompressionLevel.normal,
  );
  final file = File('../../fixtures/asset_chunk/chunk_v1_aes_gzip.dat');
  file.parent.createSync(recursive: true);
  file.writeAsBytesSync(sealed);
  stdout.writeln('Wrote ${file.path} (${sealed.length} bytes)');
}

/// The key the golden chunk is sealed with. Not a secret and not an example to
/// copy: a real one comes from `lib/good.generated/asset_key.dart`.
final List<int> goldenKey = List<int>.generate(32, (i) => i * 7 % 256);

/// What the golden chunk contains.
const Map<String, String> goldenMembers = <String, String>{
  'assets/a.webp': 'texture bytes',
  'assets/b.ogg': 'audio bytes',
};
