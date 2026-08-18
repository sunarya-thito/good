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
