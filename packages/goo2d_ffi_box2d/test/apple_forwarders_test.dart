// Holds the Apple source list to the one src/CMakeLists.txt builds.
//
// Windows, Linux and Android compile the shim through src/CMakeLists.txt,
// which globs src/box2d/src/*.c. CocoaPods cannot glob outside the pod root,
// so ios/Classes and macos/Classes each carry a file naming those sources one
// per #include, and that list is the second place the build is described.
//
// The first time the two lists disagreed, the podspecs stopped naming any
// source at all and Apple shipped an application with no shim in it - a build
// that succeeded and then failed at the first physics call (#208). This runs
// wherever `flutter test` runs, so a source added to src/ without the
// forwarders is caught on the machine that added it.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The `#include`d paths in a forwarder, in the order they appear.
List<String> includesIn(String path) {
  final file = File(path);
  expect(file.existsSync(), isTrue, reason: '$path is missing');
  return RegExp(r'^#include\s+"([^"]+)"', multiLine: true)
      .allMatches(file.readAsStringSync())
      .map((match) => match.group(1)!)
      .toList();
}

void main() {
  const platforms = ['ios', 'macos'];

  test('every vendored Box2D source is compiled on Apple', () {
    final onDisk =
        Directory('src/box2d/src')
            .listSync()
            .map((entry) => entry.uri.pathSegments.last)
            .where((name) => name.endsWith('.c'))
            .map((name) => '../../src/box2d/src/$name')
            .toList()
          ..sort();

    expect(onDisk, isNotEmpty, reason: 'the vendored Box2D copy is missing');

    for (final platform in platforms) {
      final forwarded = includesIn('$platform/Classes/box2d.c')..sort();
      expect(
        forwarded,
        onDisk,
        reason:
            'src/box2d/src and $platform/Classes/box2d.c disagree. '
            'src/CMakeLists.txt globs that directory, so the other platforms '
            'have already picked the change up.',
      );
    }
  });

  test('every shim source is compiled on Apple', () {
    final onDisk =
        Directory('src')
            .listSync()
            .whereType<File>()
            .map((file) => file.uri.pathSegments.last)
            .where((name) => name.endsWith('.c'))
            .map((name) => '../../src/$name')
            .toList()
          ..sort();

    expect(onDisk, isNotEmpty);

    for (final platform in platforms) {
      final forwarded = includesIn('$platform/Classes/goo2d_ffi_box2d.c')
        ..sort();
      expect(forwarded, onDisk, reason: 'src/*.c and $platform disagree');
    }
  });

  test('the two platforms compile the same files', () {
    for (final name in ['box2d.c', 'goo2d_ffi_box2d.c']) {
      expect(
        File('ios/Classes/$name').readAsStringSync(),
        File('macos/Classes/$name').readAsStringSync(),
        reason: 'ios/Classes/$name and macos/Classes/$name have drifted',
      );
    }
  });

  test('the podspecs compile Classes and nothing outside the pod root', () {
    for (final platform in platforms) {
      final podspec = File(
        '$platform/goo2d_ffi_box2d.podspec',
      ).readAsStringSync();
      final sourceFiles = RegExp(
        r'^\s*s\.source_files\s*=\s*(.+)$',
        multiLine: true,
      ).firstMatch(podspec);

      expect(sourceFiles, isNotNull, reason: '$platform names no source_files');
      expect(
        sourceFiles!.group(1),
        contains('Classes/'),
        reason: '$platform has to compile the forwarders',
      );
      expect(
        sourceFiles.group(1),
        isNot(contains('../')),
        reason:
            'CocoaPods matches source_files against the files under the pod '
            'root, so a $platform pattern starting ../ matches nothing and '
            'the pod compiles empty',
      );
    }
  });
}
