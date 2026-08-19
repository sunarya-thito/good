import 'dart:math' as math;

import 'package:good/good.dart';

/// Where a thing sits, how it is turned and how big it is, relative to its
/// parent.
///
/// Stored decomposed - position, scale and rotation as separate columns,
/// never as a matrix. Sixteen floats per entity would have to be kept up to
/// date by whoever writes any one of them, and a system that only wants a
/// position would read a whole matrix row to get it.
///
/// Rotation is a quaternion in four columns rather than three Euler angles.
/// Three angles gimbal-lock, and combining rotations is exactly what a
/// parent-child hierarchy does on every tick. Nothing here asks the game to
/// think in quaternions: [Transform3DAccessor.setEuler] and [Transform3DAccessor.lookAt]
/// write the four columns, and the angle and basis getters read them back.
///
/// The world is right-handed with **+Y up** and **-Z forward**, which is what
/// glTF uses, so a mesh exported from Blender arrives oriented correctly.
/// `goo2d` puts +Y up too, so "up" means the same thing in both dimensions.
///
/// The columns are here; everything you *do* with them is on
/// [Transform3DAccessor], reached as `entity<Transform3D>()`.
mixin Transform3D on Component {
  late final DataPointer<double> transformOffsetX;
  late final DataPointer<double> transformOffsetY;
  late final DataPointer<double> transformOffsetZ;

  late final DataPointer<double> transformScaleX;
  late final DataPointer<double> transformScaleY;
  late final DataPointer<double> transformScaleZ;

  late final DataPointer<double> transformRotationX;
  late final DataPointer<double> transformRotationY;
  late final DataPointer<double> transformRotationZ;
  late final DataPointer<double> transformRotationW;

  @override
  void describeType(ComponentDescriptor component) {
    super.describeType(component);
    component.has<Transform3D>();
  }

  @override
  void describeStruct(DataDescriptor data) {
    super.describeStruct(data);
    transformOffsetX = data.hasFloat64();
    transformOffsetY = data.hasFloat64();
    transformOffsetZ = data.hasFloat64();

    // Scale defaults to 1 and the quaternion to (0, 0, 0, 1) - each field's
    // own identity, not the storage layer's 0. A zero scale collapses every
    // point to the origin and an all-zero quaternion is not a rotation at
    // all, so an entity that simply never assigned either would be
    // degenerate with nothing anywhere saying why. Offsets keep the plain
    // default, because 0 *is* their identity. Same reasoning as
    // `Transform2D`, one dimension up.
    transformScaleX = data.hasFloat64(1);
    transformScaleY = data.hasFloat64(1);
    transformScaleZ = data.hasFloat64(1);

    transformRotationX = data.hasFloat64();
    transformRotationY = data.hasFloat64();
    transformRotationZ = data.hasFloat64();
    transformRotationW = data.hasFloat64(1);
  }
}

/// What a game does with a [Transform3D], on the **entity** rather than on
/// the component: `entity<Transform3D>().setEuler(yaw: 0.5)`.
///
/// These read and write *local* values - what the raw columns hold. The
/// world-space equivalent, with every ancestor applied, is
/// `WorldTransform3D`'s own columns (world_transform.dart).
///
/// # Why these are not methods on the mixin
///
/// A helper on the mixin has to take the entity as an argument, and then
/// nothing in the signature says whether the receiver is meant to be *that*
/// entity's component or another one's - and with two entities in the
/// signature, as [distanceTo] has, there is no receiver that is right for
/// both. Here the receiver is the entity, and each entity's component is
/// resolved from it, so a helper cannot be pointed at the wrong archetype's
/// row layout at all. `Accessor<T>` erases to `Entity` erases to `int`, and
/// implements `Entity`, so the view costs nothing and is still an entity -
/// which is why the bodies below index columns with `this` (see `Accessor` in
/// the kernel).
///
/// Nothing here allocates. The quaternion arithmetic is written out in local
/// doubles rather than through a vector type, because this is called from
/// gameplay code that runs every tick.
extension Transform3DAccessor on Accessor<Transform3D> {
  /// Local-space (no ancestors, no `WorldTransform3D`) distance between this
  /// entity's offset and [other]'s.
  ///
  /// [other] may be a different archetype with a different row layout, so it
  /// is read through its own component, not through this one's.
  double distanceTo(Entity other) {
    final ta = get<Transform3D>();
    final tb = other.get<Transform3D>();
    final dx = tb.transformOffsetX[other] - ta.transformOffsetX[this];
    final dy = tb.transformOffsetY[other] - ta.transformOffsetY[this];
    final dz = tb.transformOffsetZ[other] - ta.transformOffsetZ[this];
    return math.sqrt(dx * dx + dy * dy + dz * dz);
  }

  /// Writes the rotation columns from three angles, in radians.
  ///
  /// [yaw] turns about +Y, [pitch] about +X and [roll] about +Z, and they
  /// compose in that order: `Ry(yaw) * Rx(pitch) * Rz(roll)`. Read as body
  /// axes that is roll first, then pitch, then yaw - the order an aircraft or
  /// a camera rig wants, and the one that keeps yaw meaning "turn on the
  /// spot" no matter what pitch is.
  ///
  /// Euler angles are an input format here, not storage: the four columns
  /// this writes are what everything downstream reads, so the gimbal problem
  /// that makes three angles a bad *representation* never reaches the
  /// hierarchy. [yaw], [pitch] and [roll] - the getters - invert this.
  void setEuler({double yaw = 0, double pitch = 0, double roll = 0}) {
    final t = get<Transform3D>();
    // Half angles: a quaternion built from angle a turns by a, not a/2.
    final cy = math.cos(yaw * 0.5);
    final sy = math.sin(yaw * 0.5);
    final cp = math.cos(pitch * 0.5);
    final sp = math.sin(pitch * 0.5);
    final cr = math.cos(roll * 0.5);
    final sr = math.sin(roll * 0.5);

    // The product Ry * Rx * Rz multiplied out, so no intermediate quaternion
    // is built to be thrown away.
    t.transformRotationX[this] = cy * sp * cr + sy * cp * sr;
    t.transformRotationY[this] = sy * cp * cr - cy * sp * sr;
    t.transformRotationZ[this] = cy * cp * sr - sy * sp * cr;
    t.transformRotationW[this] = cy * cp * cr + sy * sp * sr;
  }

  /// The yaw of the current local rotation, in radians - [setEuler]'s
  /// inverse, together with [pitch] and [roll].
  ///
  /// The three do not round-trip through *every* input: the same orientation
  /// has more than one Euler spelling (a pitch beyond a quarter turn is the
  /// same orientation as a smaller pitch with yaw and roll turned half a
  /// turn), so these return the canonical one - pitch in [-pi/2, pi/2], the
  /// other two in [-pi, pi]. The *orientation* round-trips exactly; the
  /// numbers round-trip when they were already canonical.
  ///
  /// Straight up or straight down ([pitch] at exactly +-pi/2) is the gimbal
  /// case: yaw and roll are no longer separable there, only their sum, so
  /// [roll] reports 0 and [yaw] carries the whole turn.
  double get yaw {
    final t = get<Transform3D>();
    final x = t.transformRotationX[this];
    final y = t.transformRotationY[this];
    final z = t.transformRotationZ[this];
    final w = t.transformRotationW[this];
    // sin(pitch) out of the rotation matrix's m12. Clamped because a
    // quaternion that has drifted a hair past unit length would otherwise
    // put asin's argument outside [-1, 1] and return NaN.
    final sinPitch = _clampUnit(2 * (w * x - y * z));
    if (sinPitch.abs() >= _gimbalThreshold) {
      // cos(pitch) is 0, so the m02/m22 pair below is 0/0. Only yaw+-roll is
      // determined here; the whole of it is reported as yaw.
      return math.atan2(-2 * (x * z - w * y), 1 - 2 * (y * y + z * z));
    }
    return math.atan2(2 * (x * z + w * y), 1 - 2 * (x * x + y * y));
  }

  /// The pitch of the current local rotation, in radians, in [-pi/2, pi/2].
  /// See [yaw].
  double get pitch {
    final t = get<Transform3D>();
    final x = t.transformRotationX[this];
    final y = t.transformRotationY[this];
    final z = t.transformRotationZ[this];
    final w = t.transformRotationW[this];
    return math.asin(_clampUnit(2 * (w * x - y * z)));
  }

  /// The roll of the current local rotation, in radians. See [yaw] - this is
  /// the angle that is not separable when pitched straight up or down, and
  /// reports 0 there.
  double get roll {
    final t = get<Transform3D>();
    final x = t.transformRotationX[this];
    final y = t.transformRotationY[this];
    final z = t.transformRotationZ[this];
    final w = t.transformRotationW[this];
    final sinPitch = _clampUnit(2 * (w * x - y * z));
    if (sinPitch.abs() >= _gimbalThreshold) return 0;
    return math.atan2(2 * (x * y + w * z), 1 - 2 * (x * x + z * z));
  }

  /// Turns this entity to face the local-space point ([targetX], [targetY],
  /// [targetZ]), keeping world +Y as up.
  ///
  /// "Face" means its **-Z** axis points at the target, because -Z is
  /// forward. That is why a camera parented to nothing and rotated by nothing
  /// looks down -Z.
  ///
  /// Two cases have no single answer and are resolved rather than left to
  /// produce NaN:
  ///
  ///  * The target *is* the entity's own position. There is no direction to
  ///    face, so the rotation is left exactly as it was - fabricating an
  ///    orientation would silently spin something that asked to look at where
  ///    it already is.
  ///  * Straight up or straight down, where the desired forward is parallel
  ///    to +Y and "which way is up" no longer picks a roll. The fallback is
  ///    -Z for looking down and +Z for looking up, both of which leave
  ///    screen-right along +X, so a top-down camera lands the right way up.
  void lookAt(double targetX, double targetY, double targetZ) {
    final t = get<Transform3D>();
    var fx = targetX - t.transformOffsetX[this];
    var fy = targetY - t.transformOffsetY[this];
    var fz = targetZ - t.transformOffsetZ[this];
    final length = math.sqrt(fx * fx + fy * fy + fz * fz);
    if (length == 0) return;
    fx /= length;
    fy /= length;
    fz /= length;

    // The entity's +Z, which is the direction it faces away from.
    final zx = -fx;
    final zy = -fy;
    final zz = -fz;

    // Looking along +-Y makes world up useless as a reference; see the doc
    // above for why the sign is chosen this way.
    final bool parallel = fy.abs() >= _parallelThreshold;
    final double ux = 0;
    final double uy = parallel ? 0 : 1;
    final double uz = parallel ? (fy > 0 ? 1 : -1) : 0;

    // right = up x back, then up = back x right. Both come out unit-length
    // because the two inputs to each cross product are unit and
    // perpendicular.
    var rx = uy * zz - uz * zy;
    var ry = uz * zx - ux * zz;
    var rz = ux * zy - uy * zx;
    final rLength = math.sqrt(rx * rx + ry * ry + rz * rz);
    rx /= rLength;
    ry /= rLength;
    rz /= rLength;
    // Named apart from the [upX]/[upY]/[upZ] getters, which read the columns
    // this call is about to write.
    final axisUpX = zy * rz - zz * ry;
    final axisUpY = zz * rx - zx * rz;
    final axisUpZ = zx * ry - zy * rx;

    _writeBasis(t, this, rx, ry, rz, axisUpX, axisUpY, axisUpZ, zx, zy, zz);
  }

  /// [lookAt], sugar for facing [target]'s own local-space offset.
  void lookAtEntity(Entity target) {
    final tt = target.get<Transform3D>();
    lookAt(
      tt.transformOffsetX[target],
      tt.transformOffsetY[target],
      tt.transformOffsetZ[target],
    );
  }

  /// The unit direction the current local rotation faces: this entity's own
  /// -Z axis, in the space its offsets are measured in.
  ///
  /// Three scalar getters rather than one returning a vector, matching this
  /// codebase's standing zero-allocation-per-tick stance.
  double get forwardX {
    final t = get<Transform3D>();
    return -2 *
        (t.transformRotationX[this] * t.transformRotationZ[this] +
            t.transformRotationW[this] * t.transformRotationY[this]);
  }

  double get forwardY {
    final t = get<Transform3D>();
    return -2 *
        (t.transformRotationY[this] * t.transformRotationZ[this] -
            t.transformRotationW[this] * t.transformRotationX[this]);
  }

  double get forwardZ {
    final t = get<Transform3D>();
    final x = t.transformRotationX[this];
    final y = t.transformRotationY[this];
    return -(1 - 2 * (x * x + y * y));
  }

  /// The unit direction of this entity's own +X axis - to its right when
  /// facing [forwardX]/[forwardY]/[forwardZ].
  double get rightX {
    final t = get<Transform3D>();
    final y = t.transformRotationY[this];
    final z = t.transformRotationZ[this];
    return 1 - 2 * (y * y + z * z);
  }

  double get rightY {
    final t = get<Transform3D>();
    return 2 *
        (t.transformRotationX[this] * t.transformRotationY[this] +
            t.transformRotationW[this] * t.transformRotationZ[this]);
  }

  double get rightZ {
    final t = get<Transform3D>();
    return 2 *
        (t.transformRotationX[this] * t.transformRotationZ[this] -
            t.transformRotationW[this] * t.transformRotationY[this]);
  }

  /// The unit direction of this entity's own +Y axis - its up, which is world
  /// +Y only while it is unrolled and unpitched.
  double get upX {
    final t = get<Transform3D>();
    return 2 *
        (t.transformRotationX[this] * t.transformRotationY[this] -
            t.transformRotationW[this] * t.transformRotationZ[this]);
  }

  double get upY {
    final t = get<Transform3D>();
    final x = t.transformRotationX[this];
    final z = t.transformRotationZ[this];
    return 1 - 2 * (x * x + z * z);
  }

  double get upZ {
    final t = get<Transform3D>();
    return 2 *
        (t.transformRotationY[this] * t.transformRotationZ[this] +
            t.transformRotationW[this] * t.transformRotationX[this]);
  }
}

/// How close to straight up or down [Transform3DAccessor.lookAt] treats as parallel
/// to world up, as `|sin(pitch)|`. Below this the cross product with world up
/// is well-conditioned; at it, the result is numerical noise, and a
/// normalized noise vector is a random roll.
const double _parallelThreshold = 0.999999;

/// The same corner seen from the quaternion side, for [Transform3DAccessor.yaw] and
/// [Transform3DAccessor.roll]. Slightly looser than [_parallelThreshold]: those two
/// divide nothing, so the only thing at stake is which of two equivalent
/// spellings comes back.
const double _gimbalThreshold = 0.9999995;

double _clampUnit(double value) => value < -1
    ? -1
    : value > 1
    ? 1
    : value;

/// Writes the quaternion for the orthonormal basis whose columns are the
/// three axes given, into [t]'s rotation columns for [entity].
///
/// Shepperd's method: pick whichever of the four components is largest and
/// derive the other three from it, rather than always taking the one the
/// trace gives. The obvious single-formula version divides by something that
/// goes to zero for a half-turn, which is not an exotic rotation - it is
/// "facing the other way".
void _writeBasis(
  Transform3D t,
  Entity entity,
  double xAxisX,
  double xAxisY,
  double xAxisZ,
  double yAxisX,
  double yAxisY,
  double yAxisZ,
  double zAxisX,
  double zAxisY,
  double zAxisZ,
) {
  final trace = xAxisX + yAxisY + zAxisZ;
  double x, y, z, w;
  if (trace > 0) {
    final s = math.sqrt(trace + 1) * 2;
    w = 0.25 * s;
    x = (yAxisZ - zAxisY) / s;
    y = (zAxisX - xAxisZ) / s;
    z = (xAxisY - yAxisX) / s;
  } else if (xAxisX > yAxisY && xAxisX > zAxisZ) {
    final s = math.sqrt(1 + xAxisX - yAxisY - zAxisZ) * 2;
    w = (yAxisZ - zAxisY) / s;
    x = 0.25 * s;
    y = (yAxisX + xAxisY) / s;
    z = (zAxisX + xAxisZ) / s;
  } else if (yAxisY > zAxisZ) {
    final s = math.sqrt(1 + yAxisY - xAxisX - zAxisZ) * 2;
    w = (zAxisX - xAxisZ) / s;
    x = (yAxisX + xAxisY) / s;
    y = 0.25 * s;
    z = (zAxisY + yAxisZ) / s;
  } else {
    final s = math.sqrt(1 + zAxisZ - xAxisX - yAxisY) * 2;
    w = (xAxisY - yAxisX) / s;
    x = (zAxisX + xAxisZ) / s;
    y = (zAxisY + yAxisZ) / s;
    z = 0.25 * s;
  }
  t.transformRotationX[entity] = x;
  t.transformRotationY[entity] = y;
  t.transformRotationZ[entity] = z;
  t.transformRotationW[entity] = w;
}
