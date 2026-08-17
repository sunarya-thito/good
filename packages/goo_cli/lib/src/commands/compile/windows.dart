import 'package:goo_cli/src/commands/compile.dart';

/// `goo compile windows`.
///
/// The pipeline itself - codegen, asset packing, `flutter build windows`,
/// bundling the pack alongside the executable - is Phase 4 and not written.
/// What this does today is resolve and report the configuration it *would*
/// run with, which is worth having on its own: it exercises the whole command
/// path end to end, and it is how you check that a command line means what you
/// thought it meant before any of it does real work.
class WindowsCompileCommand extends CompileSubCommand {
  @override
  void execute() {
    info
      ..println('goo compile windows')
      ..printf('  input:      %s\n', [inputDir.value.path])
      ..printf('  output:     %s\n', [outputDir.value.path])
      ..printf('  encryption: %s\n', [assetEncryption.value.name]);

    // Only under --verbose: true of every run and therefore noise in the
    // ordinary one, but the first thing worth knowing when a run surprises
    // you.
    debug.println('  (paths are resolved by parseFile, so both already exist)');

    if (dryRun.value) {
      info.println('Dry run - stopping before any work.');
      return;
    }

    // Deliberately not a silent no-op. A build tool that prints a plan and
    // exits zero having built nothing is worse than one that says so: the
    // failure would surface later as a missing artifact with no explanation.
    err.println(
      'The Windows build pipeline is not implemented yet (Phase 4). Re-run '
      'with --dry-run to see the resolved configuration without this error.',
    );
  }
}
