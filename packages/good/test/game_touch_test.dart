import 'package:flutter/gestures.dart'
    show
        Offset,
        PointerCancelEvent,
        PointerDeviceKind,
        PointerDownEvent,
        PointerHoverEvent,
        PointerMoveEvent,
        PointerUpEvent,
        kPrimaryMouseButton;
import 'package:flutter/widgets.dart' show SizedBox;
import 'package:flutter_test/flutter_test.dart';

import 'package:good/src/widget/game_view.dart';

import 'package:good/src/event/fixed_loop.dart';
import 'package:good/src/game.dart';
import 'package:good/src/game_state.dart';
import 'package:good/src/input.dart';
import 'package:good/src/input/input_binding.dart';
import 'package:good/src/input/input_key.dart';
import 'package:good/src/input/input_state.dart';
import 'package:good/src/system.dart';
import 'package:good/src/declarations.g.dart';
import 'package:good/src/scannable.dart';

part 'game_touch_test.g.dart';

// Contacts, end to end on the single-copy inline path: written through the
// same InputDevice a GameView writes through, resolved by ContactBinding on a
// fixed step, and read as a PointerContacts list.
//
// The phases are derived on the reading side, so nearly every test here is
// about what the list says across *two* steps, not about what one write put
// in the block.

late Game run;

/// What [_TouchSystem] saw on each step it ran, one string per contact.
final List<String> seen = <String>[];

/// Edges from the action itself, which are the whole-hand question: is
/// anything pressing at all.
final List<String> edges = <String>[];

class _TouchSystem extends GameSystem with FixedTickable {
  final contacts = Input.of<PointerContacts>(const ContactBinding());
  final cursor = Input.of<CursorPosition>(const MouseBinding());

  /// The list object handed out on the last step, and the contact object at
  /// index 0 - both are meant to be the same instances every tick.
  PointerContacts? lastList;
  PointerContact? lastFirst;

  _TouchSystem() {
    contacts.pressed += (event) => edges.add('pressed');
    contacts.released += (event) => edges.add('released');
  }

  @override
  void onFixedUpdate() {
    final list = contacts.value;
    lastList = list;
    for (var i = 0; i < list.count; i++) {
      final contact = list[i];
      seen.add(
        '#${contact.id} ${contact.kind.name} ${contact.phase.name} '
        '${contact.viewSpace.x.toInt()},${contact.viewSpace.y.toInt()}',
      );
      if (i == 0) lastFirst = contact;
    }
    seen.add('--');
  }
}

class _TouchState extends GameState<_TouchGame> {
  @override
  void describeSystems(SystemDescriptor descriptor) {
    super.describeSystems(descriptor);
    descriptor.has(_TouchSystem.new);
  }
}

class _TouchGame extends Game {
  @override
  int get pageSize => 4096;

  @override
  Duration get fixedTimeStep => const Duration(milliseconds: 10);

  @override
  GameState createState() => _TouchState();
}

/// Two contact slots, so "every slot is live" is reachable without pressing
/// eleven fingers.
class _TwoContactGame extends _TouchGame {
  @override
  int get maxPointerContacts => 2;
}

class _ZeroContactGame extends _TouchGame {
  @override
  int get maxPointerContacts => 0;
}

// --- helpers --------------------------------------------------------------

Future<T> _boot<T extends Game>(T Function() create) async {
  final game = await Game.startInline(create);
  run = game;
  seen.clear();
  edges.clear();
  addTearDown(() async {
    if (run.isRunning) await run.stop();
  });
  return game;
}

_TouchSystem _system() => run.state.getSystem<_TouchSystem>();

void _step() => run.state.runFixedStep();

/// Everything [_TouchSystem] recorded on the most recent step, without the
/// separator.
List<String> _lastStep() {
  final end = seen.lastIndexOf('--');
  if (end < 0) return const <String>[];
  final start = seen.lastIndexOf('--', end - 1);
  return seen.sublist(start + 1, end);
}

void main() {
  _installDeclarations();

  group('one contact, over its life', () {
    test('a press, a move and a lift read began, held, then ended', () async {
      final game = await _boot(_TouchGame.new);
      final device = game.inputDevice!;

      device.pressContact(1, screenX: 10, screenY: 20);
      _step();
      expect(_lastStep(), <String>['#1 touch began 10,20']);

      device.moveContact(1, screenX: 30, screenY: 40);
      _step();
      expect(
        _lastStep(),
        <String>['#1 touch held 30,40'],
        reason: 'a contact reported before is held, not began again',
      );

      _step();
      expect(
        _lastStep(),
        <String>['#1 touch held 30,40'],
        reason:
            'a finger resting still is still holding whatever it is holding, '
            'and re-reporting began would fire a tap per tick',
      );

      device.releaseContact(1);
      _step();
      expect(_lastStep(), <String>['#1 touch ended 30,40']);

      _step();
      expect(
        _lastStep(),
        isEmpty,
        reason: 'an ended contact is reported once and then gone',
      );
    });

    test('the list and its contacts are the same objects every tick', () async {
      final game = await _boot(_TouchGame.new);
      final device = game.inputDevice!;
      final system = _system();

      device.pressContact(1, screenX: 1, screenY: 1);
      _step();
      final list = system.lastList;
      final first = system.lastFirst;

      device.moveContact(1, screenX: 2, screenY: 2);
      _step();

      expect(
        identical(system.lastList, list),
        isTrue,
        reason:
            'resolution writes into storage the action owns (the '
            'no-allocation rule) - a fresh list per tick would be a heap '
            'object sixty times a second',
      );
      expect(
        identical(system.lastFirst, first),
        isTrue,
        reason: 'the contact objects are scratch the list refills in place',
      );
    });

    test('a contact carries the view it landed in', () async {
      final game = await _boot(_TouchGame.new);
      final device = game.inputDevice!;

      device.pressContact(1, screenX: 5, screenY: 6);
      _step();
      expect(
        run.viewOfContact(_system().contacts.value[0]),
        isNull,
        reason: 'a contact written without naming a view is in none',
      );
    });
  });

  group('cancellation', () {
    test('a cancelled contact says so, and is not an ordinary lift', () async {
      final game = await _boot(_TouchGame.new);
      final device = game.inputDevice!;

      device.pressContact(1, screenX: 10, screenY: 10);
      _step();
      device.cancelContact(1);
      _step();

      final reported = _lastStep();
      expect(reported, <String>['#1 touch cancelled 10,10']);
      expect(
        reported.single,
        isNot(contains('ended')),
        reason:
            'a game that only stops a drag on ended would steer forever after '
            'a phone call - the two phases have to be tellable apart',
      );

      _step();
      expect(
        _lastStep(),
        isEmpty,
        reason: 'a cancelled contact is over, like a lifted one',
      );
    });

    test('a cancel releases the action, the way a lift does', () async {
      final game = await _boot(_TouchGame.new);
      final device = game.inputDevice!;

      device.pressContact(1, screenX: 1, screenY: 1);
      _step();
      expect(edges, <String>['pressed']);

      device.cancelContact(1);
      _step();
      expect(
        edges,
        <String>['pressed', 'released'],
        reason:
            'nothing is pressing after a cancel, so the held bit has to fall '
            'or the action stays actuated forever',
      );
    });

    test('losing the app cancels every live contact', () async {
      final game = await _boot(_TouchGame.new);
      final device = game.inputDevice!;

      device.pressContact(1, screenX: 1, screenY: 1);
      device.pressContact(2, screenX: 2, screenY: 2);
      _step();
      expect(_lastStep(), hasLength(2));

      // What `GameView` calls when the app stops being focused, and again
      // when the last view showing the game goes away.
      device.releaseAll();
      _step();

      expect(_lastStep(), <String>[
        '#1 touch cancelled 1,1',
        '#2 touch cancelled 2,2',
      ], reason: 'a finger on the screen when focus goes sends no up event');

      _step();
      expect(
        _lastStep(),
        isEmpty,
        reason: 'and nothing is left holding whatever they were driving',
      );
    });

    test('a Flutter cancel event cancels the contact it names', () async {
      final game = await _boot(_TouchGame.new);
      final device = game.inputDevice!;

      device.handlePointerEvent(
        const PointerDownEvent(
          pointer: 7,
          kind: PointerDeviceKind.touch,
          position: Offset(30, 40),
        ),
      );
      _step();
      expect(_lastStep(), <String>['#7 touch began 30,40']);

      device.handlePointerEvent(
        const PointerCancelEvent(
          pointer: 7,
          kind: PointerDeviceKind.touch,
          position: Offset(30, 40),
        ),
      );
      _step();
      expect(
        _lastStep(),
        <String>['#7 touch cancelled 30,40'],
        reason:
            'the Listener does receive touch cancels, and this is the path '
            'GameView drives - pressContact only exists for a host with no '
            'widget',
      );
    });
  });

  group('several contacts at once', () {
    test('two fingers are two contacts, ordered oldest first', () async {
      final game = await _boot(_TouchGame.new);
      final device = game.inputDevice!;

      // Pressed in the order 5 then 2, so slot order and id order disagree -
      // the list has to be sorted by id and not by where the writer put them.
      device.pressContact(5, screenX: 50, screenY: 50);
      device.pressContact(2, screenX: 20, screenY: 20);
      _step();

      expect(_lastStep(), <String>[
        '#2 touch began 20,20',
        '#5 touch began 50,50',
      ]);
    });

    test('one finger lifting leaves the other alone', () async {
      final game = await _boot(_TouchGame.new);
      final device = game.inputDevice!;

      device.pressContact(1, screenX: 1, screenY: 1);
      device.pressContact(2, screenX: 2, screenY: 2);
      _step();

      device.releaseContact(1);
      device.moveContact(2, screenX: 9, screenY: 9);
      _step();
      expect(_lastStep(), <String>[
        '#1 touch ended 1,1',
        '#2 touch held 9,9',
      ]);

      _step();
      expect(
        _lastStep(),
        <String>['#2 touch held 9,9'],
        reason: 'the second finger is still down and now sits at index 0',
      );
      expect(
        edges,
        <String>['pressed'],
        reason: 'the action stays held while anything is still pressing',
      );
    });

    test('a press with every slot live is dropped whole', () async {
      final game = await _boot(_TwoContactGame.new);
      final device = game.inputDevice!;

      device.pressContact(1, screenX: 1, screenY: 1);
      device.pressContact(2, screenX: 2, screenY: 2);
      device.pressContact(3, screenX: 3, screenY: 3);
      _step();

      expect(_lastStep(), <String>[
        '#1 touch began 1,1',
        '#2 touch began 2,2',
      ], reason: 'two slots hold two contacts, and the third has nowhere');

      device.releaseContact(3);
      _step();
      expect(
        _lastStep(),
        <String>['#1 touch held 1,1', '#2 touch held 2,2'],
        reason: 'neither the dropped press nor its lift is ever reported',
      );
    });
  });

  group('what one fixed tick can see', () {
    test('a press and a lift between two ticks is still reported', () async {
      final game = await _boot(_TouchGame.new);
      final device = game.inputDevice!;

      // Both writes land between one step and the next, which is what a tap
      // shorter than a frame does.
      device.pressContact(1, screenX: 11, screenY: 12);
      device.releaseContact(1);
      _step();

      expect(
        _lastStep(),
        <String>['#1 touch ended 11,12'],
        reason:
            'the block is a latest-value snapshot, so the began tick never '
            'existed - but the slot keeps the ended contact until a later '
            'press wants it, so the tap itself is not lost',
      );
    });

    test('the same two writes across two ticks give both phases', () async {
      final game = await _boot(_TouchGame.new);
      final device = game.inputDevice!;

      device.pressContact(1, screenX: 11, screenY: 12);
      _step();
      device.releaseContact(1);
      _step();

      expect(
        <List<String>>[
          seen.sublist(0, seen.indexOf('--')),
          _lastStep(),
        ],
        <List<String>>[
          <String>['#1 touch began 11,12'],
          <String>['#1 touch ended 11,12'],
        ],
        reason:
            'the control for the test above: spread over two ticks the same '
            'press reports both phases, so a one-phase result there is the '
            'sampling and not the reporting',
      );
    });
  });

  group('device kinds', () {
    test('a mouse button held is a contact, hovering is not', () async {
      final game = await _boot(_TouchGame.new);
      final device = game.inputDevice!;

      device.handlePointerEvent(
        const PointerHoverEvent(
          pointer: 3,
          kind: PointerDeviceKind.mouse,
          position: Offset(5, 5),
        ),
      );
      _step();
      expect(
        _lastStep(),
        isEmpty,
        reason: 'a mouse merely over the window is not pressing on it',
      );

      device.handlePointerEvent(
        const PointerDownEvent(
          pointer: 3,
          kind: PointerDeviceKind.mouse,
          buttons: kPrimaryMouseButton,
          position: Offset(5, 5),
        ),
      );
      _step();
      expect(
        _lastStep(),
        <String>['#3 mouse began 5,5'],
        reason:
            'a game written for fingers is then playable with a mouse, and a '
            'game with its own mouse controls skips ContactKind.mouse',
      );
    });

    test('a stylus reports as a stylus', () async {
      final game = await _boot(_TouchGame.new);
      final device = game.inputDevice!;

      device.handlePointerEvent(
        const PointerDownEvent(
          pointer: 4,
          kind: PointerDeviceKind.stylus,
          position: Offset(7, 8),
        ),
      );
      _step();
      expect(_lastStep(), <String>['#4 stylus began 7,8']);
    });

    test('a touch drives no cursor and no mouse button', () async {
      final game = await _boot(_TouchGame.new);
      final device = game.inputDevice!;

      device.handlePointerEvent(
        const PointerDownEvent(
          pointer: 9,
          kind: PointerDeviceKind.touch,
          position: Offset(300, 400),
        ),
      );
      _step();

      expect(
        _system().cursor.value.screenSpace.x,
        0,
        reason:
            'CursorPosition is where the *cursor* is, and a finger does not '
            'move one - a touchscreen would otherwise teleport the cursor a '
            'mouse game aims with',
      );
      expect(device.isDown(InputKey.leftMouseButton), isFalse);
      expect(
        _lastStep(),
        <String>['#9 touch began 300,400'],
        reason: 'what the finger does move is the contact table',
      );
    });

    test('a touch move updates the contact and nothing else', () async {
      final game = await _boot(_TouchGame.new);
      final device = game.inputDevice!;

      device.handlePointerEvent(
        const PointerDownEvent(
          pointer: 2,
          kind: PointerDeviceKind.touch,
          position: Offset(1, 1),
        ),
      );
      device.handlePointerEvent(
        const PointerMoveEvent(
          pointer: 2,
          kind: PointerDeviceKind.touch,
          position: Offset(60, 70),
        ),
      );
      _step();
      expect(_lastStep(), <String>['#2 touch began 60,70']);

      device.handlePointerEvent(
        const PointerUpEvent(
          pointer: 2,
          kind: PointerDeviceKind.touch,
          position: Offset(60, 70),
        ),
      );
      _step();
      expect(_lastStep(), <String>['#2 touch ended 60,70']);
    });
  });

  group('the contact count is a getter on the game', () {
    test('an override sizes the block', () async {
      await _boot(_TwoContactGame.new);
      expect(run.maxPointerContacts, 2);
      expect(
        InputState.byteLengthFor(run.maxPointerContacts),
        lessThan(InputState.byteLengthFor(10)),
        reason: 'the block is sized from the getter, not from a constant',
      );
    });

    test('the block cannot be resized once it is allocated', () {
      final registry = InputRegistry()..maxContacts = 4;
      registry.allocate();
      addTearDown(() => registry.release(owned: true));
      expect(
        () => registry.maxContacts = 6,
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            allOf(
              contains('maxPointerContacts'),
              contains('read once'),
              contains('offsets'),
            ),
          ),
        ),
        reason:
            'both isolate copies index the contact table by offsets computed '
            'from this number, so resizing it under a live buffer would have '
            'one copy reading a table that starts somewhere else',
      );
    });

    test('a block with no contact slots is refused', () async {
      await expectLater(
        Game.startInline(_ZeroContactGame.new),
        throwsA(
          isA<ArgumentError>().having(
            (error) => error.message,
            'message',
            contains('at least one contact'),
          ),
        ),
      );
    });
  });

  group('the binding', () {
    test('contacts cannot be a source in a composite', () {
      expect(
        () => CompositeBinding<PointerContacts>(
          const ContactBinding(),
          const ContactBinding(),
        ),
        throwsA(
          isA<AssertionError>().having(
            (error) => error.message.toString(),
            'message',
            allOf(contains('one screen'), contains('twice')),
          ),
        ),
      );
    });

    test('combining two contact lists throws in release mode too', () {
      expect(
        () => const ContactBinding().combine(
          PointerContacts.empty(),
          PointerContacts.empty(),
        ),
        throwsA(
          isA<UnsupportedError>().having(
            (error) => error.message,
            'message',
            contains('one screen'),
          ),
        ),
      );
    });

    test('it round-trips through JSON and compares by content', () {
      expect(
        ContactBinding.fromJson(const ContactBinding().toJson()),
        const ContactBinding(),
      );
      expect(const ContactBinding().hashCode, const ContactBinding().hashCode);
    });

    test('an unbound contact action reads an empty list', () async {
      await _boot(_TouchGame.new);
      final system = _system();
      system.contacts.binding = null;
      _step();
      expect(
        system.contacts.value.count,
        0,
        reason:
            'Game.describeInputs registers the type-level default, so an '
            'unbound action reads "nothing is pressing" instead of throwing '
            'on a value nobody outside the framework can construct',
      );
    });
  });

  group('reading the list', () {
    test('an index past the count names the bound it broke', () async {
      final game = await _boot(_TouchGame.new);
      game.inputDevice!.pressContact(1, screenX: 1, screenY: 1);
      _step();

      final contacts = _system().contacts.value;
      expect(contacts.count, 1);
      expect(
        () => contacts[1],
        throwsA(
          isA<IndexError>().having(
            (error) => error.toString(),
            'toString',
            allOf(contains('index'), contains('less than 1')),
          ),
        ),
        reason:
            'count is what bounds the list, not the slots the block carries - '
            'indexing up to maxPointerContacts would read stale scratch',
      );
    });
  });

  group('through a real GameView', () {
    testWidgets('a finger on the widget reaches the game', (tester) async {
      final game = await _boot(_TouchGame.new);
      await tester.pumpWidget(GameView.headless(game: game));

      final finger = await tester.startGesture(
        const Offset(120, 240),
        kind: PointerDeviceKind.touch,
      );
      _step();
      expect(_lastStep(), hasLength(1));
      expect(_lastStep().single, contains('touch began 120,240'));

      await finger.moveTo(const Offset(160, 260));
      _step();
      expect(_lastStep().single, contains('touch held 160,260'));

      await finger.up();
      _step();
      expect(_lastStep().single, contains('touch ended 160,260'));
    });

    testWidgets('two fingers on the widget are two contacts', (tester) async {
      final game = await _boot(_TouchGame.new);
      await tester.pumpWidget(GameView.headless(game: game));

      final left = await tester.startGesture(
        const Offset(10, 10),
        pointer: 1,
        kind: PointerDeviceKind.touch,
      );
      final right = await tester.startGesture(
        const Offset(90, 90),
        pointer: 2,
        kind: PointerDeviceKind.touch,
      );
      _step();

      expect(
        _lastStep(),
        hasLength(2),
        reason:
            'a raw Listener reports both, where one GestureDetector pan would '
            'swallow the second - DragGestureRecognizer is mono-drag',
      );
      await left.up();
      await right.up();
    });

    testWidgets('the view going away cancels a finger still down', (
      tester,
    ) async {
      final game = await _boot(_TouchGame.new);
      await tester.pumpWidget(GameView.headless(game: game));

      final finger = await tester.startGesture(
        const Offset(50, 50),
        kind: PointerDeviceKind.touch,
      );
      _step();
      expect(_lastStep(), hasLength(1));

      await tester.pumpWidget(const SizedBox.shrink());
      _step();

      expect(
        _lastStep().single,
        contains('cancelled'),
        reason:
            'the events that would have said the finger lifted left with the '
            'view, so a contact left live would drive whatever it was driving '
            'forever',
      );

      // The gesture outlived the widget that was routing it; ending it here
      // keeps the test binding from complaining about a live pointer.
      await finger.up();
    });
  });
}
