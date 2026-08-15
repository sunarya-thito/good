import 'dart:async';

import 'package:flutter/material.dart' hide Texture;
import 'package:goo2d/goo2d.dart';

import 'package:goo2d_example/demo/demo.dart';
import 'package:goo2d_example/demo/demo_game.dart';
import 'package:goo2d_example/harness/recorder.dart';

/// Hosts any [Demo] and owns **all** of the Flutter.
///
/// The split this exists to enforce: a case file under `demo/` imports `goo2d`
/// and declares prefabs, systems and a `Game`; it never builds a widget, never
/// mentions `MaterialApp`, and never knows a menu exists. Everything a reader
/// has to wade through to find the engine - the app shell, the stats overlay,
/// the buttons, the recorder - is here, once, for every case.
///
/// Cases arrive as **factories** rather than instances: selecting a case
/// builds a fresh one, because a `Demo` holds the `Game` it created and a
/// `Game` is single-use by design (one instance, one run).
class DemoApp extends StatefulWidget {
  const DemoApp({required this.demos, super.key});

  final List<Demo Function()> demos;

  @override
  State<DemoApp> createState() => _DemoAppState();
}

class _DemoAppState extends State<DemoApp> {
  Demo? _demo;
  int _selected = 0;

  /// True while a case is being swapped: the previous game has to stop before
  /// the next one starts, and both are asynchronous.
  bool _switching = false;

  final DemoRecorder _recorder = DemoRecorder();

  /// Repaints the overlay so the frame numbers move. The *numbers* come from
  /// the engine (`Game.fps`, `Game.frameMillis`); this only decides how often
  /// to look at them, which is a UI concern and deliberately not the engine's.
  Timer? _readout;

  @override
  void initState() {
    super.initState();
    _readout = Timer.periodic(
      const Duration(milliseconds: 250),
      (_) => setState(() {}),
    );
    unawaited(_select(0));
  }

  @override
  void dispose() {
    _readout?.cancel();
    _demo?.game.stop();
    super.dispose();
  }

  Future<void> _select(int index) async {
    if (_switching) return;
    setState(() => _switching = true);
    final previous = _demo;
    if (previous != null) {
      if (_recorder.isRecording) _stopRecording(previous.game);
      _demo = null;
      setState(() {});
      await previous.game.stop();
    }
    final demo = widget.demos[index]();
    final game = demo.create();
    await Game.start(game);
    if (!mounted) {
      await game.stop();
      return;
    }
    setState(() {
      _selected = index;
      _demo = demo;
      _switching = false;
    });
  }

  void _onSample() {
    final demo = _demo;
    if (demo == null) return;
    _recorder.sample(demo.game);
  }

  void _stopRecording(DemoGame game) {
    _recorder.stop();
    game.systemMicros.removeListener(_onSample);
  }

  void _toggleRecording(BuildContext context, Demo demo) {
    if (_recorder.isRecording) {
      _stopRecording(demo.game);
      setState(() {});
      showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('measurement'),
          content: SingleChildScrollView(
            child: SelectableText(
              _recorder.report(demo.name, demo.game.spawnedCount.value),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('close'),
            ),
          ],
        ),
      );
      return;
    }
    _recorder.start();
    demo.game.systemMicros.addListener(_onSample);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final demo = _demo;
    return MaterialApp(
      title: 'goo2d',
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFF07090C),
        // `Builder` so the callbacks below capture a context *under* the
        // MaterialApp. The State's own context sits above it, where there is
        // no Navigator - `showDialog` with it threw "Null check operator used
        // on a null value" from `Navigator.of`, naming neither the cause nor
        // this file.
        body: Builder(
          builder: (context) => Row(
            children: <Widget>[
              _CaseMenu(
                demos: widget.demos,
                selected: _selected,
                enabled: !_switching,
                onSelect: _select,
              ),
              Expanded(
                child: Stack(
                  children: <Widget>[
                    if (demo != null)
                      GameView(camera: demo.game.defaultCamera)
                    else
                      const Center(child: CircularProgressIndicator()),
                    if (demo != null) _Readout(game: demo.game),
                    if (demo != null)
                      _Controls(
                        demo: demo,
                        recording: _recorder.isRecording,
                        onRecord: () => _toggleRecording(context, demo),
                        onChanged: () => setState(() {}),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The menu. Reads [Demo.name] and [Demo.blurb] off a freshly built instance -
/// building one is cheap, since nothing starts until `create()`.
class _CaseMenu extends StatelessWidget {
  const _CaseMenu({
    required this.demos,
    required this.selected,
    required this.enabled,
    required this.onSelect,
  });

  final List<Demo Function()> demos;
  final int selected;
  final bool enabled;
  final void Function(int index) onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 232,
      color: const Color(0xFF0E1218),
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 12),
        children: <Widget>[
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Text(
              'goo2d',
              style: TextStyle(
                color: Color(0xFFE0E0E0),
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          for (var i = 0; i < demos.length; i++)
            _CaseTile(
              demo: demos[i](),
              active: i == selected,
              enabled: enabled,
              onTap: () => onSelect(i),
            ),
        ],
      ),
    );
  }
}

class _CaseTile extends StatelessWidget {
  const _CaseTile({
    required this.demo,
    required this.active,
    required this.enabled,
    required this.onTap,
  });

  final Demo demo;
  final bool active;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: active ? const Color(0xFF1B2430) : Colors.transparent,
      child: InkWell(
        onTap: enabled && !active ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                demo.name,
                style: TextStyle(
                  color: active
                      ? const Color(0xFF7FD1FF)
                      : const Color(0xFFE0E0E0),
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                demo.blurb,
                style: const TextStyle(
                  color: Color(0xFF7C8895),
                  fontSize: 11,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The buttons and switches a case declared, rendered generically.
class _Controls extends StatefulWidget {
  const _Controls({
    required this.demo,
    required this.recording,
    required this.onRecord,
    required this.onChanged,
  });

  final Demo demo;
  final bool recording;
  final VoidCallback onRecord;
  final VoidCallback onChanged;

  @override
  State<_Controls> createState() => _ControlsState();
}

class _ControlsState extends State<_Controls> {
  final Map<String, bool> _toggles = <String, bool>{};
  final Map<String, double> _sliders = <String, double>{};

  @override
  void initState() {
    super.initState();
    // Push each slider's initial value once, so what the case is doing matches
    // what the slider shows without the user having to touch it.
    for (final slider in widget.demo.sliders) {
      _sliders[slider.label] = slider.initial;
      unawaited(slider.set(slider.initial.round()));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomRight,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Wrap(
          spacing: 10,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            for (final slider in widget.demo.sliders) ...<Widget>[
              SizedBox(
                width: 300,
                child: Row(
                  children: <Widget>[
                    Text(
                      '${slider.label} '
                      '${(_sliders[slider.label] ?? slider.initial).round()}',
                      style: const TextStyle(color: Color(0xFFE0E0E0)),
                    ),
                    Expanded(
                      child: Slider(
                        value: _sliders[slider.label] ?? slider.initial,
                        min: slider.min,
                        max: slider.max,
                        onChanged: (value) {
                          setState(() => _sliders[slider.label] = value);
                          unawaited(slider.set(value.round()));
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
            for (final toggle in widget.demo.toggles) ...<Widget>[
              Text(
                toggle.label,
                style: TextStyle(
                  color: (toggle.enabled?.call() ?? true)
                      ? const Color(0xFFE0E0E0)
                      : const Color(0xFF6B7378),
                ),
              ),
              Switch(
                value: _toggles[toggle.label] ?? toggle.initial,
                onChanged: (toggle.enabled?.call() ?? true)
                    ? (on) async {
                        setState(() => _toggles[toggle.label] = on);
                        await toggle.set(on);
                        widget.onChanged();
                      }
                    : null,
              ),
            ],
            for (final action in widget.demo.actions)
              FilledButton.tonal(
                onPressed: (action.enabled?.call() ?? true)
                    ? () async {
                        await action.run();
                        widget.onChanged();
                      }
                    : null,
                child: Text(action.label),
              ),
            FloatingActionButton.extended(
              heroTag: 'record',
              backgroundColor: widget.recording ? Colors.red : null,
              onPressed: widget.onRecord,
              label: Text(widget.recording ? 'stop' : 'record'),
              icon: Icon(
                widget.recording ? Icons.stop : Icons.fiber_manual_record,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The stats overlay. Identical for every case, because every case's `Game`
/// extends [DemoGame] and therefore publishes the same channels.
class _Readout extends StatelessWidget {
  const _Readout({required this.game});

  final DemoGame game;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topLeft,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: DefaultTextStyle(
          style: const TextStyle(
            color: Color(0xFFC7D0D9),
            fontFamily: 'monospace',
            fontSize: 12,
            height: 1.45,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _Line(label: 'entities', channel: game.spawnedCount),
              _Line(label: 'sprites', channel: game.spritesDrawn),
              const SizedBox(height: 6),
              _Line(label: 'case', channel: game.caseMicros, ms: true),
              _Line(label: 'present', channel: game.presentMicros, ms: true),
              _Line(label: '  walk', channel: game.presentWalkMicros, ms: true),
              _Line(label: '  sort', channel: game.presentSortMicros, ms: true),
              _Line(
                label: '  write',
                channel: game.presentWriteMicros,
                ms: true,
              ),
              _Line(label: 'step', channel: game.stepMicros, ms: true),
              _Line(label: 'systems', channel: game.systemMicros, ms: true),
              // Compare the two: a large gap is contention, not workload.
              _Line(label: 'sys min', channel: game.bestSystemMicros, ms: true),
              // Directly under the two it divides, because it is what makes
              // them comparable to anything - see DemoGame.stepsPerAdvance.
              _Line(label: 'steps/adv', channel: game.stepsPerAdvance),
              _Line(label: 'advance', channel: game.advanceMicros, ms: true),
              // If this is far larger than `advance`, the loop is starved
              // rather than slow and the tick is not the problem.
              _Line(label: 'interval', channel: game.intervalMicros, ms: true),
              const SizedBox(height: 6),
              // `fps` is a **count** of frames actually presented over the
              // wall clock they spanned - not one over the frame time, which
              // would read 250 for a game sitting comfortably at a vsynced 60.
              Text('sim fps      ${game.simulationFps.toStringAsFixed(1)}'),
              // `sim fps` counts *published frames*, one per `advance`. The
              // simulation's real rate is that times the steps each advance
              // ran, and the two diverge exactly when the machine stops
              // affording one step per frame.
              Text(
                'sim step/s   '
                '${(game.simulationFps * game.stepsPerAdvance.value).toStringAsFixed(1)}',
              ),
              Text('fps          ${game.fps.toStringAsFixed(1)}'),
              // The jank number. `fps` is throughput and averages the window;
              // this is pacing and does not. A high fps next to a large gap is
              // not a contradiction - it is the exact description of a game
              // that stutters.
              Text(
                'worst gap    '
                '${game.worstFrameIntervalMillis.toStringAsFixed(2)} ms',
              ),
              const SizedBox(height: 6),
              const Text(
                'profile mode only',
                style: TextStyle(color: Color(0xFF6B7378), fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.label, required this.channel, this.ms = false});

  final String label;
  final StateChannel<int> channel;
  final bool ms;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: channel,
      builder: (context, value, _) => Text(
        '${label.padRight(12)} '
        '${ms ? '${(value / 1000).toStringAsFixed(2)} ms' : '$value'}',
      ),
    );
  }
}
