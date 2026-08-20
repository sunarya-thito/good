import 'dart:io';

/// Removes the loose copies of assets that are now inside a chunk.
///
/// # Why a release build has to do this
///
/// Flutter bundles what `flutter: assets:` lists. The packed directory has to
/// be listed or the chunks never ship - but the asset directory is listed too,
/// and left alone a release build carries every asset twice: once loose and
/// legible, once inside an encrypted chunk. That is double the download, and it
/// hands back in plaintext exactly what packing was for.
///
/// # What comes out, and why it is that set
///
/// [packed] is the logical paths the pack step wrote into a chunk, so the bytes
/// of every file removed here are in one. Nothing else in [assetDir] is
/// touched: a file no chunk carries is still the only copy of itself, and
/// emptying the directory would destroy it for nothing.
///
/// This used to remove the *compaction outputs* instead, which is a different
/// set in both directions. A file placed in [assetDir] by hand is packed and
/// was never a compaction output, so it survived and shipped a second time in
/// plaintext. A compaction output the pubspec does not declare is not packed,
/// and was deleted anyway.
///
/// Compaction rebuilds anything it generated. A hand-placed original has
/// nowhere to come back from, so a caller that can tell the two apart should
/// say which is which - see `BuildSubCommand._stripLoose`.
///
/// Returns how many files were removed.
int stripLoose({
  required Directory assetDir,
  required Iterable<String> packed,
  required String assetRoot,
  void Function(String path)? onStrip,
}) {
  final root = assetRoot.endsWith('/') ? assetRoot : '$assetRoot/';
  var removed = 0;
  for (final logical in packed) {
    // The same arithmetic `packAssets` used to find the file it read, so strip
    // and pack cannot disagree about which file a logical path names.
    final relative = logical.startsWith(root)
        ? logical.substring(root.length)
        : logical;
    final file = File('${assetDir.path}/$relative');
    if (!file.existsSync()) continue;
    file.deleteSync();
    removed++;
    onStrip?.call(relative);
  }
  return removed;
}
