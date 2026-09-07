// GENERATED - do not edit.
//
// Regenerate with `dart run good_tool` from
// packages/good_tool, and commit what changes.
// `dart run good_tool --check` is what CI runs; it fails if
// this file is not what the generator would write.
//
// One function per class this package can instantiate that
// declares anything. A declaration is a field holding its own
// value, with nothing open around it, so this is the only
// record of what a class declared - and a class's field list
// is the one thing a running program cannot ask for.
//
// The order inside each list is the order the fields would
// have been initialised in: the class's own, then each
// mixin's with the last name in the `with` clause first,
// then the superclass's. That order is the field order of
// every row of the archetype, so reordering a list here
// relays out the entities.
//
// A commented-out line is a declaration held by a private
// field. Dart privacy is per library and this is a different
// one, so nothing here can read it - it keeps its place so
// that what the row is missing, and where, is visible.
//
// Beside each list is every type an instance of that class
// is, the class itself first, then the names in its extends,
// with and implements clauses in that order, each followed by
// its own supertypes. Nothing reads that order positionally;
// it is fixed so two machines write one file.
//
// A type the generator did not read - anything in dart: or in
// a package outside the run - is not listed, because nothing
// downstream of this file can act on a name it never saw. A
// type it did read and this library cannot name keeps its
// place as a comment.

import 'package:good/good.dart';
import 'package:good_net/src/listener.dart';
import 'package:good_net/src/message.dart';
import 'package:good_net/src/system.dart';

List<ScannableField> _networkSystem(Object object) {
  final owner = object as NetworkSystem;
  return <ScannableField>[
    owner.peerJoinedEvent,
    owner.peerLeftEvent,
    owner.sessionOpenedEvent,
    owner.sessionClosedEvent,
  ];
}

const List<Type> _supertypes$NetworkSystem = <Type>[
  NetworkSystem,
  GameSystem,
  GameListenerBase,
  GameListener,
  EventBus,
  Scannable,
  Coroutines,
  ScannableField,
  FixedTickable,
  Tickable,
  NetSender,
  NetListener,
];

/// Every class `package:good_net` can instantiate that holds a
/// declaration, and how to read one.
///
/// Pass this to `Game.declarations` - together with the table
/// of every other engine package the game uses, and the one
/// generated for the game itself - so a registration can read
/// what a constructed object declared.
const GeneratedDeclarations goodNetDeclarations = GeneratedDeclarations(
  package: 'good_net',
  collectors: <DeclarationCollector>[
    DeclarationCollector(
      NetworkSystem,
      _networkSystem,
      _supertypes$NetworkSystem,
    ),
  ],
  dependencies: <GeneratedDeclarations>[
    goodDeclarations,
  ],
);
