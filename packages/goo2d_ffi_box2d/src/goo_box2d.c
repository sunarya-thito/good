// Implementation of the goo2d Box2D shim. See goo_box2d.h for why this
// layer exists at all.
//
// Every function here is a thin translation: unpack integer handles into
// Box2D's id structs, convert radians to/from b2Rot, call Box2D, pack the
// result back. There is no state in this file - no caches, no tables, no
// registries. That is deliberate: anything remembered here would be a
// second copy of something the Dart side already owns, and it would have to
// be kept in step by hand (the one-fact-one-place rule).

#include "goo_box2d.h"
#include "goo_threads.h"

#include "box2d/box2d.h"
#include "box2d/collision.h"
#include "box2d/id.h"
#include "box2d/math_functions.h"
#include "box2d/types.h"

#include <string.h>

// The Dart side sends body types as plain ints. If Box2D ever renumbers
// b2BodyType these fire at compile time, rather than silently turning every
// dynamic body static at runtime - the kind of failure that looks like a
// physics bug and is not one.
_Static_assert( b2_staticBody == 0, "b2_staticBody must be 0" );
_Static_assert( b2_kinematicBody == 1, "b2_kinematicBody must be 1" );
_Static_assert( b2_dynamicBody == 2, "b2_dynamicBody must be 2" );

// goo2d's PolygonBody declares up to 8 points because Box2D caps a convex
// polygon there. If upstream raises the cap, hasPolygonCollider's default
// should be revisited alongside it rather than silently diverging.
_Static_assert( B2_MAX_POLYGON_VERTICES == 8, "goo2d assumes an 8-vertex polygon cap" );

// --- handle helpers ---------------------------------------------------------
//
// b2StoreWorldId packs into 32 bits and the others into 64. Both widen to
// int64_t losslessly; zero stays zero, which is Box2D's own null.

static inline b2WorldId unpackWorld( int64_t h )
{
	return b2LoadWorldId( (uint32_t)h );
}

static inline b2BodyId unpackBody( int64_t h )
{
	return b2LoadBodyId( (uint64_t)h );
}

static inline b2ShapeId unpackShape( int64_t h )
{
	return b2LoadShapeId( (uint64_t)h );
}

// --- sanity -----------------------------------------------------------------

int32_t gooB2Version( void )
{
	b2Version v = b2GetVersion();
	return ( v.major << 16 ) | ( v.minor << 8 ) | ( v.revision & 0xFF );
}

// --- world ------------------------------------------------------------------

// Thread pools, by world index.
//
// **The one piece of state in this file, and it is here on purpose.** The
// header above says the shim remembers nothing, because anything remembered
// would be a second copy of something Dart already owns. A thread pool is not
// that: it is native state with no Dart counterpart, and it has to be owned
// somewhere so `gooWorldDestroy` can shut the threads down. A `b2WorldId`
// carries a dense `index1`, so a flat array is the whole lookup.
//
// 128 is Box2D's own `B2_MAX_WORLDS` (`src/constants.h`), which is why the
// bound is what it is rather than a number picked here.
#define GOO_MAX_WORLDS 128
static GooThreadPool* gooWorldPools[GOO_MAX_WORLDS];

int64_t gooWorldCreate( float gravityX, float gravityY )
{
	return gooWorldCreateThreaded( gravityX, gravityY, 1 );
}

int64_t gooWorldCreateThreaded( float gravityX, float gravityY, int32_t workerCount )
{
	b2WorldDef def = b2DefaultWorldDef();
	def.gravity = ( b2Vec2 ){ gravityX, gravityY };

	// Null below a count of 2 - `gooThreadPoolCreate` says so - and then the
	// world def is left exactly as Box2D's default, which is the promise
	// gooWorldCreate makes.
	GooThreadPool* pool = gooThreadPoolCreate( workerCount );
	if ( pool != NULL )
	{
		def.workerCount = workerCount;
		def.enqueueTask = gooThreadPoolEnqueue;
		def.finishTask = gooThreadPoolFinish;
		def.userTaskContext = pool;
	}

	b2WorldId world = b2CreateWorld( &def );
	if ( pool != NULL )
	{
		if ( world.index1 > 0 && world.index1 < GOO_MAX_WORLDS )
		{
			gooWorldPools[world.index1] = pool;
		}
		else
		{
			// Box2D refused the world, so nothing will ever destroy it.
			gooThreadPoolDestroy( pool );
		}
	}
	return (int64_t)b2StoreWorldId( world );
}

int32_t gooWorldWorkerCount( int64_t world )
{
	if ( world == 0 )
	{
		return 1;
	}
	const uint16_t index = unpackWorld( world ).index1;
	if ( index == 0 || index >= GOO_MAX_WORLDS )
	{
		return 1;
	}
	return gooThreadPoolWorkerCount( gooWorldPools[index] );
}

void gooWorldDestroy( int64_t world )
{
	if ( world == 0 )
	{
		return;
	}
	const b2WorldId id = unpackWorld( world );
	b2DestroyWorld( id );

	// After the world, never before: destroying the pool first would leave
	// Box2D holding enqueue/finish pointers into freed threads if anything in
	// teardown stepped, and joining threads that are mid-task is a hang.
	if ( id.index1 > 0 && id.index1 < GOO_MAX_WORLDS )
	{
		gooThreadPoolDestroy( gooWorldPools[id.index1] );
		gooWorldPools[id.index1] = NULL;
	}
}

void gooWorldStep( int64_t world, float timeStep, int32_t subStepCount )
{
	b2World_Step( unpackWorld( world ), timeStep, subStepCount );
}

// --- bodies -----------------------------------------------------------------

int64_t gooBodyCreate( int64_t world, int32_t type, float x, float y, float angle )
{
	b2BodyDef def = b2DefaultBodyDef();
	def.type = (b2BodyType)type;
	def.position = ( b2Vec2 ){ x, y };
	def.rotation = b2MakeRot( angle );
	b2BodyId body = b2CreateBody( unpackWorld( world ), &def );
	return (int64_t)b2StoreBodyId( body );
}

void gooBodyDestroy( int64_t body )
{
	if ( body == 0 )
	{
		return;
	}
	b2DestroyBody( unpackBody( body ) );
}

void gooBodySetEnabled( int64_t body, int32_t enabled )
{
	if ( enabled )
	{
		b2Body_Enable( unpackBody( body ) );
	}
	else
	{
		b2Body_Disable( unpackBody( body ) );
	}
}

int32_t gooBodyIsValid( int64_t body )
{
	if ( body == 0 )
	{
		return 0;
	}
	return b2Body_IsValid( unpackBody( body ) ) ? 1 : 0;
}

void gooBodySetTransform( int64_t body, float x, float y, float angle )
{
	b2Body_SetTransform( unpackBody( body ), ( b2Vec2 ){ x, y }, b2MakeRot( angle ) );
}

void gooBodyGetTransform( int64_t body, float* outXya )
{
	b2Transform t = b2Body_GetTransform( unpackBody( body ) );
	outXya[0] = t.p.x;
	outXya[1] = t.p.y;
	outXya[2] = b2Rot_GetAngle( t.q );
}

void gooBodySetLinearVelocity( int64_t body, float vx, float vy )
{
	b2Body_SetLinearVelocity( unpackBody( body ), ( b2Vec2 ){ vx, vy } );
}

void gooBodySetAngularVelocity( int64_t body, float w )
{
	b2Body_SetAngularVelocity( unpackBody( body ), w );
}

void gooBodyGetVelocity( int64_t body, float* outVel )
{
	b2BodyId id = unpackBody( body );
	b2Vec2 v = b2Body_GetLinearVelocity( id );
	outVel[0] = v.x;
	outVel[1] = v.y;
	outVel[2] = b2Body_GetAngularVelocity( id );
}

void gooBodySetGravityScale( int64_t body, float scale )
{
	b2Body_SetGravityScale( unpackBody( body ), scale );
}

void gooBodySetDamping( int64_t body, float linear, float angular )
{
	b2BodyId id = unpackBody( body );
	b2Body_SetLinearDamping( id, linear );
	b2Body_SetAngularDamping( id, angular );
}

void gooBodySetFixedRotation( int64_t body, int32_t fixed )
{
	b2Body_SetFixedRotation( unpackBody( body ), fixed != 0 );
}

void gooBodySetBullet( int64_t body, int32_t bullet )
{
	b2Body_SetBullet( unpackBody( body ), bullet != 0 );
}

void gooBodySetType( int64_t body, int32_t type )
{
	b2Body_SetType( unpackBody( body ), (b2BodyType)type );
}

void gooBodyApplyForce( int64_t body, float fx, float fy, int32_t wake )
{
	b2Body_ApplyForceToCenter( unpackBody( body ), ( b2Vec2 ){ fx, fy }, wake != 0 );
}

void gooBodyApplyImpulse( int64_t body, float ix, float iy, int32_t wake )
{
	b2Body_ApplyLinearImpulseToCenter( unpackBody( body ), ( b2Vec2 ){ ix, iy }, wake != 0 );
}

void gooBodyApplyTorque( int64_t body, float torque, int32_t wake )
{
	b2Body_ApplyTorque( unpackBody( body ), torque, wake != 0 );
}

// --- shapes -----------------------------------------------------------------

// The parameter block every has*Collider maps onto. Built locally per call
// so there is no shared mutable state to get stale.
static b2ShapeDef makeShapeDef( float density, float friction, float restitution,
								uint64_t category, uint64_t mask, int32_t isSensor )
{
	b2ShapeDef def = b2DefaultShapeDef();
	def.density = density;
	def.material.friction = friction;
	def.material.restitution = restitution;
	def.filter.categoryBits = category;
	def.filter.maskBits = mask;
	def.isSensor = isSensor != 0;
	// Off by default in Box2D. goo2d's CollisionListener is the whole point
	// of having colliders, so both are enabled up front; a shape that turns
	// out not to need them can be quietened with gooShapeEnable*Events.
	def.enableContactEvents = true;
	def.enableSensorEvents = true;
	return def;
}

int64_t gooShapeAddCircle( int64_t body, float cx, float cy, float radius, float density,
						   float friction, float restitution, uint64_t category, uint64_t mask,
						   int32_t isSensor )
{
	b2ShapeDef def = makeShapeDef( density, friction, restitution, category, mask, isSensor );
	b2Circle circle = { { cx, cy }, radius };
	b2ShapeId shape = b2CreateCircleShape( unpackBody( body ), &def, &circle );
	return (int64_t)b2StoreShapeId( shape );
}

int64_t gooShapeAddBox( int64_t body, float cx, float cy, float halfWidth, float halfHeight,
						float angle, float density, float friction, float restitution,
						uint64_t category, uint64_t mask, int32_t isSensor )
{
	b2ShapeDef def = makeShapeDef( density, friction, restitution, category, mask, isSensor );
	// b2MakeOffsetBox carries the collider's own offset/rotation, so the
	// shape sits where goo2d's ColliderBody says without a second transform.
	b2Polygon box = b2MakeOffsetBox( halfWidth, halfHeight, ( b2Vec2 ){ cx, cy }, b2MakeRot( angle ) );
	b2ShapeId shape = b2CreatePolygonShape( unpackBody( body ), &def, &box );
	return (int64_t)b2StoreShapeId( shape );
}

int64_t gooShapeAddCapsule( int64_t body, float cx, float cy, float radius, float halfHeight,
							float density, float friction, float restitution, uint64_t category,
							uint64_t mask, int32_t isSensor )
{
	b2ShapeDef def = makeShapeDef( density, friction, restitution, category, mask, isSensor );
	// halfHeight is half the TOTAL height including the caps, so the
	// straight section is what is left after removing one radius at each
	// end. A capsule shorter than it is wide has no straight section at
	// all; clamping to zero collapses both cap centres onto the origin,
	// which IS a circle - the same degenerate answer
	// CapsuleBody.containsLocalPoint gives, rather than an error.
	float segment = halfHeight - radius;
	if ( segment < 0.0f )
	{
		segment = 0.0f;
	}
	b2Capsule capsule = { { cx, cy - segment }, { cx, cy + segment }, radius };
	b2ShapeId shape = b2CreateCapsuleShape( unpackBody( body ), &def, &capsule );
	return (int64_t)b2StoreShapeId( shape );
}

int64_t gooShapeAddPolygon( int64_t body, const float* pointsXy, int32_t count, float density,
							float friction, float restitution, uint64_t category, uint64_t mask,
							int32_t isSensor )
{
	if ( count < 3 || count > B2_MAX_POLYGON_VERTICES )
	{
		return 0;
	}

	b2Vec2 points[B2_MAX_POLYGON_VERTICES];
	for ( int32_t i = 0; i < count; ++i )
	{
		points[i].x = pointsXy[2 * i];
		points[i].y = pointsXy[2 * i + 1];
	}

	// b2ComputeHull rejects degenerate input (collinear, coincident, too
	// few) by returning a zero count. Creating a shape from that would make
	// a collider that exists and collides with nothing, which is far harder
	// to diagnose than a null handle at the call site.
	b2Hull hull = b2ComputeHull( points, count );
	if ( hull.count < 3 )
	{
		return 0;
	}

	b2ShapeDef def = makeShapeDef( density, friction, restitution, category, mask, isSensor );
	b2Polygon polygon = b2MakePolygon( &hull, 0.0f );
	b2ShapeId shape = b2CreatePolygonShape( unpackBody( body ), &def, &polygon );
	return (int64_t)b2StoreShapeId( shape );
}

int64_t gooShapeGetBody( int64_t shape )
{
	return (int64_t)b2StoreBodyId( b2Shape_GetBody( unpackShape( shape ) ) );
}

void gooShapeDestroy( int64_t shape, int32_t updateBodyMass )
{
	if ( shape == 0 )
	{
		return;
	}
	b2DestroyShape( unpackShape( shape ), updateBodyMass != 0 );
}

void gooShapeSetFilter( int64_t shape, uint64_t category, uint64_t mask )
{
	b2ShapeId id = unpackShape( shape );
	// Read-modify-write rather than a fresh b2Filter, so groupIndex (which
	// this shim does not expose) keeps whatever it was set to.
	b2Filter filter = b2Shape_GetFilter( id );
	filter.categoryBits = category;
	filter.maskBits = mask;
	b2Shape_SetFilter( id, filter );
}

void gooShapeEnableContactEvents( int64_t shape, int32_t flag )
{
	b2Shape_EnableContactEvents( unpackShape( shape ), flag != 0 );
}

void gooShapeEnableSensorEvents( int64_t shape, int32_t flag )
{
	b2Shape_EnableSensorEvents( unpackShape( shape ), flag != 0 );
}

// --- bulk transfer ----------------------------------------------------------
//
// Two calls per tick instead of 2N. The skip-on-invalid rule in each loop
// is what lets the Dart side keep a stable, sparse array across a tick in
// which entities died, instead of compacting it (and re-deriving which
// slot belongs to which entity) every frame.

void gooBodiesPushTransforms( const int64_t* bodies, const float* xya, int32_t count )
{
	for ( int32_t i = 0; i < count; ++i )
	{
		int64_t h = bodies[i];
		if ( h == 0 )
		{
			continue;
		}
		b2BodyId id = unpackBody( h );
		if ( !b2Body_IsValid( id ) )
		{
			continue;
		}
		const float* p = xya + 3 * i;
		b2Body_SetTransform( id, ( b2Vec2 ){ p[0], p[1] }, b2MakeRot( p[2] ) );
	}
}

void gooBodiesPullTransforms( const int64_t* bodies, float* outXya, int32_t count )
{
	for ( int32_t i = 0; i < count; ++i )
	{
		int64_t h = bodies[i];
		if ( h == 0 )
		{
			continue;
		}
		b2BodyId id = unpackBody( h );
		if ( !b2Body_IsValid( id ) )
		{
			continue;
		}
		b2Transform t = b2Body_GetTransform( id );
		float* p = outXya + 3 * i;
		p[0] = t.p.x;
		p[1] = t.p.y;
		p[2] = b2Rot_GetAngle( t.q );
	}
}

void gooBodiesPushVelocities( const int64_t* bodies, const float* vel, int32_t count )
{
	for ( int32_t i = 0; i < count; ++i )
	{
		int64_t h = bodies[i];
		if ( h == 0 )
		{
			continue;
		}
		b2BodyId id = unpackBody( h );
		if ( !b2Body_IsValid( id ) )
		{
			continue;
		}
		const float* p = vel + 3 * i;
		b2Body_SetLinearVelocity( id, ( b2Vec2 ){ p[0], p[1] } );
		b2Body_SetAngularVelocity( id, p[2] );
	}
}

void gooBodiesPullVelocities( const int64_t* bodies, float* outVel, int32_t count )
{
	for ( int32_t i = 0; i < count; ++i )
	{
		int64_t h = bodies[i];
		if ( h == 0 )
		{
			continue;
		}
		b2BodyId id = unpackBody( h );
		if ( !b2Body_IsValid( id ) )
		{
			continue;
		}
		b2Vec2 v = b2Body_GetLinearVelocity( id );
		float* p = outVel + 3 * i;
		p[0] = v.x;
		p[1] = v.y;
		p[2] = b2Body_GetAngularVelocity( id );
	}
}

// --- contact and sensor events ----------------------------------------------

int32_t gooWorldDrainContacts( int64_t world, int64_t* out, int32_t maxEvents )
{
	b2ContactEvents events = b2World_GetContactEvents( unpackWorld( world ) );

	int32_t written = 0;
	for ( int i = 0; i < events.beginCount && written < maxEvents; ++i, ++written )
	{
		int64_t* record = out + 3 * written;
		record[0] = GOO_TOUCH_BEGIN;
		record[1] = (int64_t)b2StoreShapeId( events.beginEvents[i].shapeIdA );
		record[2] = (int64_t)b2StoreShapeId( events.beginEvents[i].shapeIdB );
	}
	for ( int i = 0; i < events.endCount && written < maxEvents; ++i, ++written )
	{
		int64_t* record = out + 3 * written;
		record[0] = GOO_TOUCH_END;
		record[1] = (int64_t)b2StoreShapeId( events.endEvents[i].shapeIdA );
		record[2] = (int64_t)b2StoreShapeId( events.endEvents[i].shapeIdB );
	}
	// Hit events (b2ContactHitEvent) are deliberately not drained: they carry
	// an impact point and speed and only fire above a threshold, which is a
	// different feature from touch tracking. Adding them here would mean a
	// wider record for every caller to serve a case none of them asked for.
	return written;
}

int32_t gooWorldDrainSensors( int64_t world, int64_t* out, int32_t maxEvents )
{
	b2SensorEvents events = b2World_GetSensorEvents( unpackWorld( world ) );

	int32_t written = 0;
	for ( int i = 0; i < events.beginCount && written < maxEvents; ++i, ++written )
	{
		int64_t* record = out + 3 * written;
		record[0] = GOO_TOUCH_BEGIN;
		record[1] = (int64_t)b2StoreShapeId( events.beginEvents[i].sensorShapeId );
		record[2] = (int64_t)b2StoreShapeId( events.beginEvents[i].visitorShapeId );
	}
	for ( int i = 0; i < events.endCount && written < maxEvents; ++i, ++written )
	{
		int64_t* record = out + 3 * written;
		record[0] = GOO_TOUCH_END;
		record[1] = (int64_t)b2StoreShapeId( events.endEvents[i].sensorShapeId );
		record[2] = (int64_t)b2StoreShapeId( events.endEvents[i].visitorShapeId );
	}
	return written;
}

int32_t gooWorldContactEventCount( int64_t world )
{
	b2ContactEvents events = b2World_GetContactEvents( unpackWorld( world ) );
	return events.beginCount + events.endCount;
}

int32_t gooWorldSensorEventCount( int64_t world )
{
	b2SensorEvents events = b2World_GetSensorEvents( unpackWorld( world ) );
	return events.beginCount + events.endCount;
}

// --- joints -----------------------------------------------------------------

static inline b2JointId unpackJoint( int64_t h )
{
	return b2LoadJointId( (uint64_t)h );
}

/// Both creators need the same two checks, and a joint between a dead body
/// and a live one is a crash rather than a no-op inside Box2D.
static int jointBodiesValid( int64_t bodyA, int64_t bodyB )
{
	if ( bodyA == 0 || bodyB == 0 )
	{
		return 0;
	}
	return b2Body_IsValid( unpackBody( bodyA ) ) && b2Body_IsValid( unpackBody( bodyB ) );
}

int64_t gooJointCreateDistance( int64_t bodyA, int64_t bodyB, float ax, float ay, float bx, float by,
								float length, int32_t enableSpring, float hertz, float dampingRatio,
								int32_t enableLimit, float minLength, float maxLength,
								int32_t collideConnected )
{
	if ( !jointBodiesValid( bodyA, bodyB ) )
	{
		return 0;
	}

	b2BodyId a = unpackBody( bodyA );
	b2DistanceJointDef def = b2DefaultDistanceJointDef();
	def.bodyIdA = a;
	def.bodyIdB = unpackBody( bodyB );
	def.localAnchorA = ( b2Vec2 ){ ax, ay };
	def.localAnchorB = ( b2Vec2 ){ bx, by };
	// **Zero means "keep Box2D's default"** for the three lengths, rather than
	// meaning zero. Box2D asserts a positive length and a positive minLength,
	// and those asserts compile out of a release build - so passing a literal
	// zero through would work in a debug test and quietly produce a degenerate
	// joint in the shipped game. Leaving the default in place is the only
	// reading that cannot do that, and it is what a caller who omitted the
	// argument meant anyway.
	if ( length > 0.0f )
	{
		def.length = length;
	}
	def.enableSpring = enableSpring != 0;
	def.hertz = hertz;
	def.dampingRatio = dampingRatio;
	def.enableLimit = enableLimit != 0;
	if ( minLength > 0.0f )
	{
		def.minLength = minLength;
	}
	if ( maxLength > 0.0f )
	{
		def.maxLength = maxLength;
	}
	def.collideConnected = collideConnected != 0;

	// The world is read back off the body rather than passed in: a body id
	// already names its world, and a separate world argument is a second copy
	// of that fact for a caller to get wrong.
	return (int64_t)b2StoreJointId( b2CreateDistanceJoint( b2Body_GetWorld( a ), &def ) );
}

int64_t gooJointCreateRevolute( int64_t bodyA, int64_t bodyB, float ax, float ay, float bx, float by,
								float referenceAngle, int32_t enableLimit, float lowerAngle,
								float upperAngle, int32_t enableMotor, float motorSpeed,
								float maxMotorTorque, int32_t collideConnected )
{
	if ( !jointBodiesValid( bodyA, bodyB ) )
	{
		return 0;
	}

	b2BodyId a = unpackBody( bodyA );
	b2RevoluteJointDef def = b2DefaultRevoluteJointDef();
	def.bodyIdA = a;
	def.bodyIdB = unpackBody( bodyB );
	def.localAnchorA = ( b2Vec2 ){ ax, ay };
	def.localAnchorB = ( b2Vec2 ){ bx, by };
	def.referenceAngle = referenceAngle;
	def.enableLimit = enableLimit != 0;
	def.lowerAngle = lowerAngle;
	def.upperAngle = upperAngle;
	def.enableMotor = enableMotor != 0;
	def.motorSpeed = motorSpeed;
	def.maxMotorTorque = maxMotorTorque;
	def.collideConnected = collideConnected != 0;

	return (int64_t)b2StoreJointId( b2CreateRevoluteJoint( b2Body_GetWorld( a ), &def ) );
}

int64_t gooJointCreatePrismatic( int64_t bodyA, int64_t bodyB, float ax, float ay, float bx, float by,
								 float axisX, float axisY, float referenceAngle, int32_t enableLimit,
								 float lower, float upper, int32_t enableMotor, float motorSpeed,
								 float maxMotorForce, int32_t collideConnected )
{
	if ( !jointBodiesValid( bodyA, bodyB ) )
	{
		return 0;
	}
	b2BodyId a = unpackBody( bodyA );
	b2PrismaticJointDef def = b2DefaultPrismaticJointDef();
	def.bodyIdA = a;
	def.bodyIdB = unpackBody( bodyB );
	def.localAnchorA = ( b2Vec2 ){ ax, ay };
	def.localAnchorB = ( b2Vec2 ){ bx, by };
	// A zero axis is degenerate and Box2D only catches it with an assert,
	// which is absent from a release build - so it falls back to horizontal
	// rather than producing a joint that behaves differently once shipped.
	def.localAxisA = ( axisX == 0.0f && axisY == 0.0f ) ? ( b2Vec2 ){ 1.0f, 0.0f }
													   : b2Normalize( ( b2Vec2 ){ axisX, axisY } );
	def.referenceAngle = referenceAngle;
	def.enableLimit = enableLimit != 0;
	def.lowerTranslation = lower;
	def.upperTranslation = upper;
	def.enableMotor = enableMotor != 0;
	def.motorSpeed = motorSpeed;
	def.maxMotorForce = maxMotorForce;
	def.collideConnected = collideConnected != 0;
	return (int64_t)b2StoreJointId( b2CreatePrismaticJoint( b2Body_GetWorld( a ), &def ) );
}

int64_t gooJointCreateWeld( int64_t bodyA, int64_t bodyB, float ax, float ay, float bx, float by,
							float referenceAngle, float linearHertz, float linearDampingRatio,
							float angularHertz, float angularDampingRatio, int32_t collideConnected )
{
	if ( !jointBodiesValid( bodyA, bodyB ) )
	{
		return 0;
	}
	b2BodyId a = unpackBody( bodyA );
	b2WeldJointDef def = b2DefaultWeldJointDef();
	def.bodyIdA = a;
	def.bodyIdB = unpackBody( bodyB );
	def.localAnchorA = ( b2Vec2 ){ ax, ay };
	def.localAnchorB = ( b2Vec2 ){ bx, by };
	def.referenceAngle = referenceAngle;
	def.linearHertz = linearHertz;
	def.linearDampingRatio = linearDampingRatio;
	def.angularHertz = angularHertz;
	def.angularDampingRatio = angularDampingRatio;
	def.collideConnected = collideConnected != 0;
	return (int64_t)b2StoreJointId( b2CreateWeldJoint( b2Body_GetWorld( a ), &def ) );
}

int64_t gooJointCreateWheel( int64_t bodyA, int64_t bodyB, float ax, float ay, float bx, float by,
							 float axisX, float axisY, int32_t enableSpring, float hertz,
							 float dampingRatio, int32_t enableLimit, float lower, float upper,
							 int32_t enableMotor, float motorSpeed, float maxMotorTorque,
							 int32_t collideConnected )
{
	if ( !jointBodiesValid( bodyA, bodyB ) )
	{
		return 0;
	}
	b2BodyId a = unpackBody( bodyA );
	b2WheelJointDef def = b2DefaultWheelJointDef();
	def.bodyIdA = a;
	def.bodyIdB = unpackBody( bodyB );
	def.localAnchorA = ( b2Vec2 ){ ax, ay };
	def.localAnchorB = ( b2Vec2 ){ bx, by };
	// Vertical by default: a wheel's suspension travels up and down, and +y
	// is DOWN in goo2d, so this axis points the way the spring compresses.
	def.localAxisA = ( axisX == 0.0f && axisY == 0.0f ) ? ( b2Vec2 ){ 0.0f, 1.0f }
													   : b2Normalize( ( b2Vec2 ){ axisX, axisY } );
	def.enableSpring = enableSpring != 0;
	def.hertz = hertz;
	def.dampingRatio = dampingRatio;
	def.enableLimit = enableLimit != 0;
	def.lowerTranslation = lower;
	def.upperTranslation = upper;
	def.enableMotor = enableMotor != 0;
	def.motorSpeed = motorSpeed;
	def.maxMotorTorque = maxMotorTorque;
	def.collideConnected = collideConnected != 0;
	return (int64_t)b2StoreJointId( b2CreateWheelJoint( b2Body_GetWorld( a ), &def ) );
}

int64_t gooJointCreateMotor( int64_t bodyA, int64_t bodyB, float offsetX, float offsetY,
							 float angularOffset, float maxForce, float maxTorque,
							 float correctionFactor, int32_t collideConnected )
{
	if ( !jointBodiesValid( bodyA, bodyB ) )
	{
		return 0;
	}
	b2BodyId a = unpackBody( bodyA );
	b2MotorJointDef def = b2DefaultMotorJointDef();
	def.bodyIdA = a;
	def.bodyIdB = unpackBody( bodyB );
	def.linearOffset = ( b2Vec2 ){ offsetX, offsetY };
	def.angularOffset = angularOffset;
	def.maxForce = maxForce;
	def.maxTorque = maxTorque;
	if ( correctionFactor > 0.0f )
	{
		def.correctionFactor = correctionFactor;
	}
	def.collideConnected = collideConnected != 0;
	return (int64_t)b2StoreJointId( b2CreateMotorJoint( b2Body_GetWorld( a ), &def ) );
}

int64_t gooJointCreateMouse( int64_t bodyA, int64_t bodyB, float targetX, float targetY, float hertz,
							 float dampingRatio, float maxForce, int32_t collideConnected )
{
	if ( !jointBodiesValid( bodyA, bodyB ) )
	{
		return 0;
	}
	b2BodyId a = unpackBody( bodyA );
	b2BodyId b = unpackBody( bodyB );
	b2MouseJointDef def = b2DefaultMouseJointDef();
	def.bodyIdA = a;
	def.bodyIdB = b;

	// **Created at the body, then aimed at the target - not created at the
	// target.** `b2CreateMouseJoint` anchors whichever point of the body is
	// currently at `def.target` (`mouse_joint.c` computes `anchorB` from
	// `localOriginAnchorB`, and `deltaCenter = center - targetA`), so handing
	// it a distant target means "hold the point 6 m away from your centre at
	// a spot 6 m away" - which is already true. Separation solves to zero and
	// the joint does nothing at all, which is exactly what was measured: with
	// no gravity the body never moved.
	//
	// Box2D's own samples create the joint under the cursor and then drag it,
	// which is the usage this shape is built for. Grabbing the body's centre
	// and setting the real target immediately gives the "pull this body to
	// here" behaviour a caller of this function is asking for.
	def.target = b2Body_GetPosition( b );
	if ( hertz > 0.0f )
	{
		def.hertz = hertz;
	}
	if ( dampingRatio > 0.0f )
	{
		def.dampingRatio = dampingRatio;
	}
	if ( maxForce > 0.0f )
	{
		def.maxForce = maxForce;
	}
	def.collideConnected = collideConnected != 0;

	// Wake the dragged body: a joint cannot move a sleeping one, and neither
	// creating this nor moving its target wakes anything. Box2D's own samples
	// wake on drag for the same reason.
	//
	// **This is correct but is NOT the fix for the open bug below** - waking
	// changed the measured result by nothing at all. See goo_box2d.h.
	b2Body_SetAwake( b, true );

	b2JointId joint = b2CreateMouseJoint( b2Body_GetWorld( a ), &def );
	// Now the real target, which is what makes it pull.
	b2MouseJoint_SetTarget( joint, ( b2Vec2 ){ targetX, targetY } );
	return (int64_t)b2StoreJointId( joint );
}

void gooJointSetMouseTarget( int64_t joint, float x, float y )
{
	if ( joint == 0 )
	{
		return;
	}
	b2JointId id = unpackJoint( joint );
	if ( b2Joint_IsValid( id ) && b2Joint_GetType( id ) == b2_mouseJoint )
	{
		b2MouseJoint_SetTarget( id, ( b2Vec2 ){ x, y } );
		// Same reason as creation - and the same caveat.
		b2Body_SetAwake( b2Joint_GetBodyB( id ), true );
	}
}

void gooJointDestroy( int64_t joint )
{
	if ( joint == 0 )
	{
		return;
	}
	b2JointId id = unpackJoint( joint );
	// Destroying either body destroys its joints, so a handle can already be
	// stale by the time a caller gets here through ordinary teardown.
	if ( b2Joint_IsValid( id ) )
	{
		b2DestroyJoint( id );
	}
}

int32_t gooJointIsValid( int64_t joint )
{
	return joint != 0 && b2Joint_IsValid( unpackJoint( joint ) ) ? 1 : 0;
}

void gooJointSetMotor( int64_t joint, int32_t enable, float speed, float maxEffort )
{
	if ( joint == 0 )
	{
		return;
	}
	b2JointId id = unpackJoint( joint );
	if ( !b2Joint_IsValid( id ) )
	{
		return;
	}

	// Box2D's motor setters are per joint type rather than on the base, so
	// the dispatch has to happen somewhere. Here is the right place: it keeps
	// one Dart-side entry point for "drive this joint", which is what a
	// caller actually wants, instead of exporting six near-identical ones.
	switch ( b2Joint_GetType( id ) )
	{
		case b2_revoluteJoint:
			b2RevoluteJoint_EnableMotor( id, enable != 0 );
			b2RevoluteJoint_SetMotorSpeed( id, speed );
			b2RevoluteJoint_SetMaxMotorTorque( id, maxEffort );
			break;
		case b2_distanceJoint:
			b2DistanceJoint_EnableMotor( id, enable != 0 );
			b2DistanceJoint_SetMotorSpeed( id, speed );
			b2DistanceJoint_SetMaxMotorForce( id, maxEffort );
			break;
		default:
			break;
	}
}

float gooJointGetReaction( int64_t joint, float* outForce )
{
	if ( outForce != NULL )
	{
		outForce[0] = 0.0f;
		outForce[1] = 0.0f;
	}
	if ( joint == 0 )
	{
		return 0.0f;
	}
	b2JointId id = unpackJoint( joint );
	if ( !b2Joint_IsValid( id ) )
	{
		return 0.0f;
	}
	if ( outForce != NULL )
	{
		b2Vec2 f = b2Joint_GetConstraintForce( id );
		outForce[0] = f.x;
		outForce[1] = f.y;
	}
	return b2Joint_GetConstraintTorque( id );
}

// --- diagnostics -------------------------------------------------------------

int32_t gooWorldAwakeBodyCount( int64_t world )
{
	return b2World_GetAwakeBodyCount( unpackWorld( world ) );
}

void gooWorldCounters( int64_t world, int32_t* out, int32_t count )
{
	b2Counters c = b2World_GetCounters( unpackWorld( world ) );
	const int32_t values[GOO_COUNTER_COUNT] = {
		c.bodyCount, c.shapeCount, c.contactCount, c.jointCount, c.islandCount,
	};
	int32_t n = count < GOO_COUNTER_COUNT ? count : GOO_COUNTER_COUNT;
	for ( int32_t i = 0; i < n; ++i )
	{
		out[i] = values[i];
	}
}

// --- spatial queries --------------------------------------------------------

int64_t gooWorldCastRayClosest( int64_t world, float originX, float originY, float dx, float dy,
								uint64_t category, uint64_t mask, float* outHit )
{
	b2QueryFilter filter = { category, mask };
	b2RayResult result = b2World_CastRayClosest( unpackWorld( world ), ( b2Vec2 ){ originX, originY },
												 ( b2Vec2 ){ dx, dy }, filter );
	if ( result.hit == false )
	{
		return 0;
	}

	outHit[0] = result.point.x;
	outHit[1] = result.point.y;
	outHit[2] = result.normal.x;
	outHit[3] = result.normal.y;
	outHit[4] = result.fraction;
	return (int64_t)b2StoreShapeId( result.shapeId );
}

// Per-call collection state for the overlap callback. A local passed through
// b2World_OverlapAABB's own `context` parameter - not a cache, and nothing
// survives the call, so the "no state in this file" rule still holds.
struct gooOverlapContext
{
	int64_t* out;
	int32_t max;
	int32_t count;
};

static bool gooOverlapCallback( b2ShapeId shapeId, void* context )
{
	struct gooOverlapContext* ctx = context;
	if ( ctx->count >= ctx->max )
	{
		// Returning false stops the query, which is the right answer once
		// the caller's buffer is full - continuing would visit every
		// remaining shape only to discard it.
		return false;
	}
	ctx->out[ctx->count++] = (int64_t)b2StoreShapeId( shapeId );
	return true;
}

int32_t gooWorldOverlapAABB( int64_t world, float minX, float minY, float maxX, float maxY,
							 uint64_t category, uint64_t mask, int64_t* outShapes,
							 int32_t maxShapes )
{
	b2QueryFilter filter = { category, mask };
	b2AABB aabb = { { minX, minY }, { maxX, maxY } };
	struct gooOverlapContext ctx = { outShapes, maxShapes, 0 };
	b2World_OverlapAABB( unpackWorld( world ), aabb, filter, gooOverlapCallback, &ctx );
	return ctx.count;
}
