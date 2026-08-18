import 'dart:io';

import 'package:good_net/testing.dart';
import 'package:good_net_p2p/good_net_p2p.dart';

void main() {
  runNetTransportConformance(
    'p2p',
    // Loopback, so a test run neither leaves the machine nor depends on
    // which interfaces this machine happens to have.
    create: () => P2PNetTransport(bindAddress: InternetAddress.loopbackIPv4),
    // Real sockets, so "it has arrived" is a thing that takes time. A few
    // milliseconds is several round trips over loopback.
    settle: () => Future<void>.delayed(const Duration(milliseconds: 5)),
  );
}
