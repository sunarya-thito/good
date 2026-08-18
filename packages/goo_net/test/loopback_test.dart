import 'package:goo_net/goo_net.dart';
import 'package:goo_net/testing.dart';

void main() {
  runNetTransportConformance(
    'loopback',
    create: LoopbackNetTransport.new,
    // The switchboard is a static, so a test that threw partway through would
    // otherwise leave a session code taken and fail the next test for a
    // reason that has nothing to do with it.
    tearDownAll: LoopbackNetTransport.reset,
  );
}
