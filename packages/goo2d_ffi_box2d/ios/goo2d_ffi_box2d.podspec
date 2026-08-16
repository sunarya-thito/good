# CocoaPods spec for iOS. Same shape and same caveats as the macOS one -
# see ../macos/goo2d_ffi_box2d.podspec for why Apple platforms restate the
# build instead of sharing ../src/CMakeLists.txt, and why the Dart loader
# uses DynamicLibrary.process() here.

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

  s.dependency 'Flutter'
  s.platform = :ios, '12.0'
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
    'HEADER_SEARCH_PATHS' => '"${PODS_TARGET_SRCROOT}/../src/box2d/include" "${PODS_TARGET_SRCROOT}/../src/box2d/src" "${PODS_TARGET_SRCROOT}/../src"',
    'GCC_C_LANGUAGE_STANDARD' => 'c17',
    'GCC_WARN_INHIBIT_ALL_WARNINGS' => 'YES',
  }
  s.swift_version = '5.0'
end
