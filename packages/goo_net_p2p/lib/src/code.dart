import 'dart:io';
import 'dart:typed_data';

import 'package:goo_net/goo_net.dart';

/// Turns a host's address and port into a [SessionId] and back.
///
/// # Why the code *is* the address
///
/// PeerJS hands out a short id and a public broker turns it into an address.
/// That broker is a server, and this package's whole promise is that there
/// is not one. So the code carries the address itself: joining is decoding
/// six bytes and sending a packet to them, with nothing in between that
/// anyone has to run, pay for, or keep alive.
///
/// The cost is honest and worth stating: **a code minted this way is only
/// reachable from where that address is reachable.** A LAN address works
/// across the room and nowhere else. A public address works from anywhere,
/// once the host's NAT has been persuaded to forward it - which is the part
/// STUN and hole punching do, and which needs a rendezvous to arrange, and
/// which is therefore the next landing rather than this one. Discovery
/// ([P2PNetTransport.discover]) is the other half of the same story: on a LAN
/// nobody has to type anything at all.
///
/// # The encoding
///
/// Four address bytes and a port are 48 bits. Written in base 31 - the size
/// of [SessionId.alphabet], which drops `0`/`O` and `1`/`I`/`L` so a code
/// survives being read out loud - that is ten characters, since
/// `31^10 > 2^48`. Ten is more than the six a lobby code would be, and it is
/// what carrying the address instead of an index into someone's database
/// costs.
///
/// IPv4 only, deliberately: an IPv6 address is 128 bits and would make a
/// 26-character code, which is not something a person retypes. A future
/// rendezvous-minted code is short *and* v6-capable, because a short code is
/// exactly what a directory buys you.
abstract final class EndpointCode {
  /// How many characters an encoded endpoint takes.
  static const int length = 10;

  static final BigInt _radix = BigInt.from(SessionId.alphabet.length);

  /// The code for [address] and [port]. Throws if [address] is not IPv4.
  static SessionId encode(InternetAddress address, int port) {
    if (address.type != InternetAddressType.IPv4) {
      throw ArgumentError.value(
        address.address,
        'address',
        'a join code carries an IPv4 address; see EndpointCode',
      );
    }
    final raw = address.rawAddress;
    var value =
        (raw[0] << 40) |
        (raw[1] << 32) |
        (raw[2] << 24) |
        (raw[3] << 16) |
        (port & 0xFFFF);
    final digits = List<String>.filled(length, SessionId.alphabet[0]);
    for (var i = length - 1; i >= 0; i--) {
      digits[i] = SessionId.alphabet[value % 31];
      value ~/= 31;
    }
    return SessionId(digits.join());
  }

  /// The endpoint [id] encodes, or null if it is not one of these codes -
  /// a typo, or a code some other backend minted.
  static ({InternetAddress address, int port})? decode(SessionId id) {
    if (id.value.length != length) return null;
    var value = BigInt.zero;
    for (var i = 0; i < id.value.length; i++) {
      final digit = SessionId.alphabet.indexOf(id.value[i]);
      if (digit < 0) return null;
      value = value * _radix + BigInt.from(digit);
    }
    if (value >= BigInt.one << 48) return null;
    final packed = value.toInt();
    final address = InternetAddress.fromRawAddress(
      Uint8List.fromList(<int>[
        (packed >> 40) & 0xFF,
        (packed >> 32) & 0xFF,
        (packed >> 24) & 0xFF,
        (packed >> 16) & 0xFF,
      ]),
    );
    return (address: address, port: packed & 0xFFFF);
  }
}
