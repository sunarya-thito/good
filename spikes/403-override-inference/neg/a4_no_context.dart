// The control that says the working case is driven by the override and not by
// anything ambient: with no overridden member to supply a context type, the
// same shorthand text has nothing to resolve against.
//
// Expected: an error, not an inferred type

class Loose {
  final speed = .initial(20);
}
