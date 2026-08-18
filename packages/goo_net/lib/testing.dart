/// The [NetTransport] conformance suite, as library code so that every
/// backend can run the same one.
///
/// ```dart
/// import 'package:goo_net/testing.dart';
///
/// void main() {
///   runNetTransportConformance('p2p', create: P2PNetTransport.new);
/// }
/// ```
///
/// Separate from `goo_net.dart` so that a game importing the engine does not
/// also import a test framework.
library;

export 'src/testing/conformance.dart' show runNetTransportConformance;
