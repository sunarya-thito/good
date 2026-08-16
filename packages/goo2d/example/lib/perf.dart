import 'package:flutter/material.dart';

import 'package:goo2d_example/demo/demo.dart';
import 'package:goo2d_example/demo/joints.dart';
import 'package:goo2d_example/demo/particles.dart';
import 'package:goo2d_example/demo/physics.dart';
import 'package:goo2d_example/demo/scene_graph.dart';
import 'package:goo2d_example/harness/demo_app.dart';

/// Every demo case, and nothing else.
///
/// ```
/// flutter run -t lib/perf.dart --profile
/// ```
///
/// **Run it in profile mode.** Debug-mode Dart is 10-50x slower for exactly
/// the kind of tight numeric loop this engine is made of, so a debug frame
/// time says almost nothing about a shipped one.
///
/// # How this is laid out, and why
///
/// * `demo/` - one file per case, **goo2d only**. Prefabs, systems, a `Game`
///   and a `GameState`. No widgets, no `MaterialApp`, no menu. If you are here
///   to learn the engine, these are the only files you need to read.
/// * `harness/` - every widget, once, for all cases: the app shell, the case
///   menu, the stats overlay, the recorder.
///
/// Adding a case is one file under `demo/` plus one line in the list below.
/// Cases are **factories** rather than instances because selecting one builds
/// a fresh `Demo`, and the `Game` it holds is single-use by design.
///
/// # What the overlay is telling you
///
/// The whole premise of this engine - bit-packed rows in native memory, a
/// two-isolate split, allocation-free tick paths - is a performance claim, and
/// a claim needs a number. But "FPS" alone cannot say *which* half is costing
/// you, and the halves fail differently:
///
///  * **`fps`** is what the Flutter isolate manages: replaying the draw batch
///    plus this app's own widgets.
///  * **`step` / `systems` / `case`** are the game isolate, measured around
///    the fixed step and published through channels. Unaffected by anything
///    Flutter does - that is the entire point of the split.
///  * **`present`** is the renderer walking renderables and writing the draw
///    batch. It runs on the game isolate inside `advance`, so it lands on
///    `sim fps` and not on `fps`. This is usually the surprise.
///  * **`steps/adv`** divides the first two. Read `DemoGame.stepsPerAdvance`
///    before comparing any timing to any other.
void main() => runApp(
  DemoApp(
    demos: <Demo Function()>[
      ParticlesDemo.new,
      SceneGraphDemo.new,
      PhysicsDemo.new,
      JointsDemo.new,
    ],
  ),
);
