import 'dart:io';

import 'package:goo_cli/src/assets/compact.dart';

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
/// # Why deleting is safe here, and only here
///
/// Only the outputs named by [compacted] are removed - not everything in
/// [assetDir]. Those are files this build generated from the source directory,
/// and the next `goo assets compact` rebuilds any whose output has gone
/// missing, which is why deleting them costs a re-encode at worst. Anything
/// else there is an original: a file placed by hand, or every file in a project
/// with no source directory at all, whose plan is empty and which therefore
/// loses nothing. Emptying the directory instead would destroy work that cannot
/// be rebuilt.
///
/// Returns how many files were removed.
int stripLoose({
  required Directory assetDir,
  required CompactPlan compacted,
  void Function(String output)? onStrip,
}) {
  var removed = 0;
  for (final step in compacted.steps) {
    final file = File('${assetDir.path}/${step.output}');
    if (!file.existsSync()) continue;
    file.deleteSync();
    removed++;
    onStrip?.call(step.output);
  }
  return removed;
}
