# Flexscript renderer

Import `libs/render.flex` (or the installed named library `render`). This first
backend renders through native Linux OpenGL 4.5 and `libs/gui`. Mesh data, camera
positions, shader source, material parameters and render passes come from the
application. The library imports no Setaworld code or assets.

Run the standalone custom SetaScript material and shadow demo from the repository
root:

```sh
flexscript examples/render/run.flex
```

Arrow keys move the camera; Escape closes the window. The demo builds four
caller-owned SetaScript shader modules, draws a floor and three boxes, and renders
a depth map before the surface pass. `--frames N --capture frame.ppm` makes a
bounded capture run. `--hidden` permits explicit offscreen testing.

See [the API and extraction boundary](../../docs/render.md). Existing
`render/material.flex` water policy remains compatible.
