/// Library surface for the `good` build tool - asset packing/encryption,
/// compile-time ECS struct-layout codegen (via package:analyzer, hoisting
/// good's runtime DataDescriptor layout algorithm to build time), and
/// platform build/packaging orchestration.
///
/// Nothing is exported yet. Use the package through its command line:
/// `dart pub global activate good_cli`, then `good --help`. The entry point
/// is `bin/good.dart`.
library;
