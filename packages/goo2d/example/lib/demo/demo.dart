import 'package:goo2d/goo2d.dart';

import 'package:goo2d_example/demo/demo_game.dart';

/// What a demo case is, from the harness's point of view.
///
/// # Why this exists
///
/// A case file should be readable by someone learning **goo2d**, and every
/// line of Flutter in it is a line that teaches them nothing about this engine.
/// So the split is absolute: a file under `demo/` imports `goo2d` and nothing
/// from `flutter/material.dart`, and the harness under `harness/` owns every
/// widget, the menu, the overlay and the recorder. A new case is one file with
/// no widgets in it.
///
/// The controls a case wants are declared as data ([actions], [toggles]) and
/// rendered by the harness. That is the whole reason they are not widgets: a
/// case says *"I have a button called spawn 1000"*, not *how* a button looks.
abstract class Demo {
  const Demo();

  /// Shown in the menu.
  String get name;

  /// One line under the name - what this case is demonstrating, in engine
  /// terms, not in graphics terms.
  String get blurb;

  /// Builds this case's `Game`. Called once per selection; the harness starts
  /// it, hands it back through [game], and stops it on the way out.
  DemoGame create();

  /// The running game, valid between [create] and the harness stopping it.
  DemoGame get game;

  /// Buttons, in the order they should appear.
  List<DemoAction> get actions => const <DemoAction>[];

  /// Switches, in the order they should appear.
  List<DemoToggle> get toggles => const <DemoToggle>[];

  /// Sliders, in the order they should appear.
  List<DemoSlider> get sliders => const <DemoSlider>[];

  /// Extra readout lines, appended under the standard ones.
  ///
  /// Declared as data for the same reason the controls are: a case says *"show
  /// this channel and call it solve"*, and the harness owns every widget. The
  /// alternative - putting case-specific channels on `DemoGame` - would make
  /// every case carry every other case's instrumentation.
  List<DemoStat> get stats => const <DemoStat>[];
}

/// One extra line in the overlay: a channel the case publishes and a name for
/// it. [ms] formats the value as milliseconds rather than a bare count.
class DemoStat {
  const DemoStat(this.label, this.channel, {this.ms = false});

  final String label;
  final StateChannel<int> channel;
  final bool ms;
}

/// A button the harness renders for the case that declared it.
///
/// [run] is a plain callback rather than anything Flutter-shaped, so a case can
/// declare one without importing a widget library. It returns a `Future`
/// because almost every one of them sends a command, and a command completes
/// when the simulation next pumps.
class DemoAction {
  const DemoAction(this.label, this.run, {this.enabled});

  final String label;
  final Future<void> Function() run;

  /// Optional gate - `null` means always enabled. Used for "stop spawning at
  /// the sprite cap" rather than letting the case silently drop batches.
  final bool Function()? enabled;
}

/// A slider the harness renders. [set] receives the new value, already
/// rounded to a whole number - every slider here controls a count.
class DemoSlider {
  const DemoSlider(
    this.label,
    this.set, {
    required this.min,
    required this.max,
    required this.initial,
  });

  final String label;
  final Future<void> Function(int value) set;
  final double min;
  final double max;
  final double initial;
}

/// A switch the harness renders. [set] receives the new value.
class DemoToggle {
  const DemoToggle(this.label, this.initial, this.set, {this.enabled});

  final String label;
  final bool initial;
  final Future<void> Function(bool value) set;

  /// Optional gate - used by cases whose mode cannot change once entities
  /// exist, because a half-and-half population measures neither shape.
  final bool Function()? enabled;
}
