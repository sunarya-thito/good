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

  # Classes/ holds two files that #include the real sources out of ../src.
  # CocoaPods expands source_files against the files it finds under the pod
  # root - here, the ios directory - so '../src/*.c' matches nothing and
  # produces a pod that compiles no sources at all (#208). The headers those
  # sources include are reached through HEADER_SEARCH_PATHS below, which is an
  # xcconfig path and not a glob, and does climb out of the root.
  s.source_files = 'Classes/**/*.c'

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
