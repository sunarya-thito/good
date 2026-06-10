import 'package:goo2d/src/data/component.dart';
import 'package:goo2d/src/data/enum.dart';
import 'package:goo2d/src/physics/utils/enums.dart';
import 'package:goo2d/src/physics/worker/data/collider_shape_type.dart';

class RigidbodyData extends EntityData {
  late final Field<int> bodyHandle;
  late final Field<RigidbodyType> bodyType;
  late final Field<double> gravityScale;
  late final Field<double> angularDamping;
  late final Field<double> linearDampingX;
  late final Field<double> linearDampingY;
  late final Field<bool> freezeRotation;
  late final Field<bool> simulated;

  @override
  void describe(DataDescriptor d) {
    bodyHandle = d.newInt32(initialValue: -1);
    bodyType = d.newField(
      EnumFieldParser(RigidbodyType.values),
      initialValue: RigidbodyType.dynamic,
    );
    gravityScale = d.newFloat32(initialValue: 1.0);
    angularDamping = d.newFloat32();
    linearDampingX = d.newFloat32();
    linearDampingY = d.newFloat32();
    freezeRotation = d.newBool();
    simulated = d.newBool(initialValue: true);
  }
}

class ColliderData extends EntityData {
  late final Field<int> colliderHandle;
  late final Field<ColliderShapeType> shapeType;
  late final Field<bool> isTrigger;
  late final Field<double> width;
  late final Field<double> height;
  late final Field<double> radius;
  late final Field<double> offsetX;
  late final Field<double> offsetY;
  late final Field<double> density;
  late final Field<double> friction;
  late final Field<double> bounciness;

  @override
  void describe(DataDescriptor d) {
    colliderHandle = d.newInt32(initialValue: -1);
    shapeType = d.newField(
      EnumFieldParser(ColliderShapeType.values),
      initialValue: ColliderShapeType.box,
    );
    isTrigger = d.newBool();
    width = d.newFloat32(initialValue: 1.0);
    height = d.newFloat32(initialValue: 1.0);
    radius = d.newFloat32(initialValue: 0.5);
    offsetX = d.newFloat32();
    offsetY = d.newFloat32();
    density = d.newFloat32(initialValue: 1.0);
    friction = d.newFloat32(initialValue: 0.4);
    bounciness = d.newFloat32();
  }
}
