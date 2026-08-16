# CocoaPods spec for macOS. Unlike Windows/Linux/Android, Apple platforms do
# not go through ../src/CMakeLists.txt - CocoaPods compiles the sources
# itself, so the source list and flags are restated here. That is the one
# place in this package where the build is described twice; it is forced by
# the toolchains, not chosen.
#
# Note this produces a STATICALLY linked blob inside the app binary, not a
# .dylib beside it. The Dart loader therefore uses DynamicLibrary.process()
# on Apple platforms rather than DynamicLibrary.open() - see
# lib/src/library.dart, which is the only place that distinction shows.

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

  s.source_files = 'Classes/**/*', '../src/goo_box2d.c', '../src/goo_box2d.h',
                   '../src/box2d/src/*.c', '../src/box2d/src/*.h',
                   '../src/box2d/include/box2d/*.h'

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
