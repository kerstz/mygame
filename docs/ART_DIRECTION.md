# Art direction — first environment (rainy meadow)

Primary reference: the user-supplied `reference.png` (a still of a misty grass
field). The image itself is **not** stored in this repository: it appears to be
a frame from a third-party video and its licence is unknown. It is used only as
a look target.

## What the reference shows → how STILLWORLD reproduces it in 3D

| Reference trait | Implementation |
|---|---|
| Tall, irregular grass filling fore- and mid-ground | 7-blade clumps 0.45–1.05 m, per-instance height 0.65–1.4× driven by low-frequency patch noise, random tilt/rotation (`WorldAssets._grass_clump`, `ChunkBuilder`) |
| Dark, muted green with olive/brown variation | Grass palette root→tip `#060805 → #30361f`, per-instance hue + dryness, macro noise tint (`grass.gdshader`); terrain under grass darkened to match |
| Delicate pale seed heads catching diffuse light | Separate `seedheads` layer: tall stalks with panicles of tiny spikelets, straw/grey-beige (`_seed_stalks`, `is_seedhead`) |
| Landscape dissolving into fog, no defined horizon | Meadow profile: exponential fog 0.016 (≈ 50 % at 45 m, opaque beyond ~250 m), fog colour ≈ sky colour, sky affect 0.55, volumetric fog for depth layering |
| Uniform, luminous grey sky, no harsh sun | `overcast = 1.0` grey dome in `sky.gdshader`, sun disk suppressed, sun energy 0.3, shadow opacity 0.35 |
| Soft, broad, low-contrast light | Ambient from sky dominates; contrast 0.97; AgX tonemapping (4.4+) |
| Restrained, cool, desaturated palette | Saturation 0.7, cool fog/overcast tints |
| Humid, wet | Rain 0.6, wetness lowers roughness on ground/grass, droplet glints on blades, puddles + ripples |
| Wind waves through grass | Scrolling gust texture → coherent waves, plus per-instance flutter (`grass.gdshader`) |

No full-screen blur or depth of field is used: the softness comes from fog and
light, and nearby blades stay sharp.
