import 'dart:io';

import 'package:good_tool/src/declaration_scan.dart';
import 'package:good_tool/src/engine_packages.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '_repo.dart';

// What `--declarations` reports and what it leaves alone (#290).
//
// A declaration lands on whichever owner is under construction when its
// initialiser runs. The three spellings this reports - `late`, `static`, a
// top-level variable - all run the initialiser somewhere other than where it
// is written, so the declaration lands on the wrong owner or on nobody.
//
// A check with false positives gets switched off, so most of what is here is a
// shape that must pass: an eager field, a `late` field with no initialiser at
// all, a declaration inside the static factory that exists to make one, a lazy
// variable holding something that is not a declaration, and a call on a value
// rather than on a type. Measured against this repository's own tree before
// any of it was written: 215 declaration calls across 133 files in
// `packages/*/lib`, and none of them deferred.
//
// Every fixture is a real package tree, because the scan reads pubspecs and
// walks lib/.

/// A stand-in for `good`: the registrar name every seed bottoms out at, and
/// three statics that reach it.
///
/// Written out rather than borrowed from the real package, so the entry-point
/// set a test asserts on holds what that test put there and nothing else.
FakePackage _kernel() => FakePackage(
  'good',
  files: <String, String>{
    'good.dart': '''
abstract final class DeclarationContext {
  static Object get data => throw UnimplementedError();
  static Object get events => throw UnimplementedError();
}

abstract final class Field {
  static Object float64([double initial = 0]) => DeclarationContext.data;
  static Object int32([int initial = 0]) => DeclarationContext.data;
}

abstract final class Event {
  static Object signal() => DeclarationContext.events;
}

abstract class Component {
  /// Reaches the registrar through `Field`, so it is a seed in its own right.
  static T declare<T extends Object>(T declaration) {
    DeclarationContext.data;
    return declaration;
  }
}

/// An instance method on the registrar's own side. Never an entry point: a
/// field initialiser does not write this.
class Registry {
  Object declare() => DeclarationContext.data;
}
''',
  },
);

/// A stand-in for `goo2d`: a factory that declares by calling `good`'s, which
/// is the hop the closure has to take.
FakePackage _middle() => FakePackage(
  'goo2d',
  dependencies: <String>['good'],
  files: <String, String>{
    'goo2d.dart': '''
import 'package:good/good.dart';

class CircleBody {
  CircleBody(this.radius);
  final Object radius;

  /// Names no registrar. It is a declaration because it calls two things that
  /// are, which is the only way this is reached.
  static CircleBody of({double radius = 0}) =>
      Component.declare(CircleBody(Field.float64(radius)));
}
''',
  },
);

/// The package under test, holding [files] under its `lib/`.
FakePackage _game(Map<String, String> files, {String name = 'demo'}) =>
    FakePackage(
      name,
      files: files,
      dependencies: <String>['good', 'goo2d'],
    );

/// Runs the check over [packages], reporting on the ones [only] names.
///
/// [only] left out reports on every package in the tree, which is what this
/// repository's own invocation does.
DeclarationScan _scan(List<FakePackage> packages, {List<String>? only}) {
  final repo = fakeRepo(packages);
  final found = enginePackages(<Directory>[
    Directory(p.join(repo.path, 'packages')),
  ]).packages;
  return scanDeferredDeclarations(
    packages: only == null
        ? found
        : <EnginePackage>[
            for (final package in found)
              if (only.contains(package.name)) package,
          ],
    known: found,
  );
}

/// The scan over one game library, with the two engine packages under it.
DeclarationScan _over(String source) => _scan(<FakePackage>[
  _kernel(),
  _middle(),
  _game(<String, String>{'demo.dart': source}),
], only: <String>['demo']);

void main() {
  group('reports', () {
    test('a late field initialiser', () {
      final scan = _over('''
import 'package:good/good.dart';

class Player {
  late final speed = Field.float64(3.0);
}
''');

      expect(scan.deferred, hasLength(1));
      final deferred = scan.deferred.single;
      expect(deferred.call, 'Field.float64');
      expect(deferred.holder, 'speed');
      expect(deferred.deferral, DeferralKind.late$);
      expect(deferred.where, 'demo/lib/demo.dart:4');
    });

    test('a static field initialiser, with no late written anywhere', () {
      // The spelling the engine's own error messages do not name and no test
      // in this repository covered: a `static` initialiser is lazy in Dart, so
      // it defers exactly as `late` does.
      final scan = _over('''
import 'package:good/good.dart';

class Player {
  static final speed = Field.float64(3.0);
}
''');

      expect(scan.deferred, hasLength(1));
      expect(scan.deferred.single.deferral, DeferralKind.static$);
      expect(scan.deferred.single.holder, 'speed');
    });

    test('a static late field is reported as static', () {
      // Removing `late` would leave it just as lazy, so `static` is the fact
      // that explains it and the one the line has to name.
      final scan = _over('''
import 'package:good/good.dart';

class Player {
  static late final speed = Field.float64(3.0);
}
''');

      expect(scan.deferred, hasLength(1));
      expect(scan.deferred.single.deferral, DeferralKind.static$);
    });

    test('a top-level variable', () {
      final scan = _over('''
import 'package:good/good.dart';

final speed = Field.float64(3.0);
''');

      expect(scan.deferred, hasLength(1));
      expect(scan.deferred.single.deferral, DeferralKind.topLevel);
      expect(scan.deferred.single.holder, 'speed');
    });

    test('a late local variable', () {
      final scan = _over('''
import 'package:good/good.dart';

Object build() {
  late final speed = Field.float64(3.0);
  return speed;
}
''');

      expect(scan.deferred, hasLength(1));
      expect(scan.deferred.single.deferral, DeferralKind.late$);
    });

    test('a declaration nested inside a lazy initialiser', () {
      // The walk is over what holds the call, not over where the call is, so
      // depth inside the initialiser changes nothing.
      final scan = _over('''
import 'package:good/good.dart';

class Holder {
  Holder(this.parts);
  final List<Object> parts;

  static Holder make(List<Object> parts) => Holder(parts);
}

class Player {
  late final parts = Holder.make(<Object>[Field.float64(1), Field.int32(2)]);
}
''');

      expect(scan.deferred, hasLength(2));
      expect(
        scan.deferred.map((d) => d.call),
        <String>['Field.float64', 'Field.int32'],
      );
      expect(scan.deferred.every((d) => d.holder == 'parts'), isTrue);
    });

    test('two lazy variables in one declaration list', () {
      final scan = _over('''
import 'package:good/good.dart';

class Player {
  static final a = Field.float64(1), b = Field.int32(2);
}
''');

      expect(scan.deferred.map((d) => d.holder), <String>['a', 'b']);
    });

    test('a factory reached only through another package', () {
      // `CircleBody.of` names no registrar. It is a declaration because it
      // calls `Component.declare` and `Field.float64`, and this is the whole
      // of what the closure buys: without the hop the line reads as an
      // ordinary constructor call and nothing is reported.
      final scan = _over('''
import 'package:goo2d/goo2d.dart';

class Player {
  late final body = CircleBody.of(radius: 8);
}
''');

      expect(scan.deferred, hasLength(1));
      expect(scan.deferred.single.call, 'CircleBody.of');
    });

    test("a factory of the scanned package's own", () {
      // A game writes its own factory, and nothing has told the tool about it.
      // It is reached the same way `CircleBody.of` is.
      final scan = _over('''
import 'package:good/good.dart';

class Turret {
  Turret(this.aim);
  final Object aim;

  static Turret of() => Component.declare(Turret(Field.float64(0)));
}

class Player {
  static final turret = Turret.of();
}
''');

      expect(
        scan.deferred.map((d) => d.call),
        contains('Turret.of'),
        reason: 'the closure runs over the scanned package too, not only over '
            'the engine packages under it',
      );
    });
  });

  group('leaves alone', () {
    test('an eager instance field, which is every correct site', () {
      final scan = _over('''
import 'package:good/good.dart';
import 'package:goo2d/goo2d.dart';

class Player {
  final speed = Field.float64(3.0);
  final hp = Field.int32(100);
  final body = CircleBody.of(radius: 8);
}
''');

      expect(scan.deferred, isEmpty);
      expect(
        scan.calls,
        3,
        reason: 'all three were recognised as declarations and none of them '
            'was deferred - a zero that came from finding nothing would pass '
            'the assertion above on its own',
      );
    });

    test('a late field with no initialiser', () {
      // The shape a `describeStruct` body fills in, and the one this
      // repository's own tests write twenty times over. There is no
      // initialiser to defer.
      final scan = _over('''
import 'package:good/good.dart';

class Player {
  late final Object speed;
  late Object hp;

  void describe() {
    speed = Field.float64(3.0);
    hp = Field.int32(1);
  }
}
''');

      expect(scan.deferred, isEmpty);
      expect(scan.calls, 2, reason: 'both calls were seen and neither is held '
          'by a lazy variable');
    });

    test('a declaration inside the static factory that exists to make one', () {
      // 74 sites in this repository's `lib/` are this shape. A rule that read
      // location instead of what holds the call would report every one of
      // them.
      final scan = _over('''
import 'package:good/good.dart';

class Turret {
  Turret(this.aim);
  final Object aim;

  static Turret of() => Component.declare(Turret(Field.float64(0)));

  static Turret _helper() => Turret(Field.int32(0));
}
''');

      expect(scan.deferred, isEmpty);
    });

    test('a lazy variable holding something that is not a declaration', () {
      final scan = _over('''
import 'package:good/good.dart';

final greeting = DateTime.now().toIso8601String();

class Player {
  static final label = Object();
  late final other = int.parse('3');
}
''');

      expect(scan.deferred, isEmpty);
      expect(scan.calls, 0);
    });

    test('a call on a value rather than on a type', () {
      // `Registry.declare` is an instance method, so `registry.declare()` is
      // not an entry point however the receiver is spelled.
      final scan = _over('''
import 'package:good/good.dart';

class Player {
  Player(this.registry);
  final Registry registry;

  late final made = registry.declare();
}
''');

      expect(scan.deferred, isEmpty);
    });

    test('a getter, which this does not decide', () {
      // Recorded rather than reported: separating a getter that re-declares on
      // every read from a factory needs what the entry-point closure only has
      // for statics. It is written down on `scanDeferredDeclarations`.
      final scan = _over('''
import 'package:good/good.dart';

class Player {
  Object get speed => Field.float64(3.0);
}
''');

      expect(scan.deferred, isEmpty);
      expect(scan.calls, 1, reason: 'the call is seen, and not reported');
    });
  });

  group('the entry points come from the packages read', () {
    test('a seed, a hop, and nothing an instance method contributes', () {
      // An exact count, because this is the only assertion that can see the
      // static-only filter at all. Nothing a call site writes can reach an
      // instance method - `Registry.declare()` does not compile and
      // `registry.declare()` reads as a different pair - so the filter cannot
      // change what is reported, only what the set holds. Counted here so it
      // is not a mechanism nothing measures.
      //
      // Four seeds name the registrar: Field.float64, Field.int32,
      // Event.signal and Component.declare. CircleBody.of is the hop.
      // Registry.declare names the registrar too and is an instance method, so
      // it is the one left out. DeclarationContext.data and .events are static
      // getters, which are not declarations either.
      final scan = _over('''
import 'package:good/good.dart';

class Player {
  final speed = Field.float64(1);
}
''');

      expect(scan.entryPoints, 5);
    });

    test('a scan with no engine package under it finds nothing', () {
      // The documented trap: entry points are derived from the packages read,
      // so a run that cannot see `good` reports a clean tree over code full of
      // declarations. Pinned so that a change which narrows `known` fails
      // here rather than silently reporting success.
      final repo = fakeRepo(<FakePackage>[
        _kernel(),
        _game(<String, String>{
          'demo.dart': '''
import 'package:good/good.dart';

class Player {
  late final speed = Field.float64(3.0);
}
''',
        }),
      ]);
      final found = enginePackages(<Directory>[
        Directory(p.join(repo.path, 'packages')),
      ]).packages;
      final only = <EnginePackage>[
        for (final package in found)
          if (package.name == 'demo') package,
      ];

      final blind = scanDeferredDeclarations(packages: only, known: only);
      expect(blind.deferred, isEmpty);
      expect(blind.entryPoints, 0);

      final seeing = scanDeferredDeclarations(packages: only, known: found);
      expect(seeing.deferred, hasLength(1));
    });
  });

  group('the report', () {
    test('names the file, the holder, the call and the deferral', () {
      final scan = _over('''
import 'package:good/good.dart';

class Player {
  late final speed = Field.float64(3.0);
}
''');

      expect(
        deferredDeclarationLine(scan.deferred.single),
        'demo/lib/demo.dart:4: `speed` holds Field.float64 - a `late` '
        'initialiser runs on first read',
      );
      expect(
        deferredDeclarationSummary(scan),
        contains('1 declaration(s) are held by a variable'),
      );
    });
  });
}
