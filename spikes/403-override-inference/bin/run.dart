/// A clean analysis says the types line up. It does not say the values do, so
/// this runs the probes and prints what each override actually holds.
library;

import 'package:spike403/probe_a_core.dart';
import 'package:spike403/probe_b_members.dart';
import 'package:spike403/probe_c_values.dart';
import 'package:spike403/probe_d_phantom.dart';
import 'package:spike403/widths.dart';

void main() {
  print(
    'A base   ${Player().speed.initialValue} width ${Player().speed.bitWidth}',
  );
  print('A sub    ${Fast().speed.initialValue} width ${Fast().speed.bitWidth}');
  print(
    'A wide   ${WideFast().hp.initialValue} width ${WideFast().hp.bitWidth}',
  );
  print('A rtType ${Fast().speed.runtimeType} / ${WideFast().hp.runtimeType}');

  print('B1 ${B1Sub().speed.initialValue} ${B1Sub().speed.runtimeType}');
  print('B2 ${B2Sub().speed.initialValue} ${B2Sub().speed.runtimeType}');
  print('B3 ${B3Sub().speed.initialValue} ${B3Sub().speed.runtimeType}');
  print('B4 ${B4Sub().speed.initialValue} ${B4Sub().speed.runtimeType}');
  print('B5 ${B5Sub().speed.initialValue} ${B5Sub().speed.runtimeType}');
  print('B6 ${B6Sub().speed.initialValue} ${B6Sub().speed.runtimeType}');
  print('B7 ${B7Leaf().speed.initialValue} ${B7Leaf().speed.runtimeType}');
  print('B8 ${B8Sub().speed.initialValue} ${B8Sub().speed.runtimeType}');
  print('B9 ${B9Sub().speed.initialValue} ${B9Sub().speed.runtimeType}');

  print(
    'C ${CSub().speed.initialValue} ${CSub().gravity.initialValue} '
    '${CSub().alive.initialValue} ${CSub().owner.initialValue.index} '
    '${CSub().ammo.initialValue} ${CSub().team.initialValue} '
    '${CSub().team.runtimeType}',
  );
  print('C ctor ${CtorSub().hp.initialValue} ${CtorSub().hp.runtimeType}');

  print('D ${DSub().speed.initialValue} ${DSub().speed.runtimeType}');
  print('D ${DSub().hp.initialValue} ${DSub().hp.runtimeType}');

  // The thing #198 warns about, restated as a run rather than a claim: the
  // subclass's initialiser runs first, so the object the base registers is
  // not the object the subclass declares.
  final sub = Fast();
  print('A identity ${identical(sub.speed, Player().speed)}');
}
