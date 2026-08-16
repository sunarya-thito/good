// The goo2d Box2D shim: a flat, primitives-only C surface over Box2D v3.
//
// WHY THIS EXISTS. Box2D's own C API passes small structs *by value* -
// b2Vec2, b2Rot, b2BodyId, b2Transform, b2WorldDef and friends. ffigen maps
// each of those to a Dart `Struct`, which is a heap object, so binding
// Box2D directly would allocate on every call on the hottest path in the
// engine. That is the cost this codebase already measured and removed once
// (a `Pointer` field cost 14.63ns/access against 2.25ns for a plain `int`),
// and RULES.md rule 1 forbids re-introducing it.
//
// So every parameter and return below is `int64_t`, `int32_t`, `uint64_t`,
// `float`, or a pointer to an array of those. Nothing here maps to a Dart
// Struct, so no call through this header allocates.
//
// HANDLES. Box2D ids are packed into integers by Box2D's OWN
// b2StoreBodyId/b2LoadBodyId helpers (id.h), not by arithmetic written
// here - the packing is stated once, upstream, and this shim just calls it.
// A zero handle is null, which is Box2D's own convention too, so the Dart
// side's `hasInt64` field defaulting to 0 already means "no body yet".
//
// FLOAT, NOT DOUBLE. Box2D v3 is single-precision throughout (b2Vec2 is
// two floats). Taking doubles here would widen at the boundary and narrow
// again immediately inside, adding a rounding step and doubling the bytes
// moved by the bulk calls for no precision that Box2D can actually keep.
// The Dart side fills a Float32List instead, which puts the single
// narrowing where the renderer already puts its own (see the float32 quad
// corners in render_2d.dart).
//
// ANGLES, NOT ROTORS. Box2D stores rotation as a (cos, sin) pair (b2Rot).
// This shim takes and returns plain radians and converts with Box2D's
// b2MakeRot/b2Rot_GetAngle, because the engine's Transform2D stores a
// single `transformRotation` double and a two-field rotor would have to be
// derived and re-normalised on both sides.
//
// NO userData, DELIBERATELY. The obvious way to get from a contact event
// back to a goo2d Entity is to stash the packed Entity in Box2D's
// per-shape `void* userData`. That is a 64-bit truncation bug waiting on
// 32-bit Android (armeabi-v7a is still in Flutter's default ABI set):
// `void*` is 4 bytes there, an Entity packs 16 archetype + 16 page + 32 row
// = all 64. So no userData crosses this boundary at all. Instead the Dart
// side keeps an Int64List of Entities indexed by the shape handle's OWN
// dense slot - `index1`, the high 32 bits of the packed id (see
// b2StoreShapeId in id.h). Box2D's id pool keeps that index dense and
// reuses it, which is exactly the property an index into a flat list wants,
// and the lookup is one indexed read with no map, no hash, and no
// allocation. Dart can extract it with a shift, so it costs no call here.

#ifndef GOO_BOX2D_H
#define GOO_BOX2D_H

#include <stdint.h>

#if defined( _WIN32 )
#define GOO_API __declspec( dllexport )
#else
#define GOO_API __attribute__( ( visibility( "default" ) ) )
#endif

#ifdef __cplusplus
extern "C"
{
#endif

	// --- sanity ------------------------------------------------------------

	/// Box2D's version, packed as (major << 16) | (minor << 8) | revision.
	/// The Dart loader asserts against this so a stale prebuilt library on
	/// the library search path fails loudly at boot instead of subtly at
	/// the first step.
	GOO_API int32_t gooB2Version( void );

	// --- world -------------------------------------------------------------

	/// Creates a world with the given gravity. Returns a packed world
	/// handle, or 0 on failure.
	GOO_API int64_t gooWorldCreate( float gravityX, float gravityY );

	/// A world that steps across [workerCount] threads.
	///
	/// Box2D does not create threads; this hands it a pool that does, through
	/// `enqueueTask`/`finishTask`. A [workerCount] of 1 or less is exactly
	/// [gooWorldCreate] - no pool, no threads, no behavioural difference.
	///
	/// **The pool belongs to the world and is destroyed with it**, so a caller
	/// has one lifetime to think about rather than two. That is why this is a
	/// separate constructor instead of a setter: a world cannot change its
	/// worker count, and a pool cannot outlive its world.
	///
	/// Box2D warns that only performance cores help - efficiency cores and
	/// hyper-threading "provide little benefit and may even harm performance"
	/// - so more workers than physical cores is usually slower, not faster.
	GOO_API int64_t gooWorldCreateThreaded( float gravityX, float gravityY, int32_t workerCount );

	/// How many workers [world] was created with; 1 for a single-threaded one.
	GOO_API int32_t gooWorldWorkerCount( int64_t world );

	GOO_API void gooWorldDestroy( int64_t world );

	/// Advances the world by `timeStep` seconds. `subStepCount` is Box2D's
	/// solver iteration count; 4 is its own recommended default.
	GOO_API void gooWorldStep( int64_t world, float timeStep, int32_t subStepCount );

	// --- bodies ------------------------------------------------------------

	/// `type` is 0 static, 1 kinematic, 2 dynamic - Box2D's own b2BodyType
	/// values, asserted to match in goo_box2d.c so the Dart enum cannot
	/// drift from the C one silently.
	GOO_API int64_t gooBodyCreate( int64_t world, int32_t type, float x, float y, float angle );

	GOO_API void gooBodyDestroy( int64_t body );

	/// Removes the body from simulation without destroying it, keeping its
	/// handle valid. This is how a whole entity's physics goes inert;
	/// disabling one shape of several is gooShapeSetFilter with a zero mask.
	GOO_API void gooBodySetEnabled( int64_t body, int32_t enabled );

	/// Whether the handle still resolves to a live body. Box2D's ids carry
	/// a generation counter, so this correctly reports false for a stale
	/// handle whose slot has been reused - the same problem `Scene` solves
	/// with its own generation field.
	GOO_API int32_t gooBodyIsValid( int64_t body );

	GOO_API void gooBodySetTransform( int64_t body, float x, float y, float angle );

	/// Writes {x, y, angle} into `outXya` (3 floats).
	GOO_API void gooBodyGetTransform( int64_t body, float* outXya );

	GOO_API void gooBodySetLinearVelocity( int64_t body, float vx, float vy );
	GOO_API void gooBodySetAngularVelocity( int64_t body, float w );

	/// Writes {vx, vy, w} into `outVel` (3 floats).
	GOO_API void gooBodyGetVelocity( int64_t body, float* outVel );

	GOO_API void gooBodySetGravityScale( int64_t body, float scale );
	GOO_API void gooBodySetDamping( int64_t body, float linear, float angular );
	GOO_API void gooBodySetFixedRotation( int64_t body, int32_t fixed );
	GOO_API void gooBodySetBullet( int64_t body, int32_t bullet );
	GOO_API void gooBodySetType( int64_t body, int32_t type );

	GOO_API void gooBodyApplyForce( int64_t body, float fx, float fy, int32_t wake );
	GOO_API void gooBodyApplyImpulse( int64_t body, float ix, float iy, int32_t wake );
	GOO_API void gooBodyApplyTorque( int64_t body, float torque, int32_t wake );

	// --- shapes ------------------------------------------------------------
	//
	// One entry point per goo2d ColliderBody subtype. They share a trailing
	// material/filter parameter block rather than a struct, because a struct
	// is exactly what this header exists to avoid.
	//
	// `category` and `mask` are Box2D's b2Filter bits, which are uint64_t in
	// v3.1.1 - wide enough for goo2d's `layer` (a bit index) across all 64
	// layers. `isSensor` maps goo2d's `isTrigger`.

	GOO_API int64_t gooShapeAddCircle( int64_t body, float cx, float cy, float radius, float density,
									   float friction, float restitution, uint64_t category,
									   uint64_t mask, int32_t isSensor );

	GOO_API int64_t gooShapeAddBox( int64_t body, float cx, float cy, float halfWidth,
									float halfHeight, float angle, float density, float friction,
									float restitution, uint64_t category, uint64_t mask,
									int32_t isSensor );

	/// A capsule standing on its y axis, matching goo2d's CapsuleBody:
	/// `halfHeight` is half the TOTAL height, caps included (Unity's
	/// CapsuleCollider2D.size semantics), so the straight section runs
	/// +/- (halfHeight - radius). A capsule shorter than it is wide
	/// degenerates to a circle rather than erroring - the same choice
	/// CapsuleBody.containsLocalPoint already makes.
	GOO_API int64_t gooShapeAddCapsule( int64_t body, float cx, float cy, float radius,
										float halfHeight, float density, float friction,
										float restitution, uint64_t category, uint64_t mask,
										int32_t isSensor );

	/// `pointsXy` is `count` interleaved x,y pairs (2 * count floats) in
	/// body-local space, already offset by the caller. Returns 0 if Box2D's
	/// hull builder rejects the points (fewer than 3, collinear, or beyond
	/// B2_MAX_POLYGON_VERTICES) rather than creating a degenerate shape.
	GOO_API int64_t gooShapeAddPolygon( int64_t body, const float* pointsXy, int32_t count,
										float density, float friction, float restitution,
										uint64_t category, uint64_t mask, int32_t isSensor );

	GOO_API int64_t gooShapeGetBody( int64_t shape );

	GOO_API void gooShapeDestroy( int64_t shape, int32_t updateBodyMass );

	/// Box2D v3 has no per-shape enable flag, so goo2d's
	/// `ColliderBody.enable` is expressed as a filter change: a zero mask
	/// collides with nothing. Dart passes both bits every time rather than
	/// this shim remembering a "real" mask to restore - the authoritative
	/// `layer`/`excludeLayers` already live in component storage, and
	/// caching a second copy here is the drift RULES.md rule 10 describes.
	GOO_API void gooShapeSetFilter( int64_t shape, uint64_t category, uint64_t mask );

	/// Landing 4 needs these on to receive anything from
	/// b2World_GetContactEvents / GetSensorEvents.
	GOO_API void gooShapeEnableContactEvents( int64_t shape, int32_t flag );
	GOO_API void gooShapeEnableSensorEvents( int64_t shape, int32_t flag );

	// --- bulk transfer -----------------------------------------------------
	//
	// The whole reason this shim is worth having. A per-body FFI call would
	// cost 2N calls per tick to push gameplay-authored transforms in and
	// pull simulated ones back out. These do it in two, regardless of N.
	//
	// The buffers are plain caller-owned arrays - this shim deliberately
	// knows NOTHING about goo's memory pool. The pool is bit-packed by
	// DataDescriptor's cursor, so a C struct mirroring a row would be a
	// second copy of that layout which has to agree with data_layout.dart by
	// hand, and RULES.md rule 10 exists precisely to stop that.

	/// Pushes `count` transforms into the world. `bodies` is `count` packed
	/// handles; `xya` is 3 floats per body. A zero or stale handle is
	/// skipped, so a caller need not compact its arrays when an entity dies
	/// mid-tick.
	GOO_API void gooBodiesPushTransforms( const int64_t* bodies, const float* xya, int32_t count );

	/// The reverse: reads `count` transforms out into `outXya` (3 floats
	/// per body). A skipped body leaves its 3 slots untouched, so the
	/// caller's previous values survive rather than becoming zeros.
	GOO_API void gooBodiesPullTransforms( const int64_t* bodies, float* outXya, int32_t count );

	/// Velocities alongside the transforms, same skipping rules, 3 floats
	/// per body ({vx, vy, w}).
	GOO_API void gooBodiesPushVelocities( const int64_t* bodies, const float* vel, int32_t count );
	GOO_API void gooBodiesPullVelocities( const int64_t* bodies, float* outVel, int32_t count );

	// --- contact and sensor events -----------------------------------------
	//
	// This is why Box2D **v3** was chosen over v2. v3 accumulates touch
	// transitions into flat arrays that you poll once after each step
	// (b2World_GetContactEvents / b2World_GetSensorEvents) rather than
	// calling you back mid-solve. Polling suits an FFI boundary; a callback
	// would mean a C function pointer re-entering Dart from inside the
	// solver, on the hot path, with no good answer for what may be touched
	// while Box2D is mid-step.
	//
	// Both drains write fixed-stride records of 3 int64 each:
	//
	//     [ kind, shapeA, shapeB ]
	//
	// so `out` must have room for `3 * maxEvents` int64s. The return value is
	// the number of RECORDS written, not int64s.
	//
	// Only touch transitions are reported - "still touching" is not an event
	// Box2D has, and is maintained on the Dart side from these.

/// `kind` for a pair that has just started touching.
#define GOO_TOUCH_BEGIN 0
/// `kind` for a pair that has just stopped touching.
#define GOO_TOUCH_END 1

	/// Drains this step's contact (non-sensor) touch transitions.
	///
	/// `shapeA`/`shapeB` are packed shape handles. Events beyond `maxEvents`
	/// are **dropped**, and the caller is expected to size its buffer from
	/// the previous tick's return value rather than have this grow one.
	GOO_API int32_t gooWorldDrainContacts( int64_t world, int64_t* out, int32_t maxEvents );

	/// Drains this step's sensor touch transitions. `shapeA` is the sensor,
	/// `shapeB` the visitor - an order Box2D itself guarantees, which is what
	/// lets goo2d report a trigger event without asking which side was which.
	GOO_API int32_t gooWorldDrainSensors( int64_t world, int64_t* out, int32_t maxEvents );

	/// How many contact and sensor records the last step produced, whether or
	/// not they fitted in the buffer. Lets a caller resize *after* a drain
	/// that overflowed rather than guessing up front.
	GOO_API int32_t gooWorldContactEventCount( int64_t world );
	GOO_API int32_t gooWorldSensorEventCount( int64_t world );

	// --- joints ------------------------------------------------------------
	//
	// Anchors are in each body's **local** space, which is Box2D's own
	// convention and the only one that is unambiguous: a world-space anchor
	// only means anything at the instant the joint is created, and a caller
	// who moved a body first would get a joint attached somewhere it did not
	// intend with nothing to indicate it.
	//
	// Flags are int32 0/1 rather than bool - the shim exposes no C `bool`, so
	// nothing here depends on `_Bool` having the same width as Dart expects.
	//
	// A joint is destroyed automatically when either of its bodies is, so a
	// handle held across a body's destruction goes stale; `gooJointIsValid`
	// is how to ask.

	/// Creates a distance joint - two points held a fixed distance apart, with
	/// an optional spring and optional length limits. Ropes, springs,
	/// suspension.
	///
	/// Returns the packed joint handle, or 0 if either body was invalid.
	GOO_API int64_t gooJointCreateDistance( int64_t bodyA, int64_t bodyB, float ax, float ay, float bx,
											float by, float length, int32_t enableSpring, float hertz,
											float dampingRatio, int32_t enableLimit, float minLength,
											float maxLength, int32_t collideConnected );

	/// Creates a revolute joint - two bodies sharing a pivot, with optional
	/// angle limits and an optional motor. Hinges, wheels, ragdoll elbows.
	GOO_API int64_t gooJointCreateRevolute( int64_t bodyA, int64_t bodyB, float ax, float ay, float bx,
											float by, float referenceAngle, int32_t enableLimit,
											float lowerAngle, float upperAngle, int32_t enableMotor,
											float motorSpeed, float maxMotorTorque, int32_t collideConnected );

	GOO_API void gooJointDestroy( int64_t joint );

	/// Whether [joint] still names a live joint. Zero once either of its
	/// bodies has been destroyed, which destroys the joint with it.
	GOO_API int32_t gooJointIsValid( int64_t joint );

	/// Motor control, shared by both joint types above. `speed` is rad/s for a
	/// revolute joint and m/s for a distance one; `maxEffort` is the torque or
	/// force the motor may use to reach it.
	GOO_API void gooJointSetMotor( int64_t joint, int32_t enable, float speed, float maxEffort );

	/// The force this joint is currently applying, in newtons, written as two
	/// floats (x, y) into `outForce`. Returns the torque, in newton-metres.
	///
	/// Together these are what a **breakable** joint is built from: compare
	/// against a threshold each tick and destroy the joint when it is
	/// exceeded. Box2D has no breaking of its own.
	GOO_API float gooJointGetReaction( int64_t joint, float* outForce );

	// --- diagnostics -------------------------------------------------------
	//
	// What the world actually contains, as opposed to how long it took. A step
	// time on its own cannot distinguish "many bodies" from "many bodies that
	// refuse to go to sleep", and those have completely different fixes.

	/// Bodies Box2D is still integrating. A settled pile sleeps, and a sleeping
	/// body costs almost nothing - so this next to the body count is the
	/// difference between a scene that is heavy and one that is agitated.
	GOO_API int32_t gooWorldAwakeBodyCount( int64_t world );

	/// Writes `min(count, GOO_COUNTER_COUNT)` int32 counters into `out`:
	///
	///     [ bodies, shapes, contacts, joints, islands ]
	///
	/// Flattened into a caller's array rather than returned as `b2Counters`,
	/// which is a struct by value - the one thing this shim exists to keep out
	/// of the Dart bindings.
	///
	/// **Contacts here are potential (broad-phase) pairs**, not the touching
	/// pairs the event API reports. A pile whose contact count climbs far
	/// faster than its body count is overlapping, not merely large.
	GOO_API void gooWorldCounters( int64_t world, int32_t* out, int32_t count );

/// How many counters [gooWorldCounters] can write.
#define GOO_COUNTER_COUNT 5

	// --- spatial queries ---------------------------------------------------
	//
	// `category`/`mask` are a b2QueryFilter: the query is treated as if it
	// were a shape in `category`, colliding with `mask`. Passing category 1
	// and mask ~0 queries everything.

	/// Casts a ray from (originX, originY) along (dx, dy) - a *translation*,
	/// not a direction, so its length is the ray's length.
	///
	/// Returns the packed handle of the closest shape hit, or 0 for a miss.
	/// On a hit, writes 5 floats into `outHit`:
	///
	///     [ pointX, pointY, normalX, normalY, fraction ]
	///
	/// Split that way because the handle is an integer and the rest are
	/// floats; one mixed buffer would have to be punned on the Dart side.
	/// `outHit` is untouched on a miss.
	GOO_API int64_t gooWorldCastRayClosest( int64_t world, float originX, float originY, float dx,
											float dy, uint64_t category, uint64_t mask,
											float* outHit );

	/// Collects the shapes whose fat AABB overlaps the given box, writing
	/// packed handles into `outShapes`. Returns how many were written.
	///
	/// This is a **broad-phase** test: an AABB overlap, not an exact shape
	/// overlap. It is what you want for "roughly what is in this region";
	/// callers needing exactness re-test the survivors themselves.
	///
	/// Results beyond `maxShapes` are dropped rather than growing anything.
	GOO_API int32_t gooWorldOverlapAABB( int64_t world, float minX, float minY, float maxX,
										 float maxY, uint64_t category, uint64_t mask,
										 int64_t* outShapes, int32_t maxShapes );

#ifdef __cplusplus
}
#endif

#endif // GOO_BOX2D_H
