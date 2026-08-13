import 'package:flutter_test/flutter_test.dart';

void main() {
  // Smoke test only. Layout/archetype/pool coverage lives in
  // archetype_test.dart, data_layout_test.dart, pool_test.dart; the query
  // system's coverage lands with the query system itself.
  test('package loads', () {
    expect(1 + 1, 2);
  });
}
