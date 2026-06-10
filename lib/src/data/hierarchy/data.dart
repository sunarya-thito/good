import 'package:goo2d/goo2d.dart';

// Presence = child entity. Absence = root entity (no parent).
class ChildOfData extends EntityData {
  late final Field<int> parentIndex; // entity slot index of parent
  late final Field<int> depth;       // 1 = direct child of root, 2 = grandchild, etc.

  @override
  void describe(DataDescriptor d) {
    parentIndex = d.newUint32();
    depth       = d.newUint8();
  }
}
