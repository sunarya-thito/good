import 'dart:io';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

class _TokenInfo {
  final String lexeme;
  final int line;
  _TokenInfo(this.lexeme, this.line);
}

void main() {
  // This test is guarded by an environment variable to prevent it from running during normal tests.
  if (Platform.environment['scanCodeIntegrity'] != 'true') {
    return;
  }

  test('Ensures no code changes were made during documentation', () {
    final root = p.current;
    final fileToVerify = Platform.environment['DOC_FILE'];
    if (fileToVerify == null) {
      fail('DOC_FILE env var must be set for integrity check');
    }

    final currentFile = File(p.join(root, fileToVerify));
    if (!currentFile.existsSync()) {
      fail('File $fileToVerify does not exist at ${currentFile.absolute.path}');
    }

    final currentCode = currentFile.readAsStringSync();

    // Get committed version from git
    // We use forward slashes for git paths
    final gitPath = fileToVerify.replaceAll('\\', '/');
    final res = Process.runSync('git', [
      'show',
      'HEAD:$gitPath',
    ], workingDirectory: root);

    if (res.exitCode != 0) {
      fail(
        'Failed to get committed version of $fileToVerify from git: ${res.stderr}\nCommand: git show HEAD:$gitPath',
      );
    }
    final committedCode = res.stdout.toString();

    final currentTokens = _getMeaningfulTokens(currentCode);
    final committedTokens = _getMeaningfulTokens(committedCode);

    final mismatches = <int>[];
    for (
      int i = 0;
      i < currentTokens.length && i < committedTokens.length;
      i++
    ) {
      if (currentTokens[i].lexeme != committedTokens[i].lexeme) {
        mismatches.add(i);
      }
    }

    if (mismatches.isNotEmpty) {
      print(
        '========================================================================',
      );
      print('FOUND ${mismatches.length} TOKEN MISMATCHES');
      print(
        '========================================================================\n',
      );

      for (final idx in mismatches) {
        _reportMismatch(
          currentCode,
          committedCode,
          currentTokens[idx],
          committedTokens[idx],
        );
      }
      fail('Integrity Failure: Found ${mismatches.length} token mismatches.');
    }

    if (currentTokens.length != committedTokens.length) {
      final mismatchIdx = currentTokens.length < committedTokens.length
          ? currentTokens.length
          : committedTokens.length;
      final curT = mismatchIdx < currentTokens.length
          ? currentTokens[mismatchIdx]
          : null;
      final comT = mismatchIdx < committedTokens.length
          ? committedTokens[mismatchIdx]
          : null;
      _reportMismatch(currentCode, committedCode, curT, comT);
      fail(
        'Integrity Failure: Code structure has changed. Expected ${committedTokens.length} tokens, found ${currentTokens.length}.',
      );
    }
  });
}

void _reportMismatch(
  String currentCode,
  String committedCode,
  _TokenInfo? current,
  _TokenInfo? committed,
) {
  print('--- INTEGRITY FAILURE CONTEXT ---');

  if (current != null) {
    print('Current version near Line ${current.line}:');
    _printSourceLines(currentCode, current.line);
  }

  if (committed != null) {
    print('\nCommitted version near Line ${committed.line}:');
    _printSourceLines(committedCode, committed.line);
  }
  print('----------------------------------');
}

void _printSourceLines(String code, int targetLine) {
  final lines = code.split('\n');
  final start = (targetLine - 3).clamp(0, lines.length);
  final end = (targetLine + 2).clamp(0, lines.length);

  for (int i = start; i < end; i++) {
    final ln = i + 1;
    final prefix = (ln == targetLine) ? '> ' : '  ';
    print('$prefix$ln: ${lines[i]}');
  }
}

List<_TokenInfo> _getMeaningfulTokens(String code) {
  try {
    final result = parseString(content: code, throwIfDiagnostics: false);
    final tokens = <_TokenInfo>[];
    var token = result.unit.beginToken;
    while (!token.isEof) {
      // Ignore comments for structural integrity
      tokens.add(
        _TokenInfo(
          token.lexeme,
          result.lineInfo.getLocation(token.offset).lineNumber,
        ),
      );
      token = token.next!;
    }
    return tokens;
  } catch (e) {
    print('Error parsing code for tokens: $e');
    return [];
  }
}
