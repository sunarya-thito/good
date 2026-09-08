// The primary-constructor spelling of the same override. What it reports is
// the measurement; the file is under `neg/` because it does not analyse
// clean.
//
// A parameter default has to be a constant expression, and both
// `Field.uint8(10)` and `.initial(20)` are method calls, so the second
// declaration below fails for the same reason as the first even with the
// type written out. That is not the inference giving way - it is that a
// column cannot be declared in a parameter position at all.
//
// Expected: two const_eval_method_invocation, plus the
// strict_top_level_inference #265 recorded for the un-annotated one
import 'package:spike403/probe_h_primary_constructor.dart';
import 'package:spike403/widths.dart';

class HPrimary({@override final speed = .initial(20)}) extends HBase;

class HPrimaryAnnotated({
  @override final Uint8Field speed = Uint8Field.initial(20),
}) extends HBase;
