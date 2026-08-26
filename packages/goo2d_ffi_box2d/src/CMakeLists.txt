# Builds vendored Box2D v3.1.1 together with the goo2d shim into a single
# shared library, `goo2d_box2d`.
#
# One library, not two, on purpose: the shim is the only consumer of Box2D
# here, Box2D's symbols are not part of this package's contract (the shim
# header is), and shipping two artifacts would mean two things for every
# platform's bundling step to find.
#
# Each platform wrapper (../windows, ../linux, ../android) reaches this file
# through add_subdirectory, so the source list and compile flags are stated
# once between them.
#
# It is also a build root on its own, which is what `cmake -S src -B
# build/<operating system>` configures. That is how CI and
# tool/build_native.ps1 produce the library `flutter test` loads.

cmake_minimum_required(VERSION 3.15)
project(goo2d_box2d LANGUAGES C)

set(BOX2D_DIR "${CMAKE_CURRENT_LIST_DIR}/box2d")

file(GLOB BOX2D_SOURCES "${BOX2D_DIR}/src/*.c")

if(NOT BOX2D_SOURCES)
  # A silent empty glob would produce a library exporting only the shim,
  # which then fails at the first Box2D call with an unresolved symbol -
  # far from the actual cause. Fail here instead.
  message(FATAL_ERROR "No Box2D sources found in ${BOX2D_DIR}/src - is the vendored copy missing?")
endif()

add_library(goo2d_box2d SHARED
  ${BOX2D_SOURCES}
  "${CMAKE_CURRENT_LIST_DIR}/goo_box2d.c"
  "${CMAKE_CURRENT_LIST_DIR}/goo_threads.c"
)

# Box2D's own sources include "box2d/..." headers, and its internal headers
# sit beside the sources; the shim includes both its own header and Box2D's.
target_include_directories(goo2d_box2d PRIVATE
  "${BOX2D_DIR}/include"
  "${BOX2D_DIR}/src"
  "${CMAKE_CURRENT_LIST_DIR}"
)

# Box2D v3 requires C17 (it uses _Static_assert, _Atomic and designated
# initialisers); so does the shim's _Static_assert block.
set_target_properties(goo2d_box2d PROPERTIES
  C_STANDARD 17
  C_STANDARD_REQUIRED ON
  # Everything the Dart side calls is explicitly marked GOO_API. Hiding the
  # rest keeps Box2D's ~700 internal symbols out of the export table, so a
  # host application that also links its own Box2D cannot collide with this
  # one.
  C_VISIBILITY_PRESET hidden
  VISIBILITY_INLINES_HIDDEN ON
)

if(MSVC)
  # Box2D uses SIMD intrinsics; MSVC needs AVX2 enabled explicitly on x64.
  # Guarded by architecture because this same file builds ARM (Android,
  # Apple silicon) where the flag does not exist.
  if(CMAKE_SIZEOF_VOID_P EQUAL 8 AND CMAKE_SYSTEM_PROCESSOR MATCHES "(AMD64|x86_64)")
    target_compile_options(goo2d_box2d PRIVATE /arch:AVX2)
  endif()
  # Box2D is not warning-clean at /W4 under MSVC and it is vendored code we
  # do not patch; the shim is the part we hold to a standard.
  target_compile_options(goo2d_box2d PRIVATE /W3)
else()
  target_compile_options(goo2d_box2d PRIVATE -Wall)
  if(CMAKE_SYSTEM_PROCESSOR MATCHES "(x86_64|AMD64)")
    target_compile_options(goo2d_box2d PRIVATE -mavx2 -mfma)
  endif()
  find_library(MATH_LIBRARY m)
  if(MATH_LIBRARY)
    target_link_libraries(goo2d_box2d PRIVATE ${MATH_LIBRARY})
  endif()
endif()

if(ANDROID)
  # Box2D's solver uses pthreads primitives available in the NDK's libc.
  target_link_libraries(goo2d_box2d PRIVATE log)
endif()

# goo_threads.c needs a thread library everywhere except Windows, which has
# its own in kernel32. Android and Apple carry pthreads in libc, so this is
# really for Linux - but asking CMake keeps it correct on all of them.
if(NOT WIN32)
  set(THREADS_PREFER_PTHREAD_FLAG ON)
  find_package(Threads REQUIRED)
  target_link_libraries(goo2d_box2d PRIVATE Threads::Threads)
endif()

set_target_properties(goo2d_box2d PROPERTIES
  PUBLIC_HEADER "${CMAKE_CURRENT_LIST_DIR}/goo_box2d.h"
  OUTPUT_NAME "goo2d_box2d"
)
