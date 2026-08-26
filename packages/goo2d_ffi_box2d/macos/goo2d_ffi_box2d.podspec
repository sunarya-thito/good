# CocoaPods spec for macOS. Apple platforms do not go through
# ../src/CMakeLists.txt - CocoaPods compiles the sources itself - so the source
# list and the compile flags are stated a second time here. Two things keep
# that second statement honest: Classes/box2d.c names the vendored sources one
# per line where test/apple_forwarders_test.dart can compare them against what
# CMakeLists globs, and the apple job in .github/workflows/test.yml builds an
# application against this podspec and reads the shim's symbols back out of it.
# Neither existed until #208, and until then nothing here had ever been built.
#
# The pod becomes a framework the application loads at launch, so the shim's
# symbols are in the process without a file to open. That is why the Dart
# loader calls DynamicLibrary.process() on Apple and DynamicLibrary.open()
# everywhere else - see lib/src/library.dart, the only place the distinction
# shows.

Pod::Spec.new do |s|
  s.name             = 'goo2d_ffi_box2d'
  s.version          = '0.0.1'
  s.summary          = 'Box2D v3 native bindings for goo2d.'
  s.description      = <<-DESC
Vendored Box2D v3.1.1 plus the goo2d primitives-only C shim.
                       DESC
  s.homepage         = 'https://github.com/erincatto/box2d'
  s.license          = { :type => 'MIT', :file => '../src/box2d/LICENSE' }
  s.author           = { 'goo2d' => 'goo2d@example.com' }
  s.source           = { :path => '.' }

  # Classes/ holds two files that #include the real sources out of ../src.
  # CocoaPods expands source_files against the files it finds under the pod
  # root - here, the macos directory - so '../src/*.c' matches nothing and
  # produces a pod that compiles no sources at all (#208). The headers those
  # sources include are reached through HEADER_SEARCH_PATHS below, which is an
  # xcconfig path and not a glob, and does climb out of the root.
  s.source_files = 'Classes/**/*.c'

  s.dependency 'FlutterMacOS'
  s.platform = :osx, '10.14'
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'HEADER_SEARCH_PATHS' => '"${PODS_TARGET_SRCROOT}/../src/box2d/include" "${PODS_TARGET_SRCROOT}/../src/box2d/src" "${PODS_TARGET_SRCROOT}/../src"',
    'GCC_C_LANGUAGE_STANDARD' => 'c17',
    # Box2D is vendored and not warning-clean; the shim is the part held to
    # a standard, and a vendored-code warning storm would bury real ones.
    'GCC_WARN_INHIBIT_ALL_WARNINGS' => 'YES',
  }
  s.swift_version = '5.0'
end
