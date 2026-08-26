// A minimal task system for Box2D v3, and the constraints it has to satisfy.
//
// **Opt in, and off by default.** `gooWorldCreate` still makes a
// single-threaded world - byte for byte the behaviour every existing test
// measures - and threading is reached only through `gooWorldCreateThreaded`.
//
// Box2D does not create threads. It calls `enqueueTask`/`finishTask` and
// expects a `workerIndex` in [0, workerCount) to identify who is running.
// Four properties of how it actually calls them drive this design, and
// getting any of them wrong is a hang, not a slowdown:
//
//  1. **Several tasks are in flight at once.** `solver.c` enqueues
//     `workerCount` solver tasks in a loop and only afterwards finishes
//     them. A single-task-at-a-time pool would deadlock there.
//
//  2. **Those solver tasks synchronise with each other.** They are not
//     independent work items - they meet at barriers inside the solver. So a
//     pool that ran them one after another on one thread would wait forever
//     for a peer that has not started. **Serial execution is not a valid
//     fallback for this callback**, which is the opposite of the usual
//     parallel-for assumption.
//
//  3. **The worker index must be distinct and stable per running task.**
//     Box2D indexes per-worker scratch by it, so two concurrent tasks sharing
//     an index corrupt each other's state.
//
//  4. **Enqueue must return without running any of the work.** `solver.c`
//     enqueues *all* `workerCount` solver tasks and only afterwards finishes
//     them. An enqueue that runs a slice inline - the obvious shape, and the
//     first thing written here - blocks the calling thread at a solver
//     barrier waiting for peers that have not been dispatched yet.
//
// The design that satisfies all four: **`workerCount` dedicated threads**, so
// a thread is always free for every task the solver enqueues at once, and a
// dispatch that only ever hands slices to idle threads and returns.
//
// Sizing it at `workerCount - 1` and letting the caller run one slice - the
// usual parallel-for arrangement - is wrong here for property 4.

#ifndef GOO_THREADS_H
#define GOO_THREADS_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Opaque handle to a pool of worker threads.
typedef struct GooThreadPool GooThreadPool;

/// Starts a pool of `workerCount` threads - one per worker, none of them the
/// calling thread, which only dispatches and waits (property 4 above).
/// Returns NULL for a workerCount of 1 or less, meaning "no pool, run
/// serially".
GooThreadPool* gooThreadPoolCreate( int32_t workerCount );

/// Stops every thread and frees the pool. Safe on NULL.
void gooThreadPoolDestroy( GooThreadPool* pool );

/// How many workers this pool runs. 1 for a NULL pool, the serial case.
int32_t gooThreadPoolWorkerCount( const GooThreadPool* pool );

/// The `b2EnqueueTaskCallback` / `b2FinishTaskCallback` pair, matching
/// Box2D's signatures exactly. `userContext` is the pool.
void* gooThreadPoolEnqueue( void* task, int32_t itemCount, int32_t minRange, void* taskContext,
							void* userContext );
void gooThreadPoolFinish( void* userTask, void* userContext );

#ifdef __cplusplus
}
#endif

#endif // GOO_THREADS_H
