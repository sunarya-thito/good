/// E: what `overridden_fields` costs, measured rather than asserted.
///
/// It is in `package:lints/recommended.yaml`, which `packages/good` includes
/// and a scaffolded game gets too, and `flutter analyze` exits non-zero on an
/// info. #198 recorded that the `super.speed.withInitial(20)` form trips it "on
/// every use", so the two forms are counted here side by side.
library;

import 'widths.dart';

class EBase {
  final speed = Field.uint8(10);
}

// One declaration, several reads. Counting the infos this file produces says
// whether the lint is per declaration or per use.
class EShorthand extends EBase {
  @override
  final speed = .initial(20);
}

class ESuperForm extends EBase {
  @override
  late final speed = super.speed.withInitial(20);
}

// Placement of the ignore comment. `// ignore:` applies to the line that
// follows it, and `@override` is a line.
class EIgnoreAboveAnnotation extends EBase {
  // ignore: overridden_fields
  @override
  final speed = .initial(20);
}

class EIgnoreOnDeclaration extends EBase {
  @override
  // ignore: overridden_fields
  final speed = .initial(20);
}

void readsThem() {
  print(EShorthand().speed.initialValue);
  print(EShorthand().speed.initialValue);
  print(EShorthand().speed.bitWidth);
  print(ESuperForm().speed.initialValue);
  print(ESuperForm().speed.initialValue);
  print(ESuperForm().speed.bitWidth);
}
