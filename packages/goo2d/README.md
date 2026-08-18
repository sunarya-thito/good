# goo2d

2D specialization on top of the [`good`](https://pub.dev/packages/good)
kernel, which it re-exports - so a 2D game needs this one dependency and this
one import. Transforms, the camera, sprite rendering (`DrawCanvas2D`,
`GameRenderer2D`), colliders and mouse picking live here. Box2D physics is
opt-in through
[`goo2d_physics_box2d`](https://pub.dev/packages/goo2d_physics_box2d).

Status: **working.** Transforms, world transforms, camera, colliders, sprite
rendering, mouse picking and audio *assets*. There is no audio backend or
mixer yet, and z-ordering beyond the `zIndex` sort is not implemented. The
[implementation status page](https://sunarya-thito.github.io/good/reference/roadmap/) is the honest ledger.

> **Upgrading from 0.0.2?** That version was an entirely different engine.
> Nothing carries over; see the changelog.
