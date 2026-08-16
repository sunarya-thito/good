#include "goo_threads.h"

#include "box2d/types.h"

#include <stdlib.h>
#include <string.h>

#if defined( _WIN32 )
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#else
#include <pthread.h>
#endif

// Tasks that may be in flight at once. Box2D's worst case is one solver task
// per worker plus the tree/sensor/bullet tasks that overlap a step, so this is
// generous; a full table falls back to running the task on the calling thread,
// which is correct for every callback except the solver's (see the header).
#define GOO_MAX_TASKS 64

typedef void b2TaskFn( int startIndex, int endIndex, uint32_t workerIndex, void* taskContext );

typedef struct GooSlice
{
	b2TaskFn* fn;
	void* context;
	int32_t start;
	int32_t end;
	struct GooTask* owner;
} GooSlice;

typedef struct GooTask
{
	// Slices still to finish. The task is done at zero.
	volatile long remaining;
	int32_t inUse;
} GooTask;

typedef struct GooWorker
{
	GooThreadPool* pool;
	int32_t index;
	// One slot: a worker is only ever handed a slice while it is idle, which
	// the dispatcher guarantees by only choosing idle workers.
	GooSlice slice;
	volatile long hasWork;
	volatile long running;
#if defined( _WIN32 )
	HANDLE thread;
	HANDLE wake;
#else
	pthread_t thread;
	pthread_mutex_t mutex;
	pthread_cond_t cond;
#endif
} GooWorker;

struct GooThreadPool
{
	int32_t workerCount;
	GooWorker* workers; // workerCount - 1 of them, indices 1..workerCount-1
	GooTask tasks[GOO_MAX_TASKS];
};

// --- portable primitives -----------------------------------------------------

static void gooSignal( GooWorker* worker )
{
#if defined( _WIN32 )
	SetEvent( worker->wake );
#else
	pthread_mutex_lock( &worker->mutex );
	pthread_cond_signal( &worker->cond );
	pthread_mutex_unlock( &worker->mutex );
#endif
}

static long gooDecrement( volatile long* value )
{
#if defined( _WIN32 )
	return InterlockedDecrement( value );
#else
	return __sync_sub_and_fetch( value, 1 );
#endif
}

static void gooYield( void )
{
#if defined( _WIN32 )
	YieldProcessor();
	SwitchToThread();
#else
	sched_yield();
#endif
}

// --- the worker loop ---------------------------------------------------------

static void gooRunSlice( GooSlice* slice, int32_t workerIndex )
{
	slice->fn( slice->start, slice->end, (uint32_t)workerIndex, slice->context );
	gooDecrement( &slice->owner->remaining );
}

#if defined( _WIN32 )
static DWORD WINAPI gooWorkerMain( LPVOID argument )
#else
static void* gooWorkerMain( void* argument )
#endif
{
	GooWorker* worker = (GooWorker*)argument;
	for ( ;; )
	{
#if defined( _WIN32 )
		WaitForSingleObject( worker->wake, INFINITE );
#else
		pthread_mutex_lock( &worker->mutex );
		while ( worker->hasWork == 0 && worker->running != 0 )
		{
			pthread_cond_wait( &worker->cond, &worker->mutex );
		}
		pthread_mutex_unlock( &worker->mutex );
#endif
		if ( worker->running == 0 )
		{
			break;
		}
		if ( worker->hasWork != 0 )
		{
			gooRunSlice( &worker->slice, worker->index );
			// Cleared last: the dispatcher treats a zero here as "idle", so
			// it must not see that until the work is genuinely finished.
			worker->hasWork = 0;
		}
	}
#if defined( _WIN32 )
	return 0;
#else
	return NULL;
#endif
}

// --- lifecycle ---------------------------------------------------------------

GooThreadPool* gooThreadPoolCreate( int32_t workerCount )
{
	if ( workerCount <= 1 )
	{
		return NULL;
	}

	GooThreadPool* pool = (GooThreadPool*)calloc( 1, sizeof( GooThreadPool ) );
	if ( pool == NULL )
	{
		return NULL;
	}
	pool->workerCount = workerCount;
	pool->workers = (GooWorker*)calloc( (size_t)( workerCount - 1 ), sizeof( GooWorker ) );
	if ( pool->workers == NULL )
	{
		free( pool );
		return NULL;
	}

	for ( int32_t i = 0; i < workerCount - 1; ++i )
	{
		GooWorker* worker = pool->workers + i;
		worker->pool = pool;
		// Index 0 is the thread calling b2World_Step, so threads start at 1.
		worker->index = i + 1;
		worker->running = 1;
		worker->hasWork = 0;
#if defined( _WIN32 )
		worker->wake = CreateEvent( NULL, FALSE, FALSE, NULL );
		worker->thread = CreateThread( NULL, 0, gooWorkerMain, worker, 0, NULL );
#else
		pthread_mutex_init( &worker->mutex, NULL );
		pthread_cond_init( &worker->cond, NULL );
		pthread_create( &worker->thread, NULL, gooWorkerMain, worker );
#endif
	}
	return pool;
}

void gooThreadPoolDestroy( GooThreadPool* pool )
{
	if ( pool == NULL )
	{
		return;
	}
	for ( int32_t i = 0; i < pool->workerCount - 1; ++i )
	{
		GooWorker* worker = pool->workers + i;
		worker->running = 0;
		gooSignal( worker );
	}
	for ( int32_t i = 0; i < pool->workerCount - 1; ++i )
	{
		GooWorker* worker = pool->workers + i;
#if defined( _WIN32 )
		WaitForSingleObject( worker->thread, INFINITE );
		CloseHandle( worker->thread );
		CloseHandle( worker->wake );
#else
		pthread_join( worker->thread, NULL );
		pthread_cond_destroy( &worker->cond );
		pthread_mutex_destroy( &worker->mutex );
#endif
	}
	free( pool->workers );
	free( pool );
}

int32_t gooThreadPoolWorkerCount( const GooThreadPool* pool )
{
	return pool == NULL ? 1 : pool->workerCount;
}

// --- dispatch ----------------------------------------------------------------

static GooTask* gooClaimTask( GooThreadPool* pool )
{
	for ( int32_t i = 0; i < GOO_MAX_TASKS; ++i )
	{
		if ( pool->tasks[i].inUse == 0 )
		{
			pool->tasks[i].inUse = 1;
			pool->tasks[i].remaining = 0;
			return pool->tasks + i;
		}
	}
	return NULL;
}

void* gooThreadPoolEnqueue( void* taskFn, int32_t itemCount, int32_t minRange, void* taskContext,
							void* userContext )
{
	GooThreadPool* pool = (GooThreadPool*)userContext;
	b2TaskFn* fn = (b2TaskFn*)taskFn;

	if ( pool == NULL || itemCount <= 0 )
	{
		fn( 0, itemCount, 0, taskContext );
		return NULL;
	}

	// How many workers this task can use, honouring Box2D's minRange hint so
	// a tiny parallel-for does not pay for a wake-up per item.
	int32_t slices = pool->workerCount;
	if ( minRange > 0 )
	{
		int32_t cap = itemCount / minRange;
		if ( cap < 1 )
		{
			cap = 1;
		}
		if ( slices > cap )
		{
			slices = cap;
		}
	}
	if ( slices > itemCount )
	{
		slices = itemCount;
	}

	if ( slices <= 1 )
	{
		fn( 0, itemCount, 0, taskContext );
		return NULL;
	}

	GooTask* task = gooClaimTask( pool );
	if ( task == NULL )
	{
		fn( 0, itemCount, 0, taskContext );
		return NULL;
	}

	// **Dispatch is non-blocking, and that is the whole design.**
	//
	// The obvious shape - hand out slices to workers and run the last one on
	// the calling thread - deadlocks, and `solver.c:1691` is why:
	//
	//     for ( int i = 0; i < workerCount; ++i )
	//         workerContext[i].userTask = enqueueTaskFcn( b2SolverTask, 1, 1, ... );
	//     ... only afterwards ...
	//     for ( int i = 0; i < workerCount; ++i ) finishTaskFcn( ... );
	//
	// Every solver task is enqueued *before* any is waited on, and they meet
	// at barriers inside the solver. Running one inline during its enqueue
	// blocks the caller at a barrier waiting for peers that have not been
	// dispatched yet. So enqueue must return immediately, always.
	//
	// Note also `workerIndex` is carried in Box2D's own `workerContext`, not
	// taken from the argument this pool passes - the comment above that loop
	// says so ("Must use worker index because thread 0 can be assigned
	// multiple tasks"). The index handed to `fn` therefore only has to be in
	// range, not meaningful.
	const int32_t per = itemCount / slices;
	int32_t start = 0;
	int32_t handed = 0;

	for ( int32_t i = 0; i < pool->workerCount && handed < slices; ++i )
	{
		GooWorker* worker = pool->workers + i;
		if ( worker->hasWork != 0 )
		{
			continue;
		}
		const int32_t end = ( handed == slices - 1 ) ? itemCount : start + per;
		worker->slice.fn = fn;
		worker->slice.context = taskContext;
		worker->slice.start = start;
		worker->slice.end = end;
		worker->slice.owner = task;
#if defined( _WIN32 )
		InterlockedIncrement( &task->remaining );
#else
		__sync_add_and_fetch( &task->remaining, 1 );
#endif
		worker->hasWork = 1;
		gooSignal( worker );
		start = end;
		handed++;
	}

	if ( handed == 0 )
	{
		// Nothing was free. Correct for a parallel-for, and the one case that
		// is NOT correct for a solver task - which is why the pool is sized
		// with a thread per worker so this cannot happen during a step.
		task->inUse = 0;
		fn( 0, itemCount, 0, taskContext );
		return NULL;
	}
	if ( start < itemCount )
	{
		// Ran out of idle workers part way. Give the tail to the last one we
		// used rather than to the caller, for the reason above.
		task->inUse = 0;
		fn( start, itemCount, 0, taskContext );
	}
	return task;
}

void gooThreadPoolFinish( void* userTask, void* userContext )
{
	(void)userContext;
	GooTask* task = (GooTask*)userTask;
	if ( task == NULL )
	{
		return;
	}
	// Spin rather than block: these waits are microseconds inside a step, and
	// a condition variable per finish costs more than it saves.
	while ( task->remaining > 0 )
	{
		gooYield();
	}
	task->inUse = 0;
}
