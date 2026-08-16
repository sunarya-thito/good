# See ../windows/CMakeLists.txt - identical role, identical delegation to
# ../src, which is the point of keeping the real build there.

cmake_minimum_required(VERSION 3.15)

project(goo2d_ffi_box2d_library VERSION 0.0.1 LANGUAGES C)

add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/../src" "${CMAKE_CURRENT_BINARY_DIR}/shared")

set(goo2d_ffi_box2d_bundled_libraries
  "$<TARGET_FILE:goo2d_box2d>"
  PARENT_SCOPE
)
