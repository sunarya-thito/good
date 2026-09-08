/// Runs every probe and every negative and prints what the analyzer said.
///
/// The positives under `lib/` must produce no error and no warning; the
/// negatives under `neg/` must each produce at least one error, because a
/// clean analysis on its own proves nothing - a member that had degraded to
/// `dynamic` would analyse clean too and fail only at run time.
///
///     dart run tool/check.dart
library;

import 'dart:io';

void main() {
  var failures = 0;

  for (final file in _dartFilesIn('lib')) {
    final report = _analyze(file);
    final bad = report.errors + report.warnings;
    if (bad != 0) {
      failures++;
      stdout.writeln('FAIL $file expected no error, got $bad');
      stdout.writeln(report.text);
    } else {
      final lints = report.lints.toList()..sort();
      stdout.writeln('ok   $file  no error, ${report.infos} info $lints');
    }
  }

  for (final file in _dartFilesIn('neg')) {
    final report = _analyze(file);
    if (report.errors == 0) {
      failures++;
      stdout.writeln('FAIL $file expected an error, analysed clean');
    } else {
      final codes = report.errorCodes.toList()..sort();
      stdout.writeln('ok   $file  ${report.errors} error $codes');
    }
  }

  stdout.writeln(failures == 0 ? 'all probes behaved' : '$failures failed');
  exitCode = failures == 0 ? 0 : 1;
}

Iterable<String> _dartFilesIn(String directory) =>
    Directory(directory)
        .listSync()
        .whereType<File>()
        .map((file) => file.path.replaceAll(r'\', '/'))
        .where((path) => path.endsWith('.dart'))
        .toList()
      ..sort();

_Report _analyze(String file) {
  final result = Process.runSync('dart', [
    'analyze',
    '--format=machine',
    file,
  ], runInShell: true);
  final text = '${result.stdout}${result.stderr}';
  var errors = 0;
  var warnings = 0;
  var infos = 0;
  final errorCodes = <String>{};
  final lints = <String>{};
  for (final line in text.split('\n')) {
    final parts = line.trim().split('|');
    if (parts.length < 4) continue;
    final severity = parts[0];
    final code = parts[2].toLowerCase();
    switch (severity) {
      case 'ERROR':
        errors++;
        errorCodes.add(code);
      case 'WARNING':
        warnings++;
      case 'INFO':
        infos++;
        lints.add(code);
    }
  }
  return _Report(errors, warnings, infos, errorCodes, lints, text);
}

class _Report {
  _Report(
    this.errors,
    this.warnings,
    this.infos,
    this.errorCodes,
    this.lints,
    this.text,
  );

  final int errors;
  final int warnings;
  final int infos;
  final Set<String> errorCodes;
  final Set<String> lints;
  final String text;
}
