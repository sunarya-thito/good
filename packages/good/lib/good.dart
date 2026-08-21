/// Dimension-agnostic engine kernel: ECS, shared memory pool, ring buffers,
/// scenes, fixed-tick loop, hierarchy, and the generic asset registry.
library;

// Timelines and the coroutine runtime they are driven by. Both are reached
// through members every `EntityStruct`, `SceneStruct`, `GameSystem` and
// `GameState` already has - `startCoroutine`, `describeAnimation` - so a game
// never imports either file, but it does have to be able to *spell* what they
// hand back: a `Track<double>` field, a `TimelineAnimation`, a
// `CoroutineFuture` to await.
//
// `CoroutineScheduler` comes along because `GameState.coroutines` is public and
// a type you cannot name is a type you cannot hold.
export 'src/animation/animatable.dart';
export 'src/animation/struct.dart';
export 'src/archetype.dart';
export 'src/asset.dart';
export 'src/asset_pack.dart';
export 'src/audio/audio_clip.dart';
export 'src/coroutine/coroutine.dart';
// The command API's two public layers: the shapes a command can take, and the
// record its parameters and results live in. What is hidden is the plumbing
// behind them - the registry a `Game` owns, the two descriptor implementations
// that decide which isolate handles what, and the transport-facing interfaces.
// A game declares against `CommandDescriptor` and holds commands; nothing
// outside the kernel has a reason to name the rest, and `@internal` says so.
//
// The framework ships no commands of its own. `SpawnEntityCommand` used to be
// the exception and was deleted: it named a prefab by `archetypeId`, which is
// a game-isolate identifier the Flutter isolate has no way to see. Spawning
// from main is a command the *game* declares, in terms that mean something on
// both sides.
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
// The record layer under both of them. `ParamDescriptor`/`ParamPointer` is
// how a command declares its fields, `ParamBatch`/`ParamBuffer` is what those
// fields are written into, and `ParamLayout`/`ParamLayouts` is the packing
// rule itself. Exported rather than kept internal because `good_net` builds
// its network messages on the *same* record layer rather than a parallel one
// - a message crossing a socket and a command crossing an isolate are the
// same bytes, and one packing rule with two implementations is the drift
// the one-fact-one-place rule warns about.
export 'src/command/param.dart'
    show
        CommandBatch,
        CommandResults,
        ParamBatch,
        ParamBuffer,
        ParamDescriptor,
        ParamLayout,
        ParamLayouts,
        ParamPointer;
export 'src/data.dart';
export 'src/data/hierarchy.dart';
// EventBinder is the machinery behind the two declare/collect passes - `Game`
// and `SceneStruct` drive it; nothing outside the kernel has a reason to name
// it, and `@internal` says so.
export 'src/event.dart' hide EventBinder;
export 'src/event/fixed_loop.dart';
export 'src/event/lifecycle.dart';
export 'src/event/state.dart';
export 'src/event/tick_loop.dart';
// `GameRuntime` is hidden rather than exported: it is one run's internals -
// the isolate roles, the ports, the command registry, and the inline-versus-
// spawned split itself - and everything a caller legitimately wants from it
// has a spelling on `Game` (`isRunning`, `tick`, `stop`, `createCommandBatch`,
// and `state`/`advance` on an inline run). Hiding the *name* still lets code
// inside this package reach `game.runtimeOrNull` and call through it, which is
// what the tests' tick-waiting helper does.
//
// There is no `GameHandle` in this list because there is no `GameHandle`: it
// was the main-side half of a design where a `Game` could back several runs,
// and once one instance meant one run it had nothing left to hold that `Game`
// itself could not.
export 'src/game.dart' hide GameRuntime;
export 'src/game_state.dart';
export 'src/handoff_buffer.dart';
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
export 'src/camera_view.dart' hide GameCameraDescriptor;
export 'src/scene_handle.dart';
export 'src/struct.dart';
export 'src/system.dart';
export 'src/triple_buffer.dart';
export 'src/widget/game_view.dart';
