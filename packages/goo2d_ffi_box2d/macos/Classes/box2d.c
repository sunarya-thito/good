// Compiles the vendored Box2D sources. They live in ../../src, and a podspec
// cannot name them: CocoaPods expands source_files against the files under the
// pod root, so a pattern climbing out of it matches nothing and the pod builds
// empty (#208). A file inside the root that includes them is how Flutter's own
// FFI plugin template shares one copy of the C sources across platforms.
//
// src/CMakeLists.txt globs the same directory for Windows, Linux and Android.
// test/apple_forwarders_test.dart holds this list to what that glob finds.

#include "../../src/box2d/src/aabb.c"
#include "../../src/box2d/src/arena_allocator.c"
#include "../../src/box2d/src/array.c"
#include "../../src/box2d/src/bitset.c"
#include "../../src/box2d/src/body.c"
#include "../../src/box2d/src/broad_phase.c"
#include "../../src/box2d/src/constraint_graph.c"
#include "../../src/box2d/src/contact.c"
#include "../../src/box2d/src/contact_solver.c"
#include "../../src/box2d/src/core.c"
#include "../../src/box2d/src/distance.c"
#include "../../src/box2d/src/distance_joint.c"
#include "../../src/box2d/src/dynamic_tree.c"
#include "../../src/box2d/src/geometry.c"
#include "../../src/box2d/src/hull.c"
#include "../../src/box2d/src/id_pool.c"
#include "../../src/box2d/src/island.c"
#include "../../src/box2d/src/joint.c"
#include "../../src/box2d/src/manifold.c"
#include "../../src/box2d/src/math_functions.c"
#include "../../src/box2d/src/motor_joint.c"
#include "../../src/box2d/src/mouse_joint.c"
#include "../../src/box2d/src/mover.c"
#include "../../src/box2d/src/prismatic_joint.c"
#include "../../src/box2d/src/revolute_joint.c"
#include "../../src/box2d/src/sensor.c"
#include "../../src/box2d/src/shape.c"
#include "../../src/box2d/src/solver.c"
#include "../../src/box2d/src/solver_set.c"
#include "../../src/box2d/src/table.c"
#include "../../src/box2d/src/timer.c"
#include "../../src/box2d/src/types.c"
#include "../../src/box2d/src/weld_joint.c"
#include "../../src/box2d/src/wheel_joint.c"
#include "../../src/box2d/src/world.c"
