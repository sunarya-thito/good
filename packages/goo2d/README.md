# goo2d

2D specialization on top of the [`goo`](../goo) kernel: `Transform2D` and
anything else inherently 2D. Rendering (`GameView`, `DrawCanvas2D`,
`GameRenderer2D`) and Box2D physics live in sibling packages
(`goo2d_render`, `goo2d_physics_box2d`) so this package stays free of a
Flutter dependency.

Status: API proposal, actively being implemented. See the project root plan
for the phased roadmap.
