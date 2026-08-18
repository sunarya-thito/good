## 0.1.1

Documentation only. No code changes.

The README now shows a declared collider and effector. The library docs
described the superseded effector API, where you wrote your own system and a
`compareTo` to order it before the solver; declaring `Effector2D` is the
current shape and the physics system handles the ordering.

## 0.1.0

First published release. The ECS-facing 2D physics layer:

* **Bodies and colliders**, declared as components.
* **All nine joints** — distance, motor, mouse, prismatic, revolute, weld,
  wheel and the rest of Unity's 2D set — with `Joint` as a real type, not a
  raw handle.
* **Effectors**, declared alongside the colliders they act on.
* **Raycast and overlap queries.**
* The solver runs across worker threads; the thread count is set on the `Game`.

## 0.0.1

* Package scaffolded. Never published.
