/// Dimension-agnostic engine kernel: ECS, shared memory pool, ring buffers,
/// scenes, fixed-tick loop, hierarchy, and the generic asset registry.
library;

export 'src/archetype.dart';
export 'src/asset.dart';
// The command API's three public layers: the shapes a command can take, the
// record its parameters and results live in, and the framework's own spawn
// command. What is hidden is the plumbing behind them - the registry a `Game`
// owns, the two descriptor implementations that decide which isolate handles
// what, and the transport-facing interfaces. A game declares against
// `CommandDescriptor` and holds commands; nothing outside the kernel has a
// reason to name the rest, and `@internal` says so.
export 'src/command/command.dart'
    show
        CommandBatchCalls,
        CommandDescriptor,
        CommandKey,
        GameCommand,
        GameCommandBase,
        SignalCommand,
        SinkCommand,
        SupplierCommand;
export 'src/command/param.dart'
    show CommandBatch, CommandBuffer, CommandResults, ParamDescriptor, ParamPointer;
export 'src/command/spawn.dart';
export 'src/data.dart';
export 'src/data/hierarchy.dart';
export 'src/event.dart' hide GameListenerMixin;
export 'src/event/fixed_loop.dart';
export 'src/event/state.dart';
export 'src/event/tick_loop.dart';
export 'src/game.dart';
export 'src/game_state.dart';
export 'src/heap_object.dart';
// Vector2 is part of the input system's surface (`Input<Vector2>`,
// `Vec2Binding`), so it comes along - a game should not have to add a second
// dependency to spell the type its own declaration hands back. vector_math_64
// specifically: the float64 flavour, matching the component fields a movement
// vector is going to be added to.
export 'package:vector_math/vector_math_64.dart' show Vector2;

// InputRegistry is the engine-side plumbing behind InputDescriptor - a Game
// owns one and drives it through boot, each tick and shutdown. Users declare
// against InputDescriptor and hold Inputs; nothing outside the kernel has a
// reason to name it.
export 'src/input.dart' hide InputRegistry;
export 'src/input/gamepad.dart';
export 'src/input/input_binding.dart';
export 'src/input/input_key.dart';
export 'src/input/input_state.dart';
export 'src/pool.dart';
export 'src/ring_buffer.dart';
export 'src/scene.dart';
export 'src/scene_handle.dart';
export 'src/struct.dart';
export 'src/system.dart';
export 'src/triple_buffer.dart';
export 'src/widget/game_view.dart';
