# Flutter's Windows build enters here. All the real configuration lives in
# ../src/CMakeLists.txt so that Windows, Linux and Android state the source
# list and compile flags once between them.

cmake_minimum_required(VERSION 3.15)

project(goo2d_ffi_box2d_library VERSION 0.0.1 LANGUAGES C)

add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/../src" "${CMAKE_CURRENT_BINARY_DIR}/shared")

# Flutter reads these two variables to decide what to bundle into the
# runner's output directory. Without goo2d_ffi_box2d_bundled_libraries the
# DLL builds and is then simply not shipped, and the failure appears at
# runtime as a missing library rather than at build time.
set(goo2d_ffi_box2d_bundled_libraries
  "$<TARGET_FILE:goo2d_box2d>"
  PARENT_SCOPE
)
