#include "goo_threads.h"

#include <stdlib.h>
#include <string.h>

#if defined( _WIN32 )
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#else
#include <pthread.h>
#include <sched.h>
#endif

// Tasks that may be in flight at once. Box2D's worst case in one step is a
// solver task per worker plus the tree/sensor/bullet tasks that overlap them.
#define GOO_MAX_TASKS 128

typedef void b2TaskFn( int startIndex, int endIndex, uint32_t workerIndex, void* taskContext );

typedef struct GooTask
{
	// Slices not yet finished. The task is complete at zero. Only ever
	// decremented by workers and only ever read by the thread in finish.
	volatile long remaining;
	// Owned by the dispatching thread alone - Box2D enqueues from one thread.
	int32_t inUse;
} GooTask;

typedef struct GooWorker
{
	int32_t index;
	b2TaskFn* fn;
	void* context;
	int32_t start;
	int32_t end;
	GooTask* owner;

	// 0 = idle. Claimed with a compare-and-swap by the dispatcher, cleared by
	// the worker once its slice has finished *and* been counted.
	volatile long busy;
	volatile long running;

#if defined( _WIN32 )
	HANDLE thread;
	HANDLE wake;
#else
	pthread_t thread;
	pthread_mutex_t mutex;
	pthread_cond_t cond;
	volatile long signalled;
#endif
} GooWorker;

struct GooThreadPool
{
	int32_t workerCount;
	GooWorker* workers;
	GooTask tasks[GOO_MAX_TASKS];
	// Scratch for the dispatcher's idle-worker pass, so enqueue allocates
	// nothing on a path Box2D takes many times per step.
	GooWorker** idle;
};

// --- portable primitives -----------------------------------------------------

static long gooCas( volatile long* value, long expected, long desired )
{
#if defined( _WIN32 )
	return InterlockedCompareExchange( value, desired, expected );
#else
	return __sync_val_compare_and_swap( value, expected, desired );
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

static void gooStore( volatile long* value, long desired )
{
#if defined( _WIN32 )
	InterlockedExchange( value, desired );
#else
	__sync_lock_test_and_set( value, desired );
#endif
}

static void gooWake( GooWorker* worker )
{
#if defined( _WIN32 )
	SetEvent( worker->wake );
#else
	pthread_mutex_lock( &worker->mutex );
	worker->signalled = 1;
	pthread_cond_signal( &worker->cond );
	pthread_mutex_unlock( &worker->mutex );
#endif
}

static void gooSleepUntilWoken( GooWorker* worker )
{
#if defined( _WIN32 )
	WaitForSingleObject( worker->wake, INFINITE );
#else
	pthread_mutex_lock( &worker->mutex );
	while ( worker->signalled == 0 )
	{
		pthread_cond_wait( &worker->cond, &worker->mutex );
	}
	worker->signalled = 0;
	pthread_mutex_unlock( &worker->mutex );
#endif
}

static void gooYield( void )
{
#if defined( _WIN32 )
	SwitchToThread();
#else
	sched_yield();
#endif
}

// --- the worker loop ---------------------------------------------------------

#if defined( _WIN32 )
static DWORD WINAPI gooWorkerMain( LPVOID argument )
#else
static void* gooWorkerMain( void* argument )
#endif
{
	GooWorker* worker = (GooWorker*)argument;
	for ( ;; )
	{
		gooSleepUntilWoken( worker );
		if ( worker->running == 0 )
		{
			break;
		}
		if ( worker->busy == 0 )
		{
			continue;
		}

		worker->fn( worker->start, worker->end, (uint32_t)worker->index, worker->context );

		// Count the slice done BEFORE releasing the worker. A dispatcher that
		// saw `busy == 0` first could hand this worker a new slice and, in
		// doing so, reuse a task slot whose count had not yet reached zero.
		gooDecrement( &worker->owner->remaining );
		gooStore( &worker->busy, 0 );
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
	// **A thread per worker, not workerCount - 1.** The calling thread never
	// executes a slice (see the header's property 4), so it is not one of the
	// workers - it only dispatches and waits.
	pool->workers = (GooWorker*)calloc( (size_t)workerCount, sizeof( GooWorker ) );
	pool->idle = (GooWorker**)calloc( (size_t)workerCount, sizeof( GooWorker* ) );
	if ( pool->workers == NULL || pool->idle == NULL )
	{
		free( pool->workers );
		free( pool->idle );
		free( pool );
		return NULL;
	}

	for ( int32_t i = 0; i < workerCount; ++i )
	{
		GooWorker* worker = pool->workers + i;
		worker->index = i;
		worker->running = 1;
		worker->busy = 0;
#if defined( _WIN32 )
		worker->wake = CreateEvent( NULL, FALSE, FALSE, NULL );
		worker->thread = CreateThread( NULL, 0, gooWorkerMain, worker, 0, NULL );
#else
		pthread_mutex_init( &worker->mutex, NULL );
		pthread_cond_init( &worker->cond, NULL );
		worker->signalled = 0;
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
	for ( int32_t i = 0; i < pool->workerCount; ++i )
	{
		gooStore( &pool->workers[i].running, 0 );
		gooWake( pool->workers + i );
	}
	for ( int32_t i = 0; i < pool->workerCount; ++i )
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
	free( pool->idle );
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

	// How many slices the work is worth, honouring Box2D's minRange hint so a
	// tiny parallel-for does not pay a wake-up per item.
	int32_t wanted = pool->workerCount;
	if ( minRange > 0 )
	{
		const int32_t cap = itemCount / minRange;
		if ( wanted > cap )
		{
			wanted = cap;
		}
	}
	if ( wanted > itemCount )
	{
		wanted = itemCount;
	}
	if ( wanted < 1 )
	{
		wanted = 1;
	}

	// Claim idle workers up front, so the split is over threads that are
	// certainly available. Only this thread dispatches, so a worker counted
	// idle here cannot be taken by anyone else; one that finishes meanwhile
	// simply is not used this time.
	int32_t claimed = 0;
	for ( int32_t i = 0; i < pool->workerCount && claimed < wanted; ++i )
	{
		GooWorker* worker = pool->workers + i;
		if ( gooCas( &worker->busy, 0, 1 ) == 0 )
		{
			pool->idle[claimed++] = worker;
		}
	}

	if ( claimed == 0 )
	{
		// Every thread is occupied. Running inline is correct for a
		// parallel-for and is the one case that is NOT correct for a solver
		// task. The pool holds a thread per worker so the solver's
		// simultaneous enqueues always find one, keeping this path off it.
		fn( 0, itemCount, 0, taskContext );
		return NULL;
	}

	GooTask* task = gooClaimTask( pool );
	if ( task == NULL )
	{
		for ( int32_t i = 0; i < claimed; ++i )
		{
			gooStore( &pool->idle[i]->busy, 0 );
		}
		fn( 0, itemCount, 0, taskContext );
		return NULL;
	}

	// **Set the count before waking anyone.** A worker that finished while
	// the rest were still being handed out could otherwise drive `remaining`
	// to zero early and let finish return over live slices.
	task->remaining = claimed;

	const int32_t per = itemCount / claimed;
	int32_t start = 0;
	for ( int32_t i = 0; i < claimed; ++i )
	{
		GooWorker* worker = pool->idle[i];
		// The last slice takes the remainder, so nothing is left over and no
		// slice has to run on the calling thread.
		const int32_t end = ( i == claimed - 1 ) ? itemCount : start + per;
		worker->fn = fn;
		worker->context = taskContext;
		worker->start = start;
		worker->end = end;
		worker->owner = task;
		gooWake( worker );
		start = end;
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
	// Spinning instead of blocking: these waits are microseconds inside a
	// step, and a condition variable per finish costs more than it saves.
	while ( task->remaining > 0 )
	{
		gooYield();
	}
	task->inUse = 0;
}
