/// H: the same override written as a primary-constructor parameter, which is
/// the spelling #265 landed for a component's configuration.
///
/// `strict_top_level_inference` is in `package:lints/core.yaml`, so it is on
/// wherever `recommended` is, and #265 recorded that it reports
/// `@override final textCapacity = 8` in a parameter position while the body
/// field of the same spelling infers from the getter it overrides. The
/// question here is whether the parameter position can carry the shorthand at
/// all, since a shorthand with no context type has nothing to resolve.
library;

import 'widths.dart';

class HBase {
  final speed = Field.uint8(10);
}

// The body-field spelling, for comparison in the same file.
class HBody extends HBase {
  @override
  final speed = .initial(20);
}

void checkStaticTypes() {
  takesUint8(HBody().speed);
}
