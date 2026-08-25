import 'dart:io';
import 'dart:typed_data';

import 'package:good/src/asset.dart';

/// An [AssetMount] backed by a directory on disk.
///
/// The tier that cannot come from the app bundle: a DLC folder, a mod folder,
/// a downloaded patch unpacked next to the executable, or - mounted last in a
/// debug build - the project's own `assets/` tree, so that editing a PNG and
/// restarting the simulation shows the new one without a rebuild.
///
/// A logical path is appended to [directory] as-is, so a mount of
/// `C:/games/mymod` answers `assets/player.png` with
/// `C:/games/mymod/assets/player.png`. Nothing is renamed on the way through,
/// which is what makes a directory a drop-in shadow of the shipped copy.
class DirectoryMount extends AssetMount {
  const DirectoryMount(this.directory);

  /// The directory logical paths are resolved against. No trailing separator
  /// is required and one is harmless.
  final String directory;

  File _fileFor(String path) => File('$directory/$path');

  @override
  Future<Uint8List?> tryRead(String path) async {
    final file = _fileFor(path);
    // `exists` then read, rather than reading and catching: a read that fails
    // for any reason other than absence - a permission error, a directory
    // where a file was expected - is a real fault and must not be turned into
    // "ask the tier below", which would quietly serve the shipped copy and
    // call the mod loaded.
    if (!await file.exists()) return null;
    return file.readAsBytes();
  }

  @override
  Future<AssetAvailability?> check(String path) async {
    // The one mount that can answer honestly without reading. A file that is
    // there at a non-zero size is [AssetAvailability.present]; one that is not
    // there is not this mount's asset at all, so the tiers below get asked.
    final stat = await _fileFor(path).stat();
    if (stat.type != FileSystemEntityType.file) return null;
    return stat.size > 0
        ? AssetAvailability.present
        : AssetAvailability.missing;
  }

  @override
  String get description => directory;
}
